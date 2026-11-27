--!strict
-- §15ь Л3 «Отряд»: приглашения, ответ, лимит, выход лидера.
local T = require("./lib/TestKit")
local Config = require("../src/shared/Config")
local Party = require("../src/shared/Party")

T.describe("Отряд (§15ь Л3)", function()
	T.it(
		"позвал — принял: отряд с лидером первым; отказ — без отряда",
		function()
			local st = Party.new()
			T.expect((Party.invite(st, 1, 2, 0))).toBe(true)
			T.expect((Party.reply(st, 2, true, 5))).toBe(1)
			local members = Party.membersOf(st, 2)
			T.expect(#members).toBe(2)
			T.expect(members[1]).toBe(1)
			T.expect(Party.leaderOf(st, 2)).toBe(1)
			T.expect((Party.invite(st, 1, 3, 0))).toBe(true)
			T.expect((Party.reply(st, 3, false, 1))).toBe(nil)
			T.expect(#Party.membersOf(st, 3)).toBe(1)
		end
	)

	T.it(
		"нельзя: себя, звать не лидеру, звать занятого, просрочено, сверх лимита",
		function()
			local st = Party.new()
			T.expect(select(2, Party.invite(st, 1, 1, 0))).toBe("target")
			Party.invite(st, 1, 2, 0)
			Party.reply(st, 2, true, 0)
			T.expect(select(2, Party.invite(st, 2, 3, 0))).toBe("partyLeaderOnly")
			T.expect(select(2, Party.invite(st, 5, 2, 0))).toBe("partyTaken")
			Party.invite(st, 1, 3, 0)
			T.expect(select(2, Party.reply(st, 3, true, Config.Party.InviteSec + 1))).toBe("partyExpired")
			for u = 3, Config.Party.Max do
				Party.invite(st, 1, u, 0)
				Party.reply(st, u, true, 0)
			end
			T.expect(#Party.membersOf(st, 1)).toBe(Config.Party.Max)
			T.expect(select(2, Party.invite(st, 1, 99, 0))).toBe("partyFull")
		end
	)

	T.it(
		"ушёл лидер — лидер следующий; остался один — отряда нет",
		function()
			local st = Party.new()
			Party.invite(st, 1, 2, 0)
			Party.reply(st, 2, true, 0)
			Party.invite(st, 1, 3, 0)
			Party.reply(st, 3, true, 0)
			local told = Party.leave(st, 1)
			T.expect(#told).toBe(2)
			T.expect(Party.leaderOf(st, 3)).toBe(2)
			T.expect(Party.membersOf(st, 3)[1]).toBe(2)
			Party.leave(st, 3)
			T.expect(Party.leaderOf(st, 2)).toBe(nil)
			T.expect(#Party.membersOf(st, 2)).toBe(1)
		end
	)
end)

local ClientState = require("../src/shared/ClientState")
local Places = require("../src/shared/Places")

T.describe("Отряд на клиенте (§15ь Л3)", function()
	T.it(
		"сообщения отряда и приглашения: мусор отбрасывается, один участник — не отряд",
		function()
			local cs = ClientState.new(4, 4)
			local junk: { any } = {}
			table.insert(junk, { id = 1, name = "A", level = 5 })
			table.insert(junk, { id = 2, name = "B" }) -- без уровня — будет 1
			table.insert(junk, "x") -- мусор
			ClientState.applyParty(cs, { leader = 1, members = junk })
			local party = cs.party :: ClientState.PartyInfo
			T.expect(#party.members).toBe(2)
			T.expect(party.members[2].level).toBe(1)
			ClientState.applyParty(cs, { leader = 1, members = { { id = 1, name = "A" } } })
			T.expect(cs.party).toBe(nil)
			ClientState.applyParty(cs, "junk")
			T.expect(cs.party).toBe(nil)
			ClientState.applyPartyInvite(cs, { from = 7, name = "Друг", left = 9999 }, 100)
			local inv = cs.partyInvite :: ClientState.PartyInviteInfo
			T.expect(inv.from).toBe(7)
			T.expect(inv.untilAt).toBe(100 + Config.Party.InviteSec)
		end
	)

	T.it("приглашение Roblox несёт отряд: party — UserId лидера", function()
		local inv = Places.invite({ party = 12345 })
		T.expect(inv ~= nil and inv.party == 12345).toBe(true)
		T.expect(Places.invite({ party = -3 })).toBe(nil)
		T.expect(Places.invite({ party = 1.5 })).toBe(nil)
	end)
end)
