extends Control
## Controle da serra: um trilho comprido com um pegador que o jogador arrasta com o dedo.
## Subir o pegador = empurrar a serra para a frente; descer = puxar de volta.
## Se o dedo para, a serra para. (No cooperativo, cada jogador vai ter o seu: enquanto um
## sobe, o outro desce.)

## Posição do pegador: 1 = em cima (serra empurrada), 0 = embaixo (serra puxada).
var value := 0.5
var _drag := -1            # índice do toque arrastando (-2 = mouse)
var _grab_off := 0.0

const PAD := 46.0          # espaço das setas em cima e embaixo
const KNOB_H := 58.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _track() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 20, PAD), Vector2(40, size.y - PAD * 2.0))


func _knob_y() -> float:
	var t := _track()
	return t.position.y + KNOB_H * 0.5 + (1.0 - value) * (t.size.y - KNOB_H)


func _set_from_y(y: float) -> void:
	var t := _track()
	var span := maxf(t.size.y - KNOB_H, 1.0)
	value = clampf(1.0 - (y - t.position.y - KNOB_H * 0.5) / span, 0.0, 1.0)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _drag == -1:
			_drag = e.index
			_grab(e.position.y)
		elif not e.pressed and e.index == _drag:
			_drag = -1
		accept_event()
	elif e is InputEventScreenDrag and e.index == _drag:
		_set_from_y(e.position.y + _grab_off)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _drag == -1:
			_drag = -2
			_grab(e.position.y)
		elif not e.pressed and _drag == -2:
			_drag = -1
		accept_event()
	elif e is InputEventMouseMotion and _drag == -2:
		_set_from_y(e.position.y + _grab_off)
		accept_event()


## Pegou no pegador: arrasta sem pular. Pegou fora: o pegador vem para o dedo.
func _grab(y: float) -> void:
	var ky := _knob_y()
	_grab_off = ky - y if absf(ky - y) < KNOB_H * 0.7 else 0.0
	_set_from_y(y + _grab_off)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var dark := Color(0.07, 0.06, 0.05, 0.88)
	var rim := Color(0.55, 0.45, 0.3, 0.9)
	# corpo (cantos chanfrados)
	var c := 18.0
	var body := PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])
	draw_colored_polygon(body, dark)
	draw_polyline(body + PackedVector2Array([body[0]]), rim, 3.0, true)
	# setas
	var up_c := Color(0.95, 0.88, 0.7, 0.95 if value < 0.97 else 0.35)
	var dn_c := Color(0.95, 0.88, 0.7, 0.95 if value > 0.03 else 0.35)
	var cx := w * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(cx, 12), Vector2(cx + 22, 36), Vector2(cx - 22, 36)]), up_c)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, h - 12), Vector2(cx - 22, h - 36), Vector2(cx + 22, h - 36)]), dn_c)
	# trilho com marquinhas
	var t := _track()
	draw_rect(t, Color(0.02, 0.02, 0.02, 0.9))
	draw_rect(t, Color(0.3, 0.26, 0.2), false, 2.0)
	var n := 7
	for k in n:
		var y := t.position.y + 14 + (t.size.y - 28) * k / (n - 1)
		draw_line(Vector2(t.position.x + 8, y), Vector2(t.end.x - 8, y), Color(1, 1, 1, 0.12), 3.0)
	# pegador de madeira (o cabo da serra)
	var ky := _knob_y()
	var kr := Rect2(Vector2(6, ky - KNOB_H * 0.5), Vector2(w - 12, KNOB_H))
	var wood := Color(0.55, 0.38, 0.22) if _drag == -1 else Color(0.72, 0.52, 0.3)
	draw_rect(kr, wood)
	draw_rect(Rect2(kr.position, Vector2(kr.size.x, 8)), wood.lightened(0.2))
	for k in 3:
		var yy := kr.position.y + 18 + k * 11
		draw_line(Vector2(kr.position.x + 10, yy), Vector2(kr.end.x - 10, yy), wood.darkened(0.35), 2.0)
	draw_rect(kr, Color(0.12, 0.08, 0.04), false, 2.5)
