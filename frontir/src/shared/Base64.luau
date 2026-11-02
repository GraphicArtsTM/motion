--!strict
--[[
	Base64 — упаковка бинарных данных (buffer) в строку и обратно (стандартный алфавит, с '=').
	Нужна, чтобы хранить бинарную карту в ModuleScript как обычные строки.
]]

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local encodeTable: { string } = {}
local decodeTable: { [number]: number } = {}
for i = 1, 64 do
	local ch = string.sub(ALPHABET, i, i)
	encodeTable[i - 1] = ch
	decodeTable[string.byte(ch)] = i - 1
end

local Base64 = {}

function Base64.encode(data: buffer): string
	local len = buffer.len(data)
	local out: { string } = table.create(math.ceil(len / 3))
	local i = 0
	while i < len do
		local b0 = buffer.readu8(data, i)
		local b1 = if i + 1 < len then buffer.readu8(data, i + 1) else 0
		local b2 = if i + 2 < len then buffer.readu8(data, i + 2) else 0
		local n = b0 * 65536 + b1 * 256 + b2
		local c0 = encodeTable[n // 262144]
		local c1 = encodeTable[(n // 4096) % 64]
		local c2 = if i + 1 < len then encodeTable[(n // 64) % 64] else "="
		local c3 = if i + 2 < len then encodeTable[n % 64] else "="
		table.insert(out, c0 .. c1 .. c2 .. c3)
		i += 3
	end
	return table.concat(out)
end

function Base64.decode(text: string): buffer
	local len = #text
	if len % 4 ~= 0 then
		error("base64: длина не кратна 4", 2)
	end
	local padding = 0
	if len > 0 and string.sub(text, -1) == "=" then
		padding += 1
		if string.sub(text, -2, -2) == "=" then
			padding += 1
		end
	end
	local outLen = len // 4 * 3 - padding
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local n = 0
		for k = 0, 3 do
			local byte = string.byte(text, i + k)
			local v: number
			if byte == 61 then -- '='
				if i + k <= len - padding then
					error("base64: '=' посреди данных", 2)
				end
				v = 0
			else
				local d = decodeTable[byte]
				if d == nil then
					error(string.format("base64: недопустимый символ %q", string.char(byte)), 2)
				end
				v = d
			end
			n = n * 64 + v
		end
		if o < outLen then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

return table.freeze(Base64)
