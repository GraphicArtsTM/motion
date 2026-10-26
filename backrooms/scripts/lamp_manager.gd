extends Node3D

# LampManager: панели на потолке каждой ячейки чанка (один меш на чанк,
# мерцание в шейдере) + один OmniLight на чанк + гул ламп в AudioStreamPlayer3D.
# Гул — синтезированная петля из audio_bank.gd, аудиофайлов нет вообще.
# В тёмных участках (darkness.gd) панели мертвы, света и гула нет — там
# остаётся только фонарь игрока. С порчей (world_decay.gd) лампы тусклее,
# мёртвых панелей больше, свет уходит в больной зелёный, и всё чаще лампа
# чанка мигает (lamp_flicker.gd).

const MazeChunk = preload("res://scripts/maze_chunk.gd")
const AudioBank = preload("res://scripts/audio_bank.gd")
const Darkness = preload("res://scripts/darkness.gd")
const LampMesh = preload("res://scripts/lamp_mesh.gd")
const LampFlicker = preload("res://scripts/lamp_flicker.gd")
const WorldDecay = preload("res://scripts/world_decay.gd")
const LampHaunt = preload("res://scripts/lamp_haunt.gd")

const WALL_H: float = 2.8
const LIGHT_ENERGY: float = 1.1
# 26, а не 20: лампа в центре чанка 32×32 м должна дотягиваться до углов
const LIGHT_RANGE: float = 26.0
const HUM_VOLUME_DB: float = -24.0

var lamp_shader: Shader
var chunk_nodes: Dictionary = {}


func _ready() -> void:
	lamp_shader = load("res://shaders/lamp_panel.gdshader") as Shader
	# Помехи от сущности: гасит и дёргает лампы рядом с ней (lamp_haunt.gd)
	var haunt := LampHaunt.new()
	haunt.lamps = self
	add_child(haunt)


func add_lamps(chunk) -> void:
	var pos := Vector2i(chunk.chunk_x, chunk.chunk_y)
	if chunk_nodes.has(pos):
		return

	var origin: Vector3 = chunk.get_world_position()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = LampMesh.build(lamp_shader)
	mesh_instance.position = origin
	mesh_instance.add_to_group("lamp_panels")
	add_child(mesh_instance)

	# Тьма по чанкам: часть пролётов заметно темнее — статично,
	# детерминированно от координат, чтобы мир не «дышал» хором
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos) & 0x7FFFFFFF
	var dark: bool = Darkness.is_dark_chunk(pos)
	var decay: float = WorldDecay.at(pos, chunk.style)
	var brightness: float = 0.0 if dark else rng.randf_range(0.6, 1.15) * (1.0 - 0.35 * decay)
	var panel := mesh_instance.mesh.surface_get_material(0) as ShaderMaterial
	if panel:
		panel.set_shader_parameter("brightness", brightness)
		# Мёртвый участок: все панели погашены, свет даёт только фонарь
		panel.set_shader_parameter("dead_ratio", 1.0 if dark else 0.06 + 0.3 * decay)

	var light := OmniLight3D.new()
	var mid: float = MazeChunk.CHUNK_SIZE * MazeChunk.CELL_SIZE * 0.5
	light.position = origin + Vector3(mid, WALL_H - 0.3, mid)
	light.light_color = Color(1.0, 0.93, 0.78).lerp(Color(0.84, 0.95, 0.72), decay)
	light.visible = not dark
	light.light_energy = LIGHT_ENERGY * brightness * 1.15
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.add_to_group("lamp_lights")
	add_child(light)

	# Гул ламп: синтезированная петля, высота чуть гуляет по чанкам.
	# В тёмном участке лампа не гудит вовсе — тишина и есть примета тьмы
	var hum := AudioBank.source("Ambient", AudioBank.hum(), 6.0)
	hum.position = light.position
	hum.volume_db = -80.0 if dark else HUM_VOLUME_DB
	hum.pitch_scale = rng.randf_range(0.96, 1.04)
	add_child(hum)
	# Петля стартует не с нуля: синхронные гумы раскачивали реверб Ambient.
	# Смещение — через play(from), иначе seek() сразу после play() у
	# AudioStreamPlayer3D теряется и все гумы начинают с нуля
	hum.play(rng.randf_range(0.0, 1.5))
	# Больная лампа: жребий после всех прежних, чтобы яркость и гул чанка
	# остались теми же, что до порчи
	var flicker: Node = null
	if not dark and rng.randf() < 0.08 + 0.3 * decay:
		flicker = LampFlicker.new()
		flicker.setup(light, panel, hum, rng.randi())
		light.add_child(flicker)

	# Норма лампы: к ней помехи от сущности возвращают свет, гул и панели
	chunk_nodes[pos] = {"mesh": mesh_instance, "light": light, "hum": hum, "panel": panel,
		"dark": dark, "flicker": flicker, "energy": light.light_energy,
		"brightness": brightness, "hum_db": hum.volume_db}


func remove_lamps(chunk_pos: Vector2i) -> void:
	if not chunk_nodes.has(chunk_pos):
		return
	var entry: Dictionary = chunk_nodes[chunk_pos]
	(entry["mesh"] as MeshInstance3D).queue_free()
	(entry["light"] as OmniLight3D).queue_free()
	(entry["hum"] as AudioStreamPlayer3D).queue_free()
	chunk_nodes.erase(chunk_pos)
