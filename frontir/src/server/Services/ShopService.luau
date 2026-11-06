--!strict
--[[
	ShopService — покупки за Robux (GDD §11.1, этап 9а).
	- Продукты разработчика: MarketplaceService.ProcessReceipt. Начисление только на сервере, идемпотентно по
	  PurchaseId (Profile.grantProduct), сразу сохраняем профиль; профиль ещё не загружен — NotProcessedYet
	  (Roblox повторит позже). Буст — в запас; hooks.onStock пробует сразу применить его в идущем матче.
	- Геймпассы: UserOwnsGamePassAsync при входе (кеш на сессию), PromptGamePassPurchaseFinished — купил сейчас.
	- Premium: Player.MembershipType.
	- Политика (сводная правка ч.4): PolicyService.ArePaidRandomItemsRestricted при входе (не узнали — считаем, что
	  запрещено). Пока запрещено, профиль помечен noPaidRandom: наборы ящиков не продаются, ящики за Robux
	  (неделя, премиум-пропуск) заменяются фиксированной наградой (Profile.paidReward).
	Товары без id (0 — ещё не созданы на сайте Roblox) просто не продаются.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Profile = require(Shared:WaitForChild("Profile"))
local Shop = require(Shared:WaitForChild("Shop"))

local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

export type Hooks = {
	onStock: (player: Player, key: string) -> (), -- куплен буст: применить в матче, если можно
	onChanged: (player: Player) -> (), -- профиль или пассы изменились: разослать
}

export type ShopService = {
	passes: (player: Player) -> { [string]: boolean },
	premium: (player: Player) -> boolean,
	loadPasses: (player: Player) -> (),
	noPaidRandom: (player: Player) -> boolean?, -- nil — политика ещё не узнана
	forget: (player: Player) -> (),
}

local ShopService = {}

function ShopService.start(profiles: ProfileStore.ProfileStore, hooks: Hooks): ShopService
	local owned: { [Player]: { [string]: boolean } } = {}
	local restricted: { [Player]: boolean } = {}
	local passCfg = (Config.Shop.Passes :: any) :: { [string]: { id: number } }

	MarketplaceService.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
		local player = Players:GetPlayerByUserId(info.PlayerId)
		local session = profiles.get(info.PlayerId)
		if player == nil or session == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local kind, key = Shop.productById(info.ProductId)
		if kind == nil or key == nil then
			warn("[Frontir] неизвестный продукт", info.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- Политика игрока ещё не узнана — начислим, когда узнаем (ящик может стать фиксированной наградой).
		local noRandom = restricted[player]
		if noRandom == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		session.data.noPaidRandom = noRandom
		local purchaseId = tostring(info.PurchaseId)
		local fresh = not Profile.hasPurchase(session.data, purchaseId)
		if not Profile.grantProduct(session.data, kind, key, purchaseId, os.time()) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- Сохранить сразу: деньги списаны, начисление не должно потеряться при падении сервера.
		if session.saving and not profiles.save(info.PlayerId) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if fresh and kind == "boost" then
			hooks.onStock(player, key)
		end
		hooks.onChanged(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			for key, p in passCfg do
				if p.id ~= 0 and p.id == passId then
					owned[player] = owned[player] or {}
					owned[player][key] = true
					hooks.onChanged(player)
				end
			end
		end
	)

	return {
		passes = function(player: Player): { [string]: boolean }
			return owned[player] or {}
		end,
		premium = function(player: Player): boolean
			return player.MembershipType == Enum.MembershipType.Premium
		end,
		loadPasses = function(player: Player)
			local set: { [string]: boolean } = {}
			for key, p in passCfg do
				if p.id ~= 0 then
					local ok, has = pcall(function(): boolean
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.id)
					end)
					if ok and has then
						set[key] = true
					end
				end
			end
			owned[player] = set
			local ok, policy = pcall(function(): any
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			restricted[player] = not ok
				or type(policy) ~= "table"
				or (policy :: any).ArePaidRandomItemsRestricted ~= false
		end,
		noPaidRandom = function(player: Player): boolean?
			return restricted[player]
		end,
		forget = function(player: Player)
			owned[player] = nil
			restricted[player] = nil
		end,
	}
end

return ShopService
