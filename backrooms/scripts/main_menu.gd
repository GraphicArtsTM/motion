extends Control

# Главное меню: только навигация. Вся типографика и состояния кнопок —
# в теме, раскладка — в сцене.


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%StartButton.pressed.connect(_on_start_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	$SettingsPanel.closed.connect(_on_settings_closed)
	%StartButton.grab_focus()


func _process(_delta: float) -> void:
	# Заголовок едва дышит, как люминесцентная вывеска
	var t := Time.get_ticks_msec() * 0.001
	%Title.modulate.a = 0.82 + 0.18 * (0.6 * sin(t * 7.3) + 0.4 * sin(t * 23.7))


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_settings_pressed() -> void:
	$SettingsPanel.open()


func _on_settings_closed() -> void:
	%StartButton.grab_focus()
