local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Types = require(script.Types)

export type SlotData = Types.SlotData
export type MatchSession = Types.MatchSession
export type PadConfig = Types.PadConfig
export type QueueState = Types.QueueState

local PvpMatchmaking = {}
PvpMatchmaking.__index = PvpMatchmaking

-- Internal Remotes
local remotesFolder: Folder? = nil
local queueUpdatedRemote: RemoteEvent? = nil
local leaveQueueRemote: RemoteEvent? = nil
local requestVsAiRemote: RemoteEvent? = nil

local function getOrCreateRemotes()
	if remotesFolder then return end

	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local function ensureRemote(name: string): RemoteEvent
		local r = remotesFolder:FindFirstChild(name) :: RemoteEvent?
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = remotesFolder
		end
		return r
	end

	queueUpdatedRemote = ensureRemote("QueueUpdated")
	leaveQueueRemote = ensureRemote("LeaveQueue")
	requestVsAiRemote = ensureRemote("RequestVsAi")
end

-- Active sessions by Pad instance
local padSessions: { [Instance]: any } = {}
local playerToPad: { [Player]: Instance } = {}

-- Signals
local onMatchReadyCallbacks: { (MatchSession) -> () } = {}
local onMatchCancelledCallbacks: { (MatchSession) -> () } = {}
local onMatchEndedCallbacks: { (MatchSession, number?) -> () } = {}

function PvpMatchmaking.OnMatchReady(callback: (MatchSession) -> ())
	table.insert(onMatchReadyCallbacks, callback)
end

function PvpMatchmaking.OnMatchCancelled(callback: (MatchSession) -> ())
	table.insert(onMatchCancelledCallbacks, callback)
end

function PvpMatchmaking.OnMatchEnded(callback: (MatchSession, number?) -> ())
	table.insert(onMatchEndedCallbacks, callback)
end

-- Helper to snap player onto slot
local function snapPlayerToSlot(player: Player, pad: Instance, slotNum: number)
	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	local targetPadName = (slotNum == 1) and "PinkPad" or "BluePad"
	local targetPad = pad:FindFirstChild(targetPadName) :: BasePart?
	if not targetPad then return end

	local spawnPos = targetPad.Position + Vector3.new(0, 3.2, 0)
	local lookTarget = spawnPos + Vector3.new(0, 0, -30)

	hrp.CFrame = CFrame.lookAt(spawnPos, lookTarget)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
end

-- Helper to release player from pad
local function releasePlayerFromSlot(player: Player, pushBack: boolean)
	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end

	if pushBack and hrp then
		hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, 4)
	end
end

-- Update Display Board UI
local function updateBoard(session: any)
	local pad = session.pad
	local displayBoard = pad:FindFirstChild("DisplayBoard") or pad:FindFirstChild("StatusAnchor")
	if not displayBoard then return end

	local gui = displayBoard:FindFirstChildOfClass("SurfaceGui") or displayBoard:FindFirstChildOfClass("BillboardGui")
	if not gui then return end

	local board = gui:FindFirstChild("BoardFrame")
	if not board then return end

	local slot1 = session.slot1
	local slot2 = session.slot2
	local state = session.state

	local count = 0
	if slot1 then count += 1 end
	if slot2 then count += 1 end

	-- Slot 1
	local slot1Frame = board:FindFirstChild("Slot1Frame")
	if slot1Frame then
		local avatar = slot1Frame:FindFirstChild("Avatar") :: ImageLabel?
		local nameLabel = slot1Frame:FindFirstChild("NameLabel") :: TextLabel?
		if slot1 then
			if nameLabel then nameLabel.Text = slot1.name end
			if avatar then
				if slot1.player then
					avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", slot1.player.UserId)
					avatar.ImageTransparency = 0
				else
					avatar.Image = "rbxassetid://10850239016"
					avatar.ImageTransparency = 0
				end
			end
		else
			if nameLabel then nameLabel.Text = "Waiting..." end
			if avatar then
				avatar.Image = ""
				avatar.ImageTransparency = 1
			end
		end
	end

	-- Slot 2
	local slot2Frame = board:FindFirstChild("Slot2Frame")
	if slot2Frame then
		local avatar = slot2Frame:FindFirstChild("Avatar") :: ImageLabel?
		local nameLabel = slot2Frame:FindFirstChild("NameLabel") :: TextLabel?
		if slot2 then
			if nameLabel then nameLabel.Text = slot2.name end
			if avatar then
				if slot2.player then
					avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", slot2.player.UserId)
					avatar.ImageTransparency = 0
				else
					avatar.Image = "rbxassetid://10850239016"
					avatar.ImageTransparency = 0
				end
			end
		else
			if nameLabel then nameLabel.Text = "Waiting For Opponent" end
			if avatar then
				avatar.Image = ""
				avatar.ImageTransparency = 1
			end
		end
	end

	-- Bottom Count
	local bottomFrame = board:FindFirstChild("BottomFrame")
	if bottomFrame then
		local countLabel = bottomFrame:FindFirstChild("CountLabel") :: TextLabel?
		if countLabel then
			if state == "InMatch" then
				countLabel.Text = "BATTLE IN PROGRESS"
				countLabel.TextColor3 = Color3.fromRGB(255, 75, 95)
			elseif state == "Starting" then
				countLabel.Text = "MATCH STARTING..."
				countLabel.TextColor3 = Color3.fromRGB(0, 229, 255)
			elseif count == 0 then
				countLabel.Text = "0/2 PLAYERS"
				countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			elseif count == 1 then
				countLabel.Text = "1/2 PLAYERS"
				countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			elseif count == 2 then
				countLabel.Text = "2/2 STARTING MATCH!"
				countLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
			end
		end
	end

	-- ProximityPrompts
	local pinkPad = pad:FindFirstChild("PinkPad")
	if pinkPad then
		local prompt = pinkPad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = (slot1 == nil) and (state == "Waiting")
		end
	end

	local bluePad = pad:FindFirstChild("BluePad")
	if bluePad then
		local prompt = bluePad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = (slot2 == nil) and (state == "Waiting")
		end
	end
end

-- Trigger match start
local function triggerMatchStart(session: any)
	if session.state ~= "Waiting" then return end
	session.state = "Starting"
	updateBoard(session)

	if session.slot1 and session.slot1.player then
		queueUpdatedRemote:FireClient(session.slot1.player, { inQueue = false })
	end
	if session.slot2 and session.slot2.player then
		queueUpdatedRemote:FireClient(session.slot2.player, { inQueue = false })
	end

	for _, cb in ipairs(onMatchReadyCallbacks) do
		task.spawn(cb, session)
	end
end

-- Register a Matchmaking Pad
function PvpMatchmaking.RegisterPad(pad: Instance, config: PadConfig?): MatchSession
	getOrCreateRemotes()

	local session = {
		id = pad.Name .. "_" .. tostring(math.random(1000, 9999)),
		pad = pad,
		slot1 = nil :: SlotData?,
		slot2 = nil :: SlotData?,
		state = "Waiting" :: QueueState,
		data = {},
	}

	function session:FinishMatch(winnerSlot: number?)
		session.state = "Waiting"
		if session.slot1 and session.slot1.player then
			playerToPad[session.slot1.player] = nil
			releasePlayerFromSlot(session.slot1.player, true)
		end
		if session.slot2 and session.slot2.player then
			playerToPad[session.slot2.player] = nil
			releasePlayerFromSlot(session.slot2.player, true)
		end

		session.slot1 = nil
		session.slot2 = nil
		updateBoard(session)

		for _, cb in ipairs(onMatchEndedCallbacks) do
			task.spawn(cb, session, winnerSlot)
		end
	end

	function session:CancelMatch()
		session.state = "Waiting"
		if session.slot1 and session.slot1.player then
			playerToPad[session.slot1.player] = nil
			releasePlayerFromSlot(session.slot1.player, true)
			queueUpdatedRemote:FireClient(session.slot1.player, { inQueue = false })
		end
		if session.slot2 and session.slot2.player then
			playerToPad[session.slot2.player] = nil
			releasePlayerFromSlot(session.slot2.player, true)
			queueUpdatedRemote:FireClient(session.slot2.player, { inQueue = false })
		end

		session.slot1 = nil
		session.slot2 = nil
		updateBoard(session)

		for _, cb in ipairs(onMatchCancelledCallbacks) do
			task.spawn(cb, session)
		end
	end

	padSessions[pad] = session

	local function onPlayerJoined(player: Player, slotNum: number)
		if session.state ~= "Waiting" then return end

		if slotNum == 1 then
			if session.slot1 and session.slot1.player == player then return end
			if session.slot2 and session.slot2.player == player then
				releasePlayerFromSlot(player, false)
				session.slot2 = nil
			end
			session.slot1 = {
				player = player,
				userId = player.UserId,
				isBot = false,
				name = player.DisplayName or player.Name,
				hearts = 3,
			}
		elseif slotNum == 2 then
			if session.slot2 and session.slot2.player == player then return end
			if session.slot1 and session.slot1.player == player then
				releasePlayerFromSlot(player, false)
				session.slot1 = nil
			end
			session.slot2 = {
				player = player,
				userId = player.UserId,
				isBot = false,
				name = player.DisplayName or player.Name,
				hearts = 3,
			}
		end

		playerToPad[player] = pad
		snapPlayerToSlot(player, pad, slotNum)
		updateBoard(session)
		queueUpdatedRemote:FireClient(player, { inQueue = true, slot = slotNum })

		if session.slot1 and session.slot2 then
			triggerMatchStart(session)
		end
	end

	-- Configure Pink Pad Prompt
	local pinkPad = pad:FindFirstChild("PinkPad")
	if pinkPad then
		local prompt = pinkPad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.HoldDuration = 0
			prompt.ActionText = "Join"
			prompt.ObjectText = "Pink Slot"
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 10
			prompt.Triggered:Connect(function(player)
				onPlayerJoined(player, 1)
			end)
		end
	end

	-- Configure Blue Pad Prompt
	local bluePad = pad:FindFirstChild("BluePad")
	if bluePad then
		local prompt = bluePad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.HoldDuration = 0
			prompt.ActionText = "Join"
			prompt.ObjectText = "Blue Slot"
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 10
			prompt.Triggered:Connect(function(player)
				onPlayerJoined(player, 2)
			end)
		end
	end

	updateBoard(session)
	return session
end

-- Initialize Module
function PvpMatchmaking.Init()
	getOrCreateRemotes()

	-- Handle Leave Queue Remote
	leaveQueueRemote.OnServerEvent:Connect(function(player: Player)
		local pad = playerToPad[player]
		if not pad then return end

		local session = padSessions[pad]
		if not session or session.state ~= "Waiting" then return end

		if session.slot1 and session.slot1.player == player then
			session.slot1 = nil
			playerToPad[player] = nil
			releasePlayerFromSlot(player, true)
			queueUpdatedRemote:FireClient(player, { inQueue = false })
			updateBoard(session)
		elseif session.slot2 and session.slot2.player == player then
			session.slot2 = nil
			playerToPad[player] = nil
			releasePlayerFromSlot(player, true)
			queueUpdatedRemote:FireClient(player, { inQueue = false })
			updateBoard(session)
		end
	end)

	-- Handle VS AI Remote
	requestVsAiRemote.OnServerEvent:Connect(function(player: Player)
		local pad = playerToPad[player]
		if not pad then return end

		local session = padSessions[pad]
		if not session or session.state ~= "Waiting" then return end

		if session.slot1 and session.slot1.player == player and not session.slot2 then
			session.slot2 = {
				player = nil,
				userId = 0,
				isBot = true,
				name = "Cyber Bot [AI]",
				hearts = 3,
			}
			triggerMatchStart(session)
		elseif session.slot2 and session.slot2.player == player and not session.slot1 then
			session.slot1 = {
				player = nil,
				userId = 0,
				isBot = true,
				name = "Titan Bot [AI]",
				hearts = 3,
			}
			triggerMatchStart(session)
		end
	end)

	-- Handle Disconnection Cleanup
	Players.PlayerRemoving:Connect(function(player: Player)
		local pad = playerToPad[player]
		if not pad then return end

		local session = padSessions[pad]
		if not session then return end

		playerToPad[player] = nil

		if session.state == "InMatch" then
			session:FinishMatch(nil)
		elseif session.state == "Starting" then
			session:CancelMatch()
		elseif session.state == "Waiting" then
			if session.slot1 and session.slot1.player == player then
				releasePlayerFromSlot(player, false)
				session.slot1 = nil
			end
			if session.slot2 and session.slot2.player == player then
				releasePlayerFromSlot(player, false)
				session.slot2 = nil
			end
			updateBoard(session)
		end
	end)

	-- Auto-register any tagged pads
	for _, pad in ipairs(CollectionService:GetTagged("PvpMatchmakingPad")) do
		PvpMatchmaking.RegisterPad(pad)
	end

	CollectionService:GetInstanceAddedSignal("PvpMatchmakingPad"):Connect(function(pad)
		PvpMatchmaking.RegisterPad(pad)
	end)

	print("[PvpMatchmakingModule] Matchmaking service initialized successfully!")
end

return PvpMatchmaking
