extends RigidBody3D

# CanProjectile: брошенная банка. Летит, звенит от первого удара во что
# угодно, кроме самого игрока, и зовёт сущность на точку падения.
# Через несколько секунд тихо исчезает.

const PropItems = preload("res://scripts/prop_items.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")

const NOISE_RADIUS: float = 22.0
const LIFETIME: float = 8.0
const FALL_LIMIT: float = -8.0

var struck: bool = false
var active: bool = false
var sound: AudioStreamPlayer3D = null
var prev_pos := Vector3.ZERO
var exclude_rids: Array[RID] = []


func _ready() -> void:
	mass = 0.2
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	# Мир — тримеш без толщины: без CCD мелкая быстрая банка прошьёт пол
	continuous_cd = true
	var built: Dictionary = PropItems.build_can()
	add_child(built["root"])
	# Коллайдер обязан быть ПРЯМЫМ ребёнком тела, иначе физика его не увидит
	add_child(built["shape"])
	sound = AudioBank.source("SFX", AudioBank.can_clang(), 16.0)
	sound.max_distance = 45.0
	sound.volume_db = 2.0
	add_child(sound)
	body_entered.connect(_on_body_entered)
	# Таймер с паузой: на паузе банка не должна исчезать
	get_tree().create_timer(LIFETIME, false).timeout.connect(queue_free)


# Бросок закончен, позиция выставлена — только теперь банка «в полёте»
func start() -> void:
	prev_pos = global_position
	active = true
	var player = get_tree().get_first_node_in_group("player")
	if player is CollisionObject3D:
		exclude_rids = [(player as CollisionObject3D).get_rid()]


func _physics_process(_delta: float) -> void:
	if struck or not active:
		return
	var pos := global_position
	# Кроме штатных контактов — луч по пройденному за кадр отрезку:
	# так удар ловится даже там, где коллайдер пролетает навылет
	var query := PhysicsRayQueryParameters3D.create(prev_pos, pos, 1, exclude_rids)
	prev_pos = pos
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_ring()
	if global_position.y < FALL_LIMIT:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not active or body.is_in_group("player"):
		return
	_ring()


func _ring() -> void:
	if struck:
		return
	struck = true
	sound.play()
	# Звон зовёт сущность на точку падения — слух общий, через NoiseBus
	var bus = get_tree().get_first_node_in_group("noise_bus")
	if bus:
		bus.emit_noise(global_position, NOISE_RADIUS)
