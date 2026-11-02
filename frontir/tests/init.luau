--!strict
--[[
	Запуск: `lune run tests` из папки frontir/.
	Находит все файлы tests/*.spec.luau, выполняет их и печатает итог.
	Код выхода 1, если хоть один тест упал (для CI).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestKit = require("@self/lib/TestKit")

local TESTS_DIR = "tests"

local filter = process.args[1]

local specs: { string } = {}
for _, name in fs.readDir(TESTS_DIR) do
	if string.match(name, "%.spec%.luau$") and (filter == nil or string.find(name, filter, 1, true)) then
		table.insert(specs, name)
	end
end
table.sort(specs)

local passed, failed = 0, 0
for _, spec in specs do
	local moduleName = string.gsub(spec, "%.luau$", "")
	local ok, err = pcall(require, "@self/" .. moduleName)
	local results = TestKit.takeResults()
	print(string.format("● %s", spec))
	if not ok then
		failed += 1
		print(string.format("  ✗ файл не загрузился: %s", tostring(err)))
	end
	for _, r in results do
		if r.ok then
			passed += 1
			print(string.format("  ✓ %s", r.name))
		else
			failed += 1
			print(string.format("  ✗ %s\n      %s", r.name, r.err or "?"))
		end
	end
end

print(string.format("\nИтого: %d прошло, %d упало, файлов %d", passed, failed, #specs))
if failed > 0 or #specs == 0 then
	process.exit(1)
end
