--============================================================
-- CATALYST HUB
-- Complete single-script Roblox Studio movement UI
-- LocalScript -> StarterPlayer > StarterPlayerScripts
--============================================================

-- Shows any error on screen (and in the Output window) so a problem in one
-- feature never fails silently.
local function ReportError(label, err)
	warn("[CATALYST HUB] " .. tostring(label) .. " failed:\n" .. tostring(err))

	pcall(function()
		local player = game:GetService("Players").LocalPlayer
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")

		if not playerGui then
			return
		end

		local screen = playerGui:FindFirstChild("CATALYST_ERRORS")

		if not screen then
			screen = Instance.new("ScreenGui")
			screen.Name = "CATALYST_ERRORS"
			screen.ResetOnSpawn = false
			screen.DisplayOrder = 5000
			screen.IgnoreGuiInset = true
			screen.Parent = playerGui

			local holder = Instance.new("Frame")
			holder.Name = "Holder"
			holder.BackgroundTransparency = 1
			holder.Position = UDim2.fromOffset(16, 16)
			holder.Size = UDim2.fromOffset(420, 0)
			holder.AutomaticSize = Enum.AutomaticSize.Y
			holder.Parent = screen

			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 6)
			layout.Parent = holder
		end

		local holder = screen:FindFirstChild("Holder")
		local firstLine = string.match(tostring(err), "[^\n]+") or tostring(err)

		local card = Instance.new("TextButton")
		card.AutoButtonColor = false
		card.BackgroundColor3 = Color3.fromRGB(52, 20, 26)
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.TextWrapped = true
		card.TextXAlignment = Enum.TextXAlignment.Left
		card.TextYAlignment = Enum.TextYAlignment.Top
		card.Font = Enum.Font.GothamMedium
		card.TextSize = 12
		card.TextColor3 = Color3.fromRGB(255, 225, 228)
		card.Text = "CATALYST HUB - " .. tostring(label) .. " failed\n"
			.. string.sub(firstLine, 1, 220)
			.. "\n(click to dismiss)"
		card.Parent = holder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = card

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = card

		card.MouseButton1Click:Connect(function()
			card:Destroy()
		end)
	end)
end

print("[CATALYST HUB] starting...")

local function Main()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

if not Player then
	error("CATALYST HUB must run as a LocalScript (Players.LocalPlayer is nil)")
end
local PlayerGui = Player:WaitForChild("PlayerGui")

--============================================================
-- CONFIG
--============================================================

local Config = {
	WalkSpeed = 16,
	JumpPower = 50,

	Fly = false,
	FlyJump = false,
	Noclip = false,

	FlySpeed = 72,
	FlyKey = Enum.KeyCode.F,
	MenuKey = Enum.KeyCode.P, -- minimize / restore the menu
	KeybindKey = Enum.KeyCode.L, -- open / close the keybind panel

	-- Flight feel (higher = snappier, lower = floatier)
	Acceleration = 7,
	Deceleration = 5,
	BoostMultiplier = 1.75,
	-- Fly Jump (Infinite Yield style)
	-- Space / E = up, Ctrl / Q = down, instant start and stop.
	-- Also gives you Infinite Yield's infinite jump while you're not flying.
	VerticalMultiplier = 1.0, -- up / down speed relative to fly speed

	-- Character animation
	Tilt = true,              -- lean the character into the movement
	MaxPitchTilt = 35,        -- degrees
	MaxRollTilt = 25,         -- degrees
	Pose = true,              -- arms / legs / body move while flying
	PoseAmount = 1,           -- 0 to 1.5
	Takeoff = true,           -- little lift-off kick when flight starts

	-- Camera + effects
	FOVBoost = 14,            -- extra FOV at full speed (0 = off)
	CameraRoll = 4,           -- degrees of camera bank when strafing (0 = off)
	HoverBob = 0.8,           -- gentle idle float (0 = off)
	Trail = true,
	TrailColor = "Blue",      -- Blue, Cyan, Green, Purple, Red, White, Rainbow

	-- Hitbox
	Hitbox = false,
	HitboxSize = 10,                -- studs
	HitboxShape = "Block",          -- Block | Ball | Cylinder
	HitboxMaterial = "ForceField",
	HitboxColor = "Blue",           -- Blue, Red, Green, Purple, White, Yellow, Rainbow
	HitboxTransparency = 0.7,       -- 0 = solid, 1 = invisible
	HitboxTeamCheck = false,        -- skip players on your team

	-- Look
	CornerScale = 0.6,              -- 1 = old round corners, lower = sharper (0.6 = Windows 11 style)
}

--============================================================
-- STATE
--============================================================

local Closed = false
local Minimized = false
local UiReady = false

-- runs a feature; if it throws, the error is shown but the rest keeps working
local function Safe(label, fn)
	local ok, err = xpcall(fn, debug.traceback)

	if not ok then
		ReportError(label, err)
	end
end

-- toast popups (built later, once the UI exists)
local Notify

local function Toast(title, text, accent)
	if Notify and UiReady and not Closed then
		Notify(title, text, accent)
	end
end

local FrameAverage = 1 / 60
local StatTimer = 0

local Character
local Humanoid
local Root

local FlyAttachment
local FlyVelocity
local FlyOrientation

local CurrentVelocity = Vector3.zero
local CurrentVertical = 0

local FlightTime = 0
local Lean = Vector2.zero
local BaseFOV
local Controls

local JumpVelocity = 0
local JumpHoldUntil = 0
local SliderDragging = false
local WasBoosting = false

local CharacterParts = {}
local PartAddedConnection

local MinimizeBusy = false
local Closing = false
local SetMinimized
local CloseMenu

local DropdownLayer
local DropdownCatcher
local ActiveDropdown

local SetKeybindPanel
local KeybindOpen = false

local LiftVelocity = 0
local FOVPunch = 0
local PoseBlend = 0
local PoseJoints = {}

local FlyTrail
local TrailTop
local TrailBottom

local FlightObjectNames = {
	CATALYST_FlightAttachment = true,
	CATALYST_FlightVelocity = true,
	CATALYST_FlightOrientation = true,
	CATALYST_TrailTop = true,
	CATALYST_TrailBottom = true,
	CATALYST_FlightTrail = true,
}

local TrailColors = {
	Blue = Color3.fromRGB(65, 150, 255),
	Cyan = Color3.fromRGB(80, 230, 255),
	Green = Color3.fromRGB(75, 220, 145),
	Purple = Color3.fromRGB(170, 110, 255),
	Red = Color3.fromRGB(245, 80, 95),
	White = Color3.fromRGB(235, 240, 250),
}

local SpaceHeld = false
local CtrlHeld = false

local OriginalCollision = {}
local Connections = {}

local Gui
local BootGui

local FlyToggle
local NoclipToggle
local FlyJumpToggle

local FlyStatus
local CharacterStatus
local SpeedStatus
local FlySpeedSlider
local FpsStatus
local PingStatus

--============================================================
-- CONNECTIONS
--============================================================

local function Connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Connections, connection)
	return connection
end

local function DisconnectEverything()
	for _, connection in ipairs(Connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(Connections)
end

--============================================================
-- HELPERS
--============================================================

local function New(className, properties, parent)
	local object = Instance.new(className)

	for property, value in pairs(properties or {}) do
		object[property] = value
	end

	object.Parent = parent
	return object
end

local function Corner(parent, radius)
	return New("UICorner", {
		CornerRadius = UDim.new(0, math.max(2, math.floor(radius * Config.CornerScale + 0.5)))
	}, parent)
end

local function Stroke(parent, color, transparency)
	return New("UIStroke", {
		Color = color,
		Transparency = transparency or 0,
		Thickness = 1
	}, parent)
end

local function Tween(object, time, properties)
	if not object or not object.Parent then
		return
	end

	local success, tween = pcall(function()
		return TweenService:Create(
			object,
			TweenInfo.new(
				time,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.Out
			),
			properties
		)
	end)

	if success then
		tween:Play()
	end
end

-- small squish when a button is pressed
local function AddPress(button)
	local scale = New("UIScale", {
		Scale = 1
	}, button)

	local function release()
		Tween(scale, 0.18, {
			Scale = 1
		})
	end

	Connect(button.MouseButton1Down, function()
		Tween(scale, 0.08, {
			Scale = 0.95
		})
	end)

	Connect(button.MouseButton1Up, release)
	Connect(button.MouseLeave, release)
end

--============================================================
-- COLORS
--============================================================

local Color = {
	Background = Color3.fromRGB(8, 10, 16),
	Panel = Color3.fromRGB(13, 17, 26),
	Panel2 = Color3.fromRGB(18, 23, 34),

	Blue = Color3.fromRGB(65, 150, 255),
	BlueDark = Color3.fromRGB(35, 105, 205),

	Text = Color3.fromRGB(235, 240, 250),
	Sub = Color3.fromRGB(125, 138, 160),

	Border = Color3.fromRGB(31, 40, 58),
	Green = Color3.fromRGB(75, 220, 145),
	Red = Color3.fromRGB(245, 80, 95),
}

--============================================================
-- CHARACTER
--============================================================

local function ApplyCharacterSettings()
	if not Humanoid or not Humanoid.Parent then
		return
	end

	Humanoid.WalkSpeed = Config.WalkSpeed
	Humanoid.UseJumpPower = true
	Humanoid.JumpPower = Config.JumpPower
end

local function CacheParts(character)
	table.clear(CharacterParts)

	if PartAddedConnection then
		PartAddedConnection:Disconnect()
		PartAddedConnection = nil
	end

	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			CharacterParts[object] = true
		end
	end

	PartAddedConnection = character.DescendantAdded:Connect(function(object)
		if object:IsA("BasePart") then
			CharacterParts[object] = true
		end
	end)
end

local function LoadCharacter(character)
	Character = character
	Humanoid = character:WaitForChild("Humanoid")
	Root = character:WaitForChild("HumanoidRootPart")

	CacheParts(character)
	ApplyCharacterSettings()
end

if Player.Character then
	LoadCharacter(Player.Character)
end

--============================================================
-- FLIGHT CLEANUP
--============================================================

local function RestoreFOV()
	local camera = workspace.CurrentCamera

	if camera and BaseFOV then
		Tween(camera, 0.4, {
			FieldOfView = BaseFOV
		})
	end

	BaseFOV = nil
end

--============================================================
-- FLIGHT POSE (procedural animation, no asset ids needed)
--============================================================

local function CapturePose()
	table.clear(PoseJoints)

	if not Character then
		return
	end

	local function Add(name, kind)
		local joint = Character:FindFirstChild(name, true)

		if joint and joint:IsA("Motor6D") then
			local c0 = joint.C0
			local pivot = CFrame.new(c0.Position)

			table.insert(PoseJoints, {
				Joint = joint,
				Kind = kind,
				C0 = c0,
				Pivot = pivot,
				Rotation = pivot:Inverse() * c0,
			})
		end
	end

	-- R15
	Add("RightShoulder", "RArm")
	Add("LeftShoulder", "LArm")
	Add("RightHip", "RLeg")
	Add("LeftHip", "LLeg")
	Add("Waist", "Waist")

	-- R6
	Add("Right Shoulder", "RArm")
	Add("Left Shoulder", "LArm")
	Add("Right Hip", "RLeg")
	Add("Left Hip", "LLeg")

	-- both
	Add("Neck", "Neck")
end

local function RestorePose()
	for _, data in ipairs(PoseJoints) do
		if data.Joint and data.Joint.Parent then
			data.Joint.C0 = data.C0
		end
	end

	table.clear(PoseJoints)
	PoseBlend = 0
end

local function DestroyFlightObjects()
	RestorePose()

	if FlyVelocity then
		FlyVelocity:Destroy()
		FlyVelocity = nil
	end

	if FlyOrientation then
		FlyOrientation:Destroy()
		FlyOrientation = nil
	end

	if FlyAttachment then
		FlyAttachment:Destroy()
		FlyAttachment = nil
	end

	if FlyTrail then
		FlyTrail:Destroy()
		FlyTrail = nil
	end

	if TrailTop then
		TrailTop:Destroy()
		TrailTop = nil
	end

	if TrailBottom then
		TrailBottom:Destroy()
		TrailBottom = nil
	end

	if Character then
		for _, object in ipairs(Character:GetDescendants()) do
			if FlightObjectNames[object.Name] then
				object:Destroy()
			end
		end
	end

	CurrentVelocity = Vector3.zero
	CurrentVertical = 0
	JumpVelocity = 0
	LiftVelocity = 0
	FOVPunch = 0
end

--============================================================
-- NOCLIP RESTORE
--============================================================

local function RestoreCollision()
	Config.Noclip = false

	for part, originalState in pairs(OriginalCollision) do
		if part and part.Parent then
			part.CanCollide = originalState
		end
	end

	table.clear(OriginalCollision)
end

--============================================================
-- HITBOX
--============================================================

-- Enlarges (and shows) other players' HumanoidRootPart on YOUR screen.
-- Everything is local to this client and fully restored when you turn it off.

local HitboxData = {}

local HitboxColors = {
	Blue = Color3.fromRGB(65, 150, 255),
	Red = Color3.fromRGB(245, 80, 95),
	Green = Color3.fromRGB(75, 220, 145),
	Purple = Color3.fromRGB(170, 110, 255),
	White = Color3.fromRGB(235, 240, 250),
	Yellow = Color3.fromRGB(255, 215, 80),
}

local function GetHitboxColor()
	if Config.HitboxColor == "Rainbow" then
		return Color3.fromHSV((os.clock() * 0.25) % 1, 0.75, 1)
	end

	return HitboxColors[Config.HitboxColor] or HitboxColors.Blue
end

local function RestoreHitbox(player)
	local data = HitboxData[player]

	if not data then
		return
	end

	local part = data.Part

	if part and part.Parent then
		local original = data.Original

		-- shape first, so a ball doesn't force the size
		part.Shape = original.Shape
		part.Size = original.Size
		part.Material = original.Material
		part.Color = original.Color
		part.Transparency = original.Transparency
		part.CanCollide = original.CanCollide
	end

	HitboxData[player] = nil
end

local function RestoreAllHitboxes()
	for player in pairs(HitboxData) do
		RestoreHitbox(player)
	end
end

local function ApplyHitbox(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local part = character and character:FindFirstChild("HumanoidRootPart")

	-- gone, dead or not a normal part: put it back and forget it
	if not part or not part:IsA("Part") or not humanoid or humanoid.Health <= 0 then
		RestoreHitbox(player)
		return
	end

	local data = HitboxData[player]

	-- player respawned, the old part no longer exists
	if data and data.Part ~= part then
		HitboxData[player] = nil
		data = nil
	end

	if not data then
		data = {
			Part = part,
			Original = {
				Size = part.Size,
				Shape = part.Shape,
				Material = part.Material,
				Color = part.Color,
				Transparency = part.Transparency,
				CanCollide = part.CanCollide,
			},
		}

		HitboxData[player] = data
	end

	local size = Config.HitboxSize
	local targetSize = Vector3.new(size, size, size)
	local shape = Enum.PartType[Config.HitboxShape] or Enum.PartType.Block
	local material = Enum.Material[Config.HitboxMaterial] or Enum.Material.ForceField
	local color = GetHitboxColor()

	if part.Shape ~= shape then
		part.Shape = shape
	end

	if part.Size ~= targetSize then
		part.Size = targetSize
	end

	if part.Material ~= material then
		part.Material = material
	end

	if part.Color ~= color then
		part.Color = color
	end

	if part.Transparency ~= Config.HitboxTransparency then
		part.Transparency = Config.HitboxTransparency
	end

	-- big boxes must never push you around
	if part.CanCollide then
		part.CanCollide = false
	end
end

local function UpdateHitboxes()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= Player then
			if Config.HitboxTeamCheck
				and Player.Team ~= nil
				and player.Team == Player.Team then
				RestoreHitbox(player)
			else
				ApplyHitbox(player)
			end
		end
	end

	-- forget players that left
	for player in pairs(HitboxData) do
		if not player.Parent then
			HitboxData[player] = nil
		end
	end
end

-- keeps the FLY switch in the UI matching the real flight state
-- (silent = doesn't trigger the switch callback again)
local function SyncFlyToggle()
	if FlyToggle then
		FlyToggle.Set(Config.Fly, true)
	end
end

--============================================================
-- STOP FLIGHT
--============================================================

local function StopFlight()
	local wasFlying = Config.Fly
	local exitVelocity = CurrentVelocity + Vector3.yAxis * JumpVelocity

	Config.Fly = false

	DestroyFlightObjects()
	RestoreFOV()

	CurrentVelocity = Vector3.zero
	CurrentVertical = 0
	SpaceHeld = false
	CtrlHeld = false

	if Humanoid and Humanoid.Parent then
		Humanoid.PlatformStand = false
		Humanoid.AutoRotate = true
		Humanoid.WalkSpeed = Config.WalkSpeed
		Humanoid.UseJumpPower = true
		Humanoid.JumpPower = Config.JumpPower

		pcall(function()
			Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end

	if Root and Root.Parent then
		-- keep some momentum so leaving flight doesn't feel like hitting a wall
		if wasFlying then
			Root.AssemblyLinearVelocity = exitVelocity * 0.5
		else
			Root.AssemblyLinearVelocity = Vector3.zero
		end

		Root.AssemblyAngularVelocity = Vector3.zero
	end

	if FlyStatus and FlyStatus.Parent then
		FlyStatus.Text = "OFF"

		Tween(FlyStatus, 0.25, {
			TextColor3 = Color.Sub
		})
	end

	SyncFlyToggle()

	if wasFlying then
		Toast("Flight", "Disabled", Color.Sub)
	end
end

--============================================================
-- CREATE FLIGHT
--============================================================

local function CreateFlightObjects()
	if not Root or not Root.Parent then
		return false
	end

	DestroyFlightObjects()

	FlyAttachment = Instance.new("Attachment")
	FlyAttachment.Name = "CATALYST_FlightAttachment"
	FlyAttachment.Parent = Root

	FlyVelocity = Instance.new("LinearVelocity")
	FlyVelocity.Name = "CATALYST_FlightVelocity"
	FlyVelocity.Attachment0 = FlyAttachment
	FlyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	FlyVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	FlyVelocity.MaxForce = math.huge
	FlyVelocity.VectorVelocity = Vector3.zero
	FlyVelocity.Parent = Root

	FlyOrientation = Instance.new("AlignOrientation")
	FlyOrientation.Name = "CATALYST_FlightOrientation"
	FlyOrientation.Attachment0 = FlyAttachment
	FlyOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	FlyOrientation.MaxTorque = math.huge
	FlyOrientation.MaxAngularVelocity = math.huge
	FlyOrientation.Responsiveness = 30
	FlyOrientation.RigidityEnabled = false
	FlyOrientation.Parent = Root

	-- speed trail
	TrailTop = Instance.new("Attachment")
	TrailTop.Name = "CATALYST_TrailTop"
	TrailTop.Position = Vector3.new(0, 1, 0)
	TrailTop.Parent = Root

	TrailBottom = Instance.new("Attachment")
	TrailBottom.Name = "CATALYST_TrailBottom"
	TrailBottom.Position = Vector3.new(0, -1, 0)
	TrailBottom.Parent = Root

	FlyTrail = Instance.new("Trail")
	FlyTrail.Name = "CATALYST_FlightTrail"
	FlyTrail.Attachment0 = TrailTop
	FlyTrail.Attachment1 = TrailBottom
	FlyTrail.Lifetime = 0.5
	FlyTrail.MinLength = 0.05
	FlyTrail.LightEmission = 0.9
	FlyTrail.FaceCamera = true
	FlyTrail.Enabled = false
	FlyTrail.Color = ColorSequence.new(Color.Blue)
	FlyTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	FlyTrail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	FlyTrail.Parent = Root

	return true
end

--============================================================
-- START FLIGHT
--============================================================

local function StartFlight()
	if Closed then
		return
	end

	if not Character or not Humanoid or not Root then
		return
	end

	if Humanoid.Health <= 0 then
		return
	end

	if Config.Fly then
		return
	end

	if not CreateFlightObjects() then
		return
	end

	Config.Fly = true

	CurrentVelocity = Vector3.zero
	CurrentVertical = 0
	FlightTime = 0
	Lean = Vector2.zero
	JumpVelocity = 0
	SpaceHeld = false
	CtrlHeld = false

	local camera = workspace.CurrentCamera
	BaseFOV = camera and camera.FieldOfView or nil

	WasBoosting = true
	LiftVelocity = Config.Takeoff and 26 or 0
	FOVPunch = Config.Takeoff and 7 or 0
	PoseBlend = 0
	CapturePose()

	Humanoid.PlatformStand = true
	Humanoid.AutoRotate = false

	Root.AssemblyLinearVelocity = Vector3.zero
	Root.AssemblyAngularVelocity = Vector3.zero

	if FlyStatus then
		FlyStatus.Text = "ON"

		Tween(FlyStatus, 0.25, {
			TextColor3 = Color.Green
		})
	end

	SyncFlyToggle()

	Toast("Flight", "Enabled - " .. string.upper(Config.FlyKey.Name) .. " to stop", Color.Green)
end

--============================================================
-- SAME FLIGHT ENGINE FOR TOGGLE + KEYBIND
--============================================================

local function ToggleFlight()
	if Closed then
		return
	end

	if Config.Fly then
		StopFlight()
	else
		StartFlight()
	end
end

--============================================================
-- INPUT (keyboard, gamepad and mobile thumbstick)
--============================================================

-- Roblox's own control module already merges WASD, arrows,
-- gamepad sticks and the mobile thumbstick into one move vector.
task.spawn(function()
	local ok, controls = pcall(function()
		local playerScripts = Player:WaitForChild("PlayerScripts")
		local playerModule = require(playerScripts:WaitForChild("PlayerModule", 10))
		return playerModule:GetControls()
	end)

	if ok and controls then
		Controls = controls
	end
end)

local function GetMoveInput()
	if Controls then
		return Controls:GetMoveVector() -- X = right, Z = backward
	end

	-- fallback if PlayerModule isn't available
	if UIS:GetFocusedTextBox() then
		return Vector3.zero
	end

	local x = (UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
		- (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0)

	local z = (UIS:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
		- (UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0)

	return Vector3.new(x, 0, z)
end

local function GetFlightDirection(camera)
	local move = GetMoveInput()

	if move.Magnitude < 0.001 then
		return Vector3.zero
	end

	-- full 3D: looking up/down while holding W actually flies up/down
	local cf = camera.CFrame
	local direction = cf.RightVector * move.X + cf.LookVector * -move.Z

	if direction.Magnitude > 1 then
		direction = direction.Unit
	end

	return direction
end

-- extra keys never fire if you've bound them as your fly key
local function KeyHeld(key)
	return key ~= Config.FlyKey and UIS:IsKeyDown(key)
end

local function GetVerticalInput()
	if UIS:GetFocusedTextBox() then
		return 0
	end

	local down = UIS:IsKeyDown(Enum.KeyCode.LeftControl)
		or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)

	local up = false

	if Config.FlyJump then
		-- Space / E = up, Ctrl / Q = down (like Infinite Yield)
		up = UIS:IsKeyDown(Enum.KeyCode.Space)
			or KeyHeld(Enum.KeyCode.E)
			or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
			or os.clock() < JumpHoldUntil

		down = down or KeyHeld(Enum.KeyCode.Q)
	end

	local value = 0

	if up then
		value += 1
	end

	if down then
		-- Ctrl descends slower unless Fly Jump is on
		value -= Config.FlyJump and 1 or 0.7
	end

	return value
end

local function IsBoosting()
	return UIS:IsKeyDown(Enum.KeyCode.LeftShift)
		or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
end

--============================================================
-- POSE UPDATE
--============================================================

local function UpdatePose(dt, velocity)
	if #PoseJoints == 0 then
		return
	end

	local target = Config.Pose and 1 or 0
	PoseBlend += (target - PoseBlend) * (1 - math.exp(-6 * dt))

	local amount = PoseBlend * Config.PoseAmount
	local topSpeed = Config.FlySpeed * Config.BoostMultiplier

	local fast = math.clamp(velocity.Magnitude / topSpeed, 0, 1)
	local idle = 1 - fast
	local rise = math.clamp(velocity.Y / math.max(Config.FlySpeed, 1), -1, 1)

	local swayA = math.sin(FlightTime * 2.4)
	local swayB = math.sin(FlightTime * 2.4 + 1.7)

	for _, data in ipairs(PoseJoints) do
		-- x = swing forward(+) / back(-), z = out(+) / in(-), in degrees
		local x = 0
		local z = 0
		local kind = data.Kind

		if kind == "RArm" then
			x = 8 * idle - 32 * fast + 14 * rise + 6 * swayA * idle
			z = 16 + 8 * fast + 8 * swayA * idle
		elseif kind == "LArm" then
			x = 8 * idle - 32 * fast + 14 * rise + 6 * swayB * idle
			z = -(16 + 8 * fast + 8 * swayB * idle)
		elseif kind == "RLeg" then
			x = -26 * fast - 8 * rise + 5 * swayB
			z = 4
		elseif kind == "LLeg" then
			x = -26 * fast - 8 * rise + 5 * swayA
			z = -4
		elseif kind == "Waist" then
			x = -9 * fast
			z = -Lean.Y * 8
		elseif kind == "Neck" then
			x = 9 * fast
		end

		local offset = CFrame.Angles(
			math.rad(x * amount),
			0,
			math.rad(z * amount)
		)

		if data.Joint and data.Joint.Parent then
			data.Joint.C0 = data.Pivot * offset * data.Rotation
		end
	end
end

--============================================================
-- FLIGHT LOOP
--============================================================

-- Runs right AFTER the camera updates, so facing never lags a frame behind.
local FLIGHT_BIND = "CATALYST_FlightLoop"

pcall(function()
	RunService:UnbindFromRenderStep(FLIGHT_BIND)
end)

RunService:BindToRenderStep(
	FLIGHT_BIND,
	Enum.RenderPriority.Camera.Value + 1,
	function(dt)
		if Closed or not Config.Fly then
			return
		end

		if not Character or not Humanoid or not Root then
			return
		end

		if Humanoid.Health <= 0 then
			StopFlight()
			return
		end

		if not FlyVelocity or not FlyOrientation then
			if not CreateFlightObjects() then
				StopFlight()
				return
			end
		end

		local camera = workspace.CurrentCamera

		if not camera then
			return
		end

		Humanoid.PlatformStand = true
		Humanoid.AutoRotate = false

		FlightTime += dt

		local speed = Config.FlySpeed
		local boosting = IsBoosting()

		if boosting then
			speed *= Config.BoostMultiplier

			-- little FOV punch the moment you start boosting
			if not WasBoosting then
				FOVPunch = math.max(FOVPunch, 5)
			end
		end

		WasBoosting = boosting

		local direction = GetFlightDirection(camera)
		local hasMove = direction.Magnitude > 0.01
		local jumpInput = GetVerticalInput()

		--====================================================
		-- CAMERA MOVEMENT (full 3D, smoothed)
		--====================================================

		local target = direction * speed
		local rate

		if hasMove then
			rate = Config.Acceleration

			-- reversing direction brakes harder so it doesn't feel mushy
			if CurrentVelocity.Magnitude > 1
				and CurrentVelocity.Unit:Dot(target.Unit) < 0 then
				rate = math.max(Config.Acceleration, Config.Deceleration) * 1.5
			end
		else
			rate = Config.Deceleration

			-- idle hover bob
			if Config.HoverBob > 0 and jumpInput == 0 then
				target += Vector3.yAxis
					* math.sin(FlightTime * 2.2)
					* Config.HoverBob
			end
		end

		CurrentVelocity = CurrentVelocity:Lerp(
			target,
			1 - math.exp(-rate * dt)
		)

		--====================================================
		-- FLY JUMP (Infinite Yield style: instant up / down)
		--====================================================

		-- full speed the moment you press, dead stop when you let go
		JumpVelocity = jumpInput * speed * Config.VerticalMultiplier

		-- takeoff kick fades out on its own
		LiftVelocity *= math.exp(-4 * dt)

		if math.abs(LiftVelocity) < 0.1 then
			LiftVelocity = 0
		end

		--====================================================
		-- FINAL VELOCITY
		--====================================================

		local velocity = CurrentVelocity
			+ Vector3.yAxis * (JumpVelocity + LiftVelocity)

		local cap = math.max(
			speed * 1.25,
			speed * Config.VerticalMultiplier,
			30
		)

		if velocity.Magnitude > cap then
			velocity = velocity.Unit * cap
		end

		CurrentVertical = velocity.Y
		FlyVelocity.VectorVelocity = velocity

		--====================================================
		-- FACING + LEAN
		--====================================================

		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)

		if flatLook.Magnitude > 0.001 then
			local facing = CFrame.lookAt(Vector3.zero, flatLook.Unit)
			local tilt = CFrame.identity

			local topSpeed = Config.FlySpeed * Config.BoostMultiplier
			local localVelocity = facing:VectorToObjectSpace(velocity)

			local forward = math.clamp(-localVelocity.Z / topSpeed, -1, 1)
			local sideways = math.clamp(localVelocity.X / topSpeed, -1, 1)

			Lean = Lean:Lerp(
				Vector2.new(forward, sideways),
				1 - math.exp(-8 * dt)
			)

			if Config.Tilt then
				-- lean back less than forward
				local pitch = Lean.X >= 0 and Lean.X or Lean.X * 0.5

				tilt = CFrame.Angles(
					math.rad(-pitch * Config.MaxPitchTilt),
					0,
					math.rad(-Lean.Y * Config.MaxRollTilt)
				)
			end

			FlyOrientation.CFrame = facing * tilt
		end

		--====================================================
		-- BODY ANIMATION
		--====================================================

		UpdatePose(dt, velocity)

		--====================================================
		-- TRAIL
		--====================================================

		if FlyTrail then
			local show = Config.Trail
				and velocity.Magnitude > Config.FlySpeed * 0.35

			FlyTrail.Enabled = show

			if show then
				local trailColor

				if Config.TrailColor == "Rainbow" then
					trailColor = Color3.fromHSV((FlightTime * 0.35) % 1, 0.7, 1)
				else
					trailColor = TrailColors[Config.TrailColor] or TrailColors.Blue
				end

				FlyTrail.Color = ColorSequence.new(trailColor)
			end
		end

		--====================================================
		-- SPEED FOV
		--====================================================

		if Config.FOVBoost > 0 then
			if not BaseFOV then
				BaseFOV = camera.FieldOfView
			end

			FOVPunch *= math.exp(-4 * dt)

			local fraction = math.clamp(
				velocity.Magnitude
					/ (Config.FlySpeed * Config.BoostMultiplier),
				0,
				1
			)

			local targetFOV = BaseFOV
				+ Config.FOVBoost * fraction
				+ FOVPunch

			camera.FieldOfView += (targetFOV - camera.FieldOfView)
				* (1 - math.exp(-6 * dt))
		end

		--====================================================
		-- CAMERA ROLL (banks when you strafe)
		--====================================================

		if Config.CameraRoll > 0 then
			camera.CFrame = camera.CFrame * CFrame.Angles(
				0,
				0,
				math.rad(-Lean.Y * Config.CameraRoll)
			)
		end
	end
)

--============================================================
-- NOCLIP LOOP
--============================================================

Connect(RunService.Stepped, function()
	if Closed or not Character then
		return
	end

	if Config.Noclip then
		for part in pairs(CharacterParts) do
			if part.Parent then
				if OriginalCollision[part] == nil then
					OriginalCollision[part] = part.CanCollide
				end

				part.CanCollide = false
			else
				CharacterParts[part] = nil
			end
		end
	elseif next(OriginalCollision) ~= nil then
		for part, originalState in pairs(OriginalCollision) do
			if part and part.Parent then
				part.CanCollide = originalState
			end
		end

		table.clear(OriginalCollision)
	end
end)

--============================================================
-- UI CLEANUP
--============================================================

for _, child in ipairs(PlayerGui:GetChildren()) do
	if child.Name == "CATALYST_HUB"
		or child.Name == "CATALYST_BOOT"
		or child.Name == "NOVA_AERO"
		or child.Name == "NOVA_BOOT" then
		child:Destroy()
	end
end

--============================================================
-- BOOT GUI
--============================================================

BootGui = New("ScreenGui", {
	Name = "CATALYST_BOOT",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Boot = New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color.Background,
	BorderSizePixel = 0,
}, BootGui)

local BootCenter = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.47),
	Size = UDim2.fromOffset(460, 240),
	BackgroundTransparency = 1,
}, Boot)

local BootLogo = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(80, 80),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
}, BootCenter)

Corner(BootLogo, 16)
Stroke(BootLogo, Color.Blue, 0.25)

New("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "C",
	Font = Enum.Font.GothamBlack,
	TextSize = 44,
	TextColor3 = Color.Blue,
}, BootLogo)

New("TextLabel", {
	Position = UDim2.fromOffset(0, 94),
	Size = UDim2.new(1, 0, 0, 35),
	BackgroundTransparency = 1,
	Text = "CATALYST HUB",
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	TextColor3 = Color.Text,
}, BootCenter)

local BootStatus = New("TextLabel", {
	Position = UDim2.fromOffset(0, 130),
	Size = UDim2.new(1, 0, 0, 25),
	BackgroundTransparency = 1,
	Text = "INITIALIZING...",
	Font = Enum.Font.GothamMedium,
	TextSize = 10,
	TextColor3 = Color.Sub,
}, BootCenter)

local BootBarBack = New("Frame", {
	Position = UDim2.fromOffset(50, 170),
	Size = UDim2.fromOffset(360, 5),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
}, BootCenter)

Corner(BootBarBack, 5)

local BootBar = New("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color.Blue,
	BorderSizePixel = 0,
}, BootBarBack)

Corner(BootBar, 5)

local BootPercent = New("TextLabel", {
	Position = UDim2.fromOffset(0, 184),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Text = "0%",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
}, BootCenter)

--============================================================
-- MAIN GUI
--============================================================

Gui = New("ScreenGui", {
	Name = "CATALYST_HUB",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Main = New("CanvasGroup", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(760, 520),
	BackgroundColor3 = Color.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	GroupTransparency = 1,
}, Gui)

Corner(Main, 14)
Stroke(Main, Color.Border, 0.1)

local MainScale = New("UIScale", {
	Scale = 0.92
}, Main)

--============================================================
-- SIDEBAR
--============================================================

local Sidebar = New("Frame", {
	Size = UDim2.new(0, 190, 1, 0),
	BackgroundColor3 = Color.Panel,
	BorderSizePixel = 0,
}, Main)

local Brand = New("Frame", {
	Position = UDim2.fromOffset(17, 17),
	Size = UDim2.new(1, -34, 0, 60),
	BackgroundTransparency = 1,
}, Sidebar)

local BrandIcon = New("Frame", {
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
}, Brand)

Corner(BrandIcon, 10)
Stroke(BrandIcon, Color.Blue, 0.25)

New("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "C",
	Font = Enum.Font.GothamBlack,
	TextSize = 25,
	TextColor3 = Color.Blue,
}, BrandIcon)

New("TextLabel", {
	Position = UDim2.fromOffset(57, 0),
	Size = UDim2.new(1, -57, 0, 24),
	BackgroundTransparency = 1,
	Text = "CATALYST HUB",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Brand)

New("TextLabel", {
	Position = UDim2.fromOffset(57, 25),
	Size = UDim2.new(1, -57, 0, 17),
	BackgroundTransparency = 1,
	Text = "CONTROL CENTER",
	Font = Enum.Font.GothamMedium,
	TextSize = 8,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Brand)

New("TextLabel", {
	Position = UDim2.new(0, 17, 1, -30),
	Size = UDim2.new(1, -34, 0, 16),
	BackgroundTransparency = 1,
	Text = "CATALYST HUB  -  v2.0",
	Font = Enum.Font.GothamMedium,
	TextSize = 8,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Sidebar)

--============================================================
-- CONTENT
--============================================================

local Content = New("Frame", {
	Position = UDim2.fromOffset(190, 0),
	Size = UDim2.new(1, -190, 1, 0),
	BackgroundColor3 = Color.Background,
	BorderSizePixel = 0,
}, Main)

local Header = New("Frame", {
	Size = UDim2.new(1, 0, 0, 78),
	BackgroundTransparency = 1,
}, Content)

local HeaderTitle = New("TextLabel", {
	Position = UDim2.fromOffset(25, 17),
	Size = UDim2.new(1, -115, 0, 27),
	BackgroundTransparency = 1,
	Text = "Dashboard",
	Font = Enum.Font.GothamBold,
	TextSize = 21,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Header)

local HeaderSub = New("TextLabel", {
	Position = UDim2.fromOffset(26, 44),
	Size = UDim2.new(1, -115, 0, 18),
	BackgroundTransparency = 1,
	Text = "Catalyst movement control center",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Header)

--============================================================
-- DROPDOWN LAYER
--============================================================

-- Lists open here (above all pages) so a card can never clip them.
DropdownLayer = New("Frame", {
	Name = "DropdownLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, Main)

-- invisible button behind the open list: click anywhere else to close it
DropdownCatcher = New("TextButton", {
	Name = "Catcher",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
}, DropdownLayer)

--============================================================
-- TOASTS (little notifications, bottom right)
--============================================================

local ToastHolder = New("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(280, 360),
	BackgroundTransparency = 1,
}, Gui)

New("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
}, ToastHolder)

local ToastOrder = 0

Notify = function(title, text, accent)
	-- never more than 4 on screen
	local alive = {}

	for _, child in ipairs(ToastHolder:GetChildren()) do
		if child:IsA("CanvasGroup") then
			table.insert(alive, child)
		end
	end

	if #alive >= 4 then
		alive[1]:Destroy()
	end

	ToastOrder += 1

	local toast = New("CanvasGroup", {
		LayoutOrder = ToastOrder,
		Size = UDim2.fromOffset(260, 52),
		BackgroundColor3 = Color.Panel,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, ToastHolder)

	Corner(toast, 10)
	Stroke(toast, Color.Border, 0.1)

	-- the body slides in from the right inside the (clipping) toast
	local body = New("Frame", {
		Position = UDim2.fromOffset(60, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, toast)

	local bar = New("Frame", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(0, 3, 1, -16),
		BackgroundColor3 = accent or Color.Blue,
		BorderSizePixel = 0,
	}, body)

	Corner(bar, 2)

	New("TextLabel", {
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.new(1, -34, 0, 18),
		BackgroundTransparency = 1,
		Text = string.upper(title),
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, body)

	New("TextLabel", {
		Position = UDim2.fromOffset(22, 26),
		Size = UDim2.new(1, -34, 0, 16),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 9,
		TextColor3 = Color.Sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, body)

	Tween(toast, 0.3, {
		GroupTransparency = 0
	})

	Tween(body, 0.45, {
		Position = UDim2.fromOffset(0, 0)
	})

	task.delay(2.8, function()
		if toast.Parent then
			Tween(body, 0.3, {
				Position = UDim2.fromOffset(60, 0)
			})

			Tween(toast, 0.3, {
				GroupTransparency = 1
			})

			task.delay(0.32, function()
				toast:Destroy()
			end)
		end
	end)
end

--============================================================
-- CLOSE / MINIMIZE
--============================================================

local Minimize = New("TextButton", {
	Position = UDim2.new(1, -69, 0, 23),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "—",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color.Sub,
	AutoButtonColor = false,
}, Content)

Corner(Minimize, 7)
AddPress(Minimize)

local Close = New("TextButton", {
	Position = UDim2.new(1, -38, 0, 23),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "×",
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = Color.Red,
	AutoButtonColor = false,
}, Content)

Corner(Close, 7)
AddPress(Close)

--============================================================
-- TABS
--============================================================

local Tabs = {}
local Pages = {}
local CurrentTab = "Dashboard"

local function MakeTab(name, symbol, y)
	local button = New("TextButton", {
		Position = UDim2.fromOffset(13, y),
		Size = UDim2.new(1, -26, 0, 42),
		BackgroundColor3 = Color.Panel2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, Sidebar)

	Corner(button, 8)
	AddPress(button)

	local icon = New("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromOffset(24, 42),
		BackgroundTransparency = 1,
		Text = symbol,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color.Sub,
	}, button)

	local label = New("TextLabel", {
		Position = UDim2.fromOffset(43, 0),
		Size = UDim2.new(1, -50, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextColor3 = Color.Sub,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, button)

	Tabs[name] = {
		Button = button,
		Icon = icon,
		Label = label,
		Y = y,
	}

	return button
end

MakeTab("Dashboard", "▦", 102)
MakeTab("Movement", "↕", 150)
MakeTab("Utilities", "⚙", 198)
MakeTab("Hitbox", "◎", 246)
MakeTab("Place Teleporter", "⇄", 294)

-- sliding accent bar that follows the selected tab
local TabIndicator = New("Frame", {
	Position = UDim2.fromOffset(4, 112),
	Size = UDim2.fromOffset(3, 22),
	BackgroundColor3 = Color.Blue,
	BorderSizePixel = 0,
}, Sidebar)

Corner(TabIndicator, 2)

--============================================================
-- PAGES
--============================================================

local function MakePage(name)
	local page = New("ScrollingFrame", {
		Name = name .. "Page",
		Position = UDim2.fromOffset(24, 80),
		Size = UDim2.new(1, -48, 1, -98),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color.Blue,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, Content)

	New("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)

	New("UIPadding", {
		PaddingBottom = UDim.new(0, 12)
	}, page)

	Pages[name] = page
	return page
end

local Dashboard = MakePage("Dashboard")
local Movement = MakePage("Movement")
local Utilities = MakePage("Utilities")
local HitboxPage = MakePage("Hitbox")
local TeleportPage = MakePage("Place Teleporter")

--============================================================
-- CARD
--============================================================

local function Card(parent, height)
	local card = New("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Color.Panel,
		BorderSizePixel = 0,
	}, parent)

	Corner(card, 10)
	Stroke(card, Color.Border, 0.35)

	return card
end

--============================================================
-- KEYBIND LIST (used by the dashboard block and the L panel)
--============================================================

local KeybindList = {
	{"Toggle flight", function() return string.upper(Config.FlyKey.Name) end},
	{"Minimize menu", function() return string.upper(Config.MenuKey.Name) end},
	{"Keybind panel", function() return string.upper(Config.KeybindKey.Name) end},
	{"Fly up", function() return "SPACE / E" end},
	{"Fly down", function() return "CTRL / Q" end},
	{"Boost", function() return "SHIFT" end},
	{"Close lists", function() return "ESC" end},
}

-- every key chip registers here so rebinding the fly key updates them live
local KeybindChips = {}

local function BuildKeybindRows(parent, startY, padding, rowHeight)
	for i, item in ipairs(KeybindList) do
		local y = startY + (i - 1) * rowHeight

		New("TextLabel", {
			Position = UDim2.fromOffset(padding, y),
			Size = UDim2.new(1, -(padding * 2 + 90), 0, 24),
			BackgroundTransparency = 1,
			Text = item[1],
			Font = Enum.Font.GothamMedium,
			TextSize = 9,
			TextColor3 = Color.Sub,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)

		local chip = New("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -padding, 0, y),
			Size = UDim2.fromOffset(84, 24),
			BackgroundColor3 = Color.Panel2,
			BorderSizePixel = 0,
		}, parent)

		Corner(chip, 6)
		Stroke(chip, Color.Border, 0.25)

		local label = New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = item[2](),
			Font = Enum.Font.GothamBold,
			TextSize = 8,
			TextColor3 = Color.Text,
		}, chip)

		table.insert(KeybindChips, {
			Label = label,
			Get = item[2],
		})
	end
end

--============================================================
-- DASHBOARD
--============================================================

local Welcome = Card(Dashboard, 112)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 15),
	Size = UDim2.new(1, -38, 0, 26),
	BackgroundTransparency = 1,
	Text = "Welcome to CATALYST HUB",
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Welcome)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 45),
	Size = UDim2.new(1, -38, 0, 50),
	BackgroundTransparency = 1,
	Text = "Use the Movement tab for character settings and Utilities\nfor flight and other movement controls.",
	Font = Enum.Font.GothamMedium,
	TextSize = 10,
	TextColor3 = Color.Sub,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, Welcome)

local StatusCard = Card(Dashboard, 190)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 15),
	Size = UDim2.new(1, -38, 0, 22),
	BackgroundTransparency = 1,
	Text = "SYSTEM STATUS",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, StatusCard)

local function StatusRow(parent, y, title, initial)
	New("TextLabel", {
		Position = UDim2.fromOffset(19, y),
		Size = UDim2.fromOffset(130, 20),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamMedium,
		TextSize = 9,
		TextColor3 = Color.Sub,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)

	return New("TextLabel", {
		Position = UDim2.new(1, -175, 0, y),
		Size = UDim2.fromOffset(156, 20),
		BackgroundTransparency = 1,
		Text = initial,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = Color.Green,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, parent)
end

CharacterStatus = StatusRow(StatusCard, 49, "CHARACTER", "READY")
FlyStatus = StatusRow(StatusCard, 78, "FLIGHT", "OFF")
SpeedStatus = StatusRow(StatusCard, 107, "FLY SPEED", tostring(Config.FlySpeed))
FpsStatus = StatusRow(StatusCard, 136, "FPS", "--")
PingStatus = StatusRow(StatusCard, 165, "PING", "--")

local KeybindCard = Card(Dashboard, 284)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 15),
	Size = UDim2.new(1, -38, 0, 22),
	BackgroundTransparency = 1,
	Text = "KEYBINDS",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, KeybindCard)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 38),
	Size = UDim2.new(1, -38, 0, 18),
	BackgroundTransparency = 1,
	Text = "Press " .. string.upper(Config.KeybindKey.Name) .. " to open the keybind panel.",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, KeybindCard)

BuildKeybindRows(KeybindCard, 66, 19, 30)

--============================================================
-- MOVEMENT
--============================================================

local MovementCard = Card(Movement, 245)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 15),
	Size = UDim2.new(1, -36, 0, 23),
	BackgroundTransparency = 1,
	Text = "MOVEMENT SETTINGS",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, MovementCard)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 38),
	Size = UDim2.new(1, -36, 0, 18),
	BackgroundTransparency = 1,
	Text = "Tune your character movement.",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, MovementCard)

local function IsPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function IsPointerMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local function Slider(parent, title, y, minimum, maximum, default, callback, suffix)
	local holder = New("Frame", {
		Position = UDim2.fromOffset(18, y),
		Size = UDim2.new(1, -36, 0, 72),
		BackgroundTransparency = 1,
	}, parent)

	New("TextLabel", {
		Size = UDim2.new(1, -70, 0, 20),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamMedium,
		TextSize = 9,
		TextColor3 = Color.Sub,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local valueLabel = New("TextLabel", {
		Position = UDim2.new(1, -65, 0, 0),
		Size = UDim2.fromOffset(65, 20),
		BackgroundTransparency = 1,
		Text = tostring(default) .. (suffix or ""),
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = Color.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, holder)

	local bar = New("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = Color.Panel2,
		BorderSizePixel = 0,
	}, holder)

	Corner(bar, 5)

	local fill = New("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color.Blue,
		BorderSizePixel = 0,
	}, bar)

	Corner(fill, 5)

	local knob = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Color.Text,
		BorderSizePixel = 0,
	}, bar)

	Corner(knob, 20)

	-- Invisible BUTTON over the bar. Buttons sink input, so clicking or
	-- dragging a slider can never leak through and move the window.
	-- It's also taller than the bar, so it's much easier to grab.
	local hitbox = New("TextButton", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, holder)

	local value = default
	local dragging = false

	local function SetValue(newValue)
		value = math.clamp(
			math.floor(newValue + 0.5),
			minimum,
			maximum
		)

		local alpha = (value - minimum) / (maximum - minimum)

		valueLabel.Text = tostring(value) .. (suffix or "")
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)

		callback(value)
	end

	local function UpdateFromInput(input)
		local width = bar.AbsoluteSize.X

		if width <= 0 then
			return
		end

		local alpha = math.clamp(
			(input.Position.X - bar.AbsolutePosition.X) / width,
			0,
			1
		)

		SetValue(
			minimum + ((maximum - minimum) * alpha)
		)
	end

	local function StopDragging()
		if not dragging then
			return
		end

		dragging = false
		SliderDragging = false

		Tween(knob, 0.12, {
			Size = UDim2.fromOffset(12, 12)
		})
	end

	Connect(hitbox.InputBegan, function(input)
		if not IsPointer(input) then
			return
		end

		dragging = true
		SliderDragging = true

		Tween(knob, 0.12, {
			Size = UDim2.fromOffset(16, 16)
		})

		UpdateFromInput(input)
	end)

	Connect(UIS.InputChanged, function(input)
		if dragging and IsPointerMove(input) then
			UpdateFromInput(input)
		end
	end)

	Connect(UIS.InputEnded, function(input)
		if IsPointer(input) then
			StopDragging()
		end
	end)

	SetValue(default)

	return {
		Set = SetValue,
		Get = function()
			return value
		end
	}
end

Slider(
	MovementCard,
	"WALK SPEED",
	66,
	16,
	150,
	Config.WalkSpeed,
	function(value)
		Config.WalkSpeed = value

		if Humanoid and not Config.Fly then
			Humanoid.WalkSpeed = value
		end
	end
)

Slider(
	MovementCard,
	"JUMP POWER",
	136,
	50,
	200,
	Config.JumpPower,
	function(value)
		Config.JumpPower = value

		if Humanoid then
			Humanoid.UseJumpPower = true
			Humanoid.JumpPower = value
		end
	end
)

--============================================================
-- UTILITIES
--============================================================

local UtilityCard = Card(Utilities, 390)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 15),
	Size = UDim2.new(1, -36, 0, 23),
	BackgroundTransparency = 1,
	Text = "UTILITIES",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, UtilityCard)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 38),
	Size = UDim2.new(1, -36, 0, 18),
	BackgroundTransparency = 1,
	Text = "Advanced movement controls.",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, UtilityCard)

--============================================================
-- TOGGLE
--============================================================

local function Toggle(parent, title, description, y, default, callback)
	local row = New("Frame", {
		Position = UDim2.fromOffset(18, y),
		Size = UDim2.new(1, -36, 0, 53),
		BackgroundTransparency = 1,
	}, parent)

	New("TextLabel", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -65, 0, 20),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextColor3 = Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	New("TextLabel", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, -65, 0, 20),
		BackgroundTransparency = 1,
		Text = description,
		Font = Enum.Font.GothamMedium,
		TextSize = 8,
		TextColor3 = Color.Sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local button = New("TextButton", {
		Position = UDim2.new(1, -50, 0, 8),
		Size = UDim2.fromOffset(45, 23),
		BackgroundColor3 = Color.Panel2,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, row)

	Corner(button, 20)
	AddPress(button)

	local dot = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(17, 17),
		BackgroundColor3 = Color.Sub,
		BorderSizePixel = 0,
	}, button)

	Corner(dot, 20)

	local state = false
	local controller = {}

	function controller.Set(newState, silent)
		state = newState == true

		if state then
			Tween(button, 0.15, {
				BackgroundColor3 = Color.BlueDark
			})

			Tween(dot, 0.15, {
				Position = UDim2.new(1, -20, 0.5, 0),
				BackgroundColor3 = Color.Text
			})
		else
			Tween(button, 0.15, {
				BackgroundColor3 = Color.Panel2
			})

			Tween(dot, 0.15, {
				Position = UDim2.new(0, 3, 0.5, 0),
				BackgroundColor3 = Color.Sub
			})
		end

		if not silent then
			callback(state)
		end
	end

	function controller.Get()
		return state
	end

	Connect(button.MouseButton1Click, function()
		controller.Set(not state)
	end)

	controller.Set(default)

	return controller
end

--============================================================
-- DROPDOWN
--============================================================

local DROPDOWN_ROW = 28
local DROPDOWN_MAX_ROWS = 6

local RainbowSequence = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(90, 230, 120)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(80, 120, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(200, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
})

-- swatch is a Color3, or the string "Rainbow"
local function ApplySwatch(frame, swatch)
	local gradient = frame:FindFirstChildOfClass("UIGradient")

	if swatch == "Rainbow" then
		frame.BackgroundColor3 = Color3.new(1, 1, 1)

		if not gradient then
			gradient = New("UIGradient", {}, frame)
		end

		gradient.Color = RainbowSequence
	else
		if gradient then
			gradient:Destroy()
		end

		frame.BackgroundColor3 = swatch or Color.Text
	end
end

local function CloseActiveDropdown(instant)
	if ActiveDropdown then
		ActiveDropdown.Close(instant)
	end
end

Connect(DropdownCatcher.MouseButton1Click, function()
	CloseActiveDropdown()
end)

-- keeps the open list attached to its button (scrolling, sliding pages...)
Connect(RunService.RenderStepped, function()
	if ActiveDropdown then
		ActiveDropdown.Place()
	end
end)

local function Dropdown(parent, title, description, y, options, default, callback, swatches, width, placeholder)
	width = width or 135
	placeholder = placeholder or "SELECT"

	local row = New("Frame", {
		Position = UDim2.fromOffset(18, y),
		Size = UDim2.new(1, -36, 0, 53),
		BackgroundTransparency = 1,
	}, parent)

	New("TextLabel", {
		Size = UDim2.new(1, -(width + 15), 0, 20),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextColor3 = Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	New("TextLabel", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, -(width + 15), 0, 20),
		BackgroundTransparency = 1,
		Text = description,
		Font = Enum.Font.GothamMedium,
		TextSize = 8,
		TextColor3 = Color.Sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local button = New("TextButton", {
		Position = UDim2.new(1, -width, 0, 4),
		Size = UDim2.fromOffset(width, 31),
		BackgroundColor3 = Color.Panel2,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, row)

	Corner(button, 7)
	local buttonStroke = Stroke(button, Color.Border, 0.25)
	AddPress(button)

	local textX = 12
	local buttonSwatch

	if swatches then
		buttonSwatch = New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = Color.Text,
			BorderSizePixel = 0,
		}, button)

		Corner(buttonSwatch, 12)
		textX = 31
	end

	local valueLabel = New("TextLabel", {
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX - 26, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, button)

	local arrow = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Text = "▼",
		Font = Enum.Font.GothamBold,
		TextSize = 7,
		TextColor3 = Color.Sub,
	}, button)

	local index = 1

	for i, option in ipairs(options) do
		if option == default then
			index = i
		end
	end

	local open = false
	local holder
	local list
	local listHeight = 0
	local state = {}

	local function Select(i, silent)
		index = i

		local option = options[i]

		valueLabel.Text = option and string.upper(option) or placeholder

		if buttonSwatch and option then
			ApplySwatch(buttonSwatch, swatches[option])
		end

		if option and not silent then
			callback(option, i)
		end
	end

	local function Close(instant)
		if not open then
			return
		end

		open = false

		if ActiveDropdown == state then
			ActiveDropdown = nil
			DropdownCatcher.Visible = false
		end

		Tween(arrow, 0.2, {
			Rotation = 0
		})

		Tween(buttonStroke, 0.15, {
			Color = Color.Border
		})

		local closing = holder
		holder = nil
		list = nil

		if closing then
			if instant then
				closing:Destroy()
			else
				-- list folds back up
				Tween(closing, 0.16, {
					Size = UDim2.fromOffset(closing.Size.X.Offset, 0)
				})

				task.delay(0.18, function()
					closing:Destroy()
				end)
			end
		end
	end

	local function Place()
		if not holder or not holder.Parent or not list then
			return
		end

		local scale = MainScale.Scale
		local origin = Main.AbsolutePosition

		local left = (button.AbsolutePosition.X - origin.X) / scale
		local top = (button.AbsolutePosition.Y - origin.Y) / scale
		local buttonHeight = button.AbsoluteSize.Y / scale
		local mainHeight = Main.AbsoluteSize.Y / scale

		-- button scrolled out of view (or the window is collapsing)
		if top < 80 or top + buttonHeight > mainHeight - 6 then
			Close(true)
			return
		end

		local below = top + buttonHeight + 4

		if below + listHeight <= mainHeight - 8 then
			-- opens downward
			holder.AnchorPoint = Vector2.new(0, 0)
			holder.Position = UDim2.fromOffset(left, below)

			list.AnchorPoint = Vector2.new(0, 0)
			list.Position = UDim2.fromOffset(0, 0)
		else
			-- not enough room below: opens upward
			holder.AnchorPoint = Vector2.new(0, 1)
			holder.Position = UDim2.fromOffset(left, top - 4)

			list.AnchorPoint = Vector2.new(0, 1)
			list.Position = UDim2.new(0, 0, 1, 0)
		end
	end

	state.Close = Close
	state.Place = Place

	local function Open()
		if open or #options == 0 then
			return
		end

		CloseActiveDropdown(true)

		open = true

		listHeight = math.min(#options, DROPDOWN_MAX_ROWS) * DROPDOWN_ROW + 8

		local width = button.AbsoluteSize.X / MainScale.Scale

		holder = New("Frame", {
			Size = UDim2.fromOffset(width, 0),
			BackgroundColor3 = Color.Panel,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, DropdownLayer)

		Corner(holder, 8)
		Stroke(holder, Color.Border, 0.1)

		list = New("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, listHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Color.Blue,
			CanvasSize = UDim2.fromOffset(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, holder)

		New("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, list)

		New("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
		}, list)

		for i, option in ipairs(options) do
			local selected = i == index

			local item = New("TextButton", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, DROPDOWN_ROW),
				BackgroundColor3 = Color.Border,
				BackgroundTransparency = selected and 0.55 or 1,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
			}, list)

			Corner(item, 6)

			local itemTextX = 10

			if swatches then
				local dot = New("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.fromOffset(12, 12),
					BackgroundColor3 = Color.Text,
					BorderSizePixel = 0,
				}, item)

				Corner(dot, 12)
				ApplySwatch(dot, swatches[option])

				itemTextX = 30
			end

			local label = New("TextLabel", {
				Position = UDim2.fromOffset(itemTextX, 0),
				Size = UDim2.new(1, -itemTextX - 22, 1, 0),
				BackgroundTransparency = 1,
				Text = string.upper(option),
				Font = Enum.Font.GothamMedium,
				TextSize = 9,
				TextColor3 = selected and Color.Blue or Color.Text,
				TextTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, item)

			if selected then
				local mark = New("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(1, -14, 0.5, 0),
					Size = UDim2.fromOffset(6, 6),
					BackgroundColor3 = Color.Blue,
					BorderSizePixel = 0,
				}, item)

				Corner(mark, 6)
			end

			-- options fade in one after another
			task.delay((i - 1) * 0.02, function()
				Tween(label, 0.18, {
					TextTransparency = 0
				})
			end)

			-- these die with the list, so no need to track them
			item.MouseEnter:Connect(function()
				if i ~= index then
					Tween(item, 0.1, {
						BackgroundTransparency = 0.7
					})
				end
			end)

			item.MouseLeave:Connect(function()
				if i ~= index then
					Tween(item, 0.1, {
						BackgroundTransparency = 1
					})
				end
			end)

			item.MouseButton1Click:Connect(function()
				Select(i)
				Close()
			end)
		end

		ActiveDropdown = state
		DropdownCatcher.Visible = true

		Place()

		-- closed itself because the button wasn't visible
		if not holder then
			return
		end

		Tween(holder, 0.22, {
			Size = UDim2.fromOffset(width, listHeight)
		})

		Tween(arrow, 0.2, {
			Rotation = 180
		})

		Tween(buttonStroke, 0.15, {
			Color = Color.Blue
		})

		-- scroll the current choice into view
		local target = list

		task.defer(function()
			if target and target.Parent then
				target.CanvasPosition = Vector2.new(
					0,
					math.max(0, (index - 2) * DROPDOWN_ROW)
				)
			end
		end)
	end

	Connect(button.MouseButton1Click, function()
		if open then
			Close()
		else
			Open()
		end
	end)

	Connect(button.MouseEnter, function()
		if not open then
			Tween(button, 0.12, {
				BackgroundColor3 = Color.Border
			})
		end
	end)

	Connect(button.MouseLeave, function()
		Tween(button, 0.12, {
			BackgroundColor3 = Color.Panel2
		})
	end)

	Select(index)

	return {
		Set = function(newIndex)
			Select(((newIndex - 1) % #options) + 1)
		end,
		Get = function()
			return options[index]
		end,
		-- swap the whole list (used by the place teleporter)
		SetOptions = function(newOptions, selectedIndex, newPlaceholder)
			Close(true)

			table.clear(options)

			for i, option in ipairs(newOptions) do
				options[i] = option
			end

			placeholder = newPlaceholder or placeholder

			Select(selectedIndex or 1, true)
		end,
	}
end

NoclipToggle = Toggle(
	UtilityCard,
	"NOCLIP",
	"Disable character collisions.",
	70,
	false,
	function(value)
		Config.Noclip = value
		Toast("Noclip", value and "Enabled" or "Disabled", value and Color.Green or Color.Sub)
	end
)

FlyJumpToggle = Toggle(
	UtilityCard,
	"FLY JUMP",
	"Infinite Yield style: Space / Ctrl fly up and down, jump in mid-air.",
	126,
	false,
	function(value)
		Config.FlyJump = value
		Toast("Fly Jump", value and "Enabled" or "Disabled", value and Color.Green or Color.Sub)
	end
)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 185),
	Size = UDim2.new(1, -36, 0, 18),
	BackgroundTransparency = 1,
	Text = "FLIGHT",
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	TextColor3 = Color.Blue,
	TextXAlignment = Enum.TextXAlignment.Left,
}, UtilityCard)

FlyToggle = Toggle(
	UtilityCard,
	"FLY",
	"Smooth camera-relative flight.",
	207,
	false,
	function(value)
		if Closed then
			return
		end

		if value then
			StartFlight()
		else
			StopFlight()
		end
	end
)

--============================================================
-- KEYBIND
--============================================================

local keyRow = New("Frame", {
	Position = UDim2.fromOffset(18, 267),
	Size = UDim2.new(1, -36, 0, 40),
	BackgroundTransparency = 1,
}, UtilityCard)

New("TextLabel", {
	Size = UDim2.new(1, -120, 1, 0),
	BackgroundTransparency = 1,
	Text = "FLY KEYBIND",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, keyRow)

local KeyButton = New("TextButton", {
	Position = UDim2.new(1, -105, 0, 3),
	Size = UDim2.fromOffset(105, 31),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = Config.FlyKey.Name,
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	TextColor3 = Color.Text,
	AutoButtonColor = false,
}, keyRow)

Corner(KeyButton, 7)
AddPress(KeyButton)
Stroke(KeyButton, Color.Border, 0.25)

local ListeningForKey = false

Connect(KeyButton.MouseButton1Click, function()
	if Closed then
		return
	end

	ListeningForKey = true
	KeyButton.Text = "PRESS KEY"
	KeyButton.TextColor3 = Color.Blue
end)

--============================================================
-- FLY SPEED
--============================================================

FlySpeedSlider = Slider(
	UtilityCard,
	"FLY SPEED",
	325,
	1,
	300,
	Config.FlySpeed,
	function(value)
		Config.FlySpeed = value

		if SpeedStatus then
			SpeedStatus.Text = tostring(value)
		end
	end
)

--============================================================
-- HITBOX TAB
--============================================================

Safe("Hitbox tab", function()

local HitboxSwatches = {
	Rainbow = "Rainbow",
}

for name, color in pairs(HitboxColors) do
	HitboxSwatches[name] = color
end

local HitboxCard = Card(HitboxPage, 510)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 15),
	Size = UDim2.new(1, -36, 0, 23),
	BackgroundTransparency = 1,
	Text = "HITBOX",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, HitboxCard)

New("TextLabel", {
	Position = UDim2.fromOffset(18, 38),
	Size = UDim2.new(1, -36, 0, 18),
	BackgroundTransparency = 1,
	Text = "Enlarge and show player hitboxes.",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, HitboxCard)

Toggle(
	HitboxCard,
	"HITBOX",
	"Enlarges other players' hitboxes on your screen.",
	66,
	Config.Hitbox,
	function(value)
		Config.Hitbox = value
		Toast("Hitbox", value and "Enabled" or "Disabled", value and Color.Green or Color.Sub)

		if value then
			UpdateHitboxes()
		else
			RestoreAllHitboxes()
		end
	end
)

Slider(
	HitboxCard,
	"HITBOX SIZE",
	124,
	2,
	50,
	Config.HitboxSize,
	function(value)
		Config.HitboxSize = value
	end,
	" studs"
)

Dropdown(
	HitboxCard,
	"SHAPE",
	"Pick the hitbox shape.",
	196,
	{"Block", "Ball", "Cylinder"},
	Config.HitboxShape,
	function(value)
		Config.HitboxShape = value
	end
)

Dropdown(
	HitboxCard,
	"MATERIAL",
	"Pick the hitbox material.",
	254,
	{"ForceField", "Neon", "Glass", "SmoothPlastic", "Plastic", "Metal", "Ice", "Wood"},
	Config.HitboxMaterial,
	function(value)
		Config.HitboxMaterial = value
	end
)

Dropdown(
	HitboxCard,
	"COLOR",
	"Pick the hitbox color.",
	312,
	{"Blue", "Red", "Green", "Purple", "White", "Yellow", "Rainbow"},
	Config.HitboxColor,
	function(value)
		Config.HitboxColor = value
	end,
	HitboxSwatches
)

Slider(
	HitboxCard,
	"TRANSPARENCY",
	372,
	0,
	100,
	math.floor(Config.HitboxTransparency * 100 + 0.5),
	function(value)
		Config.HitboxTransparency = value / 100
	end,
	"%"
)

Toggle(
	HitboxCard,
	"TEAM CHECK",
	"Skip players on your own team.",
	444,
	Config.HitboxTeamCheck,
	function(value)
		Config.HitboxTeamCheck = value
	end
)

end)

--============================================================
-- PLACE TELEPORTER TAB
--============================================================

Safe("Place teleporter", function()

local TeleportService = game:GetService("TeleportService")
local AssetService = game:GetService("AssetService")

local Teleporting = false
local TeleportToken = 0
local PlacesLoading = false
local PlaceLookup = {} -- list text -> place id

local TeleportCard = Card(TeleportPage, 430)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 15),
	Size = UDim2.new(1, -38, 0, 23),
	BackgroundTransparency = 1,
	Text = "PLACE TELEPORTER",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TeleportCard)

New("TextLabel", {
	Position = UDim2.fromOffset(19, 38),
	Size = UDim2.new(1, -38, 0, 18),
	BackgroundTransparency = 1,
	Text = "Pick a place from this game, or type any place ID.",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TeleportCard)

local jobText = "STUDIO"

if game.JobId ~= "" then
	jobText = string.upper(string.sub(game.JobId, 1, 8)) .. "..."
end

local PlaceRow = StatusRow(TeleportCard, 66, "CURRENT PLACE", tostring(game.PlaceId))
PlaceRow.TextColor3 = Color.Text

local ServerRow = StatusRow(TeleportCard, 95, "SERVER", jobText)
ServerRow.TextColor3 = Color.Text

New("TextLabel", {
	Position = UDim2.fromOffset(19, 184),
	Size = UDim2.fromOffset(120, 20),
	BackgroundTransparency = 1,
	Text = "PLACE ID",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TeleportCard)

local UseCurrent = New("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -19, 0, 184),
	Size = UDim2.fromOffset(96, 20),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "USE CURRENT",
	Font = Enum.Font.GothamBold,
	TextSize = 8,
	TextColor3 = Color.Blue,
	AutoButtonColor = false,
}, TeleportCard)

Corner(UseCurrent, 6)
AddPress(UseCurrent)

local PlaceInput = New("TextBox", {
	Position = UDim2.fromOffset(19, 208),
	Size = UDim2.new(1, -38, 0, 34),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "",
	PlaceholderText = "Enter a place ID",
	PlaceholderColor3 = Color.Sub,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
}, TeleportCard)

Corner(PlaceInput, 7)

local PlaceInputStroke = Stroke(PlaceInput, Color.Border, 0.25)

New("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, PlaceInput)

local function ActionButton(position, size, text, primary)
	local normal = primary and Color.BlueDark or Color.Panel2
	local hover = primary and Color.Blue or Color.Border

	local button = New("TextButton", {
		Position = position,
		Size = size,
		BackgroundColor3 = normal,
		BorderSizePixel = 0,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = Color.Text,
		AutoButtonColor = false,
	}, TeleportCard)

	Corner(button, 7)
	AddPress(button)

	if not primary then
		Stroke(button, Color.Border, 0.25)
	end

	Connect(button.MouseEnter, function()
		Tween(button, 0.12, {
			BackgroundColor3 = hover
		})
	end)

	Connect(button.MouseLeave, function()
		Tween(button, 0.12, {
			BackgroundColor3 = normal
		})
	end)

	return button
end

local TeleportButton = ActionButton(
	UDim2.fromOffset(19, 254),
	UDim2.new(0.5, -23, 0, 34),
	"TELEPORT",
	true
)

local RejoinButton = ActionButton(
	UDim2.new(0.5, 4, 0, 254),
	UDim2.new(0.5, -23, 0, 34),
	"REJOIN SERVER",
	false
)

local CopyPlaceButton = ActionButton(
	UDim2.fromOffset(19, 298),
	UDim2.new(0.5, -23, 0, 34),
	"COPY PLACE ID",
	false
)

local CopyJobButton = ActionButton(
	UDim2.new(0.5, 4, 0, 298),
	UDim2.new(0.5, -23, 0, 34),
	"COPY JOB ID",
	false
)

-- read-only box: shows what you copied, and is selected for Ctrl+C
-- when the clipboard can't be written to directly
local CopyBox = New("TextBox", {
	Position = UDim2.fromOffset(19, 342),
	Size = UDim2.new(1, -38, 0, 34),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "",
	PlaceholderText = "The copied ID shows here",
	PlaceholderColor3 = Color.Sub,
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	TextEditable = false,
}, TeleportCard)

Corner(CopyBox, 7)
Stroke(CopyBox, Color.Border, 0.25)

New("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, CopyBox)

local TeleportStatus = New("TextLabel", {
	Position = UDim2.fromOffset(19, 388),
	Size = UDim2.new(1, -150, 0, 20),
	BackgroundTransparency = 1,
	Text = "READY",
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, TeleportCard)

local RefreshPlacesButton = New("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -19, 0, 388),
	Size = UDim2.fromOffset(110, 20),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "REFRESH PLACES",
	Font = Enum.Font.GothamBold,
	TextSize = 8,
	TextColor3 = Color.Blue,
	AutoButtonColor = false,
}, TeleportCard)

Corner(RefreshPlacesButton, 6)
AddPress(RefreshPlacesButton)

local function SetTeleportStatus(text, color)
	if TeleportStatus and TeleportStatus.Parent then
		TeleportStatus.Text = text
		TeleportStatus.TextColor3 = color or Color.Sub
	end
end

-- runs a teleport and gives you a way out if nothing happens
local function RunTeleport(message, action)
	if Teleporting or Closed then
		return
	end

	Teleporting = true
	TeleportToken += 1

	local token = TeleportToken

	SetTeleportStatus(message, Color.Blue)
	Toast("Teleport", message, Color.Blue)

	local ok = pcall(action)

	if not ok then
		Teleporting = false
		SetTeleportStatus("TELEPORT FAILED", Color.Red)
		Toast("Teleport", "Failed to start", Color.Red)
		return
	end

	task.delay(12, function()
		if Teleporting and token == TeleportToken and not Closed then
			Teleporting = false
			SetTeleportStatus("NO RESPONSE - TRY AGAIN", Color.Red)
		end
	end)
end

local function TeleportToInput()
	local id = tonumber(PlaceInput.Text)

	if not id or id <= 0 or id ~= math.floor(id) then
		SetTeleportStatus("ENTER A VALID PLACE ID", Color.Red)
		return
	end

	RunTeleport("TELEPORTING TO " .. tostring(id) .. "...", function()
		TeleportService:Teleport(id, Player)
	end)
end

local function CopyValue(label, value)
	if not value or value == "" then
		SetTeleportStatus(string.upper(label) .. " NOT AVAILABLE HERE", Color.Red)
		Toast(label, "Not available (Studio or no server)", Color.Red)
		return
	end

	CopyBox.Text = value

	-- executors can write to the clipboard directly, Roblox itself can't
	local copied = pcall(function()
		local copier = setclipboard or toclipboard
		copier(value)
	end)

	if copied then
		SetTeleportStatus(string.upper(label) .. " COPIED", Color.Green)
		Toast(label, "Copied to clipboard", Color.Green)
	else
		-- fallback: select the text so Ctrl+C copies it
		pcall(function()
			CopyBox:CaptureFocus()
			CopyBox.SelectionStart = 1
			CopyBox.CursorPosition = #value + 1
		end)

		SetTeleportStatus(string.upper(label) .. " SELECTED - PRESS CTRL+C", Color.Blue)
		Toast(label, "Selected - press Ctrl+C to copy", Color.Blue)
	end
end

Connect(CopyPlaceButton.MouseButton1Click, function()
	-- the ID in the box if you typed or picked one, otherwise this place
	local value = PlaceInput.Text

	if value == "" then
		value = tostring(game.PlaceId)
	end

	CopyValue("Place ID", value)
end)

Connect(CopyJobButton.MouseButton1Click, function()
	CopyValue("Job ID", game.JobId)
end)

--============================================================
-- PLACES INSIDE THIS GAME (the list)
--============================================================

-- the list: choosing a place fills the ID box
local PlaceDropdown = Dropdown(
	TeleportCard,
	"PLACES",
	"Places found inside this game.",
	124,
	{},
	nil,
	function(option)
		local id = PlaceLookup[option]

		if id then
			PlaceInput.Text = tostring(id)
			SetTeleportStatus("SELECTED - PRESS TELEPORT", Color.Green)
		end
	end,
	nil,
	290,
	"LOADING PLACES..."
)

-- asks Roblox for every place that belongs to this experience
local function FetchPlaces()
	local ok, pages = pcall(function()
		return AssetService:GetGamePlacesAsync()
	end)

	if not ok then
		return nil, tostring(pages)
	end

	local places = {}
	local guard = 0

	while guard < 50 do
		guard += 1

		for _, place in ipairs(pages:GetCurrentPage()) do
			table.insert(places, {
				Name = tostring(place.Name),
				PlaceId = place.PlaceId,
			})
		end

		if pages.IsFinished then
			break
		end

		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)

		if not advanced then
			break
		end
	end

	return places
end

local function RefreshPlaces()
	if PlacesLoading or Closed then
		return
	end

	PlacesLoading = true
	SetTeleportStatus("LOADING PLACES...", Color.Blue)

	task.spawn(function()
		local places, failure = FetchPlaces()

		PlacesLoading = false

		if Closed then
			return
		end

		local failed = places == nil
		places = places or {}

		-- the place you're standing in should always be in the list
		local hasCurrent = false

		for _, place in ipairs(places) do
			if place.PlaceId == game.PlaceId then
				hasCurrent = true
			end
		end

		if not hasCurrent and game.PlaceId ~= 0 then
			table.insert(places, {
				Name = "This place",
				PlaceId = game.PlaceId,
			})
		end

		table.sort(places, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)

		table.clear(PlaceLookup)

		local options = {}
		local currentIndex = 1

		for i, place in ipairs(places) do
			local label = place.Name .. "  -  " .. tostring(place.PlaceId)

			if place.PlaceId == game.PlaceId then
				label = label .. "  (current)"
				currentIndex = i
			end

			options[i] = label
			PlaceLookup[label] = place.PlaceId
		end

		PlaceDropdown.SetOptions(
			options,
			currentIndex,
			"NO PLACES FOUND"
		)

		if failed then
			warn("[CATALYST HUB] couldn't list places: " .. tostring(failure))
			SetTeleportStatus("COULDN'T LOAD THE LIST - TYPE AN ID", Color.Red)
		elseif #places == 0 then
			SetTeleportStatus("NO PLACES FOUND (IS THE GAME PUBLISHED?)", Color.Red)
		else
			SetTeleportStatus(tostring(#places) .. " PLACES FOUND", Color.Green)
			Toast("Places", tostring(#places) .. " places found in this game", Color.Green)
		end
	end)
end

-- numbers only
Connect(PlaceInput:GetPropertyChangedSignal("Text"), function()
	local cleaned = string.gsub(PlaceInput.Text, "%D", "")
	cleaned = string.sub(cleaned, 1, 15)

	if cleaned ~= PlaceInput.Text then
		PlaceInput.Text = cleaned
	end
end)

Connect(PlaceInput.Focused, function()
	Tween(PlaceInputStroke, 0.15, {
		Color = Color.Blue
	})
end)

Connect(PlaceInput.FocusLost, function(enterPressed)
	Tween(PlaceInputStroke, 0.15, {
		Color = Color.Border
	})

	if enterPressed then
		TeleportToInput()
	end
end)

Connect(UseCurrent.MouseButton1Click, function()
	PlaceInput.Text = tostring(game.PlaceId)
end)

Connect(UseCurrent.MouseEnter, function()
	Tween(UseCurrent, 0.12, {
		BackgroundColor3 = Color.Border
	})
end)

Connect(UseCurrent.MouseLeave, function()
	Tween(UseCurrent, 0.12, {
		BackgroundColor3 = Color.Panel2
	})
end)

Connect(RefreshPlacesButton.MouseButton1Click, RefreshPlaces)

Connect(RefreshPlacesButton.MouseEnter, function()
	Tween(RefreshPlacesButton, 0.12, {
		BackgroundColor3 = Color.Border
	})
end)

Connect(RefreshPlacesButton.MouseLeave, function()
	Tween(RefreshPlacesButton, 0.12, {
		BackgroundColor3 = Color.Panel2
	})
end)

Connect(TeleportButton.MouseButton1Click, TeleportToInput)

Connect(RejoinButton.MouseButton1Click, function()
	RunTeleport("REJOINING...", function()
		if #Players:GetPlayers() <= 1 then
			-- you're alone, the old server won't exist anymore
			TeleportService:Teleport(game.PlaceId, Player)
		else
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Player)
		end
	end)
end)

Connect(TeleportService.TeleportInitFailed, function(player, result)
	if player ~= Player then
		return
	end

	Teleporting = false
	SetTeleportStatus("FAILED: " .. string.upper(result.Name), Color.Red)
	Toast("Teleport", "Failed: " .. result.Name, Color.Red)
end)

-- load the list as soon as the script starts
RefreshPlaces()

end)

--============================================================
-- KEYBOARD
--============================================================

Connect(UIS.InputBegan, function(input, processed)
	if Closed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	-- Escape closes an open dropdown first, then the keybind panel
	if input.KeyCode == Enum.KeyCode.Escape and ActiveDropdown then
		CloseActiveDropdown()
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape
		and KeybindOpen
		and not ListeningForKey
		and SetKeybindPanel then
		SetKeybindPanel(false)
		return
	end

	-- FlyJump held states
	if input.KeyCode == Enum.KeyCode.Space then
		SpaceHeld = true
	end

	if input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl then
		CtrlHeld = true
	end

	if ListeningForKey then
		if input.KeyCode == Enum.KeyCode.Escape then
			ListeningForKey = false
			KeyButton.Text = Config.FlyKey.Name
			KeyButton.TextColor3 = Color.Text
			return
		end

		Config.FlyKey = input.KeyCode
		KeyButton.Text = input.KeyCode.Name
		KeyButton.TextColor3 = Color.Text
		ListeningForKey = false
		return
	end

	if processed then
		return
	end

	-- SAME TOGGLE FUNCTION AS THE GUI SWITCH
	-- (StartFlight / StopFlight keep the switch in sync themselves)
	if input.KeyCode == Config.FlyKey then
		ToggleFlight()
		return
	end

	-- minimize / restore the menu
	if input.KeyCode == Config.MenuKey and SetMinimized then
		SetMinimized(not Minimized)
		return
	end

	-- open / close the keybind panel
	if input.KeyCode == Config.KeybindKey and SetKeybindPanel then
		SetKeybindPanel(not KeybindOpen)
	end
end)

Connect(UIS.InputEnded, function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		SpaceHeld = false
	end

	if input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl then
		CtrlHeld = false
	end
end)

--============================================================
-- TABS
--============================================================

local function SelectTab(name)
	if Closed then
		return
	end

	CloseActiveDropdown(true)

	CurrentTab = name

	if Tabs[name] then
		Tween(TabIndicator, 0.3, {
			Position = UDim2.fromOffset(4, Tabs[name].Y + 10)
		})
	end

	for tabName, data in pairs(Tabs) do
		local selected = tabName == name

		Tween(data.Button, 0.15, {
			BackgroundTransparency = selected and 0 or 1
		})

		Tween(data.Icon, 0.15, {
			TextColor3 = selected and Color.Blue or Color.Sub
		})

		Tween(data.Label, 0.15, {
			TextColor3 = selected and Color.Text or Color.Sub
		})
	end

	for pageName, page in pairs(Pages) do
		local show = pageName == name

		if show and not page.Visible then
			-- slide-up animation
			page.Position = UDim2.fromOffset(24, 94)
			page.Visible = true

			Tween(page, 0.3, {
				Position = UDim2.fromOffset(24, 80)
			})
		else
			page.Visible = show
		end
	end

	HeaderTitle.Text = name

	if name == "Dashboard" then
		HeaderSub.Text = "Catalyst movement control center"
	elseif name == "Movement" then
		HeaderSub.Text = "Character movement settings"
	elseif name == "Utilities" then
		HeaderSub.Text = "Advanced movement utilities"
	elseif name == "Hitbox" then
		HeaderSub.Text = "Player hitbox controls"
	elseif name == "Place Teleporter" then
		HeaderSub.Text = "Teleport to another place"
	end
end

for name, data in pairs(Tabs) do
	Connect(data.Button.MouseButton1Click, function()
		SelectTab(name)
	end)

	Connect(data.Button.MouseEnter, function()
		if CurrentTab ~= name then
			Tween(data.Button, 0.12, {
				BackgroundTransparency = 0.72
			})
		end
	end)

	Connect(data.Button.MouseLeave, function()
		if CurrentTab ~= name then
			Tween(data.Button, 0.12, {
				BackgroundTransparency = 1
			})
		end
	end)
end

--============================================================
-- JUMP REQUEST (Infinite Yield infinite jump + mobile)
--============================================================

Connect(UIS.JumpRequest, function()
	if Closed or not Config.FlyJump then
		return
	end

	if not Humanoid or not Humanoid.Parent or Humanoid.Health <= 0 then
		return
	end

	if Config.Fly then
		-- mobile jump button: hold it to rise
		if not UIS.KeyboardEnabled then
			JumpHoldUntil = os.clock() + 0.2
		end

		return
	end

	-- Infinite Yield infinite jump: jump again in mid-air
	Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end)

--============================================================
-- KEYBIND PANEL (L) - small draggable block next to the menu
--============================================================

Safe("Keybind panel", function()

local PANEL_WIDTH = 236
local PANEL_ROW = 28
local PANEL_HEIGHT = 66 + #KeybindList * PANEL_ROW + 14
local PANEL_MINI_HEIGHT = 58

local KeybindPanel = New("CanvasGroup", {
	Name = "KeybindPanel",
	Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
	BackgroundColor3 = Color.Panel,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
}, Gui)

Corner(KeybindPanel, 14)
Stroke(KeybindPanel, Color.Border, 0.1)

New("TextLabel", {
	Position = UDim2.fromOffset(16, 15),
	Size = UDim2.new(1, -96, 0, 23),
	BackgroundTransparency = 1,
	Text = "KEYBINDS",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, KeybindPanel)

New("TextLabel", {
	Position = UDim2.fromOffset(16, 38),
	Size = UDim2.new(1, -32, 0, 18),
	BackgroundTransparency = 1,
	Text = "Drag me anywhere. " .. string.upper(Config.KeybindKey.Name) .. " toggles.",
	Font = Enum.Font.GothamMedium,
	TextSize = 9,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, KeybindPanel)

local PanelMinimizeButton = New("TextButton", {
	Position = UDim2.new(1, -66, 0, 15),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "—",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color.Sub,
	AutoButtonColor = false,
}, KeybindPanel)

Corner(PanelMinimizeButton, 7)
AddPress(PanelMinimizeButton)

local PanelCloseButton = New("TextButton", {
	Position = UDim2.new(1, -36, 0, 15),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "×",
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextColor3 = Color.Red,
	AutoButtonColor = false,
}, KeybindPanel)

Corner(PanelCloseButton, 7)
AddPress(PanelCloseButton)

local function PanelHover(button, normal, hover)
	Connect(button.MouseEnter, function()
		Tween(button, 0.12, {
			BackgroundColor3 = hover
		})
	end)

	Connect(button.MouseLeave, function()
		Tween(button, 0.12, {
			BackgroundColor3 = normal
		})
	end)
end

PanelHover(PanelMinimizeButton, Color.Panel2, Color.Border)
PanelHover(PanelCloseButton, Color.Panel2, Color3.fromRGB(58, 26, 34))

BuildKeybindRows(KeybindPanel, 66, 16, PANEL_ROW)

-- 0 = hidden, 1 = fully open (drives both the slide and the fade)
local PanelAlpha = New("NumberValue", {
	Value = 0
}, Gui)

local PanelTween
local PanelMinimized = false

-- once you drag it, it stays where you put it (until you drop it back
-- next to the menu, then it docks again)
local PanelFree = false
local PanelPosition = Vector2.zero
local PanelDragging = false
local PanelDragStart = Vector2.zero
local PanelDragOrigin = Vector2.zero

local function GetDockedPosition()
	local mainPosition = Main.AbsolutePosition
	local mainSize = Main.AbsoluteSize
	local screen = Gui.AbsoluteSize
	local height = KeybindPanel.Size.Y.Offset
	local gap = 12

	-- right side of the menu, or the left side if there's no room
	local side = 1
	local x = mainPosition.X + mainSize.X + gap

	if x + PANEL_WIDTH > screen.X - 8 then
		side = -1
		x = mainPosition.X - gap - PANEL_WIDTH
	end

	x = math.clamp(x, 8, math.max(8, screen.X - PANEL_WIDTH - 8))

	local y = math.clamp(
		mainPosition.Y,
		8,
		math.max(8, screen.Y - height - 8)
	)

	return Vector2.new(x, y), side
end

local function SetPanelMinimized(state, instant)
	PanelMinimized = state
	PanelMinimizeButton.Text = state and "□" or "—"

	local size = UDim2.fromOffset(
		PANEL_WIDTH,
		state and PANEL_MINI_HEIGHT or PANEL_HEIGHT
	)

	if instant then
		KeybindPanel.Size = size
	else
		Tween(KeybindPanel, 0.3, {
			Size = size
		})
	end
end

SetKeybindPanel = function(state)
	if Closed then
		return
	end

	KeybindOpen = state

	if state and PanelMinimized then
		SetPanelMinimized(false, true)
	end

	if not state then
		PanelDragging = false
	end

	if PanelTween then
		PanelTween:Cancel()
	end

	PanelTween = TweenService:Create(
		PanelAlpha,
		TweenInfo.new(
			state and 0.4 or 0.22,
			state and Enum.EasingStyle.Back or Enum.EasingStyle.Quart,
			state and Enum.EasingDirection.Out or Enum.EasingDirection.In
		),
		{
			Value = state and 1 or 0
		}
	)

	PanelTween:Play()
end

Connect(PanelCloseButton.MouseButton1Click, function()
	SetKeybindPanel(false)
end)

Connect(PanelMinimizeButton.MouseButton1Click, function()
	SetPanelMinimized(not PanelMinimized)
end)

-- drag from anywhere on the panel (the buttons sit on top and win)
Connect(KeybindPanel.InputBegan, function(input)
	if not IsPointer(input) or not KeybindOpen then
		return
	end

	PanelDragging = true
	PanelDragStart = Vector2.new(input.Position.X, input.Position.Y)
	PanelDragOrigin = KeybindPanel.AbsolutePosition
end)

Connect(UIS.InputChanged, function(input)
	if not PanelDragging or not IsPointerMove(input) then
		return
	end

	local delta = Vector2.new(input.Position.X, input.Position.Y) - PanelDragStart
	local screen = Gui.AbsoluteSize
	local height = KeybindPanel.Size.Y.Offset

	PanelPosition = Vector2.new(
		math.clamp(PanelDragOrigin.X + delta.X, 8, math.max(8, screen.X - PANEL_WIDTH - 8)),
		math.clamp(PanelDragOrigin.Y + delta.Y, 8, math.max(8, screen.Y - height - 8))
	)

	PanelFree = true
end)

Connect(UIS.InputEnded, function(input)
	if not PanelDragging or not IsPointer(input) then
		return
	end

	PanelDragging = false

	-- dropped right next to the menu: dock again
	local docked = GetDockedPosition()

	if (PanelPosition - docked).Magnitude < 36 then
		PanelFree = false
	end
end)

-- sticks to the menu until you drag it somewhere else
Connect(RunService.RenderStepped, function()
	local alpha = PanelAlpha.Value

	if alpha <= 0.001 and not KeybindOpen then
		if KeybindPanel.Visible then
			KeybindPanel.Visible = false
		end

		return
	end

	KeybindPanel.Visible = true

	local docked, side = GetDockedPosition()
	local position = docked

	if PanelFree then
		local screen = Gui.AbsoluteSize
		local height = KeybindPanel.Size.Y.Offset

		position = Vector2.new(
			math.clamp(PanelPosition.X, 8, math.max(8, screen.X - PANEL_WIDTH - 8)),
			math.clamp(PanelPosition.Y, 8, math.max(8, screen.Y - height - 8))
		)
	end

	-- slides out from behind the menu
	local slide = (1 - alpha) * -26 * side

	KeybindPanel.Position = UDim2.fromOffset(position.X + slide, position.Y)
	KeybindPanel.GroupTransparency = 1 - math.clamp(alpha, 0, 1)
end)

end)

--============================================================
-- DRAGGING (header / sidebar / minimized bar only)
--============================================================

local Dragging = false
local DragStart
local StartCenter

local function BeginWindowDrag(input)
	if not IsPointer(input) then
		return
	end

	if SliderDragging then
		return
	end

	Dragging = true
	DragStart = input.Position
	StartCenter = Main.AbsolutePosition + Main.AbsoluteSize / 2
end

-- Only these areas drag the window. Sliders live in the page area,
-- so they can never start a window drag.
Connect(Header.InputBegan, BeginWindowDrag)
Connect(Sidebar.InputBegan, BeginWindowDrag)

Connect(UIS.InputChanged, function(input)
	if not Dragging then
		return
	end

	if SliderDragging then
		Dragging = false
		return
	end

	if not IsPointerMove(input) then
		return
	end

	local delta = input.Position - DragStart
	local screen = Gui.AbsoluteSize
	local margin = 60

	-- can't be dragged off the screen
	local x = math.clamp(StartCenter.X + delta.X, margin, screen.X - margin)
	local y = math.clamp(StartCenter.Y + delta.Y, margin, screen.Y - margin)

	Main.Position = UDim2.fromOffset(x, y)
end)

Connect(UIS.InputEnded, function(input)
	if IsPointer(input) then
		Dragging = false
	end
end)

--============================================================
-- RESIZE (curved grips in all four corners)
--============================================================

local WindowSize = Vector2.new(760, 520)

local ResizeLayer = New("Frame", {
	Name = "ResizeLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, Main)

Safe("Resize grips", function()

local MIN_WINDOW = Vector2.new(640, 440)

local resizing = false
local startMouse = Vector2.zero
local startSize = Vector2.zero
local startCenter = Vector2.zero
local dirX = 1
local dirY = 1
local activeArc

local function BeginResize(input, gx, gy, arc)
	if not IsPointer(input) then
		return
	end

	if Minimized or MinimizeBusy or Closing or not UiReady then
		return
	end

	CloseActiveDropdown(true)

	resizing = true
	dirX = gx
	dirY = gy
	activeArc = arc
	startMouse = Vector2.new(input.Position.X, input.Position.Y)
	startSize = WindowSize
	startCenter = Main.AbsolutePosition + Main.AbsoluteSize / 2

	Tween(arc, 0.12, {
		Color = Color.Blue
	})
end

-- gx / gy: which corner (1,1 = bottom right, -1,1 = bottom left ...)
local function MakeGrip(gx, gy)
	local radius = 11
	local margin = 4

	local scaleX = gx == 1 and 1 or 0
	local scaleY = gy == 1 and 1 or 0
	local anchor = Vector2.new(scaleX, scaleY)

	-- clips a big circle so only the quarter hugging the corner is visible
	local container = New("Frame", {
		AnchorPoint = anchor,
		Position = UDim2.new(
			scaleX, gx == 1 and -margin or margin,
			scaleY, gy == 1 and -margin or margin
		),
		Size = UDim2.fromOffset(radius, radius),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, ResizeLayer)

	local circle = New("Frame", {
		Position = UDim2.fromOffset(
			gx == 1 and -radius or 0,
			gy == 1 and -radius or 0
		),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		BackgroundTransparency = 1,
	}, container)

	New("UICorner", {
		CornerRadius = UDim.new(0.5, 0)
	}, circle)

	local arc = New("UIStroke", {
		Color = Color.Border,
		Thickness = 2,
		Transparency = 0.15,
	}, circle)

	local hit = New("TextButton", {
		AnchorPoint = anchor,
		Position = UDim2.new(scaleX, 0, scaleY, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, ResizeLayer)

	Connect(hit.MouseEnter, function()
		if not resizing then
			Tween(arc, 0.12, {
				Color = Color.Blue
			})
		end
	end)

	Connect(hit.MouseLeave, function()
		if not resizing then
			Tween(arc, 0.12, {
				Color = Color.Border
			})
		end
	end)

	Connect(hit.InputBegan, function(input)
		BeginResize(input, gx, gy, arc)
	end)
end

MakeGrip(1, 1)
MakeGrip(-1, 1)
MakeGrip(1, -1)
MakeGrip(-1, -1)

Connect(UIS.InputChanged, function(input)
	if not resizing or not IsPointerMove(input) then
		return
	end

	local delta = Vector2.new(input.Position.X, input.Position.Y) - startMouse
	local screen = Gui.AbsoluteSize

	local width = math.clamp(
		startSize.X + dirX * delta.X,
		MIN_WINDOW.X,
		math.max(MIN_WINDOW.X, screen.X - 24)
	)

	local height = math.clamp(
		startSize.Y + dirY * delta.Y,
		MIN_WINDOW.Y,
		math.max(MIN_WINDOW.Y, screen.Y - 24)
	)

	WindowSize = Vector2.new(width, height)
	Main.Size = UDim2.fromOffset(width, height)

	-- the corner you're NOT dragging stays where it is
	Main.Position = UDim2.fromOffset(
		startCenter.X + dirX * (width - startSize.X) / 2,
		startCenter.Y + dirY * (height - startSize.Y) / 2
	)
end)

Connect(UIS.InputEnded, function(input)
	if not resizing or not IsPointer(input) then
		return
	end

	resizing = false

	if activeArc then
		Tween(activeArc, 0.15, {
			Color = Color.Border
		})

		activeArc = nil
	end
end)

end)

--============================================================
-- MINIMIZE
--============================================================

local MINI_SIZE = UDim2.fromOffset(250, 58)

local function HoverButton(button, normal, hover)
	Connect(button.MouseEnter, function()
		Tween(button, 0.12, {
			BackgroundColor3 = hover
		})
	end)

	Connect(button.MouseLeave, function()
		Tween(button, 0.12, {
			BackgroundColor3 = normal
		})
	end)
end

HoverButton(Minimize, Color.Panel2, Color.Border)
HoverButton(Close, Color.Panel2, Color3.fromRGB(58, 26, 34))

local MiniBar = New("Frame", {
	Name = "MiniBar",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color.Panel,
	BorderSizePixel = 0,
	Visible = false,
}, Main)

Corner(MiniBar, 14)
Connect(MiniBar.InputBegan, BeginWindowDrag)

local MiniIcon = New("Frame", {
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.fromOffset(30, 30),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
}, MiniBar)

Corner(MiniIcon, 8)
Stroke(MiniIcon, Color.Blue, 0.25)

local MiniIconText = New("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "C",
	Font = Enum.Font.GothamBlack,
	TextSize = 16,
	TextColor3 = Color.Blue,
}, MiniIcon)

local MiniTitle = New("TextLabel", {
	Position = UDim2.fromOffset(54, 9),
	Size = UDim2.new(1, -150, 0, 20),
	BackgroundTransparency = 1,
	Text = "CATALYST HUB",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, MiniBar)

local MiniDot = New("Frame", {
	Position = UDim2.fromOffset(54, 34),
	Size = UDim2.fromOffset(6, 6),
	BackgroundColor3 = Color.Green,
	BorderSizePixel = 0,
}, MiniBar)

Corner(MiniDot, 6)

local MiniStatus = New("TextLabel", {
	Position = UDim2.fromOffset(65, 28),
	Size = UDim2.new(1, -150, 0, 18),
	BackgroundTransparency = 1,
	Text = "READY",
	Font = Enum.Font.GothamMedium,
	TextSize = 8,
	TextColor3 = Color.Sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, MiniBar)

local MiniRestore = New("TextButton", {
	Position = UDim2.new(1, -76, 0, 15),
	Size = UDim2.fromOffset(27, 27),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "□",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color.Blue,
	AutoButtonColor = false,
}, MiniBar)

Corner(MiniRestore, 7)
AddPress(MiniRestore)

local MiniClose = New("TextButton", {
	Position = UDim2.new(1, -43, 0, 15),
	Size = UDim2.fromOffset(27, 27),
	BackgroundColor3 = Color.Panel2,
	BorderSizePixel = 0,
	Text = "×",
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = Color.Red,
	AutoButtonColor = false,
}, MiniBar)

Corner(MiniClose, 7)
AddPress(MiniClose)

HoverButton(MiniRestore, Color.Panel2, Color.Border)
HoverButton(MiniClose, Color.Panel2, Color3.fromRGB(58, 26, 34))

-- everything in the mini bar fades in when it appears
local MiniFade = {
	{MiniBar, "BackgroundTransparency", 0},
	{MiniIcon, "BackgroundTransparency", 0},
	{MiniIconText, "TextTransparency", 0},
	{MiniTitle, "TextTransparency", 0},
	{MiniDot, "BackgroundTransparency", 0},
	{MiniStatus, "TextTransparency", 0},
	{MiniRestore, "BackgroundTransparency", 0},
	{MiniRestore, "TextTransparency", 0},
	{MiniClose, "BackgroundTransparency", 0},
	{MiniClose, "TextTransparency", 0},
}

SetMinimized = function(state)
	if Closed or Closing or MinimizeBusy or Minimized == state then
		return
	end

	CloseActiveDropdown(true)

	MinimizeBusy = true
	Minimized = state

	local position = Main.Position

	-- uses the size you resized to, and keeps the top edge in place
	local fullSize = UDim2.fromOffset(WindowSize.X, WindowSize.Y)
	local heightShift = (58 - WindowSize.Y) / 2

	ResizeLayer.Visible = not state

	if state then
		Tween(Main, 0.32, {
			Size = MINI_SIZE,
			Position = UDim2.new(
				position.X.Scale,
				position.X.Offset,
				position.Y.Scale,
				position.Y.Offset + heightShift
			),
		})

		task.delay(0.1, function()
			if Closed or not Minimized then
				return
			end

			Sidebar.Visible = false
			Content.Visible = false
			MiniBar.Visible = true

			for _, item in ipairs(MiniFade) do
				item[1][item[2]] = 1

				Tween(item[1], 0.25, {
					[item[2]] = item[3]
				})
			end
		end)
	else
		MiniBar.Visible = false
		Sidebar.Visible = true
		Content.Visible = true

		Tween(Main, 0.32, {
			Size = fullSize,
			Position = UDim2.new(
				position.X.Scale,
				position.X.Offset,
				position.Y.Scale,
				position.Y.Offset - heightShift
			),
		})
	end

	task.delay(0.34, function()
		MinimizeBusy = false
	end)
end

Connect(Minimize.MouseButton1Click, function()
	SetMinimized(true)
end)

Connect(MiniRestore.MouseButton1Click, function()
	SetMinimized(false)
end)

Connect(MiniClose.MouseButton1Click, function()
	if CloseMenu then
		CloseMenu()
	end
end)

--============================================================
-- PERMANENT CLOSE
--============================================================

local function Shutdown()
	if Closed then
		return
	end

	Closed = true
	ListeningForKey = false
	Minimized = false

	Config.Fly = false
	Config.FlyJump = false

	DestroyFlightObjects()

	if Humanoid and Humanoid.Parent then
		Humanoid.PlatformStand = false
		Humanoid.AutoRotate = true
		Humanoid.WalkSpeed = Config.WalkSpeed
		Humanoid.UseJumpPower = true
		Humanoid.JumpPower = Config.JumpPower

		pcall(function()
			Humanoid:ChangeState(
				Enum.HumanoidStateType.GettingUp
			)
		end)
	end

	RestoreCollision()
	RestoreAllHitboxes()
	RestoreFOV()

	DisconnectEverything()

	if PartAddedConnection then
		PartAddedConnection:Disconnect()
		PartAddedConnection = nil
	end

	pcall(function()
		RunService:UnbindFromRenderStep(FLIGHT_BIND)
	end)

	if Character then
		for _, object in ipairs(Character:GetDescendants()) do
			if FlightObjectNames[object.Name] then
				object:Destroy()
			end
		end
	end

	if BootGui and BootGui.Parent then
		BootGui:Destroy()
	end

	if Gui and Gui.Parent then
		Gui:Destroy()
	end
end

-- shrinks away, then shuts everything down
CloseMenu = function()
	if Closed or Closing then
		return
	end

	Closing = true

	if SetKeybindPanel then
		SetKeybindPanel(false)
	end

	if MainScale and MainScale.Parent then
		TweenService:Create(
			MainScale,
			TweenInfo.new(
				0.25,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.In
			),
			{
				Scale = 0.01
			}
		):Play()
	end

	Tween(Main, 0.25, {
		GroupTransparency = 1
	})

	task.delay(0.27, Shutdown)
end

Connect(Close.MouseButton1Click, CloseMenu)

--============================================================
-- RESPAWN
--============================================================

Connect(Player.CharacterAdded, function(character)
	if Closed then
		return
	end

	StopFlight()
	RestoreCollision()
	LoadCharacter(character)

	Config.Fly = false
	Config.Noclip = false
	Config.FlyJump = false

	if FlyToggle then
		FlyToggle.Set(false, true)
	end

	if NoclipToggle then
		NoclipToggle.Set(false, true)
	end

	if FlyJumpToggle then
		FlyJumpToggle.Set(false, true)
	end

	if CharacterStatus then
		CharacterStatus.Text = "READY"
	end
end)

--============================================================
-- STATUS
--============================================================

Connect(RunService.Heartbeat, function(dt)
	if Closed then
		return
	end

	-- FPS / ping, refreshed twice a second
	FrameAverage = FrameAverage * 0.9 + dt * 0.1
	StatTimer += dt

	if StatTimer >= 0.5 then
		StatTimer = 0

		if FpsStatus then
			FpsStatus.Text = tostring(math.floor(1 / math.max(FrameAverage, 0.0001) + 0.5))
		end

		if PingStatus then
			local ok, ping = pcall(function()
				return Player:GetNetworkPing()
			end)

			PingStatus.Text = ok and (tostring(math.floor(ping * 1000 + 0.5)) .. " MS") or "--"
		end
	end

	if Config.Hitbox then
		UpdateHitboxes()
	end

	-- keep every key chip in sync (e.g. after you rebind the fly key)
	for _, chip in ipairs(KeybindChips) do
		local text = chip.Get()

		if chip.Label.Text ~= text then
			chip.Label.Text = text
		end
	end

	if CharacterStatus then
		if Character and Humanoid and Humanoid.Health > 0 then
			CharacterStatus.Text = "READY"
		else
			CharacterStatus.Text = "WAITING"
		end
	end

	if SpeedStatus then
		SpeedStatus.Text = tostring(Config.FlySpeed)
	end

	if Minimized then
		MiniStatus.Text = Config.Fly and "FLYING" or "READY"
		MiniDot.BackgroundColor3 = Config.Fly and Color.Blue or Color.Green
	end
end)

--============================================================
-- SELECT DASHBOARD
--============================================================

SelectTab("Dashboard")

--============================================================
-- BOOT
--============================================================

task.spawn(function()
	local booted, bootError = xpcall(function()

	local stages = {
		{"INITIALIZING CORE...", 15},
		{"LOADING MOVEMENT ENGINE...", 35},
		{"LOADING INTERFACE...", 58},
		{"CONNECTING CONTROLS...", 78},
		{"FINALIZING...", 94},
		{"READY", 100},
	}

	for _, stage in ipairs(stages) do
		if Closed or not BootGui.Parent then
			return
		end

		BootStatus.Text = stage[1]

		Tween(BootBar, 0.3, {
			Size = UDim2.new(
				stage[2] / 100,
				0,
				1,
				0
			)
		})

		local current = tonumber(
			string.match(BootPercent.Text, "%d+")
		) or 0

		for number = current, stage[2] do
			if Closed or not BootGui.Parent then
				return
			end

			BootPercent.Text = tostring(number) .. "%"
			task.wait(0.008)
		end

		task.wait(0.12)
	end

	task.wait(0.3)

	if Closed or not BootGui.Parent then
		return
	end

	-- menu pops in as the boot screen fades out
	Tween(Main, 0.45, {
		GroupTransparency = 0
	})

	TweenService:Create(
		MainScale,
		TweenInfo.new(
			0.55,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{
			Scale = 1
		}
	):Play()

	Tween(Boot, 0.4, {
		BackgroundTransparency = 1
	})

	for _, object in ipairs(BootCenter:GetDescendants()) do
		if object:IsA("TextLabel") then
			Tween(object, 0.3, {
				TextTransparency = 1
			})
		elseif object:IsA("Frame") then
			Tween(object, 0.3, {
				BackgroundTransparency = 1
			})
		elseif object:IsA("UIStroke") then
			Tween(object, 0.3, {
				Transparency = 1
			})
		end
	end

	task.wait(0.45)

	if BootGui and BootGui.Parent then
		BootGui:Destroy()
	end

	UiReady = true

	Toast(
		"CATALYST HUB",
		string.upper(Config.MenuKey.Name) .. " minimizes  -  " .. string.upper(Config.KeybindKey.Name) .. " keybinds",
		Color.Blue
	)
	end, debug.traceback)

	if not booted then
		ReportError("Boot", bootError)

		-- never leave the hub hidden behind a broken boot screen
		MainScale.Scale = 1
		Main.GroupTransparency = 0
		UiReady = true

		if BootGui and BootGui.Parent then
			BootGui:Destroy()
		end
	end
end)

print("[CATALYST HUB] loaded - P minimizes, L opens the keybinds")

end

local started, startupError = xpcall(Main, debug.traceback)

if not started then
	ReportError("startup", startupError)
end
