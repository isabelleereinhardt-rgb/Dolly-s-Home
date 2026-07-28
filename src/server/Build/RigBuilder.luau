--!nonstrict
--[[
	RigBuilder.luau
	--------------------------------------------------------------------------
	Adapter between the services and CharacterBuilder.

	The blocky placeholder rigs are gone -- CharacterBuilder now builds the real
	cast from the spec table ported out of killers.js and characters.js. This
	file survives only so KillerService, HelperService and AvaService keep the
	call they already had.

	Source order, same as everywhere else:
	  1. ServerStorage/Killers/<Name>   your own rig, if you build one
	  2. CharacterBuilder               the ported spec
	--------------------------------------------------------------------------
]]

local ServerStorage = game:GetService("ServerStorage")

local CharacterBuilder = require(script.Parent.CharacterBuilder)

local RigBuilder = {}

--- A hand-built rig from ServerStorage, if there is one for this id.
local function stored(id: string): Model?
	local folder = ServerStorage:FindFirstChild("Killers")
	if not folder then
		return nil
	end
	local template = folder:FindFirstChild(id)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return nil
end

--[[
	Builds a family member.

	`ghostly` is accepted for backwards compatibility but ignored -- whether a
	character is translucent is now a property of the character (Robby, Benny
	and Ava carry `Ghostly = true` in their spec), not of the call site.
]]
function RigBuilder.build(id: string, _ghostly: boolean?): Model?
	return stored(id) or CharacterBuilder.build(id)
end

function RigBuilder.buildAva(): Model?
	return stored("Ava") or CharacterBuilder.build("Ava")
end

return RigBuilder
