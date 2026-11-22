--!strict
--[[
	OfferQueue — входящие предложения по одному (GDD §15й Й6), без Roblox API: какие ждут ответа (адресованы мне,
	ещё не отвечены, время не вышло), самое срочное — первым; ключ предложения; доля оставшегося времени для полосы.
]]

export type Offer = { kind: string, from: number, to: number, left: number }

local OfferQueue = {}

function OfferQueue.key(o: Offer): string
	return string.format("%d:%d:%s", o.from, o.to, o.kind)
end

-- Ждущие ответа предложения державе me: leftOf(o) — сколько ещё секунд; самые срочные — первыми.
function OfferQueue.pending(
	offers: { Offer },
	me: number?,
	answered: { [string]: boolean },
	leftOf: (o: Offer) -> number
): { Offer }
	local out: { Offer } = {}
	if me == nil then
		return out
	end
	for _, o in offers do
		if o.to == me and not answered[OfferQueue.key(o)] and leftOf(o) > 0 then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a: Offer, b: Offer): boolean
		local la, lb = leftOf(a), leftOf(b)
		if la ~= lb then
			return la < lb
		end
		return OfferQueue.key(a) < OfferQueue.key(b)
	end)
	return out
end

-- Доля оставшегося времени 0..1; total — сколько было, когда предложение впервые пришло.
function OfferQueue.share(left: number, total: number): number
	return math.clamp(left / math.max(total, 1e-6), 0, 1)
end

return table.freeze(OfferQueue)
