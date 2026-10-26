extends RefCounted

# EntityRelocator: куда сущности встать, когда её нет рядом с игроком.
# Кольцо задаёт дальность, а прямая видимость — чтобы хозяин не возникал
# из воздуха в поле зрения. Клетки кольца берутся одним обходом в ширину
# (entity_navigator.cells_in_band), дальше только отбор: обход — самая
# дорогая часть, повторять его на каждую попытку незачем.

const Navigator = preload("res://scripts/entity_navigator.gd")

const MIN_METERS: float = 30.0
const MAX_METERS: float = 45.0
const CHECKS: int = 24
const BEHIND_DOT: float = -0.25


# Переброс. false — кольцо вокруг игрока пустое (загруженных клеток нет):
# сущность остаётся где была, вызов повторится на следующем кадре
static func place(entity: Node3D, chunk_manager, player: Node3D,
		senses, rng: RandomNumberGenerator) -> bool:
	var pick = _pick(chunk_manager, player, senses, rng)
	if pick == null:
		return false
	entity.global_position = Navigator.cell_to_world(pick)
	return true


# Клетка кольца. Приоритет: не на прямой видимости игрока → хотя бы
# за спиной (чтобы её увидеть, придётся повернуться) → любая из
# проверенных. Последний запас нужен, чтобы сущность не осталась висеть
# в пустоте: в открытом зале все 24 броска могут попасть в видимые клетки
static func _pick(chunk_manager, player: Node3D, senses, rng: RandomNumberGenerator) -> Variant:
	var cells: Array = Navigator.cells_in_band(chunk_manager,
		Navigator.world_to_cell(player.global_position), MIN_METERS, MAX_METERS)
	if cells.is_empty():
		return null
	var forward: Vector3 = -player.global_transform.basis.z
	var behind: Variant = null
	var any: Variant = null
	for _check in CHECKS:
		var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var pos: Vector3 = Navigator.cell_to_world(cell)
		if not _in_sight(player, senses, pos):
			return cell
		if any == null:
			any = cell
		if (pos - player.global_position).normalized().dot(forward) < BEHIND_DOT:
			behind = cell
	if behind != null:
		return behind
	return any


# Клетку видно с глаз игрока: туда не встаём. Луч считает шина слуха —
# она исключает и игрока, и саму сущность, больше ничего не нужно
static func _in_sight(player: Node3D, senses, pos: Vector3) -> bool:
	return senses.line_clear(player.global_position + Vector3(0, 1.5, 0),
		pos + Vector3(0, 1.0, 0))
