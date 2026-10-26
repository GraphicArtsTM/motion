extends PanelContainer

# Пауза на Esc. Узел в сцене помечен process_mode = ALWAYS,
# иначе скрипт встанет вместе с остановленным деревом.


func _ready() -> void:
	visible = false
	%ResumeButton.pressed.connect(_on_resume_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%SettingsPanel.closed.connect(_on_settings_closed)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			# Настройки сами закрываются на Esc — паузу не трогаем
			var settings := %SettingsPanel as Control
			if settings != null and settings.visible:
				return
			var death := %DeathScreen as PanelContainer
			var win := %WinScreen as PanelContainer
			var over := (death != null and death.visible) or (win != null and win.visible)
			if not over:
				toggle_pause()


func toggle_pause() -> void:
	var paused_now: bool = not get_tree().paused
	get_tree().paused = paused_now
	visible = paused_now
	get_node("%PauseDim").visible = paused_now
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused_now else Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	if get_tree().paused:
		toggle_pause()


func _on_settings_pressed() -> void:
	visible = false
	%SettingsPanel.open()


func _on_settings_closed() -> void:
	if get_tree().paused:
		visible = true


func _on_quit_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
