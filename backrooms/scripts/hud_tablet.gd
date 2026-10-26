extends Node

# HudTablet: в Bodycam нет постоянного интерфейса — ни прицела, ни счётчиков.
# Задача и банки живут «на планшете»: видны, пока держишь Tab, и на несколько
# секунд сами всплывают, когда что-то поменялось (подобрал предохранитель,
# бросил банку), и в начале забега. Тексты по-прежнему пишет hud.gd — здесь
# только когда их показать.

@export var objective_panel_path: NodePath
@export var inventory_panel_path: NodePath
@export var objective_label_path: NodePath
@export var cans_label_path: NodePath

const FLASH_TIME: float = 4.0
const START_TIME: float = 6.0
const FADE_SPEED: float = 5.0

@onready var panels: Array[Control] = [get_node(objective_panel_path) as Control,
	get_node(inventory_panel_path) as Control]
@onready var objective: Label = get_node(objective_label_path) as Label
@onready var cans: Label = get_node(cans_label_path) as Label

var alpha: float = 0.0
var flash: float = START_TIME
var last_text: String = ""


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	# Текст поменялся — всплываем. Первый кадр только запоминает: старт
	# уже показан своим START_TIME
	var text: String = objective.text + "|" + cans.text
	if text != last_text:
		if not last_text.is_empty():
			flash = FLASH_TIME
		last_text = text
	flash -= delta
	var want: float = 1.0 if Input.is_action_pressed("tablet") or flash > 0.0 else 0.0
	alpha = move_toward(alpha, want, delta * FADE_SPEED)
	_apply()


func _apply() -> void:
	for panel in panels:
		panel.modulate.a = alpha
		panel.visible = alpha > 0.01
