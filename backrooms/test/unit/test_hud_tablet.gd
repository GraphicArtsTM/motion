extends GutTest

# Планшет: задача и банки не висят на экране постоянно — всплывают на
# старте и при изменениях, держатся по Tab.

const HudScene = preload("res://scenes/hud.tscn")

var hud = null
var tablet = null


func before_each() -> void:
	hud = HudScene.instantiate()
	add_child_autofree(hud)
	tablet = hud.get_node("Root/Tablet")
	tablet.set_process(false)


func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		tablet._process(1.0 / 60.0)


func test_shown_at_start_then_hidden() -> void:
	_run(1.0)
	assert_true(hud.get_node("Root/ObjectivePanel").visible)
	_run(7.0)
	assert_false(hud.get_node("Root/ObjectivePanel").visible)
	assert_false(hud.get_node("Root/InventoryPanel").visible)


func test_change_flashes_panel() -> void:
	_run(8.0)
	hud.get_node("%Cans").text = "БАНКИ 4"
	_run(1.0)
	assert_true(hud.get_node("Root/InventoryPanel").visible)
	_run(5.0)
	assert_false(hud.get_node("Root/InventoryPanel").visible)


func test_tab_holds_panel() -> void:
	_run(8.0)
	Input.action_press("tablet")
	_run(10.0)
	assert_true(hud.get_node("Root/ObjectivePanel").visible)
	Input.action_release("tablet")
	_run(1.0)
	assert_false(hud.get_node("Root/ObjectivePanel").visible)


func test_no_crosshair_or_stamina_bar() -> void:
	assert_null(hud.get_node_or_null("Root/Crosshair"))
	assert_null(hud.get_node_or_null("Root/StaminaBar"))
