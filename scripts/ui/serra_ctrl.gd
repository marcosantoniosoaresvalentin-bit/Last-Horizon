extends Control
## Controle da serra: um trilho comprido com um pegador que o jogador arrasta com o dedo.
## Subir o pegador = empurrar a serra para a frente; descer = puxar de volta.
## Se o dedo para, a serra para. (No cooperativo, cada jogador vai ter o seu: enquanto um
## sobe, o outro desce.)

## Posição do pegador: 1 = em cima (serra empurrada), 0 = embaixo (serra puxada).
var value := 0.5
var _drag := -1            # índice do toque arrastando (-2 = mouse)
var _grab_off := 0.0

const PAD := 34.0          # espaço nas pontas
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
		if e.pressed and _drag == -1 and _on_knob(e.position.y):
			_drag = e.index
			_grab_off = _knob_y() - e.position.y
		elif not e.pressed and e.index == _drag:
			_drag = -1
			queue_redraw()
		accept_event()
	elif e is InputEventScreenDrag and e.index == _drag:
		_set_from_y(e.position.y + _grab_off)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _drag == -1 and _on_knob(e.position.y):
			_drag = -2
			_grab_off = _knob_y() - e.position.y
		elif not e.pressed and _drag == -2:
			_drag = -1
			queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion and _drag == -2:
		_set_from_y(e.position.y + _grab_off)
		accept_event()


## Só pega se o dedo encostar no pegador (tocar no trilho não faz nada).
func _on_knob(y: float) -> bool:
	return absf(y - _knob_y()) < KNOB_H * 0.75


func _draw() -> void:
	var w := size.x
	var h := size.y
	# corpo comprido e arredondado (cápsula)
	var r := w * 0.5
	var body := PackedVector2Array()
	for k in 17:
		var a := PI + PI * k / 16.0
		body.append(Vector2(r + cos(a) * r, r + sin(a) * r))
	for k in 17:
		var a := PI * k / 16.0
		body.append(Vector2(r + cos(a) * r, h - r + sin(a) * r))
	draw_colored_polygon(body, Color(0.07, 0.06, 0.05, 0.85))
	draw_polyline(body + PackedVector2Array([body[0]]), Color(0.55, 0.45, 0.3, 0.9), 3.0, true)
	# risco no meio (o caminho do pegador)
	var t := _track()
	var cx := w * 0.5
	draw_line(Vector2(cx, t.position.y), Vector2(cx, t.end.y), Color(0, 0, 0, 0.8), 8.0, true)
	draw_line(Vector2(cx, t.position.y), Vector2(cx, t.end.y), Color(1, 1, 1, 0.18), 2.0, true)
	# pegador de madeira (o que se arrasta)
	var ky := _knob_y()
	var kr := Rect2(Vector2(10, ky - KNOB_H * 0.5), Vector2(w - 20, KNOB_H))
	var wood := Color(0.55, 0.38, 0.22) if _drag == -1 else Color(0.74, 0.54, 0.32)
	draw_rect(kr, wood)
	draw_rect(Rect2(kr.position, Vector2(kr.size.x, 8)), wood.lightened(0.2))
	for k in 3:
		var yy := kr.position.y + 18 + k * 11
		draw_line(Vector2(kr.position.x + 10, yy), Vector2(kr.end.x - 10, yy), wood.darkened(0.35), 2.0)
	draw_rect(kr, Color(0.12, 0.08, 0.04), false, 2.5)
