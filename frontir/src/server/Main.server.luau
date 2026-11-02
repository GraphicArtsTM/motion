--!strict
--[[
	Точка входа сервера. Сервер решает всё: принимает намерения клиентов,
	считает симуляцию и рассылает изменения (docs/GDD.md §12).
	Этап 0: только проверка, что общие модули грузятся.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

print(string.format("[Frontir] server boot, config v%d, tick %d Hz", Config.Version, Config.Sim.TickRate))
