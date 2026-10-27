extends Node3D

# Camp: лагерь разведчика в тупике — ориентир и передышка. Тёплый живой
# огонёк фонаря видно издалека, особенно в мёртвом участке. Он не любит
# хозяина лабиринта, как и лампы: рядом с сущностью язычок захлёбывается
# (та же помеха, что в lamp_haunt.gd). В заначке — пара банок (F), берётся
# один раз: учёт у camp_spawner.gd по сигналу looted.

const PropCamp = preload("res://scripts/prop_camp.gd")
const LampHaunt = preload("res://scripts/lamp_haunt.gd")

signal looted

const CANS: int = 2
const PICK_RANGE: float = 2.0
const FLAME_ENERGY: float = 1.3
const HINT_TEXT: String = "Лагерь разведчика. F — забрать банки (+%d)"

var has_stash: bool = true
var hud = null
var items = null
var light: OmniLight3D = null
var stash_node: Node3D = null
var entity: Node3D = null
var player_inside: bool = false
var time: float = 0.0


func _ready() -> void:
	add_child(PropCamp.camp())
	var glass := PropCamp.glass()
	glass.position = PropCamp.LANTERN_POS
	add_child(glass)
	light = OmniLight3D.new()
	light.position = PropCamp.FLAME_POS
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = FLAME_ENERGY
	light.omni_range = 7.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	time = randf() * 10.0
	if not has_stash:
		return
	stash_node = PropCamp.stash()
	stash_node.position = PropCamp.STASH_POS
	add_child(stash_node)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICK_RANGE
	shape.shape = sphere
	shape.position = Vector3(0, 0.6, -0.6)
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


# Огонёк: медленное дыхание пламени и редкие провалы, у сущности — чаще
func _process(delta: float) -> void:
	time += delta
	if entity == null or not is_instance_valid(entity):
		var voice: Node = get_tree().get_first_node_in_group("entity_voice")
		entity = voice.get_parent() as Node3D if voice else null
	var flame: float = 0.88 + 0.08 * sin(time * 2.3) + 0.05 * sin(time * 7.9 + 1.3)
	if entity and bool(entity.get("placed")):
		var amount: float = LampHaunt.haunt_amount(_flat(entity.global_position), false)
		if fposmod(sin(floor(time * 12.0) * 78.233) * 43758.5, 1.0) < amount:
			flame *= 0.15
	light.light_energy = FLAME_ENERGY * flame


func take() -> int:
	if not has_stash:
		return 0
	has_stash = false
	player_inside = false
	if stash_node:
		stash_node.queue_free()
	looted.emit()
	return CANS


func _unhandled_input(event: InputEvent) -> void:
	if not player_inside or not has_stash or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	var got: int = take()
	if items and items.has_method("add_cans"):
		items.add_cans(got)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or not has_stash:
		return
	player_inside = true
	if hud and hud.has_method("show_hint"):
		hud.show_hint(HINT_TEXT % CANS, 3.0)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = false


func _flat(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
