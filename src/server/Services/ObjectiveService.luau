--!strict
--[[
	ObjectiveService.luau
	--------------------------------------------------------------------------
	Spawns the round's tasks, tracks shared progress, and tells everyone when
	something lands.

	Every objective is TEAM-BASED: one player picking up a potion moves the
	whole team's counter. Individual contribution is still tracked per player
	(for the end-of-round ranking), but it never gates the win.

	Progress replicates through Configuration instances under
	ReplicatedStorage.DollysHome.State.Objectives -- one child per active
	objective, with Current/Goal/Complete attributes. The HUD just reads those.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ObjectiveData = require(Shared.ObjectiveData)
local StateKeys = require(Shared.StateKeys)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local MapService = require(script.Parent.MapService)
local NoiseService = require(script.Parent.NoiseService)
local Props = require(script.Parent.Parent.Build.Props)
local TeamService = require(script.Parent.TeamService)

local ObjectiveService = {}

local ITEMS_FOLDER_NAME = "TaskItems"

type ObjectiveState = {
	Def: ObjectiveData.ObjectiveDef,
	Current: number,
	Goal: number,
	Complete: boolean,
	Config: Configuration,
	Extra: { [string]: any },
}

local active: { [string]: ObjectiveState } = {}
local order: { string } = {}
local usedSpawns: { [BasePart]: boolean } = {}
local spinners: { Instance } = {}
local spinConnection: RBXScriptConnection? = nil
local roundActive = false
local rng = Random.new()

local onAllComplete: (() -> ())? = nil

local ITEM_STYLE = {
	Potion = { Color = Color3.fromRGB(120, 220, 180), Size = Vector3.new(1.4, 2.2, 1.4), Label = "Potion" },
	Mirror = { Color = Color3.fromRGB(190, 220, 235), Size = Vector3.new(1.8, 2.2, 0.3), Label = "Mirror Fragment" },
	Cross = { Color = Color3.fromRGB(230, 210, 150), Size = Vector3.new(1.2, 2.4, 0.4), Label = "Blessed Cross" },
	Ingredient = { Color = Color3.fromRGB(220, 120, 120), Size = Vector3.new(1.6, 1.8, 1.6), Label = "Ingredient" },
}

--==========================================================================
-- Replication helpers
--==========================================================================

local function itemsFolder(): Folder
	local folder = Workspace:FindFirstChild(ITEMS_FOLDER_NAME) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ITEMS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function publish(state: ObjectiveState)
	state.Config:SetAttribute(StateKeys.Objective.Current, state.Current)
	state.Config:SetAttribute(StateKeys.Objective.Goal, state.Goal)
	state.Config:SetAttribute(StateKeys.Objective.Complete, state.Complete)
end

local function setDetail(state: ObjectiveState, detail: string)
	state.Config:SetAttribute(StateKeys.Objective.Detail, detail)
end

--==========================================================================
-- Progress
--==========================================================================

local function checkAllComplete()
	if not roundActive then
		return
	end
	for _, state in active do
		if not state.Complete then
			return
		end
	end
	roundActive = false
	if onAllComplete then
		task.spawn(onAllComplete)
	end
end

local function creditPlayer(player: Player?)
	if not player then
		return
	end
	local current = (player:GetAttribute(StateKeys.Player.RoundTasks) or 0) :: number
	player:SetAttribute(StateKeys.Player.RoundTasks, current + 1)
end

--- Advances an objective and tells everyone about it.
local function advance(objectiveId: string, amount: number, player: Player?)
	local state = active[objectiveId]
	if not state or state.Complete then
		return
	end

	state.Current = math.min(state.Goal, state.Current + amount)
	creditPlayer(player)

	local justCompleted = state.Current >= state.Goal
	if justCompleted then
		state.Complete = true
	end
	publish(state)

	Net.fireAll("TaskProgress", {
		Id = objectiveId,
		Label = state.Def.ShortLabel,
		Current = state.Current,
		Goal = state.Goal,
		Complete = state.Complete,
		By = player and player.DisplayName or nil,
	})

	if justCompleted then
		Net.fireAll("TaskCompleted", {
			Id = objectiveId,
			Label = state.Def.Label,
			ShortLabel = state.Def.ShortLabel,
		})
		Util.log("ObjectiveService", "%s complete", objectiveId)
		checkAllComplete()
	end
end

ObjectiveService.advance = advance

--==========================================================================
-- Spawn point allocation
--==========================================================================

--- A task spawn point that isn't already holding something, preferring points
--- far from `avoid` so items don't cluster.
local function claimSpawn(taskType: string, avoid: Vector3?): BasePart?
	local candidates = {}
	for _, spawnPoint in MapService.getTaskSpawns(taskType) do
		if not usedSpawns[spawnPoint] then
			table.insert(candidates, spawnPoint)
		end
	end
	if #candidates == 0 then
		return nil
	end

	Util.shuffle(candidates, rng)

	if avoid then
		table.sort(candidates, function(a, b)
			return (a.Position - avoid).Magnitude > (b.Position - avoid).Magnitude
		end)
		-- Take from the far half, at random, so it's spread but not predictable.
		local cut = math.max(1, math.floor(#candidates / 2))
		local chosen = candidates[rng:NextInteger(1, cut)]
		usedSpawns[chosen] = true
		return chosen
	end

	local chosen = candidates[1]
	usedSpawns[chosen] = true
	return chosen
end

local function releaseSpawn(spawnPoint: BasePart?)
	if spawnPoint then
		usedSpawns[spawnPoint] = nil
	end
end

--==========================================================================
-- Collectible items
--==========================================================================

--- Builds the actual modelled pickup for a task type, falling back to a plain
--- glowing block for anything without a builder.
local function buildPickup(kind: string, position: Vector3): BasePart
	local builder = ({
		Potion = Props.potionBottle,
		Cross = Props.crossProp,
		Mirror = Props.mirrorShard,
	})[kind]

	if builder then
		local built = builder()
		built.Name = `TaskItem_{kind}`
		built.Parent = itemsFolder()
		built:PivotTo(CFrame.new(position))
		local anchor = built.PrimaryPart :: BasePart
		-- A light on the pickup itself, so it reads across a dark room.
		local style = ITEM_STYLE[kind] or ITEM_STYLE.Potion
		local light = Instance.new("PointLight")
		light.Color = style.Color
		light.Brightness = 1.1
		light.Range = 12
		light.Parent = anchor
		return anchor
	end

	local style = ITEM_STYLE[kind] or ITEM_STYLE.Potion
	local item = Instance.new("Part")
	item.Name = `TaskItem_{kind}`
	item.Size = style.Size
	item.Color = style.Color
	item.Material = Enum.Material.Neon
	item.Anchored = true
	item.CanCollide = false
	item.CFrame = CFrame.new(position)
	item.Parent = itemsFolder()

	local light = Instance.new("PointLight")
	light.Color = style.Color
	light.Brightness = 1.1
	light.Range = 12
	light.Parent = item
	return item
end

local function makeItem(kind: string, position: Vector3, actionText: string): BasePart
	local style = ITEM_STYLE[kind] or ITEM_STYLE.Potion

	local item = buildPickup(kind, position)
	CollectionService:AddTag(item, Tags.TaskItem)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = style.Label
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = item

	-- Spin the whole model, not the anchor part inside it.
	local parent = item.Parent
	table.insert(spinners, (parent and parent:IsA("Model")) and parent or item)
	return item
end

--- Pickups are now Models, so the thing to spin and destroy is the model, not
--- the anchor part inside it. Falls back to the part for plain-block pickups.
local function topOf(item: BasePart): Instance
	local parent = item.Parent
	if parent and parent:IsA("Model") then
		return parent
	end
	return item
end

local function destroyItem(item: BasePart)
	local top = topOf(item)
	local index = table.find(spinners, top)
	if index then
		table.remove(spinners, index)
	end
	top:Destroy()
end

--==========================================================================
-- Kind: collect
--==========================================================================

local function spawnCollectible(state: ObjectiveState, avoid: Vector3?)
	local def = state.Def
	local taskType = def.SpawnTaskType or "Any"

	local spawnPoint = claimSpawn(taskType, avoid)
	if not spawnPoint then
		Util.warn(
			"ObjectiveService",
			"ran out of free task spawn points for %s -- tag more parts with %s",
			def.Id,
			Tags.TaskSpawn
		)
		return
	end

	local item = makeItem(taskType, spawnPoint.Position, def.HoldSeconds > 0 and "Collect" or "Take")
	local prompt = item:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
	prompt.HoldDuration = def.HoldSeconds

	state.Extra.Live[item] = spawnPoint

	prompt.Triggered:Connect(function(player)
		if not state.Extra.Live[item] or state.Complete then
			return
		end
		if not TeamService.isAlive(player) then
			return
		end

		state.Extra.Live[item] = nil
		releaseSpawn(spawnPoint)
		destroyItem(item)

		NoiseService.add(player, def.CompletionNoise or Config.Noise.Actions.CollectItem, def.Id)

		-- Crosses are heavy. Carrying more of them slows you down, which turns
		-- "grab everything" into an actual decision. PlayerService turns this
		-- attribute into an actual WalkSpeed -- see the note at the top of it.
		if def.Id == "Crosses" then
			local carried = ((player:GetAttribute(StateKeys.Player.CarriedCrosses) or 0) :: number) + 1
			player:SetAttribute(StateKeys.Player.CarriedCrosses, carried)
		end

		advance(def.Id, 1, player)

		-- Keep the field topped up if this objective respawns.
		local remaining = state.Goal - state.Current
		local liveCount = Util.count(state.Extra.Live)
		local delay = state.Extra.RespawnDelay or 0
		if not state.Complete and liveCount < state.Extra.ActiveAtOnce and remaining > liveCount then
			task.delay(delay, function()
				if state.Complete or not roundActive then
					return
				end
				spawnCollectible(state, Util.getPosition(player))
			end)
		end
	end)
end

local function setupCollect(state: ObjectiveState)
	local def = state.Def
	state.Extra.Live = {}

	if def.Id == "Potions" then
		state.Extra.ActiveAtOnce = Config.Objectives.Potions.ActiveAtOnce
		state.Extra.RespawnDelay = Config.Objectives.Potions.RespawnDelay
	else
		-- Everything else is laid out all at once.
		state.Extra.ActiveAtOnce = def.Goal
		state.Extra.RespawnDelay = 0
	end

	for _ = 1, math.min(state.Extra.ActiveAtOnce, def.Goal) do
		spawnCollectible(state, nil)
	end
end

--==========================================================================
-- Kind: ingredients
--==========================================================================

local function setupIngredients(state: ObjectiveState)
	local collected: { [string]: boolean } = {}
	state.Extra.Collected = collected
	state.Extra.Live = {}

	local names = {
		BloodSample = "Blood Sample",
		HolyWater = "Holy Water",
		Garlic = "Garlic",
		MagicDust = "Magic Dust",
	}

	local function refreshDetail()
		local have = {}
		for _, ingredient in Config.Objectives.Ingredients.Items do
			if collected[ingredient] then
				table.insert(have, names[ingredient] or ingredient)
			end
		end
		setDetail(state, #have > 0 and table.concat(have, ", ") or "Nothing gathered yet")
	end
	refreshDetail()

	for _, ingredient in Config.Objectives.Ingredients.Items do
		local pedestal = MapService.getIngredientSpawn(ingredient)
		local position: Vector3

		if pedestal then
			position = pedestal.Position + Vector3.new(0, 3, 0)
		else
			-- The map didn't tag a pedestal for this one; fall back to a generic
			-- task spawn so the objective is still completable.
			local fallback = claimSpawn("Any", nil)
			if not fallback then
				Util.warn("ObjectiveService", "nowhere to put ingredient %s", ingredient)
				continue
			end
			position = fallback.Position
		end

		local item = makeItem("Ingredient", position, "Take")
		local prompt = item:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
		prompt.HoldDuration = Config.Objectives.Ingredients.HoldSeconds
		prompt.ObjectText = names[ingredient] or ingredient

		prompt.Triggered:Connect(function(player)
			if collected[ingredient] or not TeamService.isAlive(player) then
				return
			end
			collected[ingredient] = true
			destroyItem(item)
			NoiseService.add(player, Config.Noise.Actions.CollectItem, "ingredient")
			creditPlayer(player)
			refreshDetail()

			local have = 0
			for _, needed in Config.Objectives.Ingredients.Items do
				if collected[needed] then
					have += 1
				end
			end

			-- The counter shows gathering progress, but the objective only
			-- completes at the ritual table.
			state.Current = math.min(state.Goal - 1, have)
			publish(state)

			Net.fireAll("TaskProgress", {
				Id = state.Def.Id,
				Label = state.Def.ShortLabel,
				Current = have,
				Goal = state.Goal,
				Complete = false,
				By = player.DisplayName,
			})

			if have >= #Config.Objectives.Ingredients.Items then
				Net.fireAll("Announce", {
					Kind = "Objective",
					Text = "Every ingredient is gathered. Take them to the ritual table.",
				})
			end
		end)
	end

	-- The ritual table.
	local ritual = MapService.getRitualTable()
	if not ritual then
		Util.warn("ObjectiveService", "no ritual table on this map; the sealing potion cannot be finished")
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RitualPrompt"
	prompt.ActionText = "Brew"
	prompt.ObjectText = "Ritual Table"
	prompt.HoldDuration = Config.Objectives.Ingredients.RitualHoldSeconds
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = ritual
	state.Extra.Prompt = prompt

	prompt.Triggered:Connect(function(player)
		if state.Complete or not TeamService.isAlive(player) then
			return
		end
		for _, ingredient in Config.Objectives.Ingredients.Items do
			if not collected[ingredient] then
				Net.fire(player, "Announce", {
					Kind = "Objective",
					Text = "The mixture is incomplete. Find the rest.",
				})
				return
			end
		end

		-- Brewing is loud, and it takes ten seconds to stop being loud.
		NoiseService.addOverTime(
			player,
			Config.Noise.Actions.BrewPotion,
			Config.Noise.BrewPotionSeconds,
			"brew"
		)
		state.Current = state.Goal - 1
		advance(state.Def.Id, 1, player)
		setDetail(state, "Sealed")
	end)
end

--==========================================================================
-- Kind: clock
--==========================================================================

local function setupClock(state: ObjectiveState)
	local clock = MapService.getClock()
	if not clock then
		Util.warn("ObjectiveService", "no grandfather clock on this map; auto-completing the objective")
		advance(state.Def.Id, state.Goal, nil)
		return
	end

	-- Randomised each round so nobody memorises the answer.
	local targetHour = rng:NextInteger(1, 12)
	local targetMinute = rng:NextInteger(0, 11) * 5
	state.Extra.TargetHour = targetHour
	state.Extra.TargetMinute = targetMinute

	local pretty = string.format("%d:%02d", targetHour, targetMinute)
	setDetail(state, `Set the hands to {pretty}`)
	clock:SetAttribute("TargetHour", targetHour)
	clock:SetAttribute("TargetMinute", targetMinute)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClockPrompt"
	prompt.ActionText = "Set the Hands"
	prompt.ObjectText = "Grandfather Clock"
	prompt.HoldDuration = Config.Objectives.Clock.HoldSeconds
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = clock
	state.Extra.Prompt = prompt

	prompt.Triggered:Connect(function(player)
		if state.Complete or not TeamService.isAlive(player) then
			return
		end
		-- Hand the minigame to the client; it answers over SubmitClock.
		Net.fire(player, "Announce", {
			Kind = "ClockMinigame",
			TargetHour = targetHour,
			TargetMinute = targetMinute,
		})
	end)

	state.Extra.ClockPart = clock
end

--- Handles the client's answer to the clock minigame.
function ObjectiveService.submitClock(player: Player, hour: number, minute: number)
	local state = active.Clock
	if not state or state.Complete or not TeamService.isAlive(player) then
		return
	end

	local clock = state.Extra.ClockPart :: BasePart?
	if clock then
		local position = Util.getPosition(player)
		if not position or (position - clock.Position).Magnitude > 14 then
			return -- not actually standing at the clock
		end
	end

	if type(hour) ~= "number" or type(minute) ~= "number" then
		return
	end

	-- Compare on the 12-hour dial, so 12:00 and 0:00 are the same answer.
	local function toMinutes(h: number, m: number): number
		return ((math.floor(h) % 12) * 60 + math.floor(m)) % 720
	end
	local difference = math.abs(toMinutes(hour, minute) - toMinutes(state.Extra.TargetHour, state.Extra.TargetMinute))
	difference = math.min(difference, 720 - difference)

	if difference > Config.Objectives.Clock.ToleranceMinutes then
		Net.fire(player, "Announce", { Kind = "Objective", Text = "The hands are wrong. Try again." })
		return
	end

	-- The chime is the point. Everyone nearby just told the house where they are.
	if clock then
		NoiseService.addAtPosition(clock.Position, Config.Noise.Actions.AdjustClock, 70, "clock chime")
	end
	advance(state.Def.Id, state.Goal, player)
	setDetail(state, "The clock is chiming.")
end

--==========================================================================
-- Kind: fuses
--==========================================================================

local function setupFuses(state: ObjectiveState)
	local boxes = MapService.getFuseBoxes()
	if #boxes == 0 then
		Util.warn("ObjectiveService", "no fuse boxes on this map; auto-completing the objective")
		advance(state.Def.Id, state.Goal, nil)
		return
	end

	-- While this objective is running the safe zones start dark and light up
	-- one at a time.
	for _, zone in MapService.getSafeZones() do
		zone:SetAttribute("Active", false)
		zone.Transparency = 0.97
	end
	setDetail(state, "The barriers are dark")

	local zones = MapService.getSafeZones()

	for index, box in boxes do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FusePrompt"
		prompt.ActionText = "Restore Power"
		prompt.ObjectText = "Fuse Box"
		prompt.HoldDuration = Config.Objectives.SafeZone.HoldSeconds
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = box

		prompt.Triggered:Connect(function(player)
			if state.Complete or not prompt.Enabled or not TeamService.isAlive(player) then
				return
			end
			prompt.Enabled = false

			NoiseService.add(player, Config.Noise.Actions.CollectItem * 2, "fusebox")

			local zone = zones[index]
			if zone then
				zone:SetAttribute("Active", true)
				zone.Transparency = 0.85
			end

			advance(state.Def.Id, 1, player)
			setDetail(state, `{state.Current}/{state.Goal} barriers lit`)
		end)
	end
end

--==========================================================================
-- Lore notes
--==========================================================================

local function setupLoreNotes()
	for _, note in MapService.getLoreNotes() do
		local noteId = note:GetAttribute("NoteId")
		if type(noteId) ~= "string" then
			continue
		end
		local entry = ObjectiveData.LoreNotes[noteId]
		if not entry then
			continue
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ReadPrompt"
		prompt.ActionText = "Read"
		prompt.ObjectText = "Scrap of Paper"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = note

		prompt.Triggered:Connect(function(player)
			Net.fire(player, "LoreNoteRead", {
				NoteId = noteId,
				Title = entry.Title,
				Author = entry.Author,
				Body = entry.Body,
			})
			local DataService = require(script.Parent.DataService)
			DataService.markLoreFound(player, noteId)
		end)
	end
end

--==========================================================================
-- Noisy tiles
--==========================================================================

local function setupNoisyTiles()
	-- One Touched connection per tile, debounced per player, is much cheaper
	-- than polling every player against every tile.
	local lastStep: { [Player]: number } = {}

	for _, tile in MapService.getNoisyTiles() do
		tile.CanTouch = true
		tile.Touched:Connect(function(hit)
			local player = Util.getPlayerFromDescendant(hit)
			if not player or not TeamService.isAlive(player) then
				return
			end
			local now = os.clock()
			if (lastStep[player] or 0) + 0.6 > now then
				return
			end
			lastStep[player] = now
			local amount = (tile:GetAttribute("Noise") :: number?) or Config.Noise.Actions.CreakyFloor
			NoiseService.add(player, amount, "creaky floor")
		end)
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function ObjectiveService.setCompletionCallback(callback: (() -> ())?)
	onAllComplete = callback
end

--- Starts a round's objectives. Returns the chosen combo id.
function ObjectiveService.beginRound(): string
	ObjectiveService.endRound()

	local combo = ObjectiveData.pickCombo(rng)
	roundActive = true

	local folder = Net.getObjectivesFolder()
	folder:ClearAllChildren()

	for index, objectiveId in combo.Objectives do
		local def = ObjectiveData.get(objectiveId)
		if not def then
			Util.warn("ObjectiveService", 'combo references unknown objective "%s"', objectiveId)
			continue
		end

		local configuration = Instance.new("Configuration")
		configuration.Name = def.Id
		configuration:SetAttribute(StateKeys.Objective.Label, def.Label)
		configuration:SetAttribute(StateKeys.Objective.ShortLabel, def.ShortLabel)
		configuration:SetAttribute(StateKeys.Objective.Order, index)
		configuration:SetAttribute(StateKeys.Objective.Detail, "")
		configuration.Parent = folder

		local state: ObjectiveState = {
			Def = def,
			Current = 0,
			Goal = def.Goal,
			Complete = false,
			Config = configuration,
			Extra = {},
		}
		active[def.Id] = state
		table.insert(order, def.Id)
		publish(state)

		if def.Kind == "collect" then
			setupCollect(state)
		elseif def.Kind == "ingredients" then
			setupIngredients(state)
		elseif def.Kind == "clock" then
			setupClock(state)
		elseif def.Kind == "fuses" then
			setupFuses(state)
		else
			Util.warn("ObjectiveService", 'no handler for objective kind "%s"', def.Kind)
		end
	end

	-- Safe zones default to lit unless the fuse objective turned them off.
	if not active.SafeZones then
		for _, zone in MapService.getSafeZones() do
			zone:SetAttribute("Active", true)
		end
	end

	setupNoisyTiles()
	setupLoreNotes()

	-- One shared spin loop for every floating pickup, models and bare parts
	-- alike. PivotTo handles both; one connection handles all of them.
	if not spinConnection then
		spinConnection = RunService.Heartbeat:Connect(function(dt)
			local turn = CFrame.Angles(0, dt * 1.6, 0)
			for _, item in spinners do
				if item.Parent then
					if item:IsA("Model") then
						item:PivotTo(item:GetPivot() * turn)
					elseif item:IsA("BasePart") then
						item.CFrame = item.CFrame * turn
					end
				end
			end
		end)
	end

	Util.log("ObjectiveService", "round objectives: %s", table.concat(combo.Objectives, ", "))
	return combo.Id
end

function ObjectiveService.endRound()
	roundActive = false

	for _, state in active do
		if state.Extra.Prompt then
			(state.Extra.Prompt :: ProximityPrompt):Destroy()
		end
	end
	table.clear(active)
	table.clear(order)
	table.clear(usedSpawns)
	table.clear(spinners)

	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end

	local folder = Workspace:FindFirstChild(ITEMS_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end

	Net.getObjectivesFolder():ClearAllChildren()
end

--==========================================================================
-- Queries
--==========================================================================

function ObjectiveService.isComplete(): boolean
	if next(active) == nil then
		return false
	end
	for _, state in active do
		if not state.Complete then
			return false
		end
	end
	return true
end

--- A one-line summary for the round-start banner.
function ObjectiveService.describe(): string
	local parts = {}
	for _, objectiveId in order do
		local state = active[objectiveId]
		if state then
			table.insert(parts, `{state.Def.ShortLabel} ({state.Goal})`)
		end
	end
	return table.concat(parts, "  -  ")
end

function ObjectiveService.getSnapshot()
	local out = {}
	for _, objectiveId in order do
		local state = active[objectiveId]
		if state then
			table.insert(out, {
				Id = state.Def.Id,
				Label = state.Def.Label,
				ShortLabel = state.Def.ShortLabel,
				Current = state.Current,
				Goal = state.Goal,
				Complete = state.Complete,
			})
		end
	end
	return out
end

function ObjectiveService.start()
	Net.Events.SubmitClock.OnServerEvent:Connect(function(player, hour, minute)
		ObjectiveService.submitClock(player, hour, minute)
	end)
end

return ObjectiveService
