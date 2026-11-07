--!strict
--[[
	LogoArt — логотип «WORLD CONQUER» (GDD §15л ч.5): картинка геймдизайнера, переведённая в пиксели палитры
	(сетка ~12.7 px исходника → 1 пиксель, фон «в клеточку» убран). Строка — ряд сверху вниз, знак — цвет:
	"." — прозрачно, остальные — Keys (имена палитры). Клиент рисует в EditableImage (UI/Logo).
]]

local LogoArt = {}

LogoArt.W = 149
LogoArt.H = 21
LogoArt.Keys = table.freeze({ k = "Ink", s = "Slate", t = "Steel", m = "Mist", w = "White", g = "Gold", o = "Orange" })

-- stylua: ignore
LogoArt.Rows = table.freeze({
	"...................kkkkk..kkkkk.kkkkkkk.kkkkkkkkk..kkkkk....kkkkkkkkk.......kkkkkkkk...kkkkkkk..kkkk..kkkkk.kkkkkkkk.kkkkk.kkkkkkkkkkkkkkkkkkkkkkkk..",
	"...................kgggk..kgggkkgggggggkkggggggggkkkgggk....kggggggggk......kggggggkkkkggggggkkkkggkk.kgggkkkggggggkkkgggk.kgggkkggggggggkkggggggggk.",
	".kkk..........kkk..kgggk..kgggkkgggggggkkggggggggkkkgggk....kggggggggkk....kkggggggkkkkgggggggkkkgggk.kgggkkkggggggkkkgggk.kgggkkggggggggkkggggggggkk",
	".kwsk..........sk..kgggk..kgggkgggooogggkgggooogggkkgggk....kgggooogggk....kgggooggggkgggooogggkkggggkkgggkkgggooggggkgggk.kgggkkgggoooookkgggooogggk",
	".kwwkk......k.skk..kgggk..kgggkgggooogggkgggooogggkkgggk....kgggooogggk....kgggooogggkgggooogggkkggggkkgggkkgggooogggkgggk.kgggkkgggooooookgggooogggk",
	"..kwkkk....kwkkk...kgggk..kgggkgggkkkgggkgggkkkgggkkgggk....kgggkkkgggk....kgggkkkgggkgggkkkgggkkgggggkgggkkgggkkkgggkgggk.kgggkkgggkkkkkkkgggkkkgggk",
	"...kwssk..kwksk....kgggk..kgggkgggkkkgggkgggk.kgggkkgggk....kgggkkkgggk....kgggkkkoookgggkkkgggkkgggggkgggkkgggkkkgggkgggk.kgggkkgggk.....kgggk.kgggk",
	"....kwkkkkwwsk.....kgggkkkkgggkgggk.kgggkgggkkkgggkkgggk....kgggk.kgggk...kkgggk.kkkkkgggk.kgggkkgggggggggkkgggkkkgggkgggk.kgggkkgggkkkkk.kgggkkkgggk",
	"....kkwkkwwkk......kgggkkkkgggkgggk.kgggkgggkkkgggkkgggk....kgggk.kgggk....kgggk.....kgggk.kgggkkgggggggggkkgggk.kgggkgggk.kgggkkgggkkkkk.kgggkkkgggk",
	"......kkwksk.......kgggkggkgggkgggk.kgggkggggggggokkgggk....kgggk.kgggk...kkgggk.....kgggk.kgggkkgggggggggkkgggkkkgggkgggk.kgggkkgggggggk.kggggggggok",
	"......kwkkkk.......kggggggggggkgggk.kgggkgggggggkkkkgggk....kgggk.kgggk....kgggk.....kgggk.kgggkkgggogggggkkgggk.kgggkgggk.kgggkkgggggggk.kggggggggkk",
	".....kwwkkkkk......kggggggggggkgggk.kgggkgggoooggkkkgggk....kgggk.kgggk....kgggk.....kgggk.kgggkkgggkoggggkkgggkkkgggkgggk.kgggkkgggooook.kgggoooggkk",
	"..kkkwwsk..kkkkkk..kggggggggggkgggk.kgggkgggkkkgggkkgggk....kgggk.kgggk....kgggk.kkkkkgggk.kgggkkgggkkggggkkgggkkggggkgggk.kgggkkgggkkkkk.kgggkkkgggk",
	"..kkkwkk.k..kkkkk..kggggggggggkgggk.kgggkgggkkkgggkkgggk....kgggk.kgggk...kkgggk.kgggkgggk.kgggkkgggkkggggkkgggggggggkgggk.kgggkkgggkkkk..kgggkkkgggk",
	"..kkgkk....kkgkk...kggggokggggkgggkkkgggkgggk.kgggkkgggkkkkkkgggkkkgggk....kgggkkggggkgggkkkgggkkgggk.kgggkkgggkgggggkgggkkkgggkkgggkkkkkkkgggk.kgggk",
	"..kskgkk...kgkkk...koggokkoggokogggggggokgggk.kgggkkggggggggkggggggggok....kogggggggokogggggggokkgggk.kgggkkggggggggkkogggggggokkggggggggkkgggk.kgggk",
	"..kkkkgk..kgkkssk..kkggkkkkggkkkogggggokkgggk.kgggkkggggggggkgggggggokk....kkggggggokkkogggggokkkgggk.kgggkkogggggggkkkogggggokkkggggggggkkgggk.kgggk",
	"kksk.kkk..kkk.kkkk..kggk..kggk.kkgggggkkkgggk.kgggkkggggggggkgggggggkk......kggggggkk.kkgggggkk.kgggk.kgggkkkggggggggkkkgggggkk.kggggggggkkgggk.kgggk",
	"kgk............kkk..kook..kook..koooook.koook.koookkooooooookoooooook........koooook...koooook..koook.koook.kooooooggk.koooook..kooooooookkoook.koook",
	"kk..............kk..kkkk..kkkk..kkkkkkk.kkkkk.kkkkkkkkkkkkkkkkkkkkkkk........kkkkkk....kkkkkkk..kkkkk.kkkkk..kkkkkkkkk.kkkkkkk..kkkkkkkkkkkkkkk.kkkkk",
	".................................................................................................................kkkkk...............................",
})

return table.freeze(LogoArt)
