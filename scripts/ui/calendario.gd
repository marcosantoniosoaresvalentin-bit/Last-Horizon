extends Control
## Calendário de papel, como um calendário de parede antigo, com tudo escrito à mão.
## Quem marca é o jogador (nada é marcado sozinho, só o 1º de janeiro já vem com a bolinha):
##   toca no número do dia → "Dia atual" desenha a bolinha, "Finalizar dia" desenha o X.
## Se esquecer de marcar, o jogo não avisa: dá para se perder nos dias, de propósito.
## As 12 folhas do ano; setas embaixo mudam de mês. Abre na folha que ficou aberta da última vez.
## As marcas ficam salvas no mundo (calendario.json).
##
## Uso: var cal = Calendario.new(); hud.add_child(cal); cal.abrir(sim, caminho_do_arquivo)

signal closed

const MundoSim := preload("res://scripts/mundo_sim.gd")
const FONT_PATH := "res://fontes/caveat.fonte"
const MONTHS_UP := ["JANEIRO", "FEVEREIRO", "MARÇO", "ABRIL", "MAIO", "JUNHO",
	"JULHO", "AGOSTO", "SETEMBRO", "OUTUBRO", "NOVEMBRO", "DEZEMBRO"]
const MONTHS := ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
	"julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]

const CIRCLE := 1
const CROSS := 2
const DRAW_TIME := {CIRCLE: 0.7, CROSS: 0.55}   # segundos para "escrever" cada marca

const INK := Color(0.13, 0.105, 0.085, 0.93)
const RED := Color(0.78, 0.12, 0.10, 0.85)
const PAPER_A := Color(0.84, 0.73, 0.57)
const PAPER_B := Color(0.96, 0.89, 0.76)
const C_UI := Color(0.95, 0.9, 0.8)

static var _font: Font
static var _font_bold: Font
static var _grain: NoiseTexture2D
static var _stains: NoiseTexture2D
static var _edges: GradientTexture2D

var marks := {}            # "ano-mês-dia" -> bits (CIRCLE, CROSS)
var anim := {}             # marca sendo desenhada: {key, kind, t}
var _path := ""
var _start := {}
var _last_year := 2000     # ano mais avançado que dá para folhear (o ano atual do jogo)
var _shown_y := 2000
var _shown_m := 1
var _paper := Paper.new()
var _prev: Button
var _next: Button
var _menu: Control


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
	_prev = _ui_button("‹  Mês anterior", _move.bind(-1))
	_next = _ui_button("Próximo mês  ›", _move.bind(1))
	var close := _ui_button("Fechar", fechar)
	close.name = "Fechar"
	resized.connect(_layout)
	_layout()


func abrir(sim: Node, path: String) -> void:
	_path = path
	_start = Time.get_datetime_dict_from_unix_time(MundoSim.start_unix())
	_last_year = maxi(int(sim.year()), int(_start.year))
	_load()
	_refresh()


func fechar() -> void:
	_save()
	closed.emit()
	queue_free()


static func _key(y: int, m: int, d: int) -> String:
	return "%d-%d-%d" % [y, m, d]


func mark_of(y: int, m: int, d: int) -> int:
	return int(marks.get(_key(y, m, d), 0))


# ================== SALVAR ==================

func _load() -> void:
	marks = {}
	_shown_y = int(_start.year)
	_shown_m = int(_start.month)
	if _path != "" and FileAccess.file_exists(_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if d is Dictionary:
			if d.get("marcas") is Dictionary:
				marks = d.marcas
			if d.get("folha") is Array and d.folha.size() == 2:
				_shown_y = clampi(int(d.folha[0]), int(_start.year), _last_year)
				_shown_m = clampi(int(d.folha[1]), 1, 12)
			return
	# calendário novo: só o primeiro dia vem marcado com a bolinha
	marks[_key(int(_start.year), int(_start.month), int(_start.day))] = CIRCLE


func _save() -> void:
	if _path == "":
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"marcas": marks, "folha": [_shown_y, _shown_m]}))
		f.close()


# ================== FOLHAS ==================

func _move(dir: int) -> void:
	if not anim.is_empty():
		return
	_close_menu()
	_shown_m += dir
	if _shown_m < 1:
		_shown_m = 12
		_shown_y -= 1
	elif _shown_m > 12:
		_shown_m = 1
		_shown_y += 1
	_refresh()


func _refresh() -> void:
	var k := _shown_y * 12 + _shown_m
	_prev.disabled = k <= int(_start.year) * 12 + 1
	_next.disabled = k >= _last_year * 12 + 12
	_paper.queue_redraw()


func _layout() -> void:
	var vw := size.x
	var vh := size.y
	var w := minf(vw * 0.8, (vh - 120.0) * 1.5)
	var h := w / 1.5
	_paper.size = Vector2(w, h)
	_paper.position = Vector2((vw - w) * 0.5, (vh - h) * 0.5 - 40.0)
	var by := _paper.position.y + h + 16.0
	_prev.position = Vector2(vw * 0.5 - 380, by)
	_next.position = Vector2(vw * 0.5 + 140, by)
	var close: Button = get_node_or_null("Fechar")
	if close:
		close.position = Vector2(vw * 0.5 - 90, by)
	_paper.queue_redraw()


func _ui_button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.flat = true
	b.custom_minimum_size = Vector2(180 if t == "Fechar" else 240, 64)
	b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_color_override("font_color", C_UI)
	b.add_theme_color_override("font_hover_color", Color(1, 0.8, 0.6))
	b.add_theme_color_override("font_disabled_color", Color(C_UI, 0.2))
	b.pressed.connect(cb)
	add_child(b)
	return b


func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if tap and _menu == null and not _paper.get_rect().has_point(e.position):
		fechar()
	accept_event()


# ================== MARCAR UM DIA ==================

## O jogador tocou num dia: pergunta o que marcar.
func ask_day(d: int) -> void:
	if not anim.is_empty():
		return
	_close_menu()
	var m := mark_of(_shown_y, _shown_m, d)
	_menu = ColorRect.new()
	(_menu as ColorRect).color = Color(0, 0, 0, 0.45)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.86, 0.72)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.33, 0.2)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var t := Label.new()
	t.text = "%d de %s" % [d, MONTHS[_shown_m - 1]]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", _font_bold)
	t.add_theme_font_size_override("font_size", 46)
	t.add_theme_color_override("font_color", INK)
	v.add_child(t)
	v.add_child(_menu_option("Dia atual", m & CIRCLE == 0, _mark.bind(d, CIRCLE)))
	v.add_child(_menu_option("Finalizar dia", m & CROSS == 0, _mark.bind(d, CROSS)))
	v.add_child(_menu_option("Cancelar", true, _close_menu, true))


func _menu_option(text: String, enabled: bool, cb: Callable, dim := false) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(320, 62)
	b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 40)
	b.add_theme_color_override("font_color", INK if not dim else Color(INK, 0.55))
	b.add_theme_color_override("font_hover_color", RED)
	b.add_theme_color_override("font_pressed_color", RED)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.25))
	b.pressed.connect(cb)
	return b


func _close_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


func _mark(d: int, kind: int) -> void:
	_close_menu()
	var k := _key(_shown_y, _shown_m, d)
	anim = {"key": k, "kind": kind, "t": 0.0}


func _process(delta: float) -> void:
	if anim.is_empty():
		return
	anim.t += delta / float(DRAW_TIME[anim.kind])
	if anim.t >= 1.0:
		marks[anim.key] = int(marks.get(anim.key, 0)) | int(anim.kind)
		anim = {}
		_save()
	_paper.queue_redraw()


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
	var cells := {}    # dia -> Rect2 (para saber em que dia o jogador tocou)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		var tap: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
		if not tap:
			return
		for d in cells:
			if (cells[d] as Rect2).has_point(e.position):
				cal.ask_day(d)
				break
		accept_event()

	func _draw() -> void:
		if cal == null:
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

		# números dos dias e as marcas que o jogador fez
		var num := int(minf(h * 0.072, rh * 0.62))
		cells.clear()
		for d in range(1, ndays + 1):
			var idx := first + d - 1
			var cx := L + cw * (idx % 7)
			var cy := week_b + rh * (idx / 7)
			cells[d] = Rect2(cx, cy, cw, rh)
			draw_string(fb, Vector2(cx + cw * 0.07, cy + num * 0.95), str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, num, cal.INK)
			var key: String = cal._key(y0, m0, d)
			var have: int = cal.mark_of(y0, m0, d)
			var drawing: bool = not cal.anim.is_empty() and cal.anim.key == key
			if have == 0 and not drawing:
				continue
			var mr := RandomNumberGenerator.new()
			mr.seed = hash(Vector3i(y0, m0, d))
			var center := Vector2(cx + cw * 0.6 + mr.randf_range(-2, 2), cy + rh * 0.57 + mr.randf_range(-2, 2))
			var rad := minf(cw, rh) * 0.31
			# a mesma sequência de sorteios para o círculo e o X, para a marca não "pular"
			var circle_rng := RandomNumberGenerator.new()
			circle_rng.seed = mr.seed + 1
			var cross_rng := RandomNumberGenerator.new()
			cross_rng.seed = mr.seed + 2
			var pc := 1.0 if have & cal.CIRCLE else (float(cal.anim.t) if drawing and cal.anim.kind == cal.CIRCLE else 0.0)
			var px := 1.0 if have & cal.CROSS else (float(cal.anim.t) if drawing and cal.anim.kind == cal.CROSS else 0.0)
			if pc > 0.0:
				_circle(center, rad, lw * 1.6, circle_rng, pc)
			if px > 0.0:
				_cross(center, rad * 0.62, lw * 1.6, cross_rng, px)

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
	## 'part' de 0 a 1 desenha só o pedaço já "escrito".
	func _circle(c: Vector2, r: float, width: float, rng: RandomNumberGenerator, part: float) -> void:
		var pts := PackedVector2Array()
		var a0 := rng.randf_range(0, TAU)
		var turn := TAU * rng.randf_range(1.03, 1.12)
		var squash := Vector2(rng.randf_range(0.95, 1.07), rng.randf_range(0.92, 1.03))
		var wob := []
		var n := 40
		for i in n + 1:
			wob.append(rng.randf_range(-0.015, 0.015))
		var last := int(ceil(n * clampf(part, 0.0, 1.0)))
		for i in last + 1:
			var t := float(i) / n
			var a := a0 + turn * t
			var rr: float = r * (1.0 + 0.06 * sin(a * 2.0 + a0) + wob[i] + 0.05 * t)
			pts.append(c + Vector2(cos(a) * squash.x, sin(a) * squash.y) * rr)
		if pts.size() >= 2:
			draw_polyline(pts, cal.RED, width, true)

	## X feito à mão, com traços levemente curvos. Primeiro um traço, depois o outro.
	func _cross(c: Vector2, r: float, width: float, rng: RandomNumberGenerator, part: float) -> void:
		for k in 2:
			var a := Vector2(-r, -r) if k == 0 else Vector2(r, -r)
			var b := -a
			a += Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			b += Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			var bend := (b - a).orthogonal().normalized() * rng.randf_range(-3, 3)
			var wmul := rng.randf_range(0.9, 1.15)
			var seg := clampf(part * 2.0 - k, 0.0, 1.0)
			if seg <= 0.0:
				continue
			var pts := PackedVector2Array()
			var n := 8
			for i in int(ceil(n * seg)) + 1:
				var t := minf(float(i) / n, seg)
				pts.append(c + a.lerp(b, t) + bend * sin(t * PI))
			if pts.size() >= 2:
				draw_polyline(pts, cal.RED, width * wmul, true)
