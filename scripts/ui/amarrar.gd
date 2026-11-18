extends Control
## Amarrar com cipó: o jogador gira o dedo em volta do círculo do meio da tela; cada
## volta inteira é uma volta de cipó na junta. Precisa de VOLTAS voltas.

signal terminou
signal cancelou

const VOLTAS := 4

var _ang := 0.0              # quanto já girou (rad, só para a frente: qualquer sentido)
var _last := INF
var _drag := -1
var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var b := Button.new()
	b.text = "Cancelar"
	b.add_theme_font_size_override("font_size", 22)
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.offset_left = -220
	b.offset_top = -100
	b.offset_right = -30
	b.offset_bottom = -30
	b.pressed.connect(func():
		cancelou.emit()
		queue_free())
	add_child(b)


func _center() -> Vector2:
	return size * 0.5


func _radius() -> float:
	return minf(size.x, size.y) * 0.28


func _feed(p: Vector2) -> void:
	var a := (p - _center()).angle()
	if _last != INF:
		var d := wrapf(a - _last, -PI, PI)
		_ang += absf(d) if absf(d) < 1.2 else 0.0
	_last = a
	queue_redraw()
	if _ang >= TAU * VOLTAS and not _done:
		_done = true
		terminou.emit()
		queue_free()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _drag == -1:
			_drag = e.index
			_last = INF
			_feed(e.position)
		elif not e.pressed and e.index == _drag:
			_drag = -1
		accept_event()
	elif e is InputEventScreenDrag and e.index == _drag:
		_feed(e.position)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_drag = -2
			_last = INF
			_feed(e.position)
		else:
			_drag = -1
		accept_event()
	elif e is InputEventMouseMotion and _drag == -2:
		_feed(e.position)
		accept_event()


## Para o teste: gira um pedaço sem dedo.
func girar(rad: float) -> void:
	_ang += rad
	if _ang >= TAU * VOLTAS and not _done:
		_done = true
		terminou.emit()
		queue_free()


func _draw() -> void:
	var c := _center()
	var r := _radius()
	draw_circle(c, r + 40, Color(0, 0, 0, 0.35))
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.35), 26.0, true)
	# as voltas já dadas, em cipó (marrom-esverdeado)
	var turns := _ang / TAU
	var full := int(turns)
	for k in mini(full, VOLTAS):
		draw_arc(c, r - 18 + k * 12, 0, TAU, 64, Color(0.36, 0.3, 0.14), 8.0, true)
	if full < VOLTAS:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + fmod(_ang, TAU), 64, Color(0.55, 0.45, 0.2), 20.0, true)
	var font := get_theme_default_font()
	var t1 := "Gire o dedo em volta para amarrar"
	var t2 := "Volta %d de %d" % [mini(full + 1, VOLTAS), VOLTAS]
	var s1 := font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
	var s2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	draw_string(font, Vector2(c.x - s1.x * 0.5, c.y - r - 60), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.96, 0.85))
	draw_string(font, Vector2(c.x - s2.x * 0.5, c.y + 10), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.4))
