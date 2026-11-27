--!strict
--[[
	Party — §15ь Л3 «Отряд», без Roblox API: игроки одного сервера хаба собираются в отряд и едут в матч вместе.
	Лидер (или одиночка) зовёт игрока, тот принимает за Party.InviteSec; в отряде не больше Party.Max. Ушёл лидер —
	лидер следующий по порядку; остался один — отряда нет. Ключи — UserId.
]]

local Config = require("./Config")

export type Group = { leader: number, members: { number } } -- members — с лидером, первым
export type State = {
	groups: { [number]: Group }, -- лидер → отряд
	of: { [number]: number }, -- участник → лидер
	invites: { [number]: { from: number, at: number } }, -- кого позвали → кто и когда
}

local Party = {}

function Party.new(): State
	return { groups = {}, of = {}, invites = {} }
end

function Party.leaderOf(st: State, user: number): number?
	return st.of[user]
end

-- Участники отряда user (лидер первым); не в отряде — только он сам.
function Party.membersOf(st: State, user: number): { number }
	local leader = st.of[user]
	local g = if leader ~= nil then st.groups[leader] else nil
	return if g ~= nil then table.clone(g.members) else { user }
end

-- from зовёт to. Нельзя: себя, участник чужого отряда (не лидер) зовёт, to уже в отряде, отряд полон.
function Party.invite(st: State, from: number, to: number, now: number): (boolean, string?)
	if from == to then
		return false, "target"
	end
	local leader = st.of[from]
	if leader ~= nil and leader ~= from then
		return false, "partyLeaderOnly"
	end
	if st.of[to] ~= nil then
		return false, "partyTaken"
	end
	if #Party.membersOf(st, from) >= Config.Party.Max then
		return false, "partyFull"
	end
	st.invites[to] = { from = from, at = now }
	return true, nil
end

-- to отвечает на приглашение; принял — вернёт лидера отряда.
function Party.reply(st: State, to: number, accept: boolean, now: number): (number?, string?)
	local inv = st.invites[to]
	st.invites[to] = nil
	if inv == nil or now - inv.at > Config.Party.InviteSec then
		return nil, "partyExpired"
	end
	if not accept then
		return nil, nil
	end
	local from = inv.from
	local leader = st.of[from]
	if (leader ~= nil and leader ~= from) or st.of[to] ~= nil then
		return nil, "partyTaken"
	end
	local g = st.groups[from]
	if g == nil then
		g = { leader = from, members = { from } }
		st.groups[from] = g
		st.of[from] = from
	end
	if #g.members >= Config.Party.Max then
		return nil, "partyFull"
	end
	table.insert(g.members, to)
	st.of[to] = from
	return from, nil
end

-- user выходит (или ушёл с сервера). Вернёт участников, которым надо сообщить (кроме него).
function Party.leave(st: State, user: number): { number }
	st.invites[user] = nil
	-- Его приглашения больше не действуют (иначе принявший попал бы в отряд без лидера на сервере).
	for to, inv in st.invites do
		if inv.from == user then
			st.invites[to] = nil
		end
	end
	local leader = st.of[user]
	if leader == nil then
		return {}
	end
	local g = st.groups[leader]
	st.of[user] = nil
	if g == nil then
		return {}
	end
	local at = table.find(g.members, user)
	if at ~= nil then
		table.remove(g.members, at)
	end
	st.groups[leader] = nil
	if #g.members <= 1 then
		for _, u in g.members do
			st.of[u] = nil
		end
		return g.members
	end
	local newLeader = g.members[1]
	g.leader = newLeader
	st.groups[newLeader] = g
	for _, u in g.members do
		st.of[u] = newLeader
	end
	return table.clone(g.members)
end

return table.freeze(Party)
