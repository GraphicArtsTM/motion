extends Node
class_name StaminaComponent

signal stamina_changed(current: float, max_value: float)
signal stamina_depleted
signal stamina_recovered

@export var max_stamina: float = 100.0
@export var drain_rate: float = 20.0
@export var regen_rate: float = 15.0
@export var regen_rate_crouched: float = 25.0
@export var regen_delay: float = 1.0
@export var sprint_threshold: float = 30.0

var current_stamina: float = 100.0
var regen_timer: float = 0.0
var can_sprint: bool = true
var slow_until_msec: int = 0


func _ready() -> void:
	current_stamina = max_stamina


func _process(delta: float) -> void:
	# Обновляем таймер восстановления
	if regen_timer > 0.0:
		regen_timer -= delta


func drain(delta: float) -> void:
	if current_stamina <= 0.0:
		return
	
	current_stamina -= drain_rate * delta
	regen_timer = regen_delay
	
	if current_stamina <= 0.0:
		current_stamina = 0.0
		can_sprint = false
		slow_until_msec = Time.get_ticks_msec() + 2000
		stamina_depleted.emit()
	
	stamina_changed.emit(current_stamina, max_stamina)


func regenerate(delta: float, is_crouched: bool = false) -> void:
	if regen_timer > 0.0:
		return
	
	if current_stamina >= max_stamina:
		return
	
	var rate: float = regen_rate_crouched if is_crouched else regen_rate
	current_stamina = min(current_stamina + rate * delta, max_stamina)
	
	# Проверяем порог для возобновления бега
	if not can_sprint and current_stamina >= sprint_threshold:
		can_sprint = true
		stamina_recovered.emit()
	
	stamina_changed.emit(current_stamina, max_stamina)


func can_start_sprint() -> bool:
	# Бежать можно, пока выносливость не на нуле: порог 30 — это лишь
	# условие вернуть бег ПОСЛЕ изнеможения. Иначе игрок вставал бы
	# через 3.5 секунды бега и «мигал» у порога.
	return can_sprint and current_stamina > 0.0


func get_stamina_percent() -> float:
	return current_stamina / max_stamina


# Изнеможение: 2 секунды после обнуления скорость ×0.7
func speed_multiplier() -> float:
	if Time.get_ticks_msec() < slow_until_msec:
		return 0.7
	return 1.0
