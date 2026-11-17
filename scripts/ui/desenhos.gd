extends RefCounted
## Desenhos feitos em código (sem imagem), usados em mais de uma tela.

## Mochila desenhada (usada no botão do jogo e no espaço de equipamento).
## Sem fundo em volta: só a mochila.
static func backpack(ci: CanvasItem, c: Vector2, s: float, col: Color, shade: Color) -> void:
	var u := s / 100.0
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in arr:
			out.append(c + Vector2(p[0], p[1]) * u)
		return out
	var outline := Color(0.08, 0.07, 0.05, col.a)
	# alça de cima
	ci.draw_arc(c + Vector2(0, -38) * u, 11 * u, PI, TAU, 16, col.darkened(0.25), 5 * u, true)
	# corpo
	var body: PackedVector2Array = P.call([[-30, -34], [30, -34], [38, -24], [40, 36], [34, 46], [-34, 46], [-40, 36], [-38, -24]])
	ci.draw_colored_polygon(body, col)
	# tampa
	var flap: PackedVector2Array = P.call([[-31, -34], [31, -34], [37, -22], [34, -4], [-34, -4], [-37, -22]])
	ci.draw_colored_polygon(flap, col.darkened(0.22))
	# bolso da frente
	var pocket: PackedVector2Array = P.call([[-22, 10], [22, 10], [24, 40], [-24, 40]])
	ci.draw_colored_polygon(pocket, col.darkened(0.12))
	ci.draw_colored_polygon(P.call([[-24, 10], [24, 10], [22, 20], [-22, 20]]), col.darkened(0.3))
	# fivelas
	for x in [-14, 14]:
		ci.draw_rect(Rect2(c + Vector2(x - 3, -8) * u, Vector2(6, 16) * u), Color(0.35, 0.25, 0.14, col.a))
		ci.draw_rect(Rect2(c + Vector2(x - 4, 4) * u, Vector2(8, 5) * u), Color(0.75, 0.7, 0.55, col.a))
	# sombra lateral e contornos
	if shade.a > 0.0:
		ci.draw_colored_polygon(P.call([[26, -24], [38, -24], [40, 36], [34, 46], [24, 46]]), shade)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), outline, 2.5 * u, true)
	ci.draw_polyline(flap + PackedVector2Array([flap[0]]), outline, 2.0 * u, true)
	ci.draw_polyline(pocket + PackedVector2Array([pocket[0]]), outline, 2.0 * u, true)




## Desenho de um item (ícone da mochila e do craft). Devolve false se não sabe desenhar.
static func item(ci: CanvasItem, id: String, c: Vector2, s: float) -> bool:
	var u := s / 100.0
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in arr:
			out.append(c + Vector2(p[0], p[1]) * u)
		return out
	var ink := Color(0.12, 0.08, 0.05)
	match id:
		"machado":
			# cabo de madeira na diagonal e cabeça de pedra lascada amarrada com cipó
			var handle: PackedVector2Array = P.call([[-34, 42], [-28, 46], [22, -30], [16, -34]])
			ci.draw_colored_polygon(handle, Color(0.55, 0.36, 0.2))
			ci.draw_polyline(handle + PackedVector2Array([handle[0]]), ink, 2.0 * u, true)
			ci.draw_line(c + Vector2(-26, 36) * u, c + Vector2(16, -26) * u, Color(0.7, 0.5, 0.3), 2.0 * u, true)
			var head: PackedVector2Array = P.call([[4, -40], [20, -46], [40, -38], [46, -18], [36, -8], [24, -16], [10, -22]])
			ci.draw_colored_polygon(head, Color(0.5, 0.5, 0.48))
			ci.draw_colored_polygon(P.call([[36, -8], [46, -18], [40, -38], [44, -36], [50, -18], [40, -5]]), Color(0.72, 0.72, 0.68))
			ci.draw_polyline(head + PackedVector2Array([head[0]]), ink, 2.0 * u, true)
			for k in 3:
				var y := -30 + k * 6
				ci.draw_line(c + Vector2(6 + k * 2, y) * u, c + Vector2(22 + k * 2, y - 10) * u, Color(0.45, 0.4, 0.18), 3.0 * u, true)
		"cavadeira":
			# cabo comprido na diagonal e lâmina larga de pedra (como pá) amarrada com cipó
			ci.draw_line(c + Vector2(42, -44) * u, c + Vector2(-14, 18) * u, Color(0.4, 0.26, 0.14), 7.0 * u, true)
			ci.draw_line(c + Vector2(42, -44) * u, c + Vector2(-14, 18) * u, ink, 1.2 * u, true)
			var blade: PackedVector2Array = P.call([[-10, 10], [-22, 22], [-46, 30], [-40, 44], [-30, 46], [-12, 36], [2, 18]])
			ci.draw_colored_polygon(blade, Color(0.58, 0.52, 0.42))
			ci.draw_colored_polygon(P.call([[-46, 30], [-40, 44], [-34, 45], [-42, 30]]), Color(0.74, 0.7, 0.6))
			ci.draw_polyline(blade + PackedVector2Array([blade[0]]), ink, 2.0 * u, true)
			for k in 3:
				var t := 0.1 + k * 0.08
				var pa := c + Vector2(-14, 18).lerp(Vector2(42, -44), t) * u
				ci.draw_line(pa + Vector2(-6, -6) * u, pa + Vector2(6, 6) * u, Color(0.45, 0.4, 0.18), 3.0 * u, true)
		"forquilha":
			# dois galhos cruzados em X, amarrados com cipó no meio
			for sg in [1.0, -1.0]:
				ci.draw_line(c + Vector2(-34 * sg, 40) * u, c + Vector2(26 * sg, -40) * u, Color(0.4, 0.28, 0.16), 8.0 * u, true)
				ci.draw_line(c + Vector2(-34 * sg, 40) * u, c + Vector2(26 * sg, -40) * u, ink, 1.0 * u, true)
				ci.draw_circle(c + Vector2(26 * sg, -40) * u, 4.0 * u, Color(0.65, 0.52, 0.34))
			for k in 3:
				ci.draw_line(c + Vector2(-9, 8 + k * 5) * u, c + Vector2(9, 2 + k * 5) * u, Color(0.3, 0.36, 0.14), 3.5 * u, true)
		"pedra":
			var pts: PackedVector2Array = P.call([[-36, 10], [-28, -16], [-6, -30], [22, -26], [38, -6], [32, 20], [8, 30], [-22, 28]])
			ci.draw_colored_polygon(pts, Color(0.52, 0.52, 0.5))
			ci.draw_colored_polygon(P.call([[-20, -10], [-4, -22], [16, -18], [4, -4]]), Color(0.66, 0.66, 0.63))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
		"galho":
			ci.draw_line(c + Vector2(-42, 30) * u, c + Vector2(40, -26) * u, Color(0.45, 0.3, 0.17), 9.0 * u, true)
			ci.draw_line(c + Vector2(4, 4) * u, c + Vector2(12, 24) * u, Color(0.45, 0.3, 0.17), 5.0 * u, true)
			ci.draw_line(c + Vector2(-20, 15) * u, c + Vector2(-26, -4) * u, Color(0.45, 0.3, 0.17), 4.0 * u, true)
		"cipo":
			var pts := PackedVector2Array()
			for k in 40:
				var t := k / 39.0
				pts.append(c + Vector2(lerpf(-40, 40, t), sin(t * TAU * 2.0) * 16.0 + (t - 0.5) * 20.0) * u)
			ci.draw_polyline(pts, Color(0.36, 0.42, 0.17), 6.0 * u, true)
			ci.draw_polyline(pts, Color(0.5, 0.56, 0.25), 2.0 * u, true)
		"cipo_trancado":
			# trança de 3 raízes de titica (zigue-zague cruzado) com as pontas amarradas
			for k in 2:
				var pts := PackedVector2Array()
				for i in 41:
					var t := i / 40.0
					var x := lerpf(-42, 42, t)
					var y := sin(t * TAU * 3.0 + k * PI) * 9.0 + (t - 0.5) * -40.0
					pts.append(c + Vector2(x, y) * u)
				ci.draw_polyline(pts, Color(0.42, 0.33, 0.18).darkened(k * 0.18), 8.0 * u, true)
				ci.draw_polyline(pts, Color(0.66, 0.54, 0.32).darkened(k * 0.18), 3.0 * u, true)
			for e in [Vector2(-42, 20), Vector2(42, -20)]:
				ci.draw_circle(c + e * u, 7.0 * u, Color(0.3, 0.36, 0.14))
		"rodela":
			# fatia redonda de tora: casca em volta, madeira clara e os anéis
			ci.draw_circle(c + Vector2(4, 6) * u, 40.0 * u, Color(0.3, 0.22, 0.14))
			ci.draw_circle(c, 40.0 * u, Color(0.38, 0.27, 0.16))
			ci.draw_circle(c, 33.0 * u, Color(0.78, 0.63, 0.42))
			for r in [26.0, 19.0, 12.0, 6.0]:
				ci.draw_arc(c + Vector2(1, 1) * u, r * u, 0, TAU, 32, Color(0.62, 0.46, 0.28), 1.8 * u, true)
			ci.draw_line(c + Vector2(2, 0) * u, c + Vector2(28, 14) * u, Color(0.45, 0.32, 0.2), 1.6 * u, true)
			ci.draw_arc(c, 40.0 * u, 0, TAU, 40, ink, 2.0 * u, true)
		"ripa":
			# tábua fina e comprida, com veios
			var rp: PackedVector2Array = P.call([[-44, 22], [-36, 34], [44, -22], [36, -34]])
			ci.draw_colored_polygon(rp, Color(0.7, 0.54, 0.34))
			ci.draw_colored_polygon(P.call([[-44, 22], [-36, 34], [-32, 32], [-40, 20]]), Color(0.86, 0.72, 0.5))
			for k in 3:
				var o := -5.0 + k * 5.0
				ci.draw_line(c + Vector2(-36 + o, 26 + o * 0.2) * u, c + Vector2(36 + o, -26 + o * 0.2) * u, Color(0.55, 0.4, 0.24), 1.2 * u, true)
			ci.draw_polyline(rp + PackedVector2Array([rp[0]]), ink, 2.0 * u, true)
		"balde":
			balde(ci, c, s)
		"serra", "lamina_serra":
			# lâmina de pedra com dentes (e, na serra, o cabo comprido com os dois pegadores)
			var blade: PackedVector2Array = P.call([[-30, -4], [30, -6], [34, 0], [30, 6], [-30, 8], [-35, 2]])
			if id == "lamina_serra":
				blade = P.call([[-42, -10], [42, -12], [46, 0], [42, 12], [-42, 14], [-47, 2]])
			var stone := Color(0.62, 0.48, 0.26)
			ci.draw_colored_polygon(blade, stone)
			var y0 := 8.0 if id == "serra" else 14.0
			var x0 := -30.0 if id == "serra" else -42.0
			var x1 := 30.0 if id == "serra" else 42.0
			var k := 0
			var x := x0
			while x < x1:
				ci.draw_colored_polygon(P.call([[x, y0 - 1], [x + 5, y0 - 1], [x + 2.5, y0 + 6]]), stone.darkened(0.1))
				x += 5.0
				k += 1
			ci.draw_polyline(blade + PackedVector2Array([blade[0]]), ink, 1.6 * u, true)
			for f in 4:
				ci.draw_line(c + Vector2(x0 + 8 + f * (x1 - x0 - 16) / 3.0, -4) * u, c + Vector2(x0 + 14 + f * (x1 - x0 - 16) / 3.0, 4) * u, stone.lightened(0.15), 1.5 * u, true)
			if id == "serra":
				ci.draw_line(c + Vector2(-46, -12) * u, c + Vector2(46, -12) * u, Color(0.4, 0.27, 0.15), 7 * u, true)
				for e in [-42.0, 42.0]:
					ci.draw_line(c + Vector2(e, -12) * u, c + Vector2(e, -38) * u, Color(0.36, 0.24, 0.13), 7 * u, true)
				for e in [-18.0, 0.0, 18.0]:
					ci.draw_line(c + Vector2(e - 3, -16) * u, c + Vector2(e + 3, 4) * u, Color(0.3, 0.36, 0.14), 3 * u, true)
		"pedra_machado":
			var head: PackedVector2Array = P.call([[-34, -10], [-10, -30], [24, -26], [42, -4], [30, 22], [-6, 28], [-30, 14]])
			ci.draw_colored_polygon(head, Color(0.5, 0.5, 0.47))
			ci.draw_colored_polygon(P.call([[30, 22], [42, -4], [46, 0], [34, 24]]), Color(0.72, 0.72, 0.68))
			for f in 5:
				var a := TAU * f / 5.0
				ci.draw_arc(c + Vector2(cos(a) * 14, sin(a) * 10) * u, 9 * u, a, a + 2.2, 6, Color(0.4, 0.4, 0.38), 1.5 * u, true)
			ci.draw_polyline(head + PackedVector2Array([head[0]]), ink, 2.0 * u, true)
		"pedra_cavadeira":
			var bl: PackedVector2Array = P.call([[-14, -40], [14, -40], [26, 10], [16, 40], [-16, 40], [-26, 10]])
			ci.draw_colored_polygon(bl, Color(0.58, 0.52, 0.42))
			ci.draw_colored_polygon(P.call([[-16, 40], [16, 40], [14, 34], [-14, 34]]), Color(0.74, 0.7, 0.6))
			for f in 4:
				ci.draw_arc(c + Vector2(-8 + (f % 2) * 16, -18 + f * 12) * u, 8 * u, 0.3, 2.6, 6, Color(0.46, 0.42, 0.34), 1.5 * u, true)
			ci.draw_polyline(bl + PackedVector2Array([bl[0]]), ink, 2.0 * u, true)
		_:
			return false
	return true


## Balde de ripas com aros de cipó e alça de cipó trançado.
static func balde(ci: CanvasItem, c: Vector2, s: float) -> void:
	var u := s / 100.0
	var ink := Color(0.12, 0.08, 0.05)
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in arr:
			out.append(c + Vector2(p[0], p[1]) * u)
		return out
	# alça (cipó trançado) por trás
	var arc := PackedVector2Array()
	for i in 25:
		var a := PI + PI * i / 24.0
		arc.append(c + Vector2(cos(a) * 30.0, -18.0 + sin(a) * 34.0) * u)
	ci.draw_polyline(arc, Color(0.36, 0.28, 0.15), 6.0 * u, true)
	for i in range(0, 24, 2):
		ci.draw_line(arc[i], arc[i + 1], Color(0.62, 0.5, 0.3), 2.5 * u, true)
	# corpo de ripas (um pouco mais largo em cima)
	var body: PackedVector2Array = P.call([[-34, -18], [34, -18], [29, 42], [-29, 42]])
	ci.draw_colored_polygon(body, Color(0.46, 0.36, 0.25))
	for k in 7:
		var t := (k + 1) / 8.0
		ci.draw_line(c + Vector2(lerpf(-34, 34, t), -18) * u, c + Vector2(lerpf(-29, 29, t), 42) * u, Color(0.3, 0.23, 0.15), 1.5 * u, true)
	# boca (elipse escura) e as duas ripas altas com o furo da alça
	ci.draw_colored_polygon(P.call([[-34, -18], [-20, -24], [20, -24], [34, -18], [20, -13], [-20, -13]]), Color(0.2, 0.15, 0.1))
	for sx in [-1.0, 1.0]:
		var ear: PackedVector2Array = P.call([[30 * sx, -32], [38 * sx, -32], [38 * sx, -10], [30 * sx, -10]])
		ci.draw_colored_polygon(ear, Color(0.44, 0.34, 0.23))
		ci.draw_polyline(ear + PackedVector2Array([ear[0]]), ink, 1.5 * u, true)
		ci.draw_circle(c + Vector2(34 * sx, -25) * u, 2.2 * u, Color(0.1, 0.07, 0.05))
	# aros de cipó: dois em cima, dois no meio, dois embaixo
	for y in [-12.0, -6.0, 12.0, 18.0, 32.0, 37.0]:
		var hw := lerpf(34.0, 29.0, (y + 18.0) / 60.0)
		ci.draw_line(c + Vector2(-hw - 1, y) * u, c + Vector2(hw + 1, y + 1.5) * u, Color(0.78, 0.62, 0.4), 3.6 * u, true)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, 2.0 * u, true)
