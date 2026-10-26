extends RefCounted

# ExitPower: питание двери выхода. Живёт в exit_manager, а не в двери,
# поэтому переживает выгрузку чанка: вставленные предохранители не
# теряются. Дверь только спрашивает состояние и вставляет по одному.

const NEEDED: int = 3

var inserted: int = 0
var powered: bool = false


# Вставить предохранитель. false — если питание уже есть
func insert() -> bool:
	if powered:
		return false
	inserted += 1
	if inserted >= NEEDED:
		powered = true
	return true


# 0..1 — на это смотрят и свечение двери, и строка цели в HUD
func level() -> float:
	return 1.0 if powered else float(inserted) / float(NEEDED)
