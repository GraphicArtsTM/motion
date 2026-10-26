extends SceneTree

# Временная проверка трёх правок после ревью (удаляется после прогона):
# 1) камера-оптика находит HUD/Root/PostProcess и шлёт юниформы;
# 2) ПКМ/G бросают банку, кнопки и ползунки работают;
# 3) полоска выносливости красится по порогам, чужие стили не тронуты.

var fails: Array[String] = []
var world: Node = null
var hud: CanvasLayer = null
var player: Node = null
var lens: Node = null
var items: Node = null


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("FAIL: ", msg)


func frame(n: int = 1) -> void:
	for i in n:
		await process_frame


func mouse_button(pos: Vector2, index: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)


func click(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	await frame(1)
	mouse_button(pos, MOUSE_BUTTON_LEFT, true)
	await frame(1)
	mouse_button(pos, MOUSE_BUTTON_LEFT, false)
	await frame(2)


func key_event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_r_%s.png" % name)
	print("SHOT ", name)


func _run() -> void:
	await frame(2)
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frame(6)

	hud = world.get_node("HUD")
	player = world.get_node("Player")
	lens = player.get_node("CameraRoot/CameraLens") if player.has_node("CameraRoot/CameraLens") else player.find_child("CameraLens", true, false)
	items = player.get_node("PlayerItems")
	print("LENS node=", lens, " post=", hud.find_child("PostProcess", true, false))

	await _lens_checks()
	await _throw_checks()
	await _ui_checks()
	await _stamina_checks()

	print("FAILS=", fails.size())
	for f in fails:
		print("  * ", f)
	quit(1 if fails.size() > 0 else 0)


func _lens_checks() -> void:
	var mat: ShaderMaterial = lens.material
	check(mat != null, "оптика не привязала материал пост-обработки")
	if mat == null:
		return
	var t0: float = lens.tape_time
	var g0: float = lens.gain
	await frame(30)
	var t1: float = lens.tape_time
	check(t1 > t0, "tape_time не идёт: %f -> %f" % [t0, t1])
	check(lens.gain > 0.95 and lens.gain < 1.35, "gain вне диапазона: %f" % lens.gain)
	check(lens.motion.length() < 0.002, "в покое есть смаз: %s" % str(lens.motion))
	var param_motion: Vector2 = mat.get_shader_parameter("motion")
	var param_tape: float = mat.get_shader_parameter("tape_time")
	var param_gain: float = mat.get_shader_parameter("gain")
	check(param_tape == t1, "tape_time не доходит до материала: %f vs %f" % [param_tape, t1])
	check(is_equal_approx(param_gain, lens.gain), "gain не доходит до материала")
	check(param_motion.is_equal_approx(lens.motion), "motion не доходит до материала")

	# Резкий разворот мышью: смаз и перекос строк должны ожить
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frame(2)
	for i in 4:
		var mm := InputEventMouseMotion.new()
		mm.relative = Vector2(90.0, 18.0)
		mm.position = root.get_visible_rect().size * 0.5
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await frame(1)
	var spike_motion: float = lens.motion.length()
	var spike_shutter: float = absf(lens.shutter)
	print("LENS spike motion=", spike_motion, " shutter=", spike_shutter, " gain=", lens.gain, " tape=", lens.tape_time)
	check(spike_motion > 0.001, "после разворота нет смаза: %f" % spike_motion)
	check(spike_shutter > 0.0005, "после разворота нет перекоса строк: %f" % spike_shutter)
	check(mat.get_shader_parameter("motion").length() > 0.001, "смаз не доходит до шейдера")

	# Пробежка: кадр не сыпется, ошибок нет
	key_event(KEY_W, true)
	await frame(40)
	key_event(KEY_W, false)
	await frame(20)
	await shot("world_moved")
	check(lens.motion.length() < 0.004, "смаз не гаснет после остановки: %f" % lens.motion.length())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _throw_checks() -> void:
	var cans0: int = items.cans
	var center: Vector2 = root.get_visible_rect().size * 0.5
	Input.warp_mouse(center)
	await frame(1)
	mouse_button(center, MOUSE_BUTTON_RIGHT, true)
	await frame(2)
	mouse_button(center, MOUSE_BUTTON_RIGHT, false)
	await frame(4)
	check(items.cans == cans0 - 1, "ПКМ не бросил банку: %d -> %d" % [cans0, items.cans])
	var projectiles := 0
	for child in current_scene.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("can_projectile.gd"):
			projectiles += 1
	print("THROW after RMB cans=", items.cans, " projectiles=", projectiles)
	check(projectiles >= 1, "после ПКМ в сцене нет банки")

	await frame(40)
	key_event(KEY_G, true)
	await frame(2)
	key_event(KEY_G, false)
	await frame(4)
	check(items.cans == cans0 - 2, "G не бросил банку: %d" % items.cans)
	print("THROW after G cans=", items.cans)


func _ui_checks() -> void:
	var root_ctl: Control = hud.get_node("Root")
	var pause: PanelContainer = root_ctl.get_node("PauseMenu")
	var panel: Control = hud.get_node("%SettingsPanel")
	var cans: int = items.cans
	var center: Vector2 = root.get_visible_rect().size * 0.5

	# Пауза: ПКМ в пустоту не должен бросать (игра на паузе)
	key_event(KEY_ESCAPE, true)
	await frame(1)
	key_event(KEY_ESCAPE, false)
	await frame(2)
	check(paused and pause.visible, "Esc не открыл паузу")
	mouse_button(center, MOUSE_BUTTON_RIGHT, true)
	await frame(1)
	mouse_button(center, MOUSE_BUTTON_RIGHT, false)
	await frame(3)
	check(items.cans == cans, "на паузе ПКМ всё-таки бросил банку")

	# Клик по настоящей кнопке «НАСТРОЙКИ»
	var settings_btn: Button = pause.get_node("%SettingsButton")
	await click(settings_btn.get_global_rect().get_center())
	check(panel.visible, "клик мышью не открыл настройки")
	check(not pause.visible, "меню паузы осталось под настройками")

	# Ползунок тянется мышью, затем значение возвращается как было
	var sens: HSlider = panel.get_node("%SensSlider")
	var sens_before: float = sens.value
	var track: Rect2 = sens.get_global_rect()
	var from: Vector2 = Vector2(track.position.x + track.size.x * 0.3, track.get_center().y)
	var to: Vector2 = Vector2(track.position.x + track.size.x * 0.7, track.get_center().y)
	Input.warp_mouse(from)
	await frame(1)
	mouse_button(from, MOUSE_BUTTON_LEFT, true)
	await frame(1)
	for i in 5:
		var mm := InputEventMouseMotion.new()
		mm.position = from.lerp(to, float(i + 1) / 5.0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
		await frame(1)
	mouse_button(to, MOUSE_BUTTON_LEFT, false)
	await frame(2)
	print("UI slider before=", sens_before, " after=", sens.value, " label=", panel.get_node("%SensLabel").text)
	check(not is_equal_approx(sens.value, sens_before), "ползунок не тянется мышью")
	check(panel.get_node("%SensLabel").text == "%.1f" % sens.value, "подпись ползунка не обновилась")

	# Кнопка «ГОТОВО» мышью
	var back: Button = panel.get_node("%BackButton")
	sens.set_value_no_signal(sens_before)
	await frame(1)
	await click(back.get_global_rect().get_center())
	check(not panel.visible, "клик по «ГОТОВО» не закрыл настройки")
	check(pause.visible, "после «ГОТОВО» меню паузы не вернулось")
	check(paused, "после «ГОТОВО» пауза пропала")

	# Esc снимает паузу
	key_event(KEY_ESCAPE, true)
	await frame(1)
	key_event(KEY_ESCAPE, false)
	await frame(2)
	check(not paused and not pause.visible, "Esc не снял паузу")


func _stamina_checks() -> void:
	var bar: ProgressBar = hud.get_node("%StaminaBar")
	var fill: StyleBoxFlat = hud.bar_fill
	check(fill != null, "hud.bar_fill не создан")
	check(bar.get_theme_stylebox("fill") == fill, "полоска не получила свою копию стиля")

	# Чужой ProgressBar должен остаться на стиле темы
	var other := ProgressBar.new()
	other.max_value = 100.0
	other.value = 50.0
	root.add_child(other)
	await frame(1)
	var other_color: Color = other.get_theme_stylebox("fill").bg_color
	check(not is_equal_approx(other_color.r, 0.9) or not is_equal_approx(other_color.g, 0.85), "чужой ProgressBar взял цвет HUD")
	print("STAM other fill color=", other_color)
	other.queue_free()

	var stamina = player.get_node("StaminaComponent")
	var samples := {}
	# Бег до 0: на 100 единиц при 20/с это 5 секунд
	key_event(KEY_W, true)
	key_event(KEY_SHIFT, true)
	for i in 320:
		await frame(1)
		var pct: float = stamina.current_stamina / stamina.max_stamina
		var key := ""
		if pct < 0.15:
			key = "red"
		elif pct < 0.3:
			key = "yellow"
		elif pct > 0.3:
			key = "normal"
		if key != "" and not samples.has(key):
			samples[key] = ["%.1f" % (pct * 100.0), fill.bg_color, bar.visible]
			print("STAM ", key, " at ", samples[key][0], "% color=", fill.bg_color, " bar_visible=", bar.visible)
	key_event(KEY_SHIFT, false)
	key_event(KEY_W, false)
	await frame(2)

	check(samples.has("normal"), "не поймал нормальное состояние полоски")
	check(samples.has("yellow"), "полоска не пожелтела ниже 30%")
	check(samples.has("red"), "полоска не покраснела ниже 15%")
	if samples.has("normal"):
		check(samples["normal"][2], "полоска не появилась при беге")
		check(samples["normal"][1] == Color(0.9, 0.85, 0.7), "нормальный цвет не из HUD")
	if samples.has("yellow"):
		check(samples["yellow"][1] == Color(0.85, 0.7, 0.3), "жёлтый цвет не тот")
	if samples.has("red"):
		check(samples["red"][1] == Color(0.8, 0.2, 0.15), "красный цвет не тот")
	print("STAM final=", stamina.current_stamina, " bar_visible=", bar.visible)
