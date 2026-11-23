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

	func _init() -> void:
		clip_text = true          # o texto (invisível) não alarga o botão: todos do mesmo tamanho

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
		if cap_h > 0.0 and get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > size.x + 4:
			cap_h = 38.0                        # nome comprido: duas linhas embaixo
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
			while w > size.x + 4 and fs > 15:
				fs -= 1
				w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var linhas := [text]
			if w > size.x + 4:
				# comprido: em duas linhas (quebra no espaço mais perto do meio)
				var meio := text.length() / 2
				var corte := -1
				for d in text.length():
					for q in [meio - d, meio + d]:
						if q > 0 and q < text.length() and text[q] == " ":
							corte = q
							break
					if corte >= 0:
						break
				if corte > 0:
					linhas = [text.substr(0, corte), text.substr(corte + 1)]
				fs = 16
				for ln in linhas:
					while font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x + 8 and fs > 11:
						fs -= 1
			for li in linhas.size():
				var ln2: String = linhas[li]
				var w2 := font.get_string_size(ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var pos := Vector2((size.x - w2) * 0.5, size.y - 6 - (linhas.size() - 1 - li) * (fs + 1))
				draw_string_outline(font, pos, ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
				draw_string(font, pos, ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.93, 0.86))


static func kind_for(text: String) -> String:
	var t := text.to_lower()
	if t.begins_with("modelar"):
		return "modelar"
	if t.begins_with("pegar pedra"):
		return "it_pedra"
	if t.begins_with("bater"):
		return "bater"
	if t.begins_with("sair"):
		return "sair"
	if t.begins_with("pedra de machado"):
		return "it_pedra_machado"
	if t.begins_with("lâmina de cavadeira"):
		return "it_pedra_cavadeira"
	if t.begins_with("lâmina de serra"):
		return "it_lamina_serra"
	if t.begins_with("lâmina de pá"):
		return "it_pedra_pa"
	if t.begins_with("cunha"):
		return "it_cunha"
	if t.begins_with("pedra de marreta"):
		return "it_pedra_marreta"
	if t.begins_with("rachar"):
		return "rachar"
	if t.begins_with("serrar"):
		return "serrar"
	if t.begins_with("parar"):
		return "parar"
	if t.begins_with("colocar"):
		return "colocar"
	if t.begins_with("girar"):
		return "girar"
	if t.begins_with("guardar"):
		return "guardar"
	if t.begins_with("trabalhar"):
		return "trabalhar"
	if t.contains("rodela"):
		return "cortar_rodela" if t.begins_with("cortar") else "pegar_rodela"
	if t.begins_with("cortar galho"):
		return "cortar_galho"
	if t.begins_with("pegar galho"):
		return "pegar_galho"
	if t.contains("forquilha"):
		return "forquilha"
	if t.begins_with("apoiar"):
		return "apoiar"
	if t.begins_with("jogar terra"):
		return "cavar"
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
	if t.begins_with("atirar"):
		return "atirar"
	if t.begins_with("laçar"):
		return "lacar"
	if t.begins_with("força"):
		return "forca"
	if t.begins_with("pular"):
		return "pular"
	if t.begins_with("craft"):
		return "craft"
	if t.begins_with("projeto"):
		return "projetos"
	if t.begins_with("amarr"):
		return "cipo"
	if t.begins_with("calend"):
		return "calendario"
	if t.begins_with("menu"):
		return "menu"
	# o resto: o desenho de verdade da coisa que se pega ou se usa
	for par in ACAO_ITEM:
		if t.begins_with(str(par[0])):
			return "it_" + str(par[1])
	return "pegar"


## Começo do texto do botão -> o item desenhado no botão.
const ACAO_ITEM := [
	["pegar coco de babaçu", "coco_babacu"], ["pegar coco", "coco"], ["pegar goiaba", "goiaba"],
	["pegar folhas de goiabeira", "folha_goiabeira"], ["pegar frutos", "fruto_buriti"], ["pegar folha seca", "folha_buriti_seca"],
	["pegar folha de babaçu", "folha_babacu"], ["cortar folha de babaçu", "folha_babacu"], ["colher capim", "capim_seco"],
	["arrancar jararaca", "taia"], ["colher timbó", "raiz_timbo"], ["pegar sementes de andiroba", "semente_andiroba"],
	["passar óleo", "oleo_andiroba"], ["envenenar", "veneno_timbo"], ["encher a cabaça", "moringa_agua"],
	["beber água", "moringa_limpa"], ["pegar água", "balde"], ["encher o balde", "balde"], ["despejar", "balde"],
	["pegar a carne", "carne_crua"], ["soltar a carne", "carne_crua"], ["enrolar o couro", "couro_vaca"], ["pegar o couro", "couro_vaca"],
	["pôr no cepo", "lenha"], ["rebocar", "argila"], ["furar", "pino"], ["pegar peça", "tabua"], ["pegar tábua", "tabua"],
	["dormir", "cama"], ["tirar o osso", "osso"], ["pegar osso", "osso"], ["arremessar", "vara_pesca"], ["recolher", "linha_pesca"], ["pegar a corda", "corda_10"], ["puxar a corda", "corda_10"],
]


## Forma com luz (clara em cima, escura embaixo); a sombra preta fica chapada.
static func _pp(ci: CanvasItem, pts: PackedVector2Array, cor: Color) -> void:
	if cor.r + cor.g + cor.b < 0.02:
		ci.draw_colored_polygon(pts, cor)
		return
	Desenhos._poly(ci, pts, cor)


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
		"lacar":
			# a laçada aberta girando no ar, com a corda descendo
			var lp := PackedVector2Array()
			for i in 33:
				var a := TAU * i / 32.0
				lp.append(c + Vector2(cos(a) * 34, -12 + sin(a) * 18) * u)
			ci.draw_polyline(lp, ink, 9 * u, true)
			ci.draw_polyline(lp, col.call(Color(0.72, 0.6, 0.32)), 6 * u, true)
			ci.draw_line(c + Vector2(20, 2) * u, c + Vector2(30, 44) * u, ink, 9 * u, true)
			ci.draw_line(c + Vector2(20, 2) * u, c + Vector2(30, 44) * u, col.call(Color(0.72, 0.6, 0.32)), 6 * u, true)
			if not shadow:
				for k2 in 3:
					var a2 := -0.6 + k2 * 0.6
					ci.draw_arc(c + Vector2(0, -12) * u, 44 * u, a2 - 0.2, a2, 8, Color(1, 1, 1, 0.5), 2.5 * u, true)
		"forca":
			# o braço dobrado fazendo força (o bíceps) puxando a corda
			var braco: PackedVector2Array = P.call([[-38, 34], [-30, 6], [-14, -12], [6, -30], [22, -36], [30, -26], [18, -12], [4, -2], [-6, 18], [-12, 38]])
			_pp(ci, braco, col.call(Color(0.86, 0.66, 0.5)))
			ci.draw_polyline(braco + PackedVector2Array([braco[0]]), ink, 2.5 * u, true)
			ci.draw_circle(c + Vector2(-12, 0) * u, 15 * u, col.call(Color(0.9, 0.7, 0.54)))
			ci.draw_arc(c + Vector2(-12, 0) * u, 15 * u, PI * 1.05, PI * 1.95, 12, ink, 2.5 * u, true)
			ci.draw_line(c + Vector2(26, -30) * u, c + Vector2(46, 40) * u, ink, 8 * u, true)
			ci.draw_line(c + Vector2(26, -30) * u, c + Vector2(46, 40) * u, col.call(Color(0.72, 0.6, 0.32)), 5 * u, true)
		"atirar":
			# o arco com a flecha no ponto de soltar
			var pa := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				pa.append(c + Vector2(-20 + sin(t * PI) * 30, lerpf(-44, 44, t)) * u)
			ci.draw_polyline(pa, col.call(Color(0.5, 0.33, 0.18)), 8 * u, true)
			ci.draw_line(pa[0], c + Vector2(-34, 0) * u, col.call(Color(0.85, 0.8, 0.55)), 2.5 * u, true)
			ci.draw_line(pa[16], c + Vector2(-34, 0) * u, col.call(Color(0.85, 0.8, 0.55)), 2.5 * u, true)
			ci.draw_line(c + Vector2(-38, 0) * u, c + Vector2(40, 0) * u, col.call(Color(0.7, 0.52, 0.32)), 5 * u, true)
			_pp(ci, P.call([[38, -9], [54, 0], [38, 9]]), col.call(Color(0.6, 0.6, 0.58)))
		"projetos":
			# folha de planta azul enrolada com o desenho em linhas brancas
			var pg: PackedVector2Array = P.call([[-40, -34], [36, -34], [36, 38], [-40, 38]])
			_pp(ci, pg, col.call(Color(0.16, 0.33, 0.6)))
			ci.draw_polyline(pg + PackedVector2Array([pg[0]]), ink, 2.5 * u, true)
			if not shadow:
				var wl := Color(0.92, 0.95, 1.0)
				for gx in [-24, -8, 8, 24]:
					ci.draw_line(c + Vector2(gx, -30) * u, c + Vector2(gx, 34) * u, Color(1, 1, 1, 0.18), 1.0, true)
				# o desenho: uma armação com a serra no meio
				ci.draw_line(c + Vector2(-26, 26) * u, c + Vector2(24, 26) * u, wl, 3 * u, true)
				ci.draw_line(c + Vector2(-6, 26) * u, c + Vector2(-6, -22) * u, wl, 3 * u, true)
				ci.draw_line(c + Vector2(6, 26) * u, c + Vector2(6, -22) * u, wl, 3 * u, true)
				ci.draw_line(c + Vector2(-12, -22) * u, c + Vector2(12, -22) * u, wl, 3 * u, true)
				ci.draw_line(c + Vector2(0, -16) * u, c + Vector2(0, 14) * u, Color(1, 0.8, 0.4), 2.5 * u, true)
				ci.draw_line(c + Vector2(6, 6) * u, c + Vector2(26, 6) * u, wl, 3 * u, true)
			ci.draw_circle(c + Vector2(-40, -34) * u, 7 * u, col.call(Color(0.12, 0.25, 0.48)))
			ci.draw_circle(c + Vector2(-40, 38) * u, 7 * u, col.call(Color(0.12, 0.25, 0.48)))
		"craft":
			# martelo de pedra e faca de lasca cruzados
			ci.draw_line(c + Vector2(-34, 36) * u, c + Vector2(26, -24) * u, col.call(WOOD), 9 * u, true)
			ci.draw_line(c + Vector2(-34, 36) * u, c + Vector2(26, -24) * u, ink, 1.5 * u, true)
			var head: PackedVector2Array = P.call([[10, -44], [44, -12], [32, 0], [-2, -32]])
			_pp(ci, head, col.call(Color(0.5, 0.5, 0.47)))
			ci.draw_polyline(head + PackedVector2Array([head[0]]), ink, 2.5 * u, true)
			ci.draw_line(c + Vector2(34, 36) * u, c + Vector2(4, 6) * u, col.call(WOOD), 8 * u, true)
			var blade: PackedVector2Array = P.call([[6, 8], [-34, -40], [-24, -44], [12, 0]])
			_pp(ci, blade, col.call(Color(0.72, 0.72, 0.68)))
			ci.draw_polyline(blade + PackedVector2Array([blade[0]]), ink, 2.5 * u, true)
		"calendario":
			var page: PackedVector2Array = P.call([[-38, -30], [38, -30], [38, 42], [-38, 42]])
			_pp(ci, page, col.call(BONE))
			_pp(ci, P.call([[-38, -30], [38, -30], [38, -12], [-38, -12]]), col.call(RED))
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
			_pp(ci, pts, col.call(BONE))
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
			_pp(ci, arr, col.call(Color(0.98, 0.62, 0.25)))
			ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"cortar":
			# tronco em pé com o corte e o machado de pedra
			var tr: PackedVector2Array = P.call([[-38, -46], [-10, -46], [-6, 46], [-44, 46]])
			_pp(ci, tr, col.call(BARK))
			ci.draw_polyline(tr + PackedVector2Array([tr[0]]), ink, 2.5 * u, true)
			_pp(ci, P.call([[-8, -4], [-24, 8], [-6, 18]]), col.call(WOOD_LIGHT))
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
			_pp(ci, lg, col.call(BARK))
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
				_pp(ci, arr, col.call(Color(0.98, 0.62, 0.25) if up else Color(0.55, 0.8, 0.45)))
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
				_pp(ci, arr, col.call(Color(0.98, 0.62, 0.25)))
				ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"forquilha", "apoiar":
			# X de galhos amarrado; apoiar: tora deitada em cima
			ci.draw_line(c + Vector2(-34, 42) * u, c + Vector2(22, -24) * u, col.call(BARK), 8 * u, true)
			ci.draw_line(c + Vector2(34, 42) * u, c + Vector2(-22, -24) * u, col.call(BARK), 8 * u, true)
			ci.draw_circle(c + Vector2(0, 16) * u, 7 * u, col.call(Color(0.25, 0.3, 0.12)))
			if k == "apoiar":
				var lg: PackedVector2Array = P.call([[-46, -30], [36, -30], [36, -6], [-46, -6]])
				_pp(ci, lg, col.call(BARK.lightened(0.1)))
				ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 2 * u, true)
				ci.draw_circle(c + Vector2(36, -18) * u, 12 * u, col.call(WOOD_LIGHT))
		"modelar", "bater":
			# pedra no chão e a pedra de bater em cima, com risquinhos da batida
			if shadow:
				ci.draw_circle(c + Vector2(0, 22) * u, 26 * u, sh)
			else:
				Desenhos.item(ci, "pedra", c + Vector2(0, 22) * u, s * 0.62)
				Desenhos.item(ci, "pedra", c + Vector2(-8, -24) * u, s * 0.42)
				for k2 in 3:
					var a2 := -0.9 + k2 * 0.9
					var o := c + Vector2(14, -2) * u
					ci.draw_line(o + Vector2(cos(a2), sin(a2) * 0.6) * 10 * u, o + Vector2(cos(a2), sin(a2) * 0.6) * 22 * u, col.call(Color(1.0, 0.8, 0.3)), 3 * u, true)
		"sair":
			ci.draw_line(c + Vector2(-24, -24) * u, c + Vector2(24, 24) * u, col.call(BONE), 9 * u, true)
			ci.draw_line(c + Vector2(24, -24) * u, c + Vector2(-24, 24) * u, col.call(BONE), 9 * u, true)
		"serrar":
			# rodela com a serra em cima
			if shadow:
				ci.draw_circle(c + Vector2(-4, 16) * u, 30 * u, sh)
			else:
				Desenhos.item(ci, "rodela", c + Vector2(-4, 16) * u, s * 0.66)
				Desenhos.item(ci, "serra", c + Vector2(4, -18) * u, s * 0.8)
		"parar":
			var sq: PackedVector2Array = P.call([[-26, -26], [26, -26], [26, 26], [-26, 26]])
			_pp(ci, sq, col.call(RED))
			ci.draw_polyline(sq + PackedVector2Array([sq[0]]), ink, 2.5 * u, true)
		"colocar":
			# chão com a marca tracejada de onde vai ficar e a seta descendo
			ci.draw_line(c + Vector2(-46, 34) * u, c + Vector2(46, 34) * u, col.call(Color(0.3, 0.45, 0.16)), 5 * u, true)
			for j in 6:
				var x0 := -36.0 + j * 13.0
				ci.draw_line(c + Vector2(x0, 24) * u, c + Vector2(x0 + 7, 24) * u, col.call(BONE), 3 * u, true)
			var arr: PackedVector2Array = P.call([[-9, -44], [9, -44], [9, -8], [20, -8], [0, 16], [-20, -8], [-9, -8]])
			_pp(ci, arr, col.call(Color(0.55, 0.8, 0.45)))
			ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"girar":
			ci.draw_arc(c, 32 * u, -PI * 0.35, PI * 1.25, 28, col.call(BONE), 8 * u, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * 32 * u
			var arr: PackedVector2Array = PackedVector2Array([tip + Vector2(-14, -10) * u, tip + Vector2(12, -6) * u, tip + Vector2(2, 18) * u])
			_pp(ci, arr, col.call(BONE))
		"guardar":
			if shadow:
				ci.draw_circle(c, 34 * u, sh)
			else:
				Desenhos.backpack(ci, c + Vector2(0, 4) * u, s * 0.8, Color(0.42, 0.45, 0.27), Color(0, 0, 0, 0.2))
		"trabalhar":
			# tora deitada nas forquilhas com o machado em cima (bancada de trabalho)
			for sx in [-26.0, 24.0]:
				ci.draw_line(c + Vector2(sx - 12, 44) * u, c + Vector2(sx + 10, 4) * u, col.call(BARK), 6 * u, true)
				ci.draw_line(c + Vector2(sx + 12, 44) * u, c + Vector2(sx - 10, 4) * u, col.call(BARK), 6 * u, true)
			var lg: PackedVector2Array = P.call([[-46, -10], [40, -10], [40, 12], [-46, 12]])
			_pp(ci, lg, col.call(BARK.lightened(0.1)))
			ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 2 * u, true)
			ci.draw_circle(c + Vector2(40, 1) * u, 11 * u, col.call(WOOD_LIGHT))
			if shadow:
				ci.draw_line(c + Vector2(-14, -12) * u, c + Vector2(22, -48) * u, sh, 10 * u, true)
			else:
				Desenhos.item(ci, "machado", c + Vector2(4, -28) * u, s * 0.55)
		"cortar_rodela", "pegar_rodela":
			if shadow:
				ci.draw_circle(c + Vector2(0, 12) * u, 30 * u, sh)
			else:
				Desenhos.item(ci, "rodela", c + Vector2(-6, 14) * u, s * 0.72)
			if k == "cortar_rodela":
				if shadow:
					ci.draw_line(c + Vector2(6, -2) * u, c + Vector2(34, -46) * u, sh, 10 * u, true)
				else:
					Desenhos.item(ci, "machado", c + Vector2(18, -22) * u, s * 0.6)
			else:
				var arr: PackedVector2Array = P.call([[22, -14], [22, -28], [12, -28], [32, -48], [52, -28], [42, -28], [42, -14]])
				_pp(ci, arr, col.call(Color(0.98, 0.62, 0.25)))
				ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"rachar":
			# tora deitada com a rachadura em cima, a cunha cravada e a marreta descendo
			var log: PackedVector2Array = P.call([[-46, 6], [40, 6], [46, 20], [40, 34], [-46, 34], [-50, 20]])
			_pp(ci, log, col.call(Color(0.42, 0.29, 0.17)))
			if not shadow:
				ci.draw_circle(c + Vector2(42, 20) * u, 12 * u, Color(0.78, 0.62, 0.4))
				ci.draw_arc(c + Vector2(42, 20) * u, 7 * u, 0, TAU, 14, Color(0.55, 0.4, 0.25), 1.5 * u, true)
				ci.draw_polyline(P.call([[-40, 7], [-24, 9], [-12, 6], [2, 9], [16, 6], [30, 8]]), Color(0.1, 0.06, 0.03), 3 * u, true)
			ci.draw_polyline(log + PackedVector2Array([log[0]]), ink, 2 * u, true)
			var wd: PackedVector2Array = P.call([[-4, -14], [10, -14], [10, -4], [3, 10], [-4, -4]])
			_pp(ci, wd, col.call(Color(0.5, 0.5, 0.48)))
			ci.draw_polyline(wd + PackedVector2Array([wd[0]]), ink, 2 * u, true)
			if shadow:
				ci.draw_line(c + Vector2(22, -50) * u, c + Vector2(4, -26) * u, sh, 12 * u, true)
			else:
				Desenhos.item(ci, "marreta", c + Vector2(14, -36) * u, s * 0.55)
		"cavar":
			# chão com buraco e a cavadeira cravada
			_pp(ci, P.call([[-46, 22], [46, 22], [46, 46], [-46, 46]]), col.call(Color(0.42, 0.3, 0.18)))
			ci.draw_line(c + Vector2(-46, 22) * u, c + Vector2(46, 22) * u, col.call(Color(0.3, 0.45, 0.16)), 5 * u, true)
			_pp(ci, P.call([[-30, 22], [-2, 22], [-8, 36], [-24, 36]]), col.call(Color(0.08, 0.06, 0.04)))
			if shadow:
				ci.draw_line(c + Vector2(30, -46) * u, c + Vector2(0, 20) * u, sh, 10 * u, true)
			else:
				Desenhos.item(ci, "cavadeira", c + Vector2(10, -10) * u, s * 0.85)
		"fincar":
			# tora em pé enterrada no chão, com seta para baixo
			_pp(ci, P.call([[-46, 20], [46, 20], [46, 46], [-46, 46]]), col.call(Color(0.42, 0.3, 0.18)))
			ci.draw_line(c + Vector2(-46, 20) * u, c + Vector2(46, 20) * u, col.call(Color(0.3, 0.45, 0.16)), 5 * u, true)
			var lg: PackedVector2Array = P.call([[-16, -30], [10, -30], [10, 36], [-16, 36]])
			_pp(ci, lg, col.call(BARK))
			ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 2.5 * u, true)
			_pp(ci, P.call([[-16, -30], [10, -30], [6, -36], [-12, -36]]), col.call(WOOD_LIGHT))
			var arr: PackedVector2Array = P.call([[28, -40], [38, -40], [38, -20], [46, -20], [33, -4], [20, -20], [28, -20]])
			_pp(ci, arr, col.call(Color(0.55, 0.8, 0.45)))
			ci.draw_polyline(arr + PackedVector2Array([arr[0]]), ink, 2 * u, true)
		"cipo":
			# rolo de raiz de titica com uma folha
			for ring in 3:
				var rr := 30.0 - ring * 7.0
				ci.draw_arc(c + Vector2(0, 6) * u, rr * u, 0, TAU, 28, col.call(Color(0.5, 0.4, 0.26).darkened(ring * 0.12)), 6 * u, true)
			ci.draw_line(c + Vector2(28, 8) * u, c + Vector2(44, 38) * u, col.call(Color(0.5, 0.4, 0.26)), 6 * u, true)
			var lf: PackedVector2Array = P.call([[-10, -26], [-30, -46], [-6, -44], [4, -30]])
			_pp(ci, lf, col.call(Color(0.22, 0.45, 0.16)))
			ci.draw_polyline(lf + PackedVector2Array([lf[0]]), ink, 2 * u, true)
		"argila":
			var pts := PackedVector2Array()
			for i in 18:
				var a := TAU * i / 18.0
				var r := 34.0 * (0.85 + 0.15 * sin(i * 2.3))
				pts.append(c + Vector2(cos(a) * r * 1.2, sin(a) * r * 0.85 + 6) * u)
			_pp(ci, pts, col.call(Color(0.6, 0.32, 0.2)))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.5 * u, true)
			if not shadow:
				ci.draw_circle(c + Vector2(-12, -6) * u, 7 * u, Color(0.78, 0.5, 0.36))
		"semente":
			if not shadow:
				var wing: PackedVector2Array = P.call([[-4, -6], [-44, -18], [-48, -2], [-4, 6]])
				_pp(ci, wing, Color(0.66, 0.5, 0.32))
				ci.draw_polyline(wing + PackedVector2Array([wing[0]]), INK, 2 * u, true)
				var body: PackedVector2Array = P.call([[20, 0], [6, -12], [-8, 0], [6, 12]])
				_pp(ci, body, Color(0.42, 0.26, 0.14))
				ci.draw_polyline(body + PackedVector2Array([body[0]]), INK, 2 * u, true)
		_ when k.begins_with("it_"):
			if not shadow:
				Desenhos.item(ci, k.substr(3), c, s * 0.85)
		_:
			# a mão aberta (pegar): a palma, os dedos com as juntas e o polegar
			var pele: Color = col.call(Color(0.9, 0.72, 0.56))
			var palm: PackedVector2Array = P.call([[-22, -4], [20, -6], [24, 18], [16, 36], [-14, 38], [-22, 22]])
			for i in 4:
				var x := -16.0 + i * 11.0
				var topo := -36.0 + absf(i - 1.4) * 6.0
				var dedo: PackedVector2Array = P.call([[x - 5, 0], [x - 5, topo + 4], [x - 3, topo], [x + 3, topo], [x + 5, topo + 4], [x + 5, 0]])
				_pp(ci, dedo, pele)
				ci.draw_polyline(dedo, ink, 2 * u, true)
				if not shadow:
					ci.draw_line(c + Vector2(x - 3, topo + 12) * u, c + Vector2(x + 3, topo + 12) * u, Color(0.6, 0.4, 0.3, 0.6), 1.2 * u, true)
					ci.draw_arc(c + Vector2(x, topo + 4) * u, 2.6 * u, PI, TAU, 6, Color(1, 0.95, 0.9, 0.7), 1.2 * u, true)
			var pol: PackedVector2Array = P.call([[-20, 16], [-34, 6], [-44, -6], [-40, -10], [-28, -2], [-16, 4]])
			_pp(ci, pol, pele)
			ci.draw_polyline(pol, ink, 2 * u, true)
			_pp(ci, palm, pele)
			if not shadow:
				ci.draw_arc(c + Vector2(-2, 22) * u, 14 * u, PI * 1.1, PI * 1.7, 8, Color(0.6, 0.4, 0.3, 0.6), 1.5 * u, true)
			ci.draw_polyline(palm + PackedVector2Array([palm[0]]), ink, 2 * u, true)
