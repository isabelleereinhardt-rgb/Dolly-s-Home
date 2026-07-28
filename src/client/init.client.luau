--!strict
--[[
	init.client.luau
	--------------------------------------------------------------------------
	Client bootstrap.

	Requiring Shared.Net blocks until the server has built the DollysHome
	folder, so every controller below can assume the remotes and the state
	container already exist.

	Controllers are started in a pcall each: a broken HUD should not take the
	input handler down with it.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
require(Shared.Net) -- waits for the server's remote folder

local Controllers = script.Controllers

local AlertController = require(Controllers.AlertController)
local AudioController = require(Controllers.AudioController)
local HudController = require(Controllers.HudController)
local InputController = require(Controllers.InputController)
local ModalController = require(Controllers.ModalController)
local ResultsController = require(Controllers.ResultsController)
local SpectateController = require(Controllers.SpectateController)
local VoteController = require(Controllers.VoteController)

local player = Players.LocalPlayer
player:WaitForChild("PlayerGui")

local START_ORDER: { { Name: string, Start: () -> () } } = {
	{ Name = "HudController", Start = HudController.start },
	{ Name = "AlertController", Start = AlertController.start },
	{ Name = "VoteController", Start = VoteController.start },
	{ Name = "ResultsController", Start = ResultsController.start },
	{ Name = "ModalController", Start = ModalController.start },
	{ Name = "InputController", Start = InputController.start },
	{ Name = "AudioController", Start = AudioController.start },
	{ Name = "SpectateController", Start = SpectateController.start },
}

for _, entry in START_ORDER do
	local ok, err = pcall(entry.Start)
	if not ok then
		warn(`[DollysHome] {entry.Name} failed to start: {err}`)
	end
end

print("[DollysHome] client ready.")
