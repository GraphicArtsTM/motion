extends SceneTree

# Временная проверка экранов и полоски после ревью (удаляется после прогона).

var fails: Array[String] = []
var world: Node = null
var hud: CanvasLayer = null
var player: Node = null


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
	await frame(3)


func key_event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_r_%s.png" % name)
	print("SHOT ", name, " ", root.get_texture().get_image().get_size())


func _run() -> void:
	await frame(2)
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frame(6)
	hud = world.get_node("HUD")
	player = world.get_node("Player")

	# Экран смерти: «ЗАНОВО» настоящей мышью
	hud.show_death("проверка кнопок мышью")
	await frame(3)
	check(paused, "смерть не поставила паузу")
	var death: PanelContainer = hud.get_node("%DeathScreen")
	await click(death.get_node("%RestartButton").get_global_rect().get_center())
	await frame(6)
	check(not paused, "после клика по «ЗАНОВО» дерево на паузе")
	check(current_scene != null and current_scene.name == "World", "мир не перезагрузился кликом")

	# Экран победы: «ЕЩЁ РАЗ» настоящей мышью
	hud = current_scene.get_node("HUD")
	player = current_scene.get_node("Player")
	hud.show_win("")
	await frame(3)
	var win: PanelContainer = hud.get_node("%WinScreen")
	await click(win.get_node("%WinRestartButton").get_global_rect().get_center())
	await frame(6)
	check(not paused, "после клика «ЕЩЁ РАЗ» дерево на паузе")

	# Полоска: жёлтая и красная, снимки
	hud = current_scene.get_node("HUD")
	player = current_scene.get_node("Player")
	var stamina = player.get_node("StaminaComponent")
	var bar: ProgressBar = hud.get_node("%StaminaBar")
	var fill: StyleBoxFlat = hud.bar_fill
	key_event(KEY_W, true)
	key_event(KEY_SHIFT, true)
	var got_yellow := false
	var got_red := false
	for i in 320:
		await frame(1)
		var pct: float = stamina.current_stamina / stamina.max_stamina
		if not got_yellow and pct < 0.28 and pct > 0.17:
			got_yellow = true
			print("BAR yellow at ", pct, " color=", fill.bg_color, " rect=", bar.get_global_rect())
			await shot("bar_yellow")
		if not got_red and pct < 0.12:
			got_red = true
			print("BAR red at ", pct, " color=", fill.bg_color, " rect=", bar.get_global_rect())
			await shot("bar_red")
			break
	key_event(KEY_SHIFT, false)
	key_event(KEY_W, false)
	await frame(2)
	check(got_yellow, "не поймал жёлтую полоску")
	check(got_red, "не поймал красную полоску")

	# Полоска гаснет после восстановления
	for i in 420:
		await frame(1)
		if not bar.visible:
			break
	print("BAR hidden after regen visible=", bar.visible, " stamina=", stamina.current_stamina)
	check(not bar.visible, "полоска не погасла после восстановления")

	print("FAILS=", fails.size())
	for f in fails:
		print("  * ", f)
	quit(1 if fails.size() > 0 else 0)
