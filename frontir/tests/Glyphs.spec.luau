--!strict
-- §15ъ: символы, которых нет в шрифте игры (Montserrat) и нет среди эмодзи Roblox, на экране — пустой квадрат.
-- Так было с «✕», «✗», «▸», «▾», «▦» (живая игра, 27.11.2026). Проверяем код интерфейса (без комментариев) и строки.
-- Нужен значок — картинка (MenuKit.icon) или символ из шрифта: «×», «▶», «▼», «←», «→», «◆», «•» или эмодзи.
local fs = require("@lune/fs")
local T = require("./lib/TestKit")

local BANNED =
	{ "✕", "✗", "✖", "▸", "▾", "◂", "▴", "▦", "◎", "↩", "≡", "★", "☆", "✦", "⟳" }

local function files(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			files(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

T.describe("Символы на экране есть в шрифте (§15ъ)", function()
	T.it("в коде интерфейса и строках нет символов-«квадратов»", function()
		local list: { string } = {}
		files("src/client", list)
		table.insert(list, "src/shared/Strings.luau")
		local bad: { string } = {}
		for _, path in list do
			local n = 0
			local inBlock = false -- внутри --[[ … ]]
			for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
				n += 1
				local code = line
				if inBlock then
					local close = string.find(code, "]]", 1, true)
					code = if close ~= nil then string.sub(code, close + 2) else ""
					inBlock = close == nil
				end
				local open = string.find(code, "--[[", 1, true)
				if open ~= nil then
					inBlock = string.find(code, "]]", open + 4, true) == nil
					code = string.sub(code, 1, open - 1)
				end
				code = string.match(code, "^(.-)%-%-") or code
				for _, ch in BANNED do
					if string.find(code, ch, 1, true) ~= nil then
						table.insert(bad, string.format("%s:%d «%s»", path, n, ch))
					end
				end
			end
		end
		for _, b in bad do
			print("  ! " .. b)
		end
		T.expect(#bad).toBe(0)
	end)
end)
