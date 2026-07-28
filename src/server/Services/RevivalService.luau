--!strict
--[[
	RevivalService.luau
	--------------------------------------------------------------------------
	Nobody dies instantly in Dolly's Home. Reaching zero health puts you down
	with thirty seconds on the clock, and a teammate holding E for three seconds
	brings you back at half health. If nobody comes, you're out for the round.

	A downed player is a decision problem for the whole team: three people
	sprinting to a rescue is three noise meters climbing at once.

	Note that players never actually reach Humanoid.Health == 0 -- health is
	pinned at 1 while downed. Letting the Humanoid die would tear down the
	character model and Roblox would respawn them, which is not what "downed"
	means here.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local NoiseService = require(script.Parent.NoiseService)
local TeamService = require(script.Parent.TeamService)

local RevivalService = {}

type DownRecord = {
	Player: Player,
	DownedAt: number,
	ExpiresAt: number,
	Prompt: ProximityPrompt?,
	Highlight: Highlight?,
	Billboard: BillboardGui?,
	Thread: thread?,
	DownedBy: string?,
}

local downed: { [Player]: DownRecord } = {}
local immuneUntil: { [Player]: number } = {}
local reviving: { [Player]: Player } = {} -- target -> reviver

-- Round-scoped callback so GameStateManager can react to a wipe without
-- RevivalService having to know the round loop exists.
local onRosterChanged: (() -> ())? = nil

--==========================================================================
-- Queries
--==========================================================================

function RevivalService.isDowned(player: Player): boolean
	return downed[player] ~= nil
end

function RevivalService.getRemaining(player: Player): number
	local record = downed[player]
	if not record then
		return 0
	end
	return math.max(0, record.ExpiresAt - Util.now())
end

function RevivalService.setRosterChangedCallback(callback: (() -> ())?)
	onRosterChanged = callback
end

local function notifyRosterChanged()
	if onRosterChanged then
		task.spawn(onRosterChanged)
	end
end

--==========================================================================
-- Damage
--==========================================================================

--[[
	The single entry point for hurting a player. Everything -- killer swipes,
	traps, falls -- routes through here so the downed state can never be
	bypassed.
]]
function RevivalService.applyDamage(player: Player, amount: number, sourceName: string?)
	if amount <= 0 then
		return
	end
	if not TeamService.isAlive(player) then
		return
	end
	if (immuneUntil[player] or 0) > Util.now() then
		return
	end

	local _, humanoid = Util.getCharacterParts(player)
	if not humanoid then
		return
	end

	local remaining = humanoid.Health - amount
	if remaining > 1 then
		humanoid.Health = remaining
		Net.fire(player, "Announce", { Kind = "Hurt", Text = "", Amount = amount })
		return
	end

	humanoid.Health = 1
	RevivalService.down(player, sourceName)
end

function RevivalService.heal(player: Player, amount: number)
	local _, humanoid = Util.getCharacterParts(player)
	if not humanoid or downed[player] then
		return
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
end

function RevivalService.fullHeal(player: Player)
	local _, humanoid = Util.getCharacterParts(player)
	if not humanoid then
		return
	end
	if downed[player] then
		RevivalService.revive(nil, player)
		return
	end
	humanoid.Health = humanoid.MaxHealth
end

--==========================================================================
-- Down
--==========================================================================

local function buildDownedUI(player: Player, record: DownRecord)
	local character, _, root = Util.getCharacterParts(player)
	if not character or not root then
		return
	end

	-- Visible through walls to teammates -- the design doc's "wounded symbol
	-- visible through walls".
	local highlight = Instance.new("Highlight")
	highlight.Name = "InjuredHighlight"
	highlight.FillColor = Color3.fromRGB(200, 40, 40)
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Color3.fromRGB(255, 110, 110)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	record.Highlight = highlight

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "InjuredBillboard"
	billboard.Size = UDim2.fromScale(9, 2.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Parent = character
	record.Billboard = billboard

	local label = Instance.new("TextLabel")
	label.Name = "Countdown"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 120, 120)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Text = "INJURED"
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = Config.Revival.ReviveHoldSeconds
	prompt.MaxActivationDistance = Config.Revival.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	record.Prompt = prompt

	prompt.PromptButtonHoldBegan:Connect(function(reviver)
		if TeamService.isAlive(reviver) then
			reviving[player] = reviver
			-- Kneeling to revive is not quiet.
			NoiseService.addOverTime(reviver, Config.Noise.Actions.Revive, Config.Revival.ReviveHoldSeconds, "revive")
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(reviver)
		if reviving[player] == reviver then
			reviving[player] = nil
		end
	end)
	prompt.Triggered:Connect(function(reviver)
		RevivalService.revive(reviver, player)
	end)

	-- Live countdown on the billboard.
	task.spawn(function()
		while downed[player] == record and billboard.Parent do
			local remaining = math.ceil(RevivalService.getRemaining(player))
			label.Text = `INJURED  -  {remaining}s`
			label.TextColor3 = remaining <= 10 and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 150, 120)
			task.wait(0.25)
		end
	end)
end

function RevivalService.down(player: Player, sourceName: string?)
	if downed[player] or not TeamService.isInRound(player) then
		return
	end

	local character, humanoid, root = Util.getCharacterParts(player)
	if not character or not humanoid or not root then
		return
	end

	-- Hiding doesn't survive being downed.
	local HidingService = require(script.Parent.HidingService)
	if HidingService.isHidden(player) then
		HidingService.forceOut(player)
	end

	humanoid.Health = 1
	humanoid.WalkSpeed = Config.Revival.CrawlSpeed
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local record: DownRecord = {
		Player = player,
		DownedAt = Util.now(),
		ExpiresAt = Util.now() + Config.Revival.BleedOutSeconds,
		DownedBy = sourceName,
	}
	downed[player] = record

	player:SetAttribute(StateKeys.Player.Injured, true)
	player:SetAttribute(StateKeys.Player.Alive, false)
	player:SetAttribute(StateKeys.Player.ReviveEndsAt, record.ExpiresAt)

	buildDownedUI(player, record)
	NoiseService.reset(player)

	Net.fireAll("InjuredAlert", {
		Kind = "Downed",
		UserId = player.UserId,
		Name = player.DisplayName,
		Position = root.Position,
		ExpiresAt = record.ExpiresAt,
		By = sourceName,
	})

	Util.log("RevivalService", "%s downed by %s", player.Name, sourceName or "?")
	notifyRosterChanged()

	-- Bleed-out timer.
	record.Thread = task.spawn(function()
		while downed[player] == record do
			if Util.now() >= record.ExpiresAt then
				RevivalService.eliminate(player)
				return
			end
			task.wait(0.25)
		end
	end)
end

--==========================================================================
-- Revive
--==========================================================================

local function teardownDownedUI(record: DownRecord)
	if record.Prompt then
		record.Prompt:Destroy()
	end
	if record.Highlight then
		record.Highlight:Destroy()
	end
	if record.Billboard then
		record.Billboard:Destroy()
	end
end

--- `reviver` may be nil for a self-revive (health potion).
function RevivalService.revive(reviver: Player?, target: Player): boolean
	local record = downed[target]
	if not record then
		return false
	end
	if reviver and not TeamService.isAlive(reviver) then
		return false
	end

	-- Verify the reviver is actually next to them. ProximityPrompt already
	-- enforces this, but a forged remote wouldn't.
	if reviver then
		local reviverPos = Util.getPosition(reviver)
		local targetPos = Util.getPosition(target)
		if not reviverPos or not targetPos then
			return false
		end
		if (reviverPos - targetPos).Magnitude > Config.Revival.ReviveRange + 4 then
			return false
		end
	end

	downed[target] = nil
	reviving[target] = nil
	teardownDownedUI(record)

	local _, humanoid = Util.getCharacterParts(target)
	if humanoid then
		humanoid.Health = math.max(1, humanoid.MaxHealth * Config.Revival.ReviveHealthPercent)
		humanoid.WalkSpeed = Config.Player.WalkSpeed
		humanoid.JumpPower = Config.Player.JumpPower
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	target:SetAttribute(StateKeys.Player.Injured, false)
	target:SetAttribute(StateKeys.Player.Alive, true)
	target:SetAttribute(StateKeys.Player.ReviveEndsAt, 0)

	local immunityEnd = Util.now() + Config.Revival.PostReviveImmunitySeconds
	immuneUntil[target] = immunityEnd
	if reviver then
		immuneUntil[reviver] = immunityEnd
		local count = (reviver:GetAttribute(StateKeys.Player.RoundRevives) or 0) :: number
		reviver:SetAttribute(StateKeys.Player.RoundRevives, count + 1)
	end

	Net.fireAll("InjuredAlert", {
		Kind = "Revived",
		UserId = target.UserId,
		Name = target.DisplayName,
		ReviverName = reviver and reviver.DisplayName or nil,
	})

	Util.log("RevivalService", "%s revived by %s", target.Name, reviver and reviver.Name or "self")
	notifyRosterChanged()
	return true
end

--==========================================================================
-- Eliminate
--==========================================================================

function RevivalService.eliminate(player: Player)
	local record = downed[player]
	if record then
		downed[player] = nil
		reviving[player] = nil
		teardownDownedUI(record)
	end

	if not TeamService.isInRound(player) then
		return
	end

	TeamService.exitRound(player, true)

	local _, humanoid = Util.getCharacterParts(player)
	if humanoid then
		humanoid.WalkSpeed = Config.Player.WalkSpeed
		humanoid.JumpPower = Config.Player.JumpPower
		humanoid.Health = humanoid.MaxHealth
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	NoiseService.reset(player)

	Net.fireAll("InjuredAlert", {
		Kind = "Eliminated",
		UserId = player.UserId,
		Name = player.DisplayName,
	})

	-- MapService is required lazily: RevivalService is loaded before the map
	-- exists, and a top-level require would fix the load order unnecessarily.
	local MapService = require(script.Parent.MapService)
	local spawns = MapService.getLobbySpawns()
	local destination = spawns[math.random(1, math.max(1, #spawns))]
	if destination then
		local character = player.Character
		if character and character.PrimaryPart then
			character:PivotTo(destination)
		end
	end

	Util.log("RevivalService", "%s eliminated", player.Name)
	notifyRosterChanged()
end

--- Clears every downed state without eliminating anyone (round ended).
function RevivalService.clearAll()
	for player, record in downed do
		teardownDownedUI(record)
		downed[player] = nil
		player:SetAttribute(StateKeys.Player.Injured, false)
		player:SetAttribute(StateKeys.Player.ReviveEndsAt, 0)

		local _, humanoid = Util.getCharacterParts(player)
		if humanoid then
			humanoid.WalkSpeed = Config.Player.WalkSpeed
			humanoid.JumpPower = Config.Player.JumpPower
			humanoid.Health = humanoid.MaxHealth
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
	table.clear(reviving)
	table.clear(immuneUntil)
end

--==========================================================================
-- Lifecycle
--==========================================================================

function RevivalService.start()
	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if not humanoid then
			return
		end

		humanoid.MaxHealth = Config.Player.MaxHealth
		humanoid.Health = Config.Player.MaxHealth
		humanoid.WalkSpeed = Config.Player.WalkSpeed
		humanoid.JumpPower = Config.Player.JumpPower
		humanoid.UseJumpPower = true
		humanoid.BreakJointsOnDeath = false

		-- Safety net: anything that drains health without going through
		-- applyDamage (falling, a stray script) still results in a down rather
		-- than a death.
		humanoid.HealthChanged:Connect(function(health)
			if health <= 0.5 and TeamService.isAlive(player) and not downed[player] then
				humanoid.Health = 1
				RevivalService.down(player, "the house")
			end
		end)

		humanoid.Died:Connect(function()
			if TeamService.isInRound(player) then
				RevivalService.eliminate(player)
			end
		end)
	end

	local function onPlayer(player: Player)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			task.spawn(watchCharacter, player, character)
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local record = downed[player]
		if record then
			teardownDownedUI(record)
			downed[player] = nil
		end
		immuneUntil[player] = nil
		reviving[player] = nil
		notifyRosterChanged()
	end)
end

return RevivalService
