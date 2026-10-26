extends GutTest

# Хватка сущности: шкаф спасает, только если сущность не видела, как
# игрок в него залез.

const EntityGrab = preload("res://scripts/entity_grab.gd")


class FakePlayer extends Node3D:
	var hidden_spot = null
	var is_sprinting: bool = false

	func is_hidden() -> bool:
		return hidden_spot != null


class FakeSenses extends RefCounted:
	var clear: bool = true

	func line_clear(_from: Vector3, _to: Vector3) -> bool:
		return clear

	func eye_position() -> Vector3:
		return Vector3.ZERO


var entity: CharacterBody3D = null
var player: FakePlayer = null
var spot: Node3D = null
var senses: FakeSenses = null
var grab = null


func before_each() -> void:
	entity = CharacterBody3D.new()
	player = FakePlayer.new()
	spot = Node3D.new()
	add_child_autofree(entity)
	add_child_autofree(player)
	add_child_autofree(spot)
	senses = FakeSenses.new()
	grab = EntityGrab.new(entity, player, senses)


func _hide() -> void:
	player.hidden_spot = spot
	player.global_position = spot.global_position


func test_seen_hiding_is_remembered() -> void:
	spot.global_position = Vector3(10, 0, 0)
	grab.saw_player()
	grab.tick(0.1, true)
	_hide()
	grab.tick(0.016, true)
	assert_true(grab.hunting_spot())
	entity.global_position = Vector3(8.5, 0, 0)
	assert_eq(grab.check(), "Оно видело, как ты спрятался.")


func test_unseen_hiding_is_safe() -> void:
	spot.global_position = Vector3(10, 0, 0)
	grab.saw_player()
	grab.tick(1.0, true)
	_hide()
	grab.tick(0.016, true)
	assert_false(grab.hunting_spot())
	entity.global_position = Vector3(9.5, 0, 0)
	assert_eq(grab.check(), "")


func test_wandering_entity_does_not_remember() -> void:
	grab.saw_player()
	_hide()
	grab.tick(0.016, false)
	assert_false(grab.hunting_spot())


func test_far_from_spot_is_safe() -> void:
	spot.global_position = Vector3(10, 0, 0)
	grab.saw_player()
	_hide()
	grab.tick(0.016, true)
	entity.global_position = Vector3(0, 0, 0)
	assert_eq(grab.check(), "")


func test_leaving_spot_forgets_it() -> void:
	grab.saw_player()
	_hide()
	grab.tick(0.016, true)
	player.hidden_spot = null
	grab.tick(0.016, true)
	assert_false(grab.hunting_spot())


func test_spot_memory_expires() -> void:
	grab.saw_player()
	_hide()
	grab.tick(0.016, true)
	grab.tick(EntityGrab.SPOT_MEMORY + 0.1, true)
	assert_false(grab.hunting_spot())


func test_catch_in_the_open() -> void:
	player.global_position = Vector3(1.0, 0, 0)
	assert_eq(grab.check(), "Оно нашло тебя.")
	player.is_sprinting = true
	assert_eq(grab.check(), "Оно нашло тебя. Не надо было бежать.")
	senses.clear = false
	assert_eq(grab.check(), "", "сквозь стену не хватает")
	senses.clear = true
	player.global_position = Vector3(2.0, 0, 0)
	assert_eq(grab.check(), "")
