extends Control

# BodycamOverlay: следы записи на кадре. Уголки видоискателя, мигающий REC,
# номер камеры, таймкод и заряд — то, что видит игрок на стекле камеры.
# Это декорация: ни на что не влияет и ничего не решает, поэтому живёт
# отдельно от hud.gd (цель, банки, подсказки).

@export var blink_hz: float = 1.3
# Заряд тает примерно за двадцать минут и не доходит до нуля: запись не
# должна обрываться посреди забега, а 0% при мигающем REC — нестыковка
@export var battery_drain: float = 0.0007
@export var battery_floor: float = 0.05

var elapsed: float = 0.0
var battery: float = 1.0
var clock: float = 0.0
var rec_on: bool = true
var shown_second: int = -1
var shown_percent: int = -1

@onready var rec_label: Label = $Rec
@onready var battery_label: Label = $Battery
@onready var time_label: Label = $Timecode


func _ready() -> void:
	resized.connect(queue_redraw)
	_update_battery()
	_update_clock()


func _process(delta: float) -> void:
	# REC мигает: у настоящей записи он не горит ровно
	clock = fmod(clock + delta * blink_hz, 1.0)
	var on: bool = clock < 0.55
	if on != rec_on:
		rec_on = on
		rec_label.visible = on
		queue_redraw()

	# Время и заряд идут только вместе с игрой: пауза замораживает запись.
	# Копим delta, а не часы системы — иначе таймкод прыгал бы после паузы
	elapsed += delta
	battery = maxf(battery - battery_drain * delta, battery_floor)
	_update_clock()
	_update_battery()


func _update_battery() -> void:
	var percent: int = int(round(battery * 100.0))
	if percent == shown_percent:
		return
	shown_percent = percent
	battery_label.text = "BATT %d%%" % percent
	battery_label.modulate = Color(1, 1, 1, 1) if percent > 20 else Color(1, 0.35, 0.25, 1)


func _update_clock() -> void:
	var total: int = int(elapsed)
	if total == shown_second:
		return
	shown_second = total
	var hours: int = floori(total / 3600.0)
	var minutes: int = floori(total / 60.0) % 60
	time_label.text = "%02d:%02d:%02d" % [hours, minutes, total % 60]


# Рамка видоискателя: четыре уголка. Именно они читаются как «идёт запись»
func _draw() -> void:
	if size.x < 80.0 or size.y < 80.0:
		return
	var inset: float = 16.0
	var arm: float = 30.0
	var col := Color(1.0, 1.0, 1.0, 0.30)
	var x0: float = inset
	var y0: float = inset
	var x1: float = size.x - inset
	var y1: float = size.y - inset
	draw_line(Vector2(x0, y0), Vector2(x0 + arm, y0), col, 2.0)
	draw_line(Vector2(x0, y0), Vector2(x0, y0 + arm), col, 2.0)
	draw_line(Vector2(x1, y0), Vector2(x1 - arm, y0), col, 2.0)
	draw_line(Vector2(x1, y0), Vector2(x1, y0 + arm), col, 2.0)
	draw_line(Vector2(x0, y1), Vector2(x0 + arm, y1), col, 2.0)
	draw_line(Vector2(x0, y1), Vector2(x0, y1 - arm), col, 2.0)
	draw_line(Vector2(x1, y1), Vector2(x1 - arm, y1), col, 2.0)
	draw_line(Vector2(x1, y1), Vector2(x1, y1 - arm), col, 2.0)
	# Красная точка записи рядом с надписью REC
	if rec_on:
		draw_circle(Vector2(x0 + 11.0, y0 + 15.0), 4.0, Color(0.85, 0.12, 0.10, 0.9))
