--!strict
local T = require("./lib/TestKit")
local Base64 = require("../src/shared/Base64")
local Bits = require("../src/shared/Bits")
local Noise = require("../src/shared/Noise")
local Rng = require("../src/shared/Rng")

T.describe("Bits", function()
	T.it("mul32 — умножение по модулю 2^32", function()
		T.expect(Bits.mul32(0xFFFFFFFF, 0xFFFFFFFF)).toBe(1)
		T.expect(Bits.mul32(0x10000, 0x10000)).toBe(0)
		T.expect(Bits.mul32(123456, 789)).toBe(123456 * 789)
		T.expect(Bits.mul32(0x9E3779B1, 3)).toBe((0x9E3779B1 * 3) % 4294967296)
	end)

	T.it(
		"hash2 детерминирован, в диапазоне и различает координаты",
		function()
			local a = Bits.hash2(10, 20, 7)
			T.expect(a).toBe(Bits.hash2(10, 20, 7))
			T.expect(a >= 0 and a < 4294967296).toBe(true)
			T.expect(a ~= Bits.hash2(20, 10, 7)).toBe(true)
			T.expect(a ~= Bits.hash2(10, 20, 8)).toBe(true)
		end
	)
end)

T.describe("Rng", function()
	T.it("одинаковый сид — одинаковая последовательность", function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 100 do
			T.expect(Rng.nextU32(a)).toBe(Rng.nextU32(b))
		end
	end)

	T.it("range даёт границы включительно и не выходит за них", function()
		local rng = Rng.new(1)
		local seenLo, seenHi = false, false
		for _ = 1, 2000 do
			local v = Rng.range(rng, 3, 6)
			T.expect(v >= 3 and v <= 6 and v == math.floor(v)).toBe(true)
			seenLo = seenLo or v == 3
			seenHi = seenHi or v == 6
		end
		T.expect(seenLo and seenHi).toBe(true)
	end)

	T.it("распределение nextFloat примерно равномерное", function()
		local rng = Rng.new(99)
		local sum = 0
		for _ = 1, 10000 do
			sum += Rng.nextFloat(rng)
		end
		T.expect(sum / 10000).toBeNear(0.5, 0.02)
	end)
end)

T.describe("Noise", function()
	T.it("value2 в [0,1) и непрерывен", function()
		for i = 0, 200 do
			local x = i * 0.137
			local v = Noise.value2(x, x * 0.5, 5)
			T.expect(v >= 0 and v < 1).toBe(true)
			T.expect(math.abs(Noise.value2(x + 0.001, x * 0.5, 5) - v) < 0.01).toBe(true)
		end
	end)

	T.it("fbm и ridged в [0,1]", function()
		for i = 0, 200 do
			local f = Noise.fbm(i * 0.31, i * 0.17, 3, 5, 2, 0.5)
			local r = Noise.ridged(i * 0.31, i * 0.17, 3, 4, 2, 0.5)
			T.expect(f >= 0 and f <= 1).toBe(true)
			T.expect(r >= 0 and r <= 1).toBe(true)
		end
	end)
end)

T.describe("Base64", function()
	local function fromString(s: string): buffer
		return buffer.fromstring(s)
	end

	T.it("известные векторы RFC 4648", function()
		T.expect(Base64.encode(fromString(""))).toBe("")
		T.expect(Base64.encode(fromString("f"))).toBe("Zg==")
		T.expect(Base64.encode(fromString("fo"))).toBe("Zm8=")
		T.expect(Base64.encode(fromString("foo"))).toBe("Zm9v")
		T.expect(Base64.encode(fromString("foobar"))).toBe("Zm9vYmFy")
		T.expect(buffer.tostring(Base64.decode("Zm9vYmE="))).toBe("fooba")
	end)

	T.it("туда и обратно для всех байтов", function()
		local data = buffer.create(256 * 3 + 1)
		for i = 0, buffer.len(data) - 1 do
			buffer.writeu8(data, i, (i * 7) % 256)
		end
		T.expect(buffer.tostring(Base64.decode(Base64.encode(data)))).toBe(buffer.tostring(data))
	end)

	T.it("мусор во входе — ошибка", function()
		T.expect(function()
			Base64.decode("abc")
		end).toThrow()
		T.expect(function()
			Base64.decode("ab!d")
		end).toThrow()
		T.expect(function()
			Base64.decode("a=bc")
		end).toThrow()
	end)
end)
