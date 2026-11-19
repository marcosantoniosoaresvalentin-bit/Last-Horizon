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
			# seixo arredondado: sombra embaixo, claro em cima, umas pintas
			var pts := PackedVector2Array()
			for k in 24:
				var a2 := TAU * k / 24.0
				var rr := 1.0 + 0.06 * sin(a2 * 3.0 + 1.0)
				pts.append(c + Vector2(cos(a2) * 38.0 * rr, sin(a2) * 28.0 * rr + 4.0) * u)
			ci.draw_colored_polygon(pts, Color(0.36, 0.35, 0.33))
			for k2 in 4:
				var f2 := 1.0 - k2 * 0.2
				var inner := PackedVector2Array()
				for q in pts:
					inner.append(c + Vector2(-6, -6 - k2 * 2) * u + (q - c - Vector2(0, 4) * u) * f2)
				ci.draw_colored_polygon(inner, Color(0.42, 0.41, 0.38).lightened(k2 * 0.07))
			ci.draw_circle(c + Vector2(-14, -10) * u, 5 * u, Color(0.68, 0.67, 0.63))
			for sp in [Vector2(12, 8), Vector2(-4, 14), Vector2(20, -6)]:
				ci.draw_circle(c + sp * u, 1.6 * u, Color(0.3, 0.29, 0.27))
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
			var y0 := 8.0 if id == "serra" else 14.0
			var x0 := -30.0 if id == "serra" else -42.0
			var x1 := 30.0 if id == "serra" else 42.0
			# a lâmina de pedra com os dentes embaixo (um polígono só, lascado)
			var outline := [[x0, -6.0 if id == "serra" else -12.0], [x1, -8.0 if id == "serra" else -14.0], [x1 + 4.0, 0.0]]
			var x := x1
			while x > x0:
				outline.append([x, y0])
				outline.append([x - 2.5, y0 + 6.0])
				x -= 5.0
			outline.append([x0 - 5.0, 2.0])
			flint(ci, P.call(outline), Color(0.44, 0.4, 0.33), 13, u, [3, 4])
			if id == "serra":
				ci.draw_line(c + Vector2(-46, -12) * u, c + Vector2(46, -12) * u, Color(0.4, 0.27, 0.15), 7 * u, true)
				for e in [-42.0, 42.0]:
					ci.draw_line(c + Vector2(e, -12) * u, c + Vector2(e, -38) * u, Color(0.36, 0.24, 0.13), 7 * u, true)
				for e in [-18.0, 0.0, 18.0]:
					ci.draw_line(c + Vector2(e - 3, -16) * u, c + Vector2(e + 3, 4) * u, Color(0.3, 0.36, 0.14), 3 * u, true)
		"pedra_machado":
			# cabeça de machado de pedra lascada: nuca estreita (esq.), fio largo e curvo (dir.)
			flint(ci, P.call([[-40, -6], [-30, -16], [-10, -24], [14, -30], [34, -30], [44, -14], [46, 4], [40, 22], [30, 30], [8, 24], [-12, 16], [-32, 10], [-42, 4]]),
				Color(0.2, 0.21, 0.19), 3, u, [9, 10])
		"pa":
			# cabo comprido com pegador em T e a lâmina larga de pedra
			ci.draw_line(c + Vector2(40, -44) * u, c + Vector2(-8, 10) * u, Color(0.4, 0.26, 0.14), 7.0 * u, true)
			ci.draw_line(c + Vector2(32, -50) * u, c + Vector2(48, -38) * u, Color(0.36, 0.23, 0.12), 7.0 * u, true)
			flint(ci, P.call([[-2, 4], [8, 14], [-6, 36], [-28, 48], [-46, 40], [-44, 22], [-26, 6]]), Color(0.47, 0.43, 0.35), 21, u, [2, 3, 4])
			for k in 3:
				var pa := c + Vector2(-8, 10).lerp(Vector2(40, -44), 0.05 + k * 0.07) * u
				ci.draw_line(pa + Vector2(-6, -6) * u, pa + Vector2(6, 6) * u, Color(0.45, 0.4, 0.18), 3.0 * u, true)
		"pedra_pa":
			flint(ci, P.call([[-16, -40], [16, -40], [30, -14], [38, 14], [30, 36], [0, 44], [-30, 36], [-38, 14], [-30, -14]]),
				Color(0.47, 0.43, 0.35), 9, u, [4, 5, 6])
		"pedra_cavadeira":
			# lâmina de cavadeira: estreita em cima (onde encaixa no cabo), larga e chata embaixo
			flint(ci, P.call([[-12, -42], [12, -42], [16, -24], [26, -2], [34, 20], [30, 36], [12, 42], [-12, 42], [-30, 36], [-34, 20], [-26, -2], [-16, -24]]),
				Color(0.47, 0.43, 0.35), 5, u, [6, 7])
		"cunha":
			# cunha vista de lado: grossa atrás, fio fino na frente
			flint(ci, P.call([[-40, -22], [-14, -26], [20, -14], [44, -2], [44, 4], [20, 16], [-14, 26], [-40, 22], [-44, 0]]),
				Color(0.22, 0.22, 0.21), 41, u, [3, 4, 5])
		"pedra_marreta":
			flint(ci, P.call([[-44, -14], [-30, -26], [30, -26], [44, -14], [44, 14], [30, 26], [-30, 26], [-44, 14]]),
				Color(0.26, 0.25, 0.23), 43, u, [])
		"marreta":
			# cabo na diagonal e a cabeça de pedra atravessada em cima, amarrada com cipó
			ci.draw_line(c + Vector2(-34, 44) * u, c + Vector2(18, -20) * u, Color(0.45, 0.3, 0.17), 8.0 * u, true)
			ci.draw_line(c + Vector2(-34, 44) * u, c + Vector2(18, -20) * u, ink, 1.2 * u, true)
			var hd: PackedVector2Array = P.call([[-2, -40], [10, -50], [44, -22], [36, -8], [26, -4]])
			flint(ci, P.call([[-6, -36], [8, -50], [48, -20], [36, -4], [22, 4]]), Color(0.26, 0.25, 0.23), 45, u, [])
			for k in 3:
				var y := -18 + k * 5
				ci.draw_line(c + Vector2(8 + k * 3, y) * u, c + Vector2(22 + k * 3, y - 12) * u, Color(0.45, 0.4, 0.18), 3.0 * u, true)
			var _h := hd
		"raiz_timbo":
			for k in 4:
				var a := -0.6 + k * 0.4
				ci.draw_line(c + Vector2(-30, -10 + k * 7) * u, c + Vector2(cos(a) * 44, sin(a) * 30 + 10) * u, Color(0.42, 0.3, 0.18), 6.0 * u, true)
			ci.draw_circle(c + Vector2(-30, -2) * u, 12 * u, Color(0.36, 0.26, 0.15))
		"veneno_timbo":
			var cup: PackedVector2Array = P.call([[-32, -10], [32, -10], [24, 34], [-24, 34]])
			ci.draw_colored_polygon(cup, Color(0.5, 0.36, 0.22))
			ci.draw_colored_polygon(P.call([[-30, -10], [30, -10], [28, 0], [-28, 0]]), Color(0.75, 0.82, 0.55))
			ci.draw_polyline(cup + PackedVector2Array([cup[0]]), ink, 2.0 * u, true)
			ci.draw_colored_polygon(P.call([[-4, -40], [10, -30], [2, -16], [-10, -26]]), Color(0.2, 0.4, 0.15))
		"semente_andiroba":
			for k in 3:
				var o := Vector2(-22 + k * 22, 8 - (k % 2) * 16)
				ci.draw_colored_polygon(P.call([[o.x - 16, o.y - 12], [o.x + 14, o.y - 14], [o.x + 16, o.y + 12], [o.x - 14, o.y + 14]]), Color(0.45, 0.29, 0.16))
				ci.draw_line(c + Vector2(o.x - 12, o.y) * u, c + Vector2(o.x + 12, o.y - 2) * u, Color(0.3, 0.19, 0.1), 2.0 * u, true)
		"oleo_andiroba":
			var gar: PackedVector2Array = P.call([[-14, -40], [14, -40], [14, -26], [30, -8], [30, 38], [-30, 38], [-30, -8], [-14, -26]])
			ci.draw_colored_polygon(gar, Color(0.55, 0.42, 0.26))
			ci.draw_colored_polygon(P.call([[-28, 2], [28, 2], [28, 36], [-28, 36]]), Color(0.86, 0.68, 0.22))
			ci.draw_polyline(gar + PackedVector2Array([gar[0]]), ink, 2.0 * u, true)
			ci.draw_colored_polygon(P.call([[-10, -48], [10, -48], [10, -40], [-10, -40]]), Color(0.4, 0.28, 0.16))
		"lamina_faca", "faca":
			if id == "faca":
				ci.draw_line(c + Vector2(-46, 26) * u, c + Vector2(-8, 4) * u, Color(0.55, 0.36, 0.2), 12 * u, true)
				for k in 3:
					ci.draw_line(c + Vector2(-16 + k * 4, -2 + k * 2) * u, c + Vector2(-8 + k * 4, 12 + k * 2) * u, Color(0.7, 0.58, 0.32), 3 * u, true)
			var bl: PackedVector2Array = P.call([[-10, 6], [-4, -6], [44, -34], [12, 10]]) if id == "faca" else P.call([[-40, 18], [-36, 6], [42, -26], [8, 22]])
			ci.draw_colored_polygon(bl, Color(0.46, 0.46, 0.44))
			ci.draw_polyline(bl + PackedVector2Array([bl[0]]), ink, 2.0 * u, true)
		"folha_buriti":
			ci.draw_line(c + Vector2(-44, 40) * u, c + Vector2(-4, 0) * u, Color(0.3, 0.45, 0.18), 6 * u, true)
			for k in 11:
				var a := lerpf(-2.2, 0.6, k / 10.0)
				ci.draw_line(c + Vector2(-4, 0) * u, c + (Vector2(-4, 0) + Vector2(cos(a), sin(a)) * 48) * u, Color(0.22, 0.42, 0.14), 5 * u, true)
		"ponta_pedra", "furador":
			if id == "furador":
				ci.draw_line(c + Vector2(-44, 30) * u, c + Vector2(4, -4) * u, Color(0.55, 0.36, 0.2), 13 * u, true)
				for k in 4:
					ci.draw_line(c + Vector2(-6 + k * 4, -8 + k * 3) * u, c + Vector2(4 + k * 4, 6 + k * 3) * u, Color(0.7, 0.58, 0.32), 3 * u, true)
			var tip: PackedVector2Array = P.call([[-2, -2], [10, -18], [46, -40], [22, 6], [8, 10]]) if id == "furador" else P.call([[-34, 20], [-30, -6], [40, -34], [10, 22]])
			ci.draw_colored_polygon(tip, Color(0.42, 0.42, 0.4))
			ci.draw_polyline(tip + PackedVector2Array([tip[0]]), ink, 2.0 * u, true)
		"pino":
			for k in 2:
				var o := Vector2(-14 + k * 26, 0)
				var body: PackedVector2Array = P.call([[o.x - 7, -40], [o.x + 7, -40], [o.x + 7, 26], [o.x, 44], [o.x - 7, 26]])
				ci.draw_colored_polygon(body, Color(0.66, 0.5, 0.32))
				ci.draw_line(c + Vector2(o.x - 2, -36) * u, c + Vector2(o.x - 2, 24) * u, Color(0.5, 0.36, 0.2), 2.0 * u, true)
				ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, 2.0 * u, true)
				ci.draw_colored_polygon(P.call([[o.x - 7, -40], [o.x + 7, -40], [o.x + 7, -34], [o.x - 7, -34]]), Color(0.78, 0.62, 0.42))
		"tabua", "ripa":
			var w := 26.0 if id == "tabua" else 9.0
			var pts := PackedVector2Array([c + Vector2(-44, -w) * u, c + Vector2(44, -w - 8) * u, c + Vector2(44, w - 8) * u, c + Vector2(-44, w) * u])
			ci.draw_colored_polygon(pts, Color(0.6, 0.44, 0.28))
			for k in 3:
				var y := -w + (k + 1) * w * 0.5
				ci.draw_line(c + Vector2(-40, y) * u, c + Vector2(40, y - 8) * u, Color(0.45, 0.31, 0.18), 1.5 * u, true)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
		"banda":
			var pts := PackedVector2Array()
			for k in 13:
				var a := PI * k / 12.0
				pts.append(c + Vector2(cos(a) * 44.0, -sin(a) * 34.0 + 14.0) * u)
			ci.draw_colored_polygon(pts, Color(0.36, 0.26, 0.17))
			var inner := PackedVector2Array()
			for q in pts:
				inner.append(c + (q - c - Vector2(0, 14) * u) * 0.82 + Vector2(0, 14) * u)
			ci.draw_colored_polygon(inner, Color(0.78, 0.62, 0.42))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
		"hematita", "magnetita", "goetita", "silex", "malaquita", "calcopirita":
			_mineral(ci, id, c, u)
		"lasca_silex":
			var sh: PackedVector2Array = P.call([[-36, 18], [-10, -30], [8, -38], [34, -6], [10, 30], [-20, 34]])
			ci.draw_colored_polygon(sh, Color(0.36, 0.37, 0.4))
			ci.draw_colored_polygon(P.call([[-10, -30], [8, -38], [34, -6], [14, -2]]), Color(0.55, 0.56, 0.6))
			ci.draw_polyline(sh + PackedVector2Array([sh[0]]), ink, 2.0 * u, true)
		_:
			return false
	return true


## Pedaço de minério: forma de pedra irregular, com a cor e o jeito de cada um.
static func _mineral(ci: CanvasItem, id: String, c: Vector2, u: float) -> void:
	var base: Color = {"hematita": Color(0.5, 0.17, 0.12), "magnetita": Color(0.14, 0.14, 0.16), "goetita": Color(0.64, 0.44, 0.18),
		"silex": Color(0.3, 0.31, 0.34), "malaquita": Color(0.14, 0.55, 0.32), "calcopirita": Color(0.66, 0.58, 0.26)}[id]
	var pts := PackedVector2Array()
	var sd := hash(id)
	for k in 9:
		var a := TAU * k / 9.0
		var rr := 34.0 + float((sd >> (k * 3)) & 7) * 1.8
		pts.append(c + Vector2(cos(a) * rr * 1.15, sin(a) * rr * 0.85 + 4.0) * u)
	ci.draw_colored_polygon(pts, base)
	# luz em cima
	var hi := PackedVector2Array()
	for q in pts:
		hi.append(c + (q - c) * 0.55 + Vector2(-6, -10) * u)
	ci.draw_colored_polygon(hi, base.lightened(0.18))
	match id:
		"silex":
			ci.draw_arc(c + Vector2(4, 6) * u, 30.0 * u, 0.0, TAU, 24, Color(0.82, 0.8, 0.72), 5.0 * u, true)   # córtex branco
		"malaquita":
			for k in 4:
				ci.draw_arc(c + Vector2(10, 14) * u, (8.0 + k * 7.0) * u, 3.4, 5.6, 10, Color(0.06, 0.3, 0.17), 2.0 * u, true)
		"calcopirita":
			ci.draw_circle(c + Vector2(-8, -6) * u, 5.0 * u, Color(0.95, 0.85, 0.45))
			ci.draw_circle(c + Vector2(10, 4) * u, 3.0 * u, Color(0.6, 0.35, 0.55))     # brilho furta-cor
		"magnetita":
			ci.draw_circle(c + Vector2(-6, -8) * u, 4.0 * u, Color(0.5, 0.5, 0.55))
		"hematita":
			ci.draw_line(c + Vector2(-20, 24) * u, c + Vector2(18, 26) * u, Color(0.7, 0.2, 0.15), 4.0 * u, true)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.08, 0.06, 0.05), 2.0 * u, true)


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


## Pedra lascada: o contorno pintado com facetas (cada lasca um tom), luz em cima,
## a beirada clara (o fio) e contorno escuro.
static func flint(ci: CanvasItem, pts: PackedVector2Array, base: Color, seed_: int, u: float, edge: Array) -> void:
	var ink := Color(0.08, 0.07, 0.06)
	ci.draw_colored_polygon(pts, base.darkened(0.25))
	var cen := Vector2.ZERO
	for q in pts:
		cen += q
	cen /= pts.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var n := pts.size()
	# anel de lascas na beirada (o fio) e lascas maiores para dentro
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var ia := cen + (a - cen) * rng.randf_range(0.45, 0.62)
		var ib := cen + (b - cen) * rng.randf_range(0.45, 0.62)
		var lit := clampf(0.5 - ((a + b) * 0.5 - cen).normalized().dot(Vector2(0.6, 0.8)) * 0.5, 0.0, 1.0)
		var col := base.lerp(base.lightened(0.45), lit * rng.randf_range(0.6, 1.0)).darkened(rng.randf_range(0.0, 0.15))
		ci.draw_colored_polygon(PackedVector2Array([a, b, ib, ia]), col)
		ci.draw_polyline(PackedVector2Array([ia, ib]), base.darkened(0.45), 1.0 * u, true)
		ci.draw_colored_polygon(PackedVector2Array([ia, ib, cen]), base.lerp(base.lightened(0.3), rng.randf() * 0.6))
	# fio: beirada clara (afiada)
	for ei in edge:
		var e0: Vector2 = pts[int(ei) % n]
		var e1: Vector2 = pts[(int(ei) + 1) % n]
		ci.draw_line(e0, e1, base.lightened(0.6), 3.0 * u, true)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
