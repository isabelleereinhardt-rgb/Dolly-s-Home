--!strict
--[[
	HelperService.luau
	--------------------------------------------------------------------------
	Robby and Benny -- the two who chose not to hunt.

	Robby appears and drops a safe zone that killers cannot enter.
	Benny appears near a task and warns about whoever is closest.

	And roughly one time in twenty, the helper you just ran toward is Robert
	wearing his brother's face. His eyes are red instead of blue. That's the only
	tell, and it exists so that the sight of a friendly ghost never becomes
	completely relaxing.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local KillerData = require(Shared.KillerData)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local KillerService = require(script.Parent.KillerService)
local MapService = require(script.Parent.MapService)
local RigBuilder = require(script.Parent.Parent.Build.RigBuilder)
local SafeZoneService = require(script.Parent.SafeZoneService)
local TeamService = require(script.Parent.TeamService)

local HelperService = {}

local scheduler: thread? = nil
local activeModels: { Model } = {}
local rng = Random.new()

--==========================================================================
-- Appearance
--==========================================================================

local function speak(model: Model, text: string, colour: Color3)
	local root = model.PrimaryPart
	if not root then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Dialogue"
	billboard.Size = UDim2.fromScale(14, 3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Merriweather
	label.TextColor3 = colour
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Text = text
	label.Parent = billboard

	task.delay(6, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function despawn(model: Model)
	local index = table.find(activeModels, model)
	if index then
		table.remove(activeModels, index)
	end
	if model.Parent then
		model:Destroy()
	end
end

--==========================================================================
-- Robby: safe zones
--==========================================================================

local function appearAsRobby(position: Vector3, isImposter: boolean)
	local helperId = isImposter and "Robert" or "Robby"
	local model = RigBuilder.build(helperId, true)
	if not model then
		return
	end

	model.Name = "Robby"
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	model.Parent = workspace
	CollectionService:AddTag(model, Tags.ActiveHelper)
	table.insert(activeModels, model)

	local profile = KillerData.get("Robby")
	local line = (profile and Util.pick(profile.Lines, rng)) or "Hide here, quickly!"
	speak(model, line, isImposter and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(180, 220, 255))

	if isImposter then
		-- No safe zone. The lie is the whole mechanic; the red eyes from the
		-- Robert rig are the only warning anyone gets.
		task.delay(Config.Helpers.VisibleSeconds * 0.5, function()
			despawn(model)
		end)
		return
	end

	SafeZoneService.createTemporary(position, Config.Helpers.SafeZoneRadius, Config.Helpers.SafeZoneDuration)

	Net.fireAll("HelperMessage", {
		Helper = "Robby",
		Text = line,
		Position = position,
		SafeZone = true,
		Duration = Config.Helpers.SafeZoneDuration,
	})

	task.delay(Config.Helpers.SafeZoneDuration, function()
		despawn(model)
	end)
end

--==========================================================================
-- Benny: warnings and hints
--==========================================================================

local function appearAsBenny(position: Vector3)
	local model = RigBuilder.build("Benny", true)
	if not model then
		return
	end

	model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	model.Parent = workspace
	CollectionService:AddTag(model, Tags.ActiveHelper)
	table.insert(activeModels, model)

	-- Warn about whichever killer is nearest to him.
	local nearest, distance = KillerService.getNearest(position)
	local text: string
	if nearest and distance < 90 then
		text = `Shh! {nearest.profile.Name}'s coming this way!`
	else
		local profile = KillerData.get("Benny")
		text = (profile and Util.pick(profile.Lines, rng)) or "I didn't want this... none of us did."
	end

	speak(model, text, Color3.fromRGB(190, 255, 220))

	-- Only tell players close enough to have heard him whisper.
	for _, player in TeamService.getParticipants() do
		local playerPosition = Util.getPosition(player)
		if playerPosition and (playerPosition - position).Magnitude <= Config.Helpers.WarnRange * 2 then
			Net.fire(player, "HelperMessage", {
				Helper = "Benny",
				Text = text,
				Position = position,
				KillerName = nearest and nearest.profile.Name or nil,
				KillerPosition = nearest and nearest:getPosition() or nil,
			})
		end
	end

	task.delay(Config.Helpers.VisibleSeconds, function()
		despawn(model)
	end)
end

--==========================================================================
-- Placement
--==========================================================================

--[[
	Helpers should turn up somewhere useful: near a player who is in trouble
	rather than in an empty room on the far side of the map. Preference order is
	a tagged helper spawn near a living player, then any living player's
	surroundings, then any helper spawn at all.
]]
local function choosePosition(): Vector3?
	local alive = TeamService.getAlive()
	local spawns = MapService.getHelperSpawns()

	if #alive > 0 and #spawns > 0 then
		local anchor = Util.pick(alive, rng)
		local anchorPosition = anchor and Util.getPosition(anchor)
		if anchorPosition then
			local best: BasePart? = nil
			local bestDistance = math.huge
			for _, spawnPoint in spawns do
				local distance = (spawnPoint.Position - anchorPosition).Magnitude
				-- Close enough to reach, far enough to not appear on top of them.
				if distance > 20 and distance < bestDistance then
					best = spawnPoint
					bestDistance = distance
				end
			end
			if best then
				return best.Position
			end
		end
	end

	local fallback = Util.pick(spawns, rng)
	if fallback then
		return fallback.Position
	end

	local anyone = Util.pick(alive, rng)
	if anyone then
		local position = Util.getPosition(anyone)
		if position then
			return position + Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
		end
	end

	return nil
end

--==========================================================================
-- Lifecycle
--==========================================================================

function HelperService.beginRound()
	HelperService.endRound()

	local appearances = rng:NextInteger(Config.Helpers.AppearancesPerRound.Min, Config.Helpers.AppearancesPerRound.Max)

	scheduler = task.spawn(function()
		task.wait(Config.Helpers.FirstAppearanceDelay)

		for index = 1, appearances do
			if #TeamService.getAlive() == 0 then
				return
			end

			local position = choosePosition()
			if position then
				-- Alternate so a round doesn't hand out four safe zones and no
				-- warnings, or the other way round.
				if index % 2 == 1 then
					local isImposter = rng:NextNumber() < Config.Helpers.ImposterChance
					appearAsRobby(position, isImposter)
				else
					appearAsBenny(position)
				end
			end

			task.wait(rng:NextInteger(Config.Helpers.AppearanceGap.Min, Config.Helpers.AppearanceGap.Max))
		end
	end)
end

function HelperService.endRound()
	if scheduler then
		task.cancel(scheduler)
		scheduler = nil
	end
	for index = #activeModels, 1, -1 do
		despawn(activeModels[index])
	end
	SafeZoneService.clearTemporary()
end

return HelperService
