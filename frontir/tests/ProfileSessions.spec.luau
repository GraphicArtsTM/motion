--!strict
-- Сессии профилей (GDD §11.2, правка по аудиту): ложный успех сохранения, покупки только после записи, гонка
-- «вышел, пока профиль грузился». Хранилище — подделка DataStore (копия при чтении и записи, как сериализация).
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Profile = require("../src/shared/Profile")
local ProfileSessions = require("../src/shared/ProfileSessions")

type Fake = {
	records: { [string]: any },
	calls: number,
	fail: boolean,
	yieldOnUpdate: boolean,
	before: (() -> ())?, -- до transform (другой сервер или игрок успели что-то сделать)
	store: ProfileSessions.Store,
}

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

local function fake(): Fake
	local f: Fake = {} :: any
	f.records = {}
	f.calls = 0
	f.fail = false
	f.yieldOnUpdate = false
	f.store = {
		update = function(key: string, transform: (old: any) -> any): (boolean, string?)
			f.calls += 1
			if f.yieldOnUpdate then
				coroutine.yield() -- запрос к DataStore «в пути»
			end
			local hook = f.before
			if hook ~= nil then
				f.before = nil
				hook()
			end
			if f.fail then
				return false, "DataStore error"
			end
			local result = transform(copy(f.records[key]))
			if result ~= nil then
				f.records[key] = copy(result)
			end
			return true, nil
		end,
	}
	return f
end

local clock = 1000
local yieldWaits = false -- ожидание уступает ход (только внутри своих сопрограмм теста)
local function manager(f: Fake?, jobId: string?): ProfileSessions.Manager
	return ProfileSessions.new({
		store = if f ~= nil then f.store else nil,
		jobId = jobId or "A",
		now = function(): number
			return clock
		end,
		wait = function(sec: number)
			clock += sec
			if yieldWaits then
				coroutine.yield()
			end
		end,
	})
end

local KEY = ProfileSessions.key(1)

local function grantMedals(n: number): (Profile.Data) -> boolean
	return function(d: Profile.Data): boolean
		d.medals += n
		return true
	end
end

T.describe("Сессии профилей: сохранение (правка по аудиту)", function()
	T.it(
		"загрузка берёт блокировку, сохранение пишет данные и продлевает её",
		function()
			local f = fake()
			local m = manager(f)
			local s = m.load(1)
			T.expect(s.saving).toBe(true)
			T.expect(f.records[KEY].lock.jobId).toBe("A")
			s.data.medals = 77
			T.expect(m.save(1)).toBe(true)
			T.expect(f.records[KEY].data.medals).toBe(77)
		end
	)

	T.it(
		"блокировку забрал другой сервер — сохранение НЕ успех, чужие данные целы, автосохранение молчит",
		function()
			local f = fake()
			local m = manager(f)
			local s = m.load(1)
			f.records[KEY].lock = { jobId = "B", at = clock }
			f.records[KEY].data.medals = 5 -- данные сервера B
			s.data.medals = 999
			T.expect(m.save(1)).toBe(false)
			T.expect(s.saving).toBe(false)
			T.expect(f.records[KEY].data.medals).toBe(5)
			local calls = f.calls
			m.autosave()
			T.expect(f.calls).toBe(calls)
		end
	)

	T.it("ошибка DataStore — сохранение не успех", function()
		local f = fake()
		local m = manager(f)
		m.load(1)
		f.fail = true
		T.expect(m.save(1)).toBe(false)
	end)

	T.it("снятая (nil) блокировка — тоже не наша: не пишем", function()
		local f = fake()
		local m = manager(f)
		m.load(1)
		f.records[KEY].lock = nil
		T.expect(m.save(1)).toBe(false)
	end)

	T.it(
		"чужая живая блокировка — профиль только в памяти; старая — забираем",
		function()
			local f = fake()
			f.records[KEY] = { data = Profile.new(), lock = { jobId = "B", at = clock } }
			local m = manager(f)
			local s = m.load(1)
			T.expect(s.saving).toBe(false)
			T.expect(f.records[KEY].lock.jobId).toBe("B")
			local g = fake()
			g.records[KEY] =
				{ data = Profile.new(), lock = { jobId = "B", at = clock - Config.Profile.LockStaleSec - 1 } }
			T.expect(manager(g).load(1).saving).toBe(true)
			T.expect(g.records[KEY].lock.jobId).toBe("A")
		end
	)
end)

T.describe(
	"Сессии профилей: выход во время загрузки (правка по аудиту)",
	function()
		T.it(
			"вышел, пока грузился: блокировка снята, сессии нет, автосохранение не продлевает",
			function()
				local f = fake()
				local m = manager(f)
				f.before = function()
					m.release(1) -- PlayerRemoving пришёл, пока UpdateAsync в пути
				end
				local s = m.load(1)
				T.expect(s.released).toBe(true)
				T.expect(m.get(1)).toBe(nil)
				T.expect(m.loading(1)).toBe(false)
				T.expect(f.records[KEY].lock).toBe(nil)
				local calls = f.calls
				m.autosave()
				T.expect(f.calls).toBe(calls)
			end
		)

		T.it(
			"вернулся до конца загрузки — та же загрузка, сессия одна и с блокировкой",
			function()
				local f = fake()
				f.yieldOnUpdate = true
				yieldWaits = true
				local m = manager(f)
				local first: ProfileSessions.Session? = nil
				local co1 = coroutine.create(function()
					first = m.load(1)
				end)
				coroutine.resume(co1) -- запрос в пути
				m.release(1) -- вышел
				local second: ProfileSessions.Session? = nil
				local co2 = coroutine.create(function()
					second = m.load(1) -- и вернулся
				end)
				coroutine.resume(co2) -- ждёт первую загрузку
				f.yieldOnUpdate = false
				coroutine.resume(co1)
				coroutine.resume(co2)
				yieldWaits = false
				T.expect(first ~= nil and first == second).toBe(true)
				T.expect(m.get(1) == first).toBe(true)
				T.expect(f.records[KEY].lock.jobId).toBe("A")
				T.expect((first :: ProfileSessions.Session).released).toBe(false)
			end
		)

		T.it(
			"выход: сессия убрана сразу, блокировка снята; закрытие сервера снимает все",
			function()
				local f = fake()
				local m = manager(f)
				m.load(1)
				m.load(2)
				m.release(1)
				T.expect(m.get(1)).toBe(nil)
				T.expect(f.records[KEY].lock).toBe(nil)
				m.closeAll()
				T.expect(m.get(2)).toBe(nil)
				T.expect(f.records[ProfileSessions.key(2)].lock).toBe(nil)
			end
		)
	end
)

T.describe(
	"Покупки: «куплено» только после записи (правка по аудиту)",
	function()
		T.it("запись прошла — granted, начисление уже в хранилище", function()
			local f = fake()
			local m = manager(f)
			m.load(1)
			T.expect(m.grant(1, grantMedals(10), false)).toBe("granted")
			T.expect(f.records[KEY].data.medals).toBe(10)
		end)

		T.it(
			"профиль только в памяти — retry и ничего не начислено; в Studio можно",
			function()
				local f = fake()
				f.records[KEY] = { data = Profile.new(), lock = { jobId = "B", at = clock } }
				local m = manager(f)
				local s = m.load(1)
				local called = false
				T.expect(m.grant(1, function(_d: Profile.Data): boolean
					called = true
					return true
				end, false)).toBe("retry")
				T.expect(called).toBe(false)
				T.expect(m.grant(1, grantMedals(3), true)).toBe("granted")
				T.expect(s.data.medals).toBe(3)
				T.expect(manager(nil).grant(1, grantMedals(1), false)).toBe("retry") -- профиля нет
			end
		)

		T.it(
			"запись не прошла или блокировку забрали — retry (Roblox повторит)",
			function()
				local f = fake()
				local m = manager(f)
				m.load(1)
				f.fail = true
				T.expect(m.grant(1, grantMedals(1), false)).toBe("retry")
				f.fail = false
				f.records[KEY].lock = { jobId = "B", at = clock }
				T.expect(m.grant(1, grantMedals(1), false)).toBe("retry")
			end
		)

		T.it(
			"повтор той же покупки после сбоя записи не задваивает (PurchaseId)",
			function()
				local f = fake()
				local m = manager(f)
				m.load(1)
				local function buy(d: Profile.Data): boolean
					return Profile.grantProduct(d, "unlock", "All", "p-1", clock)
				end
				f.fail = true
				T.expect(m.grant(1, buy, false)).toBe("retry")
				f.fail = false
				T.expect(m.grant(1, buy, false)).toBe("granted")
				local purchases = f.records[KEY].data.purchases
				local n = 0
				for _, id in purchases do
					if id == "p-1" then
						n += 1
					end
				end
				T.expect(n).toBe(1)
			end
		)
	end
)
