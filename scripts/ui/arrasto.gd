extends Control
## Faixa de arrastar com o dedo (modo construção): o quanto o dedo andou vira o quanto
## a peça gira, inclina ou anda — devagar e sem pulos. Mostra o que está mexendo.

signal arrastou(d: Vector2)

var text := ""
var _drag := -1            # índice do toque (-2 = mouse)
var _last := Vector2.ZERO
var _scroll := 0.0          # quanto o rolo já girou (desenho)


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
		_roll(e.position - _last)
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
		_roll(e.position - _last)
		arrastou.emit(e.position - _last)
		_last = e.position
		accept_event()


func set_text(t: String) -> void:
	if t != text:
		text = t
		queue_redraw()


func _roll(d: Vector2) -> void:
	_scroll += d.x - d.y
	queue_redraw()


## Um rolo dentro da faixa (como o de girar a bola na sinuca): os frisos andam junto
## com o dedo e se apertam nas beiradas, como num cilindro girando.
func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.045, 0.82)
	sb.border_color = Color(0.55, 0.45, 0.3, 0.95) if _drag == -1 else Color(1.0, 0.82, 0.35)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(h * 0.5))
	draw_style_box(sb, r)
	# o rolo: faixa clara no meio, escurecendo nas beiradas
	var inset := h * 0.22
	var rr := Rect2(Vector2(h * 0.45, inset), Vector2(w - h * 0.9, h - inset * 2.0))
	var bands := 40
	for k in bands:
		var u0 := float(k) / bands
		var u1 := float(k + 1) / bands
		var th := lerpf(-PI * 0.5, PI * 0.5, (u0 + u1) * 0.5)
		var lit := 0.18 + 0.32 * cos(th)
		draw_rect(Rect2(Vector2(rr.position.x + rr.size.x * u0, rr.position.y), Vector2(rr.size.x / bands + 0.6, rr.size.y)), Color(lit, lit * 0.92, lit * 0.8))
	# os frisos do rolo (giram com o dedo)
	var n := 18
	var R := rr.size.x * 0.5
	var cx := rr.position.x + R
	var ph := _scroll / R
	for k in n:
		var th := fposmod(float(k) / n * TAU + ph, TAU)
		if th > PI:
			continue                   # do outro lado do rolo (não aparece)
		var a := th - PI * 0.5
		var x := cx - sin(a) * R
		var vis := cos(a)
		draw_line(Vector2(x, rr.position.y + 3), Vector2(x, rr.end.y - 3), Color(0.05, 0.04, 0.03, 0.35 + 0.5 * vis), 1.5 + 3.0 * vis)
	# brilho em cima do rolo
	draw_rect(Rect2(rr.position, Vector2(rr.size.x, rr.size.y * 0.18)), Color(1, 1, 1, 0.08))
	# o texto num rótulo escuro por cima
	var font := get_theme_default_font()
	var fs := 22
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if text != "":
		var lb := Rect2(Vector2((w - ts.x) * 0.5 - 12, h * 0.5 - fs * 0.75), Vector2(ts.x + 24, fs * 1.5))
		var ls := StyleBoxFlat.new()
		ls.bg_color = Color(0.04, 0.035, 0.03, 0.8)
		ls.set_corner_radius_all(8)
		draw_style_box(ls, lb)
		draw_string(font, Vector2((w - ts.x) * 0.5, h * 0.5 + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.96, 0.85))
