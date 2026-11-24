--!strict
--[[
	ShopService — покупки за Robux (GDD §11.1, этап 9а).
	- Продукты разработчика: MarketplaceService.ProcessReceipt. Начисление только на сервере, идемпотентно по
	  PurchaseId (Profile.grantProduct). PurchaseGranted — только после записи профиля в DataStore
	  (profiles.grant, правка по аудиту): профиль не загружен, только в памяти или запись не прошла — NotProcessedYet
	  (Roblox повторит, в т. ч. на другом сервере); в Studio без DataStore — можно и в памяти (тестовые покупки).
	  §15ъ: профиль и политику игрока ждём до Shop.ReceiptWaitSec — Roblox повторяет покупки как раз при входе.
	  Буст — в запас; hooks.onStock пробует сразу применить его в идущем матче.
	- Геймпассы: UserOwnsGamePassAsync при входе (кеш на сессию, при сбое — Shop.PassCheckTries попыток),
	  PromptGamePassPurchaseFinished — купил сейчас.
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
local RunService = game:GetService("RunService")

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

	-- §15ъ: Roblox повторяет неначисленную покупку при входе игрока — профиль и политика в это время ещё грузятся.
	-- Ждём их (игрок здесь, не дольше ReceiptWaitSec), а не откладываем покупку до следующего входа.
	local function ready(player: Player, userId: number): (ProfileStore.Session?, boolean?)
		local deadline = os.clock() + Config.Shop.ReceiptWaitSec
		while true do
			local session = profiles.get(userId)
			local noRandom = restricted[player]
			if session ~= nil and noRandom ~= nil then
				return session, noRandom
			end
			if player.Parent ~= Players or os.clock() >= deadline then
				return nil, nil
			end
			task.wait(Config.Shop.ReceiptPollSec)
		end
	end

	MarketplaceService.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
		local player = Players:GetPlayerByUserId(info.PlayerId)
		if player == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local kind, key = Shop.productById(info.ProductId)
		if kind == nil or key == nil then
			warn("[Frontir] неизвестный продукт", info.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- Политика игрока нужна до начисления: ящик может стать фиксированной наградой.
		local session, noRandom = ready(player, info.PlayerId)
		if session == nil or noRandom == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local purchaseId = tostring(info.PurchaseId)
		local fresh = false
		-- Начислить и сразу записать: деньги списаны, «куплено» — только когда начисление уже в DataStore.
		local result = profiles.grant(info.PlayerId, function(data: Profile.Data): boolean
			data.noPaidRandom = noRandom
			fresh = not Profile.hasPurchase(data, purchaseId)
			return Profile.grantProduct(data, kind, key, purchaseId, os.time())
		end, RunService:IsStudio())
		if result ~= "granted" then
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
					-- §15ъ: сбой Roblox — повторить, иначе купленный пропуск выключен до конца сессии.
					for attempt = 1, Config.Shop.PassCheckTries do
						local ok, has = pcall(function(): boolean
							return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.id)
						end)
						if ok then
							if has then
								set[key] = true
							end
							break
						end
						if attempt < Config.Shop.PassCheckTries then
							task.wait(attempt)
						end
					end
				end
			end
			local ok, policy = pcall(function(): any
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			-- Ушёл, пока проверяли (forget уже был): не держать игрока в таблицах.
			if player.Parent ~= Players then
				return
			end
			-- Купил пропуск, пока шла проверка, — не потерять.
			local early = owned[player]
			if early ~= nil then
				for key in early do
					set[key] = true
				end
			end
			owned[player] = set
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
