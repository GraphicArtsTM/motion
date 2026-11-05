--!strict
--[[
	Session — всё, что клиент создаёт на одну карту (этап 8б, §5.2). При смене карты Main снимает это явно:
	документация Roblox не обещает, что подписки отключатся сами, пока жив скрипт, поэтому подписки, объекты
	с Destroy (EditableImage, интерфейс) и ScreenGui сессии собираются здесь и снимаются в reset().
]]

export type Destroyable = { Destroy: (self: any) -> () }

local Session = {}

local connections: { RBXScriptConnection } = {}
local objects: { Destroyable } = {}

-- Подписка на время сессии (вместо signal:Connect).
function Session.connect(signal: RBXScriptSignal, handler: (...any) -> ()): RBXScriptConnection
	local c = signal:Connect(handler)
	table.insert(connections, c)
	return c
end

-- Объект на время сессии (EditableImage, ScreenGui): в reset() — Destroy.
function Session.track<T>(object: T): T
	table.insert(objects, object :: any)
	return object
end

-- Снять всё сессии: подписки отключить, объекты уничтожить (в обратном порядке создания).
function Session.reset()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	for k = #objects, 1, -1 do
		pcall(function()
			objects[k]:Destroy()
		end)
	end
	table.clear(objects)
end

return Session
