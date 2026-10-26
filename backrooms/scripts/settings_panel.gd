extends Control

# Расширенные настройки: управление, камера, графика, звук.
# Применяются вживую через GameSettings.apply_all, сохраняются при закрытии.
# Одна сцена переиспользуется в главном меню и в паузе.

signal closed

const GameSettings = preload("res://scripts/game_settings.gd")
const FPS_VALUES := [30, 60, 120, 0]
const RES_OPTIONS := [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]


func _ready() -> void:
	visible = false
	%SprintMode.add_item("Удерживать", 0)
	%SprintMode.add_item("Переключатель", 1)
	%CrouchMode.add_item("Удерживать", 0)
	%CrouchMode.add_item("Переключатель", 1)
	%FpsMode.add_item("30", 0)
	%FpsMode.add_item("60", 1)
	%FpsMode.add_item("120", 2)
	%FpsMode.add_item("Без лимита", 3)
	%MsaaMode.add_item("Выкл", 0)
	%MsaaMode.add_item("2x", 1)
	%MsaaMode.add_item("4x", 2)
	%MsaaMode.add_item("8x", 3)
	%DisplayMode.add_item("Оконный", 0)
	%DisplayMode.add_item("Полный", 1)
	%DisplayMode.add_item("Без рамки", 2)
	%ResMode.add_item("1152×648", 0)
	%ResMode.add_item("1280×720", 1)
	%ResMode.add_item("1600×900", 2)
	%ResMode.add_item("1920×1080", 3)
	%BackButton.pressed.connect(_on_back_pressed)
	%ResetButton.pressed.connect(_on_reset_pressed)
	# PopupMenu — отдельное окно, тему родителя не наследует
	var popups: Array[OptionButton] = [
		%SprintMode, %CrouchMode, %FpsMode, %MsaaMode, %DisplayMode, %ResMode,
	]
	for button in popups:
		button.get_popup().theme = theme
	%SensSlider.value_changed.connect(_on_any_changed)
	%VolSlider.value_changed.connect(_on_any_changed)
	%SfxSlider.value_changed.connect(_on_any_changed)
	%AmbientSlider.value_changed.connect(_on_any_changed)
	%EntitySlider.value_changed.connect(_on_any_changed)
	%FovSlider.value_changed.connect(_on_any_changed)
	%BobSlider.value_changed.connect(_on_any_changed)
	%FogSlider.value_changed.connect(_on_any_changed)
	%RadiusSlider.value_changed.connect(_on_any_changed)
	%InvertCheck.toggled.connect(_on_any_toggled)
	%VsyncCheck.toggled.connect(_on_any_toggled)
	%SprintMode.item_selected.connect(_on_any_selected)
	%CrouchMode.item_selected.connect(_on_any_selected)
	%FpsMode.item_selected.connect(_on_any_selected)
	%MsaaMode.item_selected.connect(_on_any_selected)
	%DisplayMode.item_selected.connect(_on_display_selected)
	%ResMode.item_selected.connect(_on_any_selected)


func open() -> void:
	_refresh()
	visible = true
	%BackButton.grab_focus()


func _refresh() -> void:
	var data := GameSettings.load_all()
	%SensSlider.set_value_no_signal(data["sensitivity"] * 1000.0)
	%VolSlider.set_value_no_signal(data["volume"] * 100.0)
	%SfxSlider.set_value_no_signal(data["volume_sfx"] * 100.0)
	%AmbientSlider.set_value_no_signal(data["volume_ambient"] * 100.0)
	%EntitySlider.set_value_no_signal(data["volume_entity"] * 100.0)
	%FovSlider.set_value_no_signal(data["fov"])
	%BobSlider.set_value_no_signal(data["headbob_strength"] * 100.0)
	%FogSlider.set_value_no_signal(data["fog"] * 100.0)
	%RadiusSlider.set_value_no_signal(data["radius"])
	%InvertCheck.set_pressed_no_signal(data["invert_y"])
	%VsyncCheck.set_pressed_no_signal(data["vsync"])
	%SprintMode.select(1 if data["sprint_toggle"] else 0)
	%CrouchMode.select(1 if data["crouch_toggle"] else 0)
	%FpsMode.select(FPS_VALUES.find(int(data["fps_limit"])))
	%MsaaMode.select(clampi(int(data["msaa"]), 0, 3))
	%DisplayMode.select(clampi(int(data["display_mode"]), 0, 2))
	%ResMode.select(_res_index(data["resolution"]))
	%ResMode.disabled = int(data["display_mode"]) != 0
	_update_labels(data)


func _res_index(resolution) -> int:
	for i in RES_OPTIONS.size():
		if RES_OPTIONS[i] == resolution:
			return i
	return 0


func _collect() -> Dictionary:
	return {
		"sensitivity": %SensSlider.value / 1000.0,
		"invert_y": %InvertCheck.button_pressed,
		"sprint_toggle": %SprintMode.selected == 1,
		"crouch_toggle": %CrouchMode.selected == 1,
		"headbob_strength": %BobSlider.value / 100.0,
		"fov": %FovSlider.value,
		"vsync": %VsyncCheck.button_pressed,
		"fps_limit": FPS_VALUES[%FpsMode.selected],
		"msaa": %MsaaMode.selected,
		"fog": %FogSlider.value / 100.0,
		"radius": int(%RadiusSlider.value),
		"volume": %VolSlider.value / 100.0,
		"volume_sfx": %SfxSlider.value / 100.0,
		"volume_ambient": %AmbientSlider.value / 100.0,
		"volume_entity": %EntitySlider.value / 100.0,
		"display_mode": %DisplayMode.selected,
		"resolution": RES_OPTIONS[%ResMode.selected],
	}


func _update_labels(data: Dictionary) -> void:
	%SensLabel.text = "%.1f" % (data["sensitivity"] * 1000.0)
	%VolLabel.text = "%d" % int(data["volume"] * 100.0)
	%SfxLabel.text = "%d" % int(data["volume_sfx"] * 100.0)
	%AmbientLabel.text = "%d" % int(data["volume_ambient"] * 100.0)
	%EntityLabel.text = "%d" % int(data["volume_entity"] * 100.0)
	%FovLabel.text = "%d" % int(data["fov"])
	%BobLabel.text = "%d%%" % int(data["headbob_strength"] * 100.0)
	%FogLabel.text = "%d%%" % int(data["fog"] * 100.0)
	%RadiusLabel.text = "%d" % int(data["radius"])


func _apply_live() -> void:
	var data := _collect()
	_update_labels(data)
	GameSettings.apply_all(get_tree(), data)


func _on_any_changed(_value: float) -> void:
	_apply_live()


func _on_any_toggled(_pressed: bool) -> void:
	_apply_live()


func _on_any_selected(_index: int) -> void:
	_apply_live()


func _on_display_selected(_index: int) -> void:
	%ResMode.disabled = %DisplayMode.selected != 0
	_apply_live()


func _on_reset_pressed() -> void:
	var data := GameSettings.defaults()
	GameSettings.save_all(data)
	GameSettings.apply_all(get_tree(), data)
	_refresh()


func _on_back_pressed() -> void:
	close()


# Esc закрывает панель. Без этого в паузе Esc снял бы паузу
# под открытыми настройками и захватил мышь — софтлок.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	GameSettings.save_all(_collect())
	visible = false
	closed.emit()
