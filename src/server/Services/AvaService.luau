--!strict
--[[
	AvaService.luau
	--------------------------------------------------------------------------
	Ava, standing over her own grave on the Graveyard map, asking players
	whether what she did was right.

	She has no gameplay effect. That is deliberate: the question is the point,
	and answering it should not make the round easier. Responses are tallied so
	a future build can do something with the verdict.

	The Graveyard map isn't enabled yet (Config.Maps), so this service simply
	does nothing until a map tags a part DH_AvaGrave.
	--------------------------------------------------------------------------
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local MapService = require(script.Parent.MapService)
local RigBuilder = require(script.Parent.Parent.Build.RigBuilder)

local AvaService = {}

export type Prompt = {
	Id: string,
	Text: string,
	Options: { { Id: string, Text: string } },
}

--[[
	Her questions. She asks one at random; there is no "correct" answer and she
	does not argue with the one she's given.
]]
AvaService.Questions = {
	{
		Id = "WasItJust",
		Text = "They sold me for a promise. I gave them exactly what they asked for. Was that justice, or was it only spite wearing its coat?",
		Options = {
			{ Id = "Just", Text = "They chose it. You only let them have it." },
			{ Id = "Spite", Text = "You wanted them to suffer. Say so." },
			{ Id = "Unsure", Text = "I don't think anyone can answer that." },
		},
	},
	{
		Id = "ThirtyDays",
		Text = "Thirty days without harming a soul, and they would have walked out of here as people. Two of them managed it. Should the other five be given a thirty-first?",
		Options = {
			{ Id = "Mercy", Text = "Give them another. Robby and Benny did it." },
			{ Id = "Enough", Text = "They have had a hundred chances already." },
			{ Id = "Ask", Text = "Ask the people they've eaten." },
		},
	},
	{
		Id = "TheLoop",
		Text = "I reset the days when they fail. I have done it more times than I have counted. Am I giving them a chance, or am I refusing to let them end?",
		Options = {
			{ Id = "Chance", Text = "A chance. You still hope." },
			{ Id = "Refusing", Text = "You can't let go. That's not for them." },
			{ Id = "Both", Text = "Both. That's usually how it works." },
		},
	},
}

local responses: { [string]: number } = {}
local model: Model? = nil
local rng = Random.new()

--==========================================================================
-- Spawning
--==========================================================================

function AvaService.spawn()
	AvaService.despawn()

	local graves = MapService.getTaggedParts(Tags.AvaGrave)
	local grave = graves[1]
	if not grave then
		return -- not the Graveyard map
	end

	local built = RigBuilder.buildAva()
	built:PivotTo(CFrame.new(grave.Position + Vector3.new(0, 4, 2)) * CFrame.Angles(0, math.pi, 0))
	built.Parent = workspace
	model = built

	local root = built.PrimaryPart
	if not root then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AvaPrompt"
	prompt.ActionText = "Speak"
	prompt.ObjectText = "Ava"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(player)
		local question = Util.pick(AvaService.Questions, rng)
		if question then
			Net.fire(player, "AvaDialogue", question)
		end
	end)

	Util.log("AvaService", "Ava is at her grave")
end

function AvaService.despawn()
	if model and model.Parent then
		model:Destroy()
	end
	model = nil
end

--==========================================================================
-- Responses
--==========================================================================

function AvaService.getTally(): { [string]: number }
	return table.clone(responses)
end

function AvaService.start()
	Net.Events.AvaRespond.OnServerEvent:Connect(function(_player, questionId, optionId)
		if type(questionId) ~= "string" or type(optionId) ~= "string" then
			return
		end
		local key = `{questionId}:{optionId}`
		responses[key] = (responses[key] or 0) + 1
	end)
end

return AvaService
