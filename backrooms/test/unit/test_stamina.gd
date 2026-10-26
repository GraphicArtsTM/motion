extends GutTest

# Выносливость: изнеможение после нуля и его длительность в игровом времени.

const StaminaComponent = preload("res://scripts/stamina_component.gd")

var stamina = null


func before_each() -> void:
	stamina = StaminaComponent.new()
	add_child_autofree(stamina)


func test_exhaustion_slows_for_two_seconds() -> void:
	stamina.current_stamina = 1.0
	stamina.drain(1.0)
	assert_eq(stamina.current_stamina, 0.0)
	assert_false(stamina.can_start_sprint())
	assert_almost_eq(stamina.speed_multiplier(), 0.7, 0.001)
	stamina._process(1.9)
	assert_almost_eq(stamina.speed_multiplier(), 0.7, 0.001)
	stamina._process(0.2)
	assert_almost_eq(stamina.speed_multiplier(), 1.0, 0.001)


# Штраф тикает только кадрами: пауза дерева его не съедает
func test_exhaustion_ignores_wall_clock() -> void:
	stamina.current_stamina = 1.0
	stamina.drain(1.0)
	OS.delay_msec(2100)
	assert_almost_eq(stamina.speed_multiplier(), 0.7, 0.001)


func test_sprint_returns_after_threshold() -> void:
	stamina.current_stamina = 1.0
	stamina.drain(1.0)
	stamina.regen_timer = 0.0
	stamina.regenerate(1.0)
	assert_false(stamina.can_start_sprint())
	stamina.regenerate(2.0)
	assert_true(stamina.can_start_sprint())
