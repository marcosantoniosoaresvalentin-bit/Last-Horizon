extends Control
## Tela de PROJETOS: com cara de planta de engenharia (papel azul com grade, desenho em
## linhas brancas). Escolhe o que construir, vê o desenho de lado e o material, e
## "POSICIONAR" põe a planta no chão.

signal escolheu(tipo: String)
signal closed

const Maquinas := preload("res://scripts/world/maquinas.gd")
const Mochila := preload("res://scripts/ui/mochila.gd")

const C_PAPER := Color(0.08, 0.2, 0.42, 0.97)
const C_GRID := Color(1, 1, 1, 0.07)
const C_INK := Color(0.93, 0.96, 1.0)
const C_DIM := Color(0.75, 0.83, 0.95)
const C_HI := Color(1.0, 0.82, 0.35)

var _sel := ""
var _list: VBoxContainer
var _draw: Control
var _name: Label
var _desc: Label
var _need: Label
var _game: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Mochila._load_font()
	_build()


func abrir(game: Node) -> void:
	_game = game
	for k in Maquinas.TIPOS:
		var b := _btn(str(Maquinas.TIPOS[k].nome).to_upper())
		b.custom_minimum_size = Vector2(300, 64)
		b.pressed.connect(func(): _select(k))
		_list.add_child(b)
	_select(Maquinas.TIPOS.keys()[0])


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var paper := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PAPER
	sb.border_color = C_INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	paper.add_theme_stylebox_override("panel", sb)
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.offset_left = 40
	paper.offset_top = 30
	paper.offset_right = -40
	paper.offset_bottom = -30
	add_child(paper)
	var grid := Control.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(func():
		var s := grid.size
		var x := 0.0
		while x < s.x:
			grid.draw_line(Vector2(x, 0), Vector2(x, s.y), C_GRID, 1.0)
			x += 32.0
		var y := 0.0
		while y < s.y:
			grid.draw_line(Vector2(0, y), Vector2(s.x, y), C_GRID, 1.0)
			y += 32.0)
	paper.add_child(grid)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 26)
	paper.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	mc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.text = "PROJETOS  ·  PLANTAS DE CONSTRUÇÃO"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _btn("FECHAR")
	close.custom_minimum_size = Vector2(160, 56)
	close.pressed.connect(fechar)
	top.add_child(close)
	var line := ColorRect.new()
	line.color = C_INK
	line.custom_minimum_size = Vector2(0, 2)
	v.add_child(line)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	h.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 28)
	_name.add_theme_color_override("font_color", C_HI)
	right.add_child(_name)
	_draw = Control.new()
	_draw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_draw.custom_minimum_size = Vector2(0, 220)
	_draw.draw.connect(_draw_plan)
	right.add_child(_draw)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 20)
	_desc.add_theme_color_override("font_color", C_DIM)
	right.add_child(_desc)
	_need = Label.new()
	_need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_need.add_theme_font_size_override("font_size", 21)
	_need.add_theme_color_override("font_color", C_INK)
	right.add_child(_need)
	var go := _btn("POSICIONAR A PLANTA")
	go.custom_minimum_size = Vector2(0, 64)
	go.pressed.connect(func():
		escolheu.emit(_sel)
		fechar())
	right.add_child(go)


func _btn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.06 if st == "normal" else 0.16)
		s.border_color = C_INK
		s.set_border_width_all(2)
		s.set_corner_radius_all(4)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", C_INK)
	b.add_theme_color_override("font_pressed_color", C_HI)
	return b


func _select(tipo: String) -> void:
	_sel = tipo
	var t: Dictionary = Maquinas.TIPOS[tipo]
	_name.text = str(t.nome).to_upper()
	_desc.text = ""                    # sem texto de como fazer
	var n := Maquinas.needs(tipo)
	var partes := []
	if int(n.tora) > 0:
		partes.append("%d toras redondas finas" % int(n.tora))
	if int(n.meia) > 0:
		partes.append("%d meias toras" % int(n.meia))
	if int(n.tabua) > 0:
		partes.append("%d tábuas" % int(n.tabua))
	if int(n.get("pino", 0)) > 0:
		partes.append("%d pinos de madeira" % int(n.pino))
	if int(n.get("pedra", 0)) > 0:
		partes.append("%d pedras do chão" % int(n.pedra))
	if int(n.get("barro", 0)) > 0:
		partes.append("%d baldes de barro" % int(n.barro))
	var nl := int(n.lamina)
	if nl > 0:
		partes.append(("%d lâminas de faca" % nl) if str(n.lamina_item) == "lamina_faca" else ("%d lâmina de serra" % nl))
	_need.text = "MATERIAL:  " + " · ".join(partes)
	_draw.queue_redraw()


## Desenho de lado (x para a direita, y para cima), em linhas brancas, com cotas.
func _draw_plan() -> void:
	if _sel == "":
		return
	var t: Dictionary = Maquinas.TIPOS[_sel]
	var s := _draw.size
	var sc := minf(s.x / 6.6, s.y / 3.2)
	var o := Vector2(s.x * 0.5, s.y - 18)
	if t.has("laminas") or t.has("mesa") or t.has("torno") or t.has("filtro") or t.has("forno"):
		sc = minf(s.x / 2.8, s.y / 1.25)          # máquina pequena: desenho maior
	var P := func(x: float, y: float) -> Vector2:
		return o + Vector2(x * sc, -y * sc)
	var small := t.has("laminas") or t.has("mesa") or t.has("torno") or t.has("filtro") or t.has("forno")
	_draw.draw_line(P.call(-3.2 if not small else -1.2, 0), P.call(3.2 if not small else 0.9, 0), C_DIM, 1.5)
	for pc in t.pecas:
		var c: Vector3 = pc[2]
		var L := float(pc[1])
		var r := float(pc[4])
		var hh := r * (1.0 if str(pc[0]) == "tora" else (0.5 if str(pc[0]) == "meia" else 0.25))
		var rect: Rect2
		if str(pc[3]).ends_with("_lado"):
			hh = r * 0.9                              # tábua em pé de lado: a largura é a altura
		match str(pc[3]):
			"x", "x_lado": rect = Rect2(c.x - L * 0.5, c.y - hh, L, hh * 2.0)
			"y": rect = Rect2(c.x - r, c.y - L * 0.5, r * 2.0, L)
			_: rect = Rect2(c.x - r, c.y - hh, r * 2.0, hh * 2.0)
		var a: Vector2 = P.call(rect.position.x, rect.position.y)
		var b: Vector2 = P.call(rect.end.x, rect.end.y)
		_draw.draw_rect(Rect2(Vector2(a.x, b.y), Vector2(b.x - a.x, a.y - b.y)), C_INK, false, 2.0)
	var font := get_theme_default_font()
	if t.has("forno"):
		# o domo de lado, o suspiro atrás e a porta na frente
		var pts := PackedVector2Array()
		for i in 25:
			var a := PI * float(i) / 24.0
			var x := -0.1 + cos(a) * 0.82
			if x > 0.55:
				x = 0.55
			pts.append(P.call(x, sin(a) * 0.95))
		_draw.draw_polyline(pts, C_INK, 2.0)
		_draw.draw_rect(Rect2(P.call(-0.45, 1.05), P.call(-0.33, 0.85) - P.call(-0.45, 1.05)), C_INK, false, 2.0)
		_draw.draw_string(font, P.call(-0.95, 1.15), "SUSPIRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_HI)
		_draw.draw_string(font, P.call(-0.7, 0.45), "BARRO E PEDRAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HI)
		_draw.draw_string(font, P.call(0.62, 0.3), "PORTA DE BARRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		return
	if t.has("filtro"):
		_draw.draw_string(font, P.call(0.32, 1.0), "TELA DE FIBRA", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_HI)
		_draw.draw_string(font, P.call(0.32, 0.9), "AREIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_HI)
		_draw.draw_string(font, P.call(0.32, 0.82), "CARVÃO", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_HI)
		_draw.draw_string(font, P.call(0.32, 0.74), "PEDRINHAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_HI)
		_draw.draw_string(font, P.call(0.32, 0.15), "VASILHA DE BARRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_DIM)
		return
	if t.has("torno"):
		_draw.draw_string(font, P.call(0.2, 0.95), "MESA GIRATÓRIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HI)
		_draw.draw_string(font, P.call(0.32, 0.3), "VOLANTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HI)
		_draw.draw_string(font, P.call(-0.85, 0.15), "PEDAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		_draw.draw_string(font, P.call(-1.25, 0.65), "BANQUINHO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		return
	if t.has("mesa"):
		_draw.draw_string(font, P.call(0.2, 1.0), "TAMPO: 2 TÁBUAS EM 2 TRAVESSAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HI)
		_draw.draw_string(font, P.call(-1.25, 0.65), "BANQUINHO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		return
	if t.has("laminas"):
		# desfibradeira: as lâminas em pé em cima da bancada e os nomes
		for lp in t.laminas:
			var q: Vector3 = lp
			_draw.draw_line(P.call(q.x - 0.08, q.y - 0.02), P.call(q.x + 0.08, q.y - 0.02), C_HI, 3.0)
			_draw.draw_line(P.call(q.x - 0.08, q.y - 0.02), P.call(q.x, q.y + 0.03), C_HI, 2.0)
			_draw.draw_line(P.call(q.x + 0.08, q.y - 0.02), P.call(q.x, q.y + 0.03), C_HI, 2.0)
		_draw.draw_string(font, P.call(0.15, 1.05), "LÂMINAS DE FACA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HI)
		_draw.draw_string(font, P.call(0.15, 0.6), "BANCADA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		_draw.draw_string(font, P.call(-1.25, 0.65), "BANCO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
		return
	# a lâmina com os dentes para a mesa
	var lc: Vector3 = t.lamina
	_draw.draw_line(P.call(lc.x, lc.y - 0.55), P.call(lc.x, lc.y + 0.55), C_HI, 3.0)
	for k in 8:
		var y := lc.y - 0.5 + k * 0.14
		_draw.draw_line(P.call(lc.x, y), P.call(lc.x + 0.06, y - 0.03), C_HI, 2.0)
	# setas: a tora entra pela mesa de entrada e sai do outro lado
	_draw.draw_line(P.call(2.6, 1.55), P.call(1.0, 1.55), C_DIM, 2.0)
	_draw.draw_line(P.call(1.0, 1.55), P.call(1.15, 1.62), C_DIM, 2.0)
	_draw.draw_line(P.call(1.0, 1.55), P.call(1.15, 1.48), C_DIM, 2.0)
	_draw.draw_string(font, P.call(1.4, 1.75), "TORA ENTRA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
	_draw.draw_string(font, P.call(-2.8, 1.45), "SAÍDA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
	_draw.draw_string(font, P.call(0.15, 0.45), "PEDAL (DO LADO)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)
	_draw.draw_string(font, P.call(-2.1, 2.9), "VARA DE MOLA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)


func fechar() -> void:
	closed.emit()
	queue_free()
