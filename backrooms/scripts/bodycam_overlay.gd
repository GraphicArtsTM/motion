extends Control

# BodycamOverlay: что нагрудная камера вшивает в запись — дата и время UTC
# и строка с моделью и серийным номером в правом верхнем углу, белым
# моноширинным по чёрной обводке. Это декорация: ни на что не влияет и
# ничего не решает, поэтому живёт отдельно от hud.gd (цель, банки, подсказки).

# Модель вымышленная (M.E.G. — экспедиции из лора Backrooms), серийник свой
# у каждой записи: так кадр читается как улика, а не как интерфейс
const MODEL: String = "M.E.G. BODY 3"
const SERIAL_CHARS: String = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ"

var start_unix: float = 0.0
var elapsed: float = 0.0
var shown_second: int = -1

@onready var time_label: Label = $Timestamp
@onready var id_label: Label = $DeviceId


func _ready() -> void:
	start_unix = Time.get_unix_time_from_system()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var serial: String = "X6"
	for i in 6:
		serial += SERIAL_CHARS[rng.randi_range(0, SERIAL_CHARS.length() - 1)]
	id_label.text = "%s %s" % [MODEL, serial]
	_update_clock()


func _process(delta: float) -> void:
	# Время идёт только вместе с игрой: пауза замораживает запись.
	# Копим delta, а не часы системы — иначе метка прыгала бы после паузы
	elapsed += delta
	_update_clock()


func _update_clock() -> void:
	var total: int = int(start_unix + elapsed)
	if total == shown_second:
		return
	shown_second = total
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(total)
	time_label.text = "%04d-%02d-%02d T%02d:%02d:%02dZ" % [t.year, t.month, t.day,
		t.hour, t.minute, t.second]
