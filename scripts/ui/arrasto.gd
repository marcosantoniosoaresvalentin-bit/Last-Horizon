extends Control
## Faixa de arrastar com o dedo (modo construção): o quanto o dedo andou vira o quanto
## a peça gira, inclina ou anda — devagar e sem pulos. Mostra o que está mexendo.

signal arrastou(d: Vector2)

var text := ""
var _drag := -1            # índice do toque (-2 = mouse)
var _last := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _drag == -1:
			_drag = e.index
			_last = e.position
		elif not e.pressed and e.index == _drag:
			_drag = -1
		queue_redraw()
		accept_event()
	elif e is InputEventScreenDrag and e.index == _drag:
		arrastou.emit(e.position - _last)
		_last = e.position
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _drag == -1:
			_drag = -2
			_last = e.position
		elif not e.pressed and _drag == -2:
			_drag = -1
		queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion and _drag == -2:
		arrastou.emit(e.position - _last)
		_last = e.position
		accept_event()


func set_text(t: String) -> void:
	if t != text:
		text = t
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.72 if _drag == -1 else 0.88)
	sb.border_color = Color(0.55, 0.45, 0.3, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(h * 0.5))
	draw_style_box(sb, r)
	# setas nas pontas
	var col := Color(1, 1, 1, 0.75)
	var cy := h * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(26, cy), Vector2(52, cy - 18), Vector2(52, cy + 18)]), col)
	draw_colored_polygon(PackedVector2Array([Vector2(w - 26, cy), Vector2(w - 52, cy - 18), Vector2(w - 52, cy + 18)]), col)
	# riscos do "trilho"
	for k in 9:
		var x := lerpf(80.0, w - 80.0, k / 8.0)
		draw_line(Vector2(x, h - 22), Vector2(x, h - 14), Color(1, 1, 1, 0.3), 2.0)
	var font := get_theme_default_font()
	var fs := 24
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2((w - ts.x) * 0.5, cy + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.96, 0.85))
