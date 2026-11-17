extends RefCounted
## Ícones dos botões da tela do jogo, desenhados em código (no mesmo estilo da mochila):
## sem caixa em volta, com sombra para destacar do cenário e o nome embaixo.

const Desenhos := preload("res://scripts/ui/desenhos.gd")

const INK := Color(0.1, 0.08, 0.06)
const BONE := Color(0.93, 0.9, 0.82)
const WOOD := Color(0.55, 0.36, 0.2)
const WOOD_LIGHT := Color(0.8, 0.63, 0.4)
const BARK := Color(0.3, 0.22, 0.15)
const RED := Color(0.84, 0.16, 0.12)
const OLIVE := Color(0.42, 0.45, 0.27)


## Botão com ícone. O texto do botão vira a legenda embaixo e também escolhe o
## desenho ("Cortar tora", "Pegar tora", "Pular"...). Pode fixar o desenho em "kind".
class IconButton extends Button:
	const Icones := preload("res://scripts/ui/icones.gd")
	var kind := ""
	var show_caption := true

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			add_theme_color_override(c, Color(0, 0, 0, 0))

	func _set(property: StringName, _value: Variant) -> bool:
		if property == "text":
			queue_redraw.call_deferred()
		return false

	func _draw() -> void:
		var cap_h := 26.0 if show_caption and text != "" else 0.0
		var area := Vector2(size.x, size.y - cap_h)
		var s := minf(area.x, area.y) * 0.86
		var c := Vector2(size.x * 0.5, area.y * 0.5)
		var k := kind if kind != "" else Icones.kind_for(text)
		var press := 0.92 if is_pressed() else 1.0
		# sombra embaixo e o ícone por cima
		Icones.draw_icon(self, k, c + Vector2(2, 3), s * press, true)
		Icones.draw_icon(self, k, c, s * press, false)
		if cap_h > 0.0:
			var font := get_theme_default_font()
			var fs := 19
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			while w > size.x + 6 and fs > 12:
				fs -= 1
				w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2((size.x - w) * 0.5, size.y - 6)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.93, 0.86))


static func kind_for(text: String) -> String:
	var t := text.to_lower()
	if t.begins_with("cortar galho"):
		return "cortar_galho"
	if t.begins_with("pegar galho"):
		return "pegar_galho"
	if t.contains("forquilha"):
		return "forquilha"
	if t.begins_with("apoiar"):
		return "apoiar"
	if t.begins_with("cavar"):
		return "cavar"
	if t.begins_with("fincar"):
		return "fincar"
	if t.begins_with("cortar tora"):
		return "cortar_tora"
	if t.begins_with("cortar"):
		return "cortar"
	if t.begins_with("pegar tora"):
		return "pegar_tora"
	if t.begins_with("largar"):
		return "largar_tora"
	if t.contains("cipó") or t.contains("cipo"):
		return "cipo"
	if t.contains("argila"):
		return "argila"
	if t.contains("semente"):
		return "semente"
	if t.begins_with("pular"):
		return "pular"
	if t.begins_with("craft"):
		return "craft"
	if t.begins_with("calend"):
		return "calendario"
	if t.begins_with("menu"):
		return "menu"
	return "pegar"


## Desenha um ícone. shadow = só a silhueta escura (sombra).
static func draw_icon(ci: CanvasItem, k: String, c: Vector2, s: float, shadow: bool) -> void:
	var u := s / 100.0
	var sh := Color(0, 0, 0, 0.45)
	var col := func(cc: Color) -> Color:
		return sh if shadow else cc
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in arr:
			out.append(c + Vector2(p[0], p[1]) * u)
		return out
	var ink: Color = col.call(INK)
	match k:
		"craft":
			# martelo de pedra e faca de lasca cruzados
			ci.draw_line(c + Vector2(-34, 36) * u, c + Vector2(26, -24) * u, col.call(WOOD), 9 * u, true)
			ci.draw_line(c + Vector2(-34, 36) * u, c + Vector2(26, -24) * u, ink, 1.5 * u, true)
			var head: PackedVector2Array = P.call([[10, -44], [44, -12], [32, 0], [-2, -32]])
			ci.draw_colored_polygon(head, col.call(Color(0.5, 0.5, 0.47)))
			ci.draw_polyline(head + PackedVector2Array([head[0]]), ink, 2.5 * u, true)
			ci.draw_line(c + Vector2(34, 36) * u, c + Vector2(4, 6) * u, col.call(WOOD), 8 * u, true)
			var blade: PackedVector2Array = P.call([[6, 8], [-34, -40], [-24, -44], [12, 0]])
			ci.draw_colored_polygon(blade, col.call(Color(0.72, 0.72, 0.68)))
			ci.draw_polyline(blade + PackedVector2Array([blade[0]]), ink, 2.5 * u, true)
		"calendario":
			var page: PackedVector2Array = P.call([[-38, -30], [38, -30], [38, 42], [-38, 42]])
			ci.draw_colored_polygon(page, col.call(BONE))
			ci.draw_colored_polygon(P.call([[-38, -30], [38, -30], [38, -12], [-38, -12]]), col.call(RED))
			ci.draw_polyline(page + PackedVector2Array([page[0]]), ink, 3 * u, true)
			if not shadow:
				for x in [-20, 20]:
					ci.draw_line(c + Vector2(x, -40) * u, c + Vector2(x, -22) * u, INK, 5 * u, true)
				for row in 3:
					for colm in 4:
						ci.draw_circle(c + Vector2(-24 + colm * 16, 2 + row * 13) * u, 2.6 * u, INK)
				ci.draw_arc(c + Vector2(8, 15) * u, 8 * u, 0, TAU, 18, RED, 3 * u, true)
		"menu":
			# engrenagem
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				var r := 40.0 if (i % 6) < 3 else 31.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * u)
			ci.draw_colored_polygon(pts, col.call(BONE))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.5 * u, true)
			if not shadow:
				ci.draw_circle(c, 13 * u, Color(0.25, 0.25, 0.25))
				ci.draw_arc(c, 13 * u, 0, TAU, 20, INK, 2.5 * u, true)
		"pular":
			# pessoa pulando com a seta para cima
			var body: Color = col.call(BONE)
			ci.draw_circle(c + Vector2(4, -26) * u, 9 * u, body)
			ci.draw_line(c + Vector2(2, -15) * u, c + Vector2(-2, 10) * u, body, 9 * u, true)
			ci.draw_line(c + Vector2(0, -8) * u, c + Vector2(-20, -24) * u, body, 7 * u, true)
			ci.draw_line(c + Vector2(0, -8) * u, c + Vector2(20, -20) * u, body, 7 * u, true)
			ci.draw_line(c + Vector2(-2, 10) * u, c + Vector2(-20, 22) * u, body, 8 * u, true)
			ci.draw_line(c + Vector2(-20, 22) * u, c + Vector2(-12, 34) * u, body, 8 * u, true)
			ci.draw_line(c + Vector2(-2, 10) * u, c + Vector2(16, 24) * u, body, 8 * u, true)
			ci.draw_line(c + Vector2(-40, 44) * u, c + Vector2(40, 44) * u, col.call(OLIVE), 6 * u, true)
			var arr: PackedVector2Array = P.call([[30, -44], [44, -24], [35, -24], [35, 2], [25, 2], [25, -24], [16, -24]])
			ci.draw_colored_polygon(arr, col.call(Color(0.98, 0.62, 0.25)))
			ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"cortar":
			# tronco em pé com o corte e o machado de pedra
			var tr: PackedVector2Array = P.call([[-38, -46], [-10, -46], [-6, 46], [-44, 46]])
			ci.draw_colored_polygon(tr, col.call(BARK))
			ci.draw_polyline(tr + PackedVector2Array([tr[0]]), ink, 2.5 * u, true)
			ci.draw_colored_polygon(P.call([[-8, -4], [-24, 8], [-6, 18]]), col.call(WOOD_LIGHT))
			if shadow:
				ci.draw_line(c + Vector2(-2, 40) * u, c + Vector2(30, -30) * u, sh, 10 * u, true)
			else:
				Desenhos.item(ci, "machado", c + Vector2(16, 0) * u, s * 0.85)
		"cortar_tora", "pegar_tora", "largar_tora":
			# tora deitada com a ponta cortada
			var off := Vector2(0, 14) if k == "cortar_tora" else Vector2(0, 8)
			var lg: PackedVector2Array = P.call([[-40, -10], [26, -10], [26, 22], [-40, 22]])
			for i in lg.size():
				lg[i] += off * u
			ci.draw_colored_polygon(lg, col.call(BARK))
			ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 2.5 * u, true)
			var end := c + (Vector2(26, 6) + off) * u
			ci.draw_circle(end, 16 * u, col.call(WOOD_LIGHT))
			ci.draw_arc(end, 16 * u, 0, TAU, 22, ink, 2.5 * u, true)
			if not shadow:
				ci.draw_arc(end, 9 * u, 0, TAU, 16, WOOD, 2 * u, true)
				ci.draw_circle(end, 2.5 * u, WOOD)
			if k == "cortar_tora":
				if shadow:
					ci.draw_line(c + Vector2(-26, 6) * u, c + Vector2(10, -44) * u, sh, 10 * u, true)
				else:
					Desenhos.item(ci, "machado", c + Vector2(-6, -18) * u, s * 0.7)
			else:
				var up := k == "pegar_tora"
				var y0 := -46.0
				var arr: PackedVector2Array = P.call([[-10, y0 + 22], [-10, y0 + 8], [-20, y0 + 8], [0, y0 - 10], [20, y0 + 8], [10, y0 + 8], [10, y0 + 22]]) if up \
					else P.call([[-10, y0 - 8], [-10, y0 + 6], [-20, y0 + 6], [0, y0 + 24], [20, y0 + 6], [10, y0 + 6], [10, y0 - 8]])
				ci.draw_colored_polygon(arr, col.call(Color(0.98, 0.62, 0.25) if up else Color(0.55, 0.8, 0.45)))
				ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"cortar_galho", "pegar_galho":
			# galho no chão (com galhinho); cortar: machado em cima; pegar: seta para cima
			ci.draw_line(c + Vector2(-44, 28) * u, c + Vector2(40, 12) * u, col.call(BARK), 9 * u, true)
			ci.draw_line(c + Vector2(-6, 21) * u, c + Vector2(8, 2) * u, col.call(BARK), 5 * u, true)
			ci.draw_circle(c + Vector2(40, 12) * u, 4.5 * u, col.call(WOOD_LIGHT))
			if k == "cortar_galho":
				if shadow:
					ci.draw_line(c + Vector2(-20, 14) * u, c + Vector2(18, -44) * u, sh, 10 * u, true)
				else:
					Desenhos.item(ci, "machado", c + Vector2(0, -18) * u, s * 0.66)
			else:
				var arr: PackedVector2Array = P.call([[-8, -6], [-8, -20], [-18, -20], [2, -40], [22, -20], [12, -20], [12, -6]])
				ci.draw_colored_polygon(arr, col.call(Color(0.98, 0.62, 0.25)))
				ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"forquilha", "apoiar":
			# X de galhos amarrado; apoiar: tora deitada em cima
			ci.draw_line(c + Vector2(-34, 42) * u, c + Vector2(22, -24) * u, col.call(BARK), 8 * u, true)
			ci.draw_line(c + Vector2(34, 42) * u, c + Vector2(-22, -24) * u, col.call(BARK), 8 * u, true)
			ci.draw_circle(c + Vector2(0, 16) * u, 7 * u, col.call(Color(0.25, 0.3, 0.12)))
			if k == "apoiar":
				var lg: PackedVector2Array = P.call([[-46, -30], [36, -30], [36, -6], [-46, -6]])
				ci.draw_colored_polygon(lg, col.call(BARK.lightened(0.1)))
				ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 2 * u, true)
				ci.draw_circle(c + Vector2(36, -18) * u, 12 * u, col.call(WOOD_LIGHT))
		"cavar":
			# chão com buraco e a cavadeira cravada
			ci.draw_colored_polygon(P.call([[-46, 22], [46, 22], [46, 46], [-46, 46]]), col.call(Color(0.42, 0.3, 0.18)))
			ci.draw_line(c + Vector2(-46, 22) * u, c + Vector2(46, 22) * u, col.call(Color(0.3, 0.45, 0.16)), 5 * u, true)
			ci.draw_colored_polygon(P.call([[-30, 22], [-2, 22], [-8, 36], [-24, 36]]), col.call(Color(0.08, 0.06, 0.04)))
			if shadow:
				ci.draw_line(c + Vector2(30, -46) * u, c + Vector2(0, 20) * u, sh, 10 * u, true)
			else:
				Desenhos.item(ci, "cavadeira", c + Vector2(10, -10) * u, s * 0.85)
		"fincar":
			# tora em pé enterrada no chão, com seta para baixo
			ci.draw_colored_polygon(P.call([[-46, 20], [46, 20], [46, 46], [-46, 46]]), col.call(Color(0.42, 0.3, 0.18)))
			ci.draw_line(c + Vector2(-46, 20) * u, c + Vector2(46, 20) * u, col.call(Color(0.3, 0.45, 0.16)), 5 * u, true)
			var lg: PackedVector2Array = P.call([[-16, -30], [10, -30], [10, 36], [-16, 36]])
			ci.draw_colored_polygon(lg, col.call(BARK))
			ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 2.5 * u, true)
			ci.draw_colored_polygon(P.call([[-16, -30], [10, -30], [6, -36], [-12, -36]]), col.call(WOOD_LIGHT))
			var arr: PackedVector2Array = P.call([[28, -40], [38, -40], [38, -20], [46, -20], [33, -4], [20, -20], [28, -20]])
			ci.draw_colored_polygon(arr, col.call(Color(0.55, 0.8, 0.45)))
			ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"cipo":
			# rolo de raiz de titica com uma folha
			for ring in 3:
				var rr := 30.0 - ring * 7.0
				ci.draw_arc(c + Vector2(0, 6) * u, rr * u, 0, TAU, 28, col.call(Color(0.5, 0.4, 0.26).darkened(ring * 0.12)), 6 * u, true)
			ci.draw_line(c + Vector2(28, 8) * u, c + Vector2(44, 38) * u, col.call(Color(0.5, 0.4, 0.26)), 6 * u, true)
			var lf: PackedVector2Array = P.call([[-10, -26], [-30, -46], [-6, -44], [4, -30]])
			ci.draw_colored_polygon(lf, col.call(Color(0.22, 0.45, 0.16)))
			ci.draw_polyline(lf + PackedVector2Array([lf[0]]), ink, 2 * u, true)
		"argila":
			var pts := PackedVector2Array()
			for i in 18:
				var a := TAU * i / 18.0
				var r := 34.0 * (0.85 + 0.15 * sin(i * 2.3))
				pts.append(c + Vector2(cos(a) * r * 1.2, sin(a) * r * 0.85 + 6) * u)
			ci.draw_colored_polygon(pts, col.call(Color(0.6, 0.32, 0.2)))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.5 * u, true)
			if not shadow:
				ci.draw_circle(c + Vector2(-12, -6) * u, 7 * u, Color(0.78, 0.5, 0.36))
		"semente":
			if not shadow:
				var wing: PackedVector2Array = P.call([[-4, -6], [-44, -18], [-48, -2], [-4, 6]])
				ci.draw_colored_polygon(wing, Color(0.66, 0.5, 0.32))
				ci.draw_polyline(wing + PackedVector2Array([wing[0]]), INK, 2 * u, true)
				var body: PackedVector2Array = P.call([[20, 0], [6, -12], [-8, 0], [6, 12]])
				ci.draw_colored_polygon(body, Color(0.42, 0.26, 0.14))
				ci.draw_polyline(body + PackedVector2Array([body[0]]), INK, 2 * u, true)
		_:
			# mão aberta (pegar)
			var palm: PackedVector2Array = P.call([[-24, -2], [22, -2], [24, 30], [-20, 34]])
			ci.draw_colored_polygon(palm, col.call(Color(0.93, 0.76, 0.6)))
			for i in 4:
				var x := -18 + i * 12
				ci.draw_line(c + Vector2(x, 0) * u, c + Vector2(x, -32 + absf(i - 1.5) * 6) * u, col.call(Color(0.93, 0.76, 0.6)), 9 * u, true)
			ci.draw_line(c + Vector2(-22, 14) * u, c + Vector2(-40, 0) * u, col.call(Color(0.93, 0.76, 0.6)), 9 * u, true)
			ci.draw_polyline(palm + PackedVector2Array([palm[0]]), ink, 2 * u, true)
