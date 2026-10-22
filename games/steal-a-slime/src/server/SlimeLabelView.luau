--!strict
--[[
	SlimeLabelView (Roblox adapter, contract/slime-labels.md)

	Writes the label attributes on a slime model (the values are pure:
	Shared.SlimeLabel; each client draws the tag or the pad sign) and scales the model to its
	growth (FEATURES.GrowingSlimes). Every write is skipped when the value is
	unchanged, so a reconcile a few times a second replicates almost nothing.
	Studio only: a model attribute PcwGrowth (whole percent) replaces the real
	growth, so the pc-watcher shot can show a known 50% (never active live).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EggKind = require(ReplicatedStorage.Shared.EggKind)
local Genome = require(ReplicatedStorage.Shared.Genome)
local Growth = require(ReplicatedStorage.Shared.Growth)
local SlimeLabel = require(ReplicatedStorage.Shared.SlimeLabel)

local SlimeLabelView = {}

-- Model scale LabelHeight was last measured at (weak: dropped with the model).
local measuredAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Whole percent to show for this model: the Studio override, else the slime's real growth.
function SlimeLabelView.percentFor(model: Instance, slime: Genome.Slime): number
	local override = if RunService:IsStudio() then model:GetAttribute(Constants.GROWTH_OVERRIDE_ATTRIBUTE) else nil
	if type(override) == "number" then
		return Growth.percentAt(override / 100)
	end
	return Growth.percent(slime)
end

local function setIfChanged(model: Model, name: string, value: any)
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- Scales the model when its whole growth percent changes (model attribute Growth). A Mystery Egg never scales: its
-- Growth is the incubation progress at server time `now`, so the pad sign's bar fills up to the hatch.
function SlimeLabelView.applyGrowth(model: Model, slime: Genome.Slime, now: number)
	if slime.egg then
		setIfChanged(model, Constants.GROWTH_ATTRIBUTE, math.floor(EggKind.progress(slime, now) * 100))
		return
	end
	local percent = SlimeLabelView.percentFor(model, slime)
	if model:GetAttribute(Constants.GROWTH_ATTRIBUTE) == percent then
		return
	end
	model:SetAttribute(Constants.GROWTH_ATTRIBUTE, percent)
	model:ScaleTo(Growth.scaleAt(percent / 100))
end

-- Name, tier, income, the status row (`status`, else a Mystery Egg's at server time `now`) and the pad it rests on
-- (nil off a pad); LabelHeight is re-measured after any scale change (growth, boss scale).
function SlimeLabelView.apply(
	model: Model,
	body: BasePart,
	slime: Genome.Slime,
	incomePerSec: number,
	pad: number?,
	now: number,
	status: string?
)
	local name, tier = SlimeLabel.attributes(slime)
	setIfChanged(model, Constants.LABEL_STATUS_ATTRIBUTE, status or SlimeLabel.eggStatus(slime, now))
	setIfChanged(model, Constants.LABEL_NAME_ATTRIBUTE, name)
	setIfChanged(model, Constants.LABEL_TIER_ATTRIBUTE, tier)
	setIfChanged(model, Constants.LABEL_PAD_ATTRIBUTE, pad)
	if SlimeLabel.incomeChanged(model:GetAttribute(Constants.LABEL_INCOME_ATTRIBUTE), incomePerSec) then
		model:SetAttribute(Constants.LABEL_INCOME_ATTRIBUTE, incomePerSec)
	end
	local scale = model:GetScale()
	if measuredAt[model] == scale then
		return
	end
	-- From Body's centre to the model's highest part (mesh top, crown, halo), on the scaled model.
	local box, size = model:GetBoundingBox()
	local height = Growth.labelOffset(box.Position.Y + size.Y / 2 - body.Position.Y)
	model:SetAttribute(Constants.LABEL_HEIGHT_ATTRIBUTE, math.floor(height * 100 + 0.5) / 100)
	measuredAt[model] = scale
end

return SlimeLabelView
