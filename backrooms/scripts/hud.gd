extends CanvasLayer

# HUD: прицел, полоска выносливости, цель, подсказки, экран смерти.
# Пауза — отдельный скрипт pause_menu.gd на узле PauseMenu.

const GameSettings = preload("res://scripts/game_settings.gd")
const ExitPower = preload("res://scripts/exit_power.gd")

@export var stamina_path: NodePath
@export var player_path: NodePath

@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var bar_fill: StyleBoxFlat = stamina_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
@onready var hint_label: Label = %Hint
@onready var objective_label: Label = %Objective
@onready var cans_label: Label = %Cans
@onready var death_screen: PanelContainer = %DeathScreen
@onready var post_process: ColorRect = %PostProcess

var stamina_node
var player_node: Node3D
var items_node = null
var is_dead: bool = false
var bar_hide_timer: float = 0.0
var hint_hide_timer: float = 0.0
var run_elapsed: float = 0.0
var fuse_count: int = 0
var inserted_count: int = 0
var powered: bool = false


func _ready() -> void:
	stamina_bar.visible = false
	# Стиль из темы копируем: перекрашивать общий ресурс нельзя
	stamina_bar.add_theme_stylebox_override("fill", bar_fill)
	hint_label.visible = false
	death_screen.visible = false
	%WinScreen.visible = false
	%RestartButton.pressed.connect(_on_restart_pressed)
	%MenuButton.pressed.connect(_on_menu_pressed)
	%WinRestartButton.pressed.connect(_on_restart_pressed)
	%WinMenuButton.pressed.connect(_on_menu_pressed)

	player_node = get_node_or_null(player_path) as Node3D

	# Настройки из файла применяются при старте мира: не только игрок и звук,
	# но и туман, дальность чанков, VSync/лимит FPS — иначе они «забываются»
	GameSettings.apply_all(get_tree(), GameSettings.load_all())

	stamina_node = get_node_or_null(stamina_path)
	if stamina_node and stamina_node.has_signal("stamina_changed"):
		stamina_node.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(stamina_node.current_stamina, stamina_node.max_stamina)

	# Цель и снаряжение: сколько предохранителей в руках и банок в запасе
	items_node = player_node.get_node_or_null("PlayerItems") if player_node else null
	if items_node:
		items_node.fuses_changed.connect(_on_fuses_changed)
		items_node.cans_changed.connect(_on_cans_changed)
		_on_cans_changed(items_node.cans)
	_refresh_objective()

	show_hint("WASD — ходьба · Shift — бег · C — присед · F — взять · L — фонарь", 8.0)


func _process(delta: float) -> void:
	if is_dead or player_node == null:
		return
	# Время забега идёт вместе с записью: пауза его не накручивает
	run_elapsed += delta

	# Страховка от падения сквозь мир — смерть вместо бесконечной пустоты
	if player_node.global_position.y < -5.0:
		show_death("Ты упал за пределы лабиринта.")
		return

	# Полоска гаснет через 2 секунды после полного восстановления
	if stamina_bar.visible and bar_hide_timer > 0.0:
		bar_hide_timer -= delta
		if bar_hide_timer <= 0.0 and stamina_bar.value >= stamina_bar.max_value:
			stamina_bar.visible = false

	if hint_label.visible and hint_hide_timer > 0.0:
		hint_hide_timer -= delta
		if hint_hide_timer <= 0.0:
			hint_label.visible = false


func _on_stamina_changed(current: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = current
	_update_bar_color(current / max_value)
	stamina_bar.visible = true
	bar_hide_timer = 2.0 if current >= max_value else 0.0


func _update_bar_color(percent: float) -> void:
	if percent < 0.15:
		bar_fill.bg_color = Color(0.8, 0.2, 0.15)
	elif percent < 0.3:
		bar_fill.bg_color = Color(0.85, 0.7, 0.3)
	else:
		bar_fill.bg_color = Color(0.9, 0.85, 0.7)


func show_hint(text: String, duration: float = 0.0) -> void:
	hint_label.text = text
	hint_label.visible = true
	hint_hide_timer = duration


# Свободна ли строка подсказок: чужие подсказки фонарь перебивать не должен
func can_show_hint() -> bool:
	return not hint_label.visible


# only_text — погасить, только если на строке всё ещё своя подсказка
func hide_hint(only_text: String = "") -> void:
	if only_text.is_empty() or hint_label.text == only_text:
		hint_label.visible = false


func _on_fuses_changed(count: int) -> void:
	fuse_count = count
	_refresh_objective()


func _on_cans_changed(count: int) -> void:
	cans_label.text = "БАНКИ %d" % count


func set_powered() -> void:
	powered = true
	_refresh_objective()


# Сколько предохранителей уже сидит в двери — решает exit_door._apply_power().
# Без этого строка цели считала бы только руки и «теряла» вставленные
func set_inserted(count: int) -> void:
	if count == inserted_count:
		return
	inserted_count = count
	_refresh_objective()


func _refresh_objective() -> void:
	if powered:
		objective_label.text = "ДВЕРЬ ЗАПИТАНА — ЖМИ F У ДВЕРИ"
	elif inserted_count + fuse_count >= ExitPower.NEEDED:
		objective_label.text = ("ВСТАВЛЕНО %d/%d, В РУКАХ %d — ИЩИ ДВЕРЬ ВЫХОДА (низкий гул)"
			% [inserted_count, ExitPower.NEEDED, fuse_count])
	else:
		objective_label.text = ("ПРЕДОХРАНИТЕЛИ %d/%d · В РУКАХ %d — ищи свечение и высокий гул"
			% [inserted_count, ExitPower.NEEDED, fuse_count])


# Ужас 0..1 — зовёт сущность, когда она рядом: дышит виньеткой и зерном
func set_dread(value: float) -> void:
	if is_dead:
		value = 0.0
	if post_process and post_process.material:
		post_process.material.set_shader_parameter("dread", clampf(value, 0.0, 1.0))


func show_death(reason: String = "") -> void:
	_end_run(%DeathReason, death_screen, reason)


func show_win(reason: String = "") -> void:
	var text := reason
	if not text.is_empty():
		text += "\n"
	_end_run(%WinReason, %WinScreen, text + "Время забега: " + _format_time())


func _end_run(reason_label: Label, screen: PanelContainer, reason: String) -> void:
	if is_dead:
		return
	is_dead = true
	hide_hint()
	reason_label.text = reason
	screen.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _format_time() -> String:
	var total_sec := int(run_elapsed)
	return "%02d:%02d" % [total_sec / 60, total_sec % 60]


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
