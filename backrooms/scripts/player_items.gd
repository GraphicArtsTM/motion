extends Node

# PlayerItems: что игрок несёт — предохранители из лабиринта и банки
# для отвлечения сущности. Только учёт и сигналы, никакого ввода:
# бросок — в throw_component.gd, дверь спрашивает про предохранители.

signal fuses_changed(count: int)
signal cans_changed(count: int)

@export var start_cans: int = 5

var fuses: int = 0
var cans: int = 0


func _ready() -> void:
	add_to_group("player_items")
	cans = start_cans
	cans_changed.emit(cans)


func add_fuse() -> void:
	fuses += 1
	fuses_changed.emit(fuses)


func take_fuse() -> bool:
	if fuses <= 0:
		return false
	fuses -= 1
	fuses_changed.emit(fuses)
	return true


# Заначка в лагере разведчика (camp.gd)
func add_cans(count: int) -> void:
	if count <= 0:
		return
	cans += count
	cans_changed.emit(cans)


func take_can() -> bool:
	if cans <= 0:
		return false
	cans -= 1
	cans_changed.emit(cans)
	return true
