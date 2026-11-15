extends Node2D
## Cena do jogo: o mundo visto de cima, com a câmera seguindo o personagem.
## O tempo passa sozinho: dia, noite e chuva vêm da simulação do mundo.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const CELL := 40.0                 # tamanho de uma célula do mapa, em pixels
const SPEED := 170.0               # velocidade do personagem
const JOY_RADIUS := 70.0

var sim: Node
var _img: Image
var _tex: ImageTexture
var _ground: Sprite2D
var _player: Node2D
var _cam: Camera2D
var _night: CanvasModulate
var _hud: CanvasLayer
var _clock: Label
var _loading: Label
var _rain_layer: Control
var _joy_ui: Control

var _face := 0.0
var _walk := 0.0
var _moving := false
var _in_water := false
var _rain_amount := 0.0
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO


func _ready() -> void:
	_night = CanvasModulate.new()
	add_child(_night)

	_ground = Sprite2D.new()
	_ground.centered = false
	_ground.scale = Vector2(CELL, CELL)
	_ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_ground)

	_player = Node2D.new()
	_player.draw.connect(_draw_player)
	add_child(_player)

	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 6.0
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(MundoSim.W * CELL)
	_cam.limit_bottom = int(MundoSim.H * CELL)
	_player.add_child(_cam)

	_build_hud()

	sim = MundoSim.new()
	add_child(sim)
	sim.world_ready.connect(_on_world_ready)


func _build_hud() -> void:
	_rain_layer = Control.new()
	var rain_cl := CanvasLayer.new()
	rain_cl.layer = 1
	add_child(rain_cl)
	_rain_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_layer.draw.connect(_draw_rain)
	rain_cl.add_child(_rain_layer)

	_hud = CanvasLayer.new()
	_hud.layer = 2
	add_child(_hud)

	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.059, 0.102)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "LoadingBg"
	_hud.add_child(bg)

	_loading = Label.new()
	_loading.text = "Gerando o mundo…"
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 30)
	_loading.add_theme_color_override("font_color", Color(0.91, 0.86, 0.77))
	_hud.add_child(_loading)

	_clock = Label.new()
	_clock.position = Vector2(24, 18)
	_clock.add_theme_font_size_override("font_size", 24)
	_clock.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_clock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_clock.add_theme_constant_override("outline_size", 6)
	_clock.visible = false
	_hud.add_child(_clock)

	var menu := Button.new()
	menu.text = "Menu"
	menu.add_theme_font_size_override("font_size", 20)
	menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -124
	menu.offset_top = 16
	menu.offset_right = -20
	menu.offset_bottom = 60
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_hud.add_child(menu)

	_joy_ui = Control.new()
	_joy_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_ui.draw.connect(_draw_joy)
	_hud.add_child(_joy_ui)


func _on_world_ready() -> void:
	_player.position = (Vector2(sim.spawn) + Vector2(0.5, 0.5)) * CELL
	_cam.reset_smoothing()
	_loading.visible = false
	_hud.get_node("LoadingBg").visible = false
	_clock.visible = true


func _process(delta: float) -> void:
	var px: PackedByteArray = sim.take_pixels()
	if not px.is_empty():
		if _img == null:
			_img = Image.create_from_data(MundoSim.W, MundoSim.H, false, Image.FORMAT_RGB8, px)
			_tex = ImageTexture.create_from_image(_img)
			_ground.texture = _tex
		else:
			_img.set_data(MundoSim.W, MundoSim.H, false, Image.FORMAT_RGB8, px)
			_tex.update(_img)
	if not sim.is_ready:
		return

	_move_player(delta)

	# relógio, chuva e noite
	var h: float = sim.hour()
	_clock.text = "Dia %d · %02d:%02d%s" % [sim.day(), int(h), int(fmod(h, 1.0) * 60.0), " · Chovendo" if sim.raining else ""]
	_rain_amount = move_toward(_rain_amount, 1.0 if sim.raining else 0.0, delta * 0.4)
	var dark := 0.0
	if h < 5.0 or h > 20.0: dark = 1.0
	elif h < 7.0: dark = 1.0 - (h - 5.0) / 2.0
	elif h > 18.0: dark = (h - 18.0) / 2.0
	var day_col := Color(1, 1, 1).lerp(Color(0.78, 0.82, 0.9), _rain_amount)
	_night.color = day_col.lerp(Color(0.28, 0.32, 0.5), dark)
	_rain_layer.queue_redraw()
	_player.queue_redraw()


func _move_player(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if _joy_id >= 0:
		dir = _joy_vec
	_moving = dir.length() > 0.1
	var cell := Vector2i((_player.position / CELL).floor())
	_in_water = sim.water_at(cell) > 0.12
	if _moving:
		var sp := SPEED * (0.45 if _in_water else 1.0)
		_player.position += dir.limit_length(1.0) * sp * delta
		_player.position = _player.position.clamp(Vector2(10, 10), Vector2(MundoSim.W, MundoSim.H) * CELL - Vector2(10, 10))
		_face = dir.angle()
		_walk += delta * 10.0 * dir.length()


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _joy_id < 0 and e.position.x < get_viewport().get_visible_rect().size.x * 0.65:
			_joy_id = e.index
			_joy_origin = e.position
			_joy_vec = Vector2.ZERO
		elif not e.pressed and e.index == _joy_id:
			_joy_id = -1
			_joy_vec = Vector2.ZERO
		_joy_ui.queue_redraw()
	elif e is InputEventScreenDrag and e.index == _joy_id:
		_joy_vec = ((e.position - _joy_origin) / JOY_RADIUS).limit_length(1.0)
		_joy_ui.queue_redraw()


func _draw_joy() -> void:
	if _joy_id < 0:
		return
	_joy_ui.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	_joy_ui.draw_circle(_joy_origin + _joy_vec * JOY_RADIUS, 28, Color(1, 0.54, 0.24, 0.7))


func _draw_rain() -> void:
	if _rain_amount <= 0.01:
		return
	var sz := _rain_layer.size
	_rain_layer.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.35, 0.45, 0.6, 0.12 * _rain_amount))
	var n := int(160 * _rain_amount)
	for k in n:
		var p := Vector2(randf() * sz.x, randf() * sz.y)
		_rain_layer.draw_line(p, p + Vector2(-6, 22), Color(0.82, 0.9, 0.97, 0.4), 2.0)


func _draw_player() -> void:
	var p := _player
	var rot := Transform2D(_face, Vector2.ZERO)
	p.draw_set_transform_matrix(rot)
	if _in_water:
		p.draw_arc(Vector2.ZERO, 26 + sin(Time.get_ticks_msec() / 200.0) * 2, 0, TAU, 32, Color(0.85, 0.95, 1, 0.5), 2.0)
	else:
		p.draw_set_transform(Vector2(3, 4), _face, Vector2(1, 0.75))
		p.draw_circle(Vector2.ZERO, 17, Color(0, 0, 0, 0.25))
		p.draw_set_transform_matrix(rot)
	var sw := sin(_walk) * 7.0 if _moving else 0.0
	# pés
	if not _in_water:
		p.draw_circle(Vector2(sw, 8), 5, Color(0.23, 0.17, 0.12))
		p.draw_circle(Vector2(-sw, -8), 5, Color(0.23, 0.17, 0.12))
	# corpo (camisa) e braços
	p.draw_set_transform(Vector2.ZERO, _face, Vector2(0.62, 1.0))
	p.draw_circle(Vector2.ZERO, 16, Color(0.79, 0.47, 0.18))
	p.draw_set_transform_matrix(rot)
	p.draw_circle(Vector2(-sw * 0.6 + 3, 15), 4.5, Color(0.73, 0.52, 0.36))
	p.draw_circle(Vector2(sw * 0.6 + 3, -15), 4.5, Color(0.73, 0.52, 0.36))
	# cabeça
	p.draw_circle(Vector2(1, 0), 8.5, Color(0.17, 0.11, 0.08))
	p.draw_set_transform_matrix(Transform2D())
