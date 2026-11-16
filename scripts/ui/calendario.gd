extends Control
## Calendário de papel, como um calendário de parede antigo, com tudo escrito à mão.
## - O dia de hoje fica com um círculo vermelho em volta.
## - Os dias que já passaram ficam com o círculo e um X vermelho no meio.
## - Setas ‹ › mudam o mês (do mês em que o mundo começou até o mês atual).
## Toque fora do papel (ou em "Fechar") para fechar.
##
## Uso: var cal = Calendario.new(); hud.add_child(cal); cal.abrir(sim)

signal closed

const MundoSim := preload("res://scripts/mundo_sim.gd")
const FONT_PATH := "res://fontes/caveat.fonte"
const MONTHS_UP := ["JANEIRO", "FEVEREIRO", "MARÇO", "ABRIL", "MAIO", "JUNHO",
	"JULHO", "AGOSTO", "SETEMBRO", "OUTUBRO", "NOVEMBRO", "DEZEMBRO"]

const INK := Color(0.13, 0.105, 0.085, 0.93)
const RED := Color(0.78, 0.12, 0.10, 0.85)
const PAPER_A := Color(0.84, 0.73, 0.57)
const PAPER_B := Color(0.96, 0.89, 0.76)

static var _font: Font
static var _font_bold: Font
static var _grain: NoiseTexture2D
static var _stains: NoiseTexture2D
static var _edges: GradientTexture2D

var _today := {}
var _start := {}
var _shown_y := 2000
var _shown_m := 3
var _paper := Paper.new()
var _prev: Button
var _next: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_assets()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_paper.cal = self
	add_child(_paper)
	_prev = _arrow("‹", -1)
	_next = _arrow("›", 1)
	var close := Button.new()
	close.text = "Fechar"
	close.flat = true
	close.add_theme_font_override("font", _font_bold)
	close.add_theme_font_size_override("font_size", 40)
	close.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	close.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	close.offset_left = -90
	close.offset_right = 90
	close.offset_top = -74
	close.offset_bottom = -14
	close.pressed.connect(fechar)
	add_child(close)
	resized.connect(_layout)
	_layout()


func abrir(sim: Node) -> void:
	_today = sim.date()
	_start = Time.get_datetime_dict_from_unix_time(MundoSim.start_unix())
	_shown_y = int(_today.year)
	_shown_m = int(_today.month)
	_refresh()


func fechar() -> void:
	closed.emit()
	queue_free()


func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if tap and not _paper.get_rect().has_point(e.position):
		fechar()
	accept_event()


func _arrow(t: String, dir: int) -> Button:
	var b := Button.new()
	b.text = t
	b.flat = true
	b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 90)
	b.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.95, 0.9, 0.8, 0.15))
	b.custom_minimum_size = Vector2(80, 120)
	b.pressed.connect(_move.bind(dir))
	add_child(b)
	return b


func _move(dir: int) -> void:
	_shown_m += dir
	if _shown_m < 1:
		_shown_m = 12
		_shown_y -= 1
	elif _shown_m > 12:
		_shown_m = 1
		_shown_y += 1
	_refresh()


func _key(y: int, m: int) -> int:
	return y * 12 + m


func _refresh() -> void:
	if _today.is_empty():
		return
	_prev.disabled = _key(_shown_y, _shown_m) <= _key(int(_start.year), int(_start.month))
	_next.disabled = _key(_shown_y, _shown_m) >= _key(int(_today.year), int(_today.month))
	_paper.queue_redraw()


func _layout() -> void:
	var vw := size.x
	var vh := size.y
	var w := minf(vw * 0.80, (vh - 110.0) * 1.5)
	var h := w / 1.5
	_paper.size = Vector2(w, h)
	_paper.position = Vector2((vw - w) * 0.5, (vh - h) * 0.5 - 30.0)
	_prev.position = Vector2(_paper.position.x - 95, _paper.position.y + h * 0.5 - 60)
	_next.position = Vector2(_paper.position.x + w + 15, _paper.position.y + h * 0.5 - 60)
	_paper.queue_redraw()


## Estado de um dia do mês mostrado: 0 = nada, 1 = hoje (círculo), 2 = já passou (círculo e X).
func day_state(d: int) -> int:
	var t := _key(int(_today.year), int(_today.month))
	var s := _key(int(_start.year), int(_start.month))
	var k := _key(_shown_y, _shown_m)
	if k < s or k > t:
		return 0
	if k == s and d < int(_start.day):
		return 0     # antes do mundo existir
	if k < t:
		return 2
	if d < int(_today.day):
		return 2
	return 1 if d == int(_today.day) else 0


# ================== FONTE E TEXTURAS ==================

static func _load_assets() -> void:
	if _font == null:
		var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
		if bytes.is_empty():
			_font = ThemeDB.fallback_font
			_font_bold = ThemeDB.fallback_font
		else:
			var ff := FontFile.new()
			ff.data = bytes
			_font = ff
			var fv := FontVariation.new()
			fv.base_font = ff
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
			_font_bold = fv
	if _grain == null:
		_grain = _noise_tex(512, 0.035, 7, [PAPER_A, PAPER_B, Color(0.98, 0.93, 0.82)], [0.0, 0.55, 1.0])
		_stains = _noise_tex(256, 0.012, 3, [Color(0.55, 0.38, 0.2, 0.0), Color(0.55, 0.38, 0.2, 0.0), Color(0.5, 0.33, 0.16, 0.32)], [0.0, 0.58, 1.0])
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.86, 1.0])
		g.colors = PackedColorArray([Color(0.45, 0.3, 0.15, 0.0), Color(0.45, 0.3, 0.15, 0.0), Color(0.45, 0.28, 0.12, 0.28), Color(0.35, 0.2, 0.08, 0.6)])
		_edges = GradientTexture2D.new()
		_edges.gradient = g
		_edges.fill = GradientTexture2D.FILL_SQUARE
		_edges.fill_from = Vector2(0.5, 0.5)
		_edges.fill_to = Vector2(1.0, 0.5)
		_edges.width = 256
		_edges.height = 256


static func _noise_tex(px: int, freq: float, seed_: int, colors: Array, offsets: Array) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array(offsets)
	ramp.colors = PackedColorArray(colors)
	var t := NoiseTexture2D.new()
	t.width = px
	t.height = px
	t.seamless = true
	t.noise = n
	t.color_ramp = ramp
	return t


# ================== O PAPEL ==================

class Paper extends Control:
	var cal

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		if cal == null or cal._today.is_empty():
			return
		var w := size.x
		var h := size.y
		var rng := RandomNumberGenerator.new()
		rng.seed = 77

		# papel com bordas gastas e sombra
		var edge := PackedVector2Array()
		var uvs := PackedVector2Array()
		var steps := 64
		for i in steps:
			var t := float(i) / steps
			var p: Vector2
			if t < 0.25:
				p = Vector2(t * 4.0 * w, rng.randf_range(-2, 3))
			elif t < 0.5:
				p = Vector2(w + rng.randf_range(-3, 2), (t - 0.25) * 4.0 * h)
			elif t < 0.75:
				p = Vector2(w - (t - 0.5) * 4.0 * w, h + rng.randf_range(-3, 2))
			else:
				p = Vector2(rng.randf_range(-2, 3), h - (t - 0.75) * 4.0 * h)
			edge.append(p)
			uvs.append(Vector2(p.x / w, p.y / h))
		var shadow := PackedVector2Array()
		for p in edge:
			shadow.append(p + Vector2(8, 10))
		_fan(shadow, PackedVector2Array(), Color(0, 0, 0, 0.35), null)
		_fan(edge, uvs, Color(1, 1, 1), cal._grain)
		_fan(edge, uvs, Color(1, 1, 1), cal._stains)
		_fan(edge, uvs, Color(1, 1, 1), cal._edges)

		# quadro, faixa do título, linha dos dias da semana e a grade
		var y0: int = cal._shown_y
		var m0: int = cal._shown_m
		var first := MundoSim.first_weekday(y0, m0)
		var ndays := MundoSim.days_in_month(y0, m0)
		var rows := ceili((first + ndays) / 7.0)
		var L := w * 0.055
		var R := w - w * 0.055
		var T := h * 0.075
		var B := h - h * 0.07
		var title_b := T + h * 0.165
		var week_b := title_b + h * 0.085
		var cw := (R - L) / 7.0
		var rh := (B - week_b) / rows
		var lw := maxf(1.5, w / 700.0)
		_line(Vector2(L, T), Vector2(R, T), lw * 1.3, rng)
		_line(Vector2(L, B), Vector2(R, B), lw * 1.3, rng)
		_line(Vector2(L, T), Vector2(L, B), lw * 1.3, rng)
		_line(Vector2(R, T), Vector2(R, B), lw * 1.3, rng)
		_line(Vector2(L, title_b), Vector2(R, title_b), lw, rng)
		_line(Vector2(L, week_b), Vector2(R, week_b), lw, rng)
		for r in range(1, rows):
			_line(Vector2(L, week_b + rh * r), Vector2(R, week_b + rh * r), lw, rng)
		for c in range(1, 7):
			_line(Vector2(L + cw * c, title_b), Vector2(L + cw * c, B), lw, rng)

		# título: mês e ano escritos à mão
		var big := int(h * 0.15)
		var fb: Font = cal._font_bold
		var f: Font = cal._font
		draw_string(fb, Vector2(L + w * 0.025, title_b - h * 0.03), cal.MONTHS_UP[m0 - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, big, cal.INK)
		draw_string(fb, Vector2(R - w * 0.025 - w * 0.3, title_b - h * 0.03), str(y0), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.3, big, cal.INK)
		var wk := int(h * 0.062)
		for c in 7:
			draw_string(f, Vector2(L + cw * c, week_b - h * 0.022), MundoSim.WEEKDAYS[c], HORIZONTAL_ALIGNMENT_CENTER, cw, wk, cal.INK)

		# números dos dias e as marcas vermelhas
		var num := int(minf(h * 0.072, rh * 0.62))
		for d in range(1, ndays + 1):
			var idx := first + d - 1
			var cx := L + cw * (idx % 7)
			var cy := week_b + rh * (idx / 7)
			draw_string(fb, Vector2(cx + cw * 0.07, cy + num * 0.95), str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, num, cal.INK)
			var st: int = cal.day_state(d)
			if st > 0:
				var mr := RandomNumberGenerator.new()
				mr.seed = hash(Vector3i(y0, m0, d))
				var center := Vector2(cx + cw * 0.6 + mr.randf_range(-2, 2), cy + rh * 0.57 + mr.randf_range(-2, 2))
				var rad := minf(cw, rh) * 0.31
				_circle(center, rad, lw * 1.6, mr)
				if st == 2:
					_cross(center, rad * 0.62, lw * 1.6, mr)

	## Desenha o contorno em fatias saindo do centro (sempre funciona, mesmo com a borda irregular).
	func _fan(pts: PackedVector2Array, uvs: PackedVector2Array, color: Color, tex: Texture2D) -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var cuv := Vector2(0.5, 0.5)
		var cols := PackedColorArray([color, color, color])
		var n := pts.size()
		for i in n:
			var j := (i + 1) % n
			var tri := PackedVector2Array([c, pts[i], pts[j]])
			if tex:
				draw_primitive(tri, cols, PackedVector2Array([cuv, uvs[i], uvs[j]]), tex)
			else:
				draw_primitive(tri, cols, PackedVector2Array())


	## Linha de tinta levemente torta.
	func _line(a: Vector2, b: Vector2, width: float, rng: RandomNumberGenerator) -> void:
		var pts := PackedVector2Array()
		var n := 6
		var perp := (b - a).orthogonal().normalized()
		for i in n + 1:
			var t := float(i) / n
			var j := 0.0 if i == 0 or i == n else rng.randf_range(-0.9, 0.9)
			pts.append(a.lerp(b, t) + perp * j)
		draw_polyline(pts, cal.INK, width, true)

	## Círculo feito à mão: não fecha certinho e passa um pouco do começo.
	func _circle(c: Vector2, r: float, width: float, rng: RandomNumberGenerator) -> void:
		var pts := PackedVector2Array()
		var a0 := rng.randf_range(0, TAU)
		var turn := TAU * rng.randf_range(1.03, 1.12)
		var squash := Vector2(rng.randf_range(0.95, 1.07), rng.randf_range(0.92, 1.03))
		var n := 40
		for i in n + 1:
			var t := float(i) / n
			var a := a0 + turn * t
			var rr := r * (1.0 + 0.06 * sin(a * 2.0 + a0) + rng.randf_range(-0.015, 0.015) + 0.05 * t)
			pts.append(c + Vector2(cos(a) * squash.x, sin(a) * squash.y) * rr)
		draw_polyline(pts, cal.RED, width, true)

	## X feito à mão, com traços levemente curvos.
	func _cross(c: Vector2, r: float, width: float, rng: RandomNumberGenerator) -> void:
		for k in 2:
			var a := Vector2(-r, -r) if k == 0 else Vector2(r, -r)
			var b := -a
			a += Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			b += Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			var bend := (b - a).orthogonal().normalized() * rng.randf_range(-3, 3)
			var pts := PackedVector2Array()
			for i in 6:
				var t := i / 5.0
				pts.append(c + a.lerp(b, t) + bend * sin(t * PI))
			draw_polyline(pts, cal.RED, width * rng.randf_range(0.9, 1.15), true)
