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
		_:
			return false
	return true
