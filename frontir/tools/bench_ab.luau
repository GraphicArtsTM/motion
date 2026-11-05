--!strict
--[[
	Честное сравнение нагрузки: `main` (или другая ссылка git) и текущая рабочая копия в одном запуске на одной машине.
	Поднимает git worktree ссылки в build/bench-<ref>, гоняет tools/bench по очереди — ссылка, рабочая копия,
	ссылка, рабочая копия… — по runs раз и берёт МИНИМУМ среднего тика (минимум меньше всего зависит от фона машины).
	Запуск из frontir/:  lune run tools/bench_ab [карта=World] [держав=60] [секунд=180] [прогонов=5] [ссылка=origin/main]
	В отчётах о производительности — только эти цифры (CLAUDE.md).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local map = process.args[1] or "World"
local nations = process.args[2] or "60"
local seconds = process.args[3] or "180"
local runs = tonumber(process.args[4]) or 5
local ref = process.args[5] or "origin/main"

local function run(cmd: string, args: { string }, cwd: string?): (boolean, string)
	local result = process.exec(cmd, args, { cwd = cwd })
	return result.ok, result.stdout .. result.stderr
end

-- Рабочая копия ссылки: build/bench-<ref> (пересоздаётся на свежий коммит ссылки).
local cwd = process.cwd
local dirName = "bench-" .. string.gsub(ref, "[^%w]", "-")
local worktree = cwd .. "/build/" .. dirName
if not fs.isDir(cwd .. "/build") then
	fs.writeDir(cwd .. "/build")
end
if fs.isDir(worktree) then
	run("git", { "worktree", "remove", "--force", worktree }, cwd)
end
local ok, out = run("git", { "worktree", "add", "--detach", worktree, ref }, cwd)
if not ok then
	error("не удалось поднять worktree для " .. ref .. ":\n" .. out)
end
local _, sha = run("git", { "rev-parse", "--short", ref }, cwd)
local _, head = run("git", { "rev-parse", "--short", "HEAD" }, cwd)
local refDir = worktree .. "/frontir"

local function bench(dir: string): number
	local okBench, text = run("lune", { "run", "tools/bench", map, nations, seconds }, dir)
	local ms = tonumber(string.match(text, "тик средний ([%d%.]+) мс"))
	if not okBench or ms == nil then
		error("tools/bench упал в " .. dir .. ":\n" .. text)
	end
	return ms :: number
end

print(
	string.format(
		"bench_ab: %s, держав %s, %s с, прогонов %d; %s (%s) против рабочей копии (%s)",
		map,
		nations,
		seconds,
		runs,
		ref,
		(string.gsub(sha, "%s", "")),
		(string.gsub(head, "%s", ""))
	)
)
local refTimes: { number } = {}
local ownTimes: { number } = {}
for k = 1, runs do
	local a = bench(refDir)
	local b = bench(cwd)
	table.insert(refTimes, a)
	table.insert(ownTimes, b)
	print(string.format("  прогон %d: %s %.2f мс, ветка %.2f мс", k, ref, a, b))
end
local refMin = math.min(table.unpack(refTimes))
local ownMin = math.min(table.unpack(ownTimes))
print(
	string.format(
		"МИНИМУМ: %s %.2f мс, ветка %.2f мс — ветка %.0f%% от %s",
		ref,
		refMin,
		ownMin,
		ownMin / refMin * 100,
		ref
	)
)
run("git", { "worktree", "remove", "--force", worktree }, cwd)
