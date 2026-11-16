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


