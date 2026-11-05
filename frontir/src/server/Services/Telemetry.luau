--!strict
--[[
	Telemetry — отправка аналитики в Roblox (AnalyticsService, этап 10в). Что отправлять, решает чистый
	Shared.Analytics; здесь — только вызовы сервиса. Ошибка сервиса (Studio, лимиты) игре не мешает: pcall и одна
	строка в Output. В Studio без публикации AnalyticsService может молчать — это нормально.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Analytics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Analytics"))

local Telemetry = {}

local FIELDS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

local warned = false
local function guard(fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok and not warned then
		warned = true
		warn("[Frontir] аналитика недоступна:", err)
	end
end

function Telemetry.custom(player: Player, record: Analytics.Record)
	local fields: { [string]: string } = {}
	for k, v in record.fields do
		if FIELDS[k] ~= nil then
			fields[FIELDS[k]] = v
		end
	end
	guard(function()
		AnalyticsService:LogCustomEvent(player, record.name, record.value, fields)
	end)
end

function Telemetry.funnel(player: Player, step: Analytics.FunnelStep)
	guard(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step.step, step.name)
	end)
end

return table.freeze(Telemetry)
