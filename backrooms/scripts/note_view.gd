extends PanelContainer

# NoteView: прочитанная записка поверх кадра — листок из блокнота, тёмные
# чернила. Игру не останавливает: хозяин лабиринта ходит и пока ты читаешь,
# поэтому закрывается сам, если отойти. F или Esc убирают листок (Esc здесь
# перехватывается раньше паузы). Счётчик «ЗАПИСКИ n/10» на планшете ведёт
# тоже он: hud_tablet.gd всплывает, когда текст счётчика меняется.

const NoteTexts = preload("res://scripts/note_texts.gd")

# Отошёл дальше — листок убран в карман
const WALK_AWAY: float = 3.5
const FADE_SPEED: float = 7.0

@export var page_label_path: NodePath
@export var title_label_path: NodePath
@export var body_label_path: NodePath
@export var counter_label_path: NodePath

@onready var page_label: Label = get_node(page_label_path) as Label
@onready var title_label: Label = get_node(title_label_path) as Label
@onready var body_label: Label = get_node(body_label_path) as Label
@onready var counter_label: Label = get_node(counter_label_path) as Label

var open: bool = false
var origin := Vector3.ZERO
var player: Node3D = null


func _ready() -> void:
	add_to_group("note_view")
	visible = false
	modulate.a = 0.0
	counter_label.text = counter_text(0, NoteTexts.count())


static func counter_text(read: int, total: int) -> String:
	return "ЗАПИСКИ %d/%d" % [read, total]


func show_note(index: int, read: int, total: int) -> void:
	page_label.text = "ЗАПИСКА %d/%d · M.E.G." % [index + 1, total]
	title_label.text = NoteTexts.title(index)
	body_label.text = NoteTexts.body(index)
	counter_label.text = counter_text(read, total)
	player = get_tree().get_first_node_in_group("player") as Node3D
	origin = player.global_position if player else Vector3.ZERO
	open = true
	visible = true


func close() -> void:
	open = false


func _input(event: InputEvent) -> void:
	if not open:
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event as InputEventKey).physical_keycode == KEY_ESCAPE
	if esc or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if open and player and player.global_position.distance_to(origin) > WALK_AWAY:
		close()
	modulate.a = move_toward(modulate.a, 1.0 if open else 0.0, delta * FADE_SPEED)
	visible = modulate.a > 0.01
