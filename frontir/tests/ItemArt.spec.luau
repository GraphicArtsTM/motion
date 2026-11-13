--!strict
-- Картинки предметов (§15л ч.9): у каждого товара, узора, вспышки, титула, задания, технологии и предмета Арсенала.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local ItemArt = require("../src/shared/ItemArt")
local Shop = require("../src/shared/Shop")

T.describe("Картинки предметов (§15л ч.9)", function()
	T.it(
		"есть у всего, что показывают окна; картинка W×H без пустых пикселей",
		function()
			local need: { string } = { "shop.Crates", "shop.PathPremium" }
			for _, list in { Shop.BoostKeys :: any, Shop.PassKeys :: any, Shop.PackKeys :: any } :: { { string } } do
				for _, key in list do
					table.insert(need, "shop." .. key)
				end
			end
			for _, it in Config.Cosmetics.Patterns do
				table.insert(need, "pattern." .. it.id)
			end
			for _, it in Config.Cosmetics.Captures do
				table.insert(need, "capture." .. it.id)
			end
			for _, it in Config.Cosmetics.Titles do
				table.insert(need, "title." .. it.id)
			end
			for _, q in Config.Quests.Pool do
				table.insert(need, "quest." .. q.kind)
			end
			for _, branch in { "Army", "Economy", "Fleet" } do
				for level = 1, #Config.Tech.Cost do
					table.insert(need, "tech." .. branch .. level)
				end
			end
			for _, key in Config.Arsenal.Order do
				table.insert(need, "arsenal." .. key)
			end
			-- Порт, аэродром, война и мир, итоги (§15л ч.11).
			for _, key in
				{
					"naval.port",
					"naval.Transport",
					"naval.Destroyer",
					"naval.land",
					"air.airfield",
					"air.Fighter",
					"air.Bomber",
					"air.raid",
					"war.declare",
					"peace.white",
					"peace.keep",
					"peace.capitulate",
					"peace.offer",
					"results.place",
					"results.peak",
					"results.time",
					"results.out",
					"results.reward",
					"results.medal1",
					"results.medal2",
					"results.medal3",
				}
			do
				table.insert(need, key)
			end
			for _, key in need do
				if not ItemArt.has(key) then
					error("нет картинки: " .. key)
				end
				local px = ItemArt.paint(key)
				T.expect(buffer.len(px)).toBe(ItemArt.W * ItemArt.H * 4)
				for i = 0, ItemArt.W * ItemArt.H - 1 do
					if buffer.readu8(px, i * 4 + 3) ~= 255 then
						error("пустой пиксель в " .. key)
					end
				end
			end
			T.expect(buffer.len(ItemArt.paint("nope"))).toBe(ItemArt.W * ItemArt.H * 4)
		end
	)
end)
