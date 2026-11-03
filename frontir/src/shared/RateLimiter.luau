--!strict
--[[
	RateLimiter — «ведро с жетонами» для лимита запросов от игрока (GDD §12, §14).
	Ведро вмещает capacity жетонов и пополняется refillPerSec в секунду; запрос тратит один жетон.
]]

export type RateLimiter = {
	capacity: number,
	refillPerSec: number,
	tokens: number,
	last: number,
	dropped: number,
}

local RateLimiter = {}

function RateLimiter.new(capacity: number, refillPerSec: number, now: number): RateLimiter
	return { capacity = capacity, refillPerSec = refillPerSec, tokens = capacity, last = now, dropped = 0 }
end

-- Можно ли выполнить запрос сейчас (и списать жетон).
function RateLimiter.allow(rl: RateLimiter, now: number): boolean
	local elapsed = math.max(0, now - rl.last)
	rl.last = now
	rl.tokens = math.min(rl.capacity, rl.tokens + elapsed * rl.refillPerSec)
	if rl.tokens >= 1 then
		rl.tokens -= 1
		return true
	end
	rl.dropped += 1
	return false
end

return table.freeze(RateLimiter)
