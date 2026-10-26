extends RefCounted

# GameSettings: чтение/запись user://settings.cfg и применение.
# Без class_name — подключается через preload (правило проекта).

const PATH := "user://settings.cfg"
const FPS_OPTIONS := [30, 60, 120, 0]


static func defaults() -> Dictionary:
	return {
		"sensitivity": 0.003,
		"invert_y": false,
		"sprint_toggle": false,
		"crouch_toggle": true,
		"headbob_strength": 1.0,
		"fov": 100.0,
		"vsync": true,
		"fps_limit": 0,
		"msaa": 2,
		"fog": 0.4,
		"radius": 2,
		"volume": 0.8,
		"volume_sfx": 0.9,
		"volume_ambient": 0.75,
		"volume_entity": 0.9,
		"display_mode": 0,
		"resolution": Vector2i(1152, 648),
	}


static func load_all() -> Dictionary:
	var data := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in data.keys():
			data[key] = cfg.get_value("game", key, data[key])
		# Миграция со старого формата (headbob был bool)
		if cfg.has_section_key("game", "headbob"):
			var old = cfg.get_value("game", "headbob", true)
			data["headbob_strength"] = 1.0 if old else 0.0
	# Дальность 1 выгружала чанки с маяками на 32–64 м при слышимости 100 м —
	# по звуку было не дойти. Старое сохранение с 1 поднимаем до 2
	data["radius"] = clampi(int(data["radius"]), 2, 3)
	return data


static func save_all(data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("game", key, data[key])
	cfg.save(PATH)


static func apply_all(tree: SceneTree, data: Dictionary) -> void:
	apply_audio(data)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if data["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(data["fps_limit"])
	tree.root.set("msaa_3d", int(data["msaa"]))
	apply_display_mode(int(data["display_mode"]), data["resolution"])
	var scene = tree.current_scene
	if scene:
		var env_node = scene.get_node_or_null("WorldEnvironment")
		if env_node and env_node.environment:
			# Шкала «туман, %» рулит всем туманом сразу — при 40% это
			# 0.016 / 0.04 / 0.015, ровно как выставлено в world.tscn,
			# а при 0% тумана нет совсем (высотного и объёмного тоже)
			var fog_level: float = float(data["fog"])
			env_node.environment.fog_density = fog_level * 0.04
			env_node.environment.fog_height_density = fog_level * 0.1
			env_node.environment.volumetric_fog_density = fog_level * 0.0375
		var chunk_manager = scene.get_node_or_null("ChunkManager")
		if chunk_manager and int(chunk_manager.get("load_radius")) != int(data["radius"]):
			chunk_manager.set("load_radius", int(data["radius"]))
			chunk_manager.call("force_update")

	apply_to_player(tree.get_first_node_in_group("player"), data)


# 0 — оконный, 1 — полный (эксклюзив), 2 — без рамки (borderless)
static func apply_display_mode(display_mode: int, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match display_mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
			var screen := DisplayServer.screen_get_size()
			DisplayServer.window_set_position((screen - resolution) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


static func apply_audio(data: Dictionary) -> void:
	_set_bus("Master", float(data["volume"]))
	_set_bus("SFX", float(data["volume_sfx"]))
	_set_bus("Ambient", float(data["volume_ambient"]))
	_set_bus("Entity", float(data["volume_entity"]))


# Шины живут в default_bus_layout.tres; нет шины — просто пропускаем
static func _set_bus(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	if volume <= 0.0:
		AudioServer.set_bus_volume_db(index, -80.0)
	else:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))


static func apply_to_player(player, data: Dictionary) -> void:
	if player == null:
		return
	player.set("mouse_sensitivity", data["sensitivity"])
	player.set("invert_y", data["invert_y"])
	player.set("sprint_toggle_mode", data["sprint_toggle"])
	player.set("crouch_toggle_mode", data["crouch_toggle"])
	# Поле зрения и силу тряски держит нагрудная камера, а не сам игрок
	var bodycam = player.get_node_or_null("BodycamComponent")
	if bodycam:
		bodycam.set("base_fov", data["fov"])
		bodycam.set("shake_strength", data["headbob_strength"])
