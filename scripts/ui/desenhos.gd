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
	_poly(ci, body, col)
	# tampa
	var flap: PackedVector2Array = P.call([[-31, -34], [31, -34], [37, -22], [34, -4], [-34, -4], [-37, -22]])
	_poly(ci, flap, col.darkened(0.22))
	# bolso da frente
	var pocket: PackedVector2Array = P.call([[-22, 10], [22, 10], [24, 40], [-24, 40]])
	_poly(ci, pocket, col.darkened(0.12))
	_poly(ci, P.call([[-24, 10], [24, 10], [22, 20], [-22, 20]]), col.darkened(0.3))
	# fivelas
	for x in [-14, 14]:
		ci.draw_rect(Rect2(c + Vector2(x - 3, -8) * u, Vector2(6, 16) * u), Color(0.35, 0.25, 0.14, col.a))
		ci.draw_rect(Rect2(c + Vector2(x - 4, 4) * u, Vector2(8, 5) * u), Color(0.75, 0.7, 0.55, col.a))
	# sombra lateral e contornos
	if shade.a > 0.0:
		_poly(ci, P.call([[26, -24], [38, -24], [40, 36], [34, 46], [24, 46]]), shade)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), outline, 2.5 * u, true)
	ci.draw_polyline(flap + PackedVector2Array([flap[0]]), outline, 2.0 * u, true)
	ci.draw_polyline(pocket + PackedVector2Array([pocket[0]]), outline, 2.0 * u, true)




## Uma forma pintada com luz: mais clara do lado de cima à esquerda (de onde vem a luz)
## e mais escura embaixo à direita, como uma coisa de verdade (e não chapada).
static func _poly(ci: CanvasItem, pts: PackedVector2Array, cor: Color) -> void:
	if pts.size() < 3:
		return
	var mn := pts[0]
	var mx := pts[0]
	for q in pts:
		mn = mn.min(q)
		mx = mx.max(q)
	var cen := (mn + mx) * 0.5
	var r := maxf((mx - mn).length() * 0.5, 0.001)
	var luz := Vector2(-0.55, -0.83)
	var cols := PackedColorArray()
	for q in pts:
		var t := clampf((q - cen).dot(luz) / r, -1.0, 1.0)
		var c2 := cor.lightened(0.17 * t) if t > 0.0 else cor.darkened(-0.24 * t)
		c2.a = cor.a
		cols.append(c2)
	ci.draw_polygon(pts, cols)


## A sombrinha no chão embaixo do item.
static func _sombra(ci: CanvasItem, c: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * s * 0.36, s * 0.4 + sin(a) * s * 0.07))
		cols.append(Color(0, 0, 0, 0.16))
	ci.draw_polygon(pts, cols)


## Desenho de um item (ícone da mochila e do craft). Devolve false se não sabe desenhar.
static func item(ci: CanvasItem, id: String, c: Vector2, s: float) -> bool:
	if not id.begins_with("acao_"):
		_sombra(ci, c, s)
	return _item(ci, id, c, s)


static func _item(ci: CanvasItem, id: String, c: Vector2, s: float) -> bool:
	if _novo(ci, id, c, s):
		return true
	return _item_velho(ci, id, c, s)


## Um pau (galho, vareta, cabo) com casca: contorno escuro, a cor, o brilho de cima e os
## nós; w: grossura.
static func _pau(ci: CanvasItem, pts: PackedVector2Array, w: float, cor: Color, u: float, nos := 0) -> void:
	var ink := Color(0.14, 0.09, 0.05)
	ci.draw_polyline(pts, ink, (w + 3.0) * u, true)
	ci.draw_polyline(pts, cor, w * u, true)
	var hi := PackedVector2Array()
	for q in pts:
		hi.append(q + Vector2(-0.18, -0.26) * w * u)
	ci.draw_polyline(hi, cor.lightened(0.28), maxf(1.0, w * 0.28) * u, true)
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(0.2, 0.28) * w * u)
	ci.draw_polyline(sh, cor.darkened(0.3), maxf(1.0, w * 0.22) * u, true)
	for k in nos:
		var t := (k + 1.0) / (nos + 1.0)
		var i := clampi(int(t * (pts.size() - 1)), 0, pts.size() - 2)
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := (b - a).normalized()
		var nn := Vector2(-d.y, d.x)
		var m := a.lerp(b, 0.5)
		ci.draw_line(m - nn * w * 0.5 * u, m + nn * w * 0.5 * u, cor.darkened(0.4), 1.6 * u, true)


## A madeira cortada (tábua, ripa, lenha): a face com os veios e a ponta com os anéis.
static func _madeira(ci: CanvasItem, a: Vector2, b: Vector2, larg: float, esp: float, cor: Color, u: float, casca := false) -> void:
	var ink := Color(0.14, 0.09, 0.05)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var face := PackedVector2Array([a - n * larg * 0.5 * u, b - n * larg * 0.5 * u, b + n * larg * 0.5 * u, a + n * larg * 0.5 * u])
	var lado := PackedVector2Array([a + n * larg * 0.5 * u, b + n * larg * 0.5 * u, b + (n * larg * 0.5 + Vector2(0, esp)) * u, a + (n * larg * 0.5 + Vector2(0, esp)) * u])
	_poly(ci, lado, cor.darkened(0.3) if not casca else Color(0.33, 0.22, 0.13))
	_poly(ci, face, cor)
	# os veios
	for k in 4:
		var o := -0.35 + k * 0.23
		var pl := PackedVector2Array()
		for i in 9:
			var t := float(i) / 8.0
			pl.append(a.lerp(b, t) + n * (o * larg + sin(t * 7.0 + k * 2.0) * 1.2) * u)
		ci.draw_polyline(pl, cor.darkened(0.25), 1.1 * u, true)
	# a ponta (corte) com os anéis
	var ponta := PackedVector2Array([b - n * larg * 0.5 * u, b + n * larg * 0.5 * u, b + (n * larg * 0.5 + Vector2(0, esp)) * u, b + (-n * larg * 0.5 + Vector2(0, esp)) * u])
	_poly(ci, ponta, cor.lightened(0.15))
	ci.draw_polyline(face + PackedVector2Array([face[0]]), ink, 1.8 * u, true)
	ci.draw_polyline(lado + PackedVector2Array([lado[0]]), ink, 1.5 * u, true)


## Os desenhos novos (mais caprichados). false se não é um deles.
static func _novo(ci: CanvasItem, id: String, c: Vector2, s: float) -> bool:
	var u := s / 100.0
	var ink := Color(0.12, 0.08, 0.05)
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in arr:
			out.append(c + Vector2(q[0], q[1]) * u)
		return out
	match id:
		"galho":
			# o galho seco com a forquilha, a casca e duas folhinhas na ponta fina
			_pau(ci, P.call([[-44, 34], [-20, 16], [4, 0], [24, -14], [44, -30]]), 8.0, Color(0.42, 0.29, 0.17), u, 3)
			_pau(ci, P.call([[-8, 8], [0, -12], [6, -30]]), 5.0, Color(0.42, 0.29, 0.17), u)
			for q in [[8, -34, -0.6], [46, -34, 0.4]]:
				var lc := c + Vector2(q[0], q[1]) * u
				var fl := PackedVector2Array()
				for k in 12:
					var a := TAU * k / 12.0
					fl.append(lc + Vector2(cos(a) * 9.0, sin(a) * 4.0).rotated(float(q[2])) * u)
				_poly(ci, fl, Color(0.5, 0.55, 0.22))
				ci.draw_polyline(fl + PackedVector2Array([fl[0]]), ink, 1.2 * u, true)
			return true
		"vareta", "espeto":
			# a vareta reta, fina, sem casca (raspada); o espeto com a ponta apontada clara
			var a0 := c + Vector2(-42, 38) * u
			var b0 := c + Vector2(40, -36) * u
			_pau(ci, PackedVector2Array([a0, a0.lerp(b0, 0.5), b0]), 5.0, Color(0.66, 0.5, 0.3), u, 2)
			if id == "espeto":
				var d := (b0 - a0).normalized()
				var nn := Vector2(-d.y, d.x)
				var pt := PackedVector2Array([b0 - nn * 3.2 * u, b0 + d * 12.0 * u, b0 + nn * 3.2 * u])
				_poly(ci, pt, Color(0.86, 0.74, 0.52))
				ci.draw_polyline(pt, ink, 1.4 * u, true)
			return true
		"cipo":
			# o cipó-titica enrolado em voltas, castanho-esverdeado com os nós
			for k in 3:
				var pts := PackedVector2Array()
				for i in 41:
					var a := TAU * i / 40.0
					pts.append(c + Vector2(cos(a) * (36.0 - k * 5.0), sin(a) * (22.0 - k * 3.0) + k * 5.0 - 4.0) * u)
				_pau(ci, pts, 4.5, Color(0.4, 0.34, 0.16).lerp(Color(0.32, 0.36, 0.16), k * 0.4), u, 6)
			_pau(ci, P.call([[30, 6], [40, 22], [46, 40]]), 4.0, Color(0.4, 0.34, 0.16), u)
			_pau(ci, P.call([[-34, -6], [-44, -24], [-40, -40]]), 4.0, Color(0.36, 0.34, 0.16), u)
			return true
		"ponta_pedra":
			flint(ci, P.call([[-34, 10], [-10, -14], [30, -32], [40, -26], [12, 10], [-20, 24]]), Color(0.5, 0.5, 0.5), 41, u, [1, 2, 3])
			return true
		"lamina_faca":
			flint(ci, P.call([[-44, 12], [-22, -4], [10, -14], [42, -20], [44, -14], [14, 6], [-18, 18], [-42, 20]]), Color(0.46, 0.47, 0.5), 77, u, [1, 2, 3, 4])
			return true
		"argila_limpa":
			# as bolas de argila limpa, lisinhas e úmidas (brilham)
			for q in [[-16, 8, 26.0], [18, 12, 22.0], [2, -16, 20.0]]:
				var bc := c + Vector2(q[0], q[1]) * u
				var bl := PackedVector2Array()
				for k in 24:
					var a := TAU * k / 24.0
					bl.append(bc + Vector2(cos(a), sin(a) * 0.9) * float(q[2]) * u)
				_poly(ci, bl, Color(0.62, 0.36, 0.24))
				ci.draw_arc(bc + Vector2(-0.25, -0.3) * float(q[2]) * u, float(q[2]) * 0.45 * u, PI * 1.0, PI * 1.6, 8, Color(1, 0.88, 0.75, 0.6), 2.5 * u, true)
				ci.draw_polyline(bl + PackedVector2Array([bl[0]]), ink, 1.8 * u, true)
			return true
		"semente":
			semente_cedro(ci, c, s)
			return true
		"semente_andiroba":
			# as sementes de andiroba: grandes, castanhas, com as faces chatas (quinas)
			for q in [[-20, 10, 0.2], [18, 12, -0.4], [0, -14, 0.9]]:
				var sc := c + Vector2(q[0], q[1]) * u
				var r := float(q[2])
				var sm := PackedVector2Array()
				for v in [[-18, -4], [-8, -18], [12, -16], [20, -2], [14, 14], [-6, 18], [-18, 10]]:
					sm.append(sc + Vector2(v[0], v[1]).rotated(r) * u)
				_poly(ci, sm, Color(0.5, 0.32, 0.17))
				# a quina clara (a face de cima) e a casquinha
				_poly(ci, PackedVector2Array([sc + Vector2(-8, -18).rotated(r) * u, sc + Vector2(12, -16).rotated(r) * u, sc + Vector2(4, -2).rotated(r) * u, sc + Vector2(-12, -4).rotated(r) * u]), Color(0.62, 0.42, 0.24))
				ci.draw_polyline(sm + PackedVector2Array([sm[0]]), ink, 1.8 * u, true)
			return true
		"raiz_timbo":
			# as raízes de timbó: tortas, cheias de nó, castanho-escuras, amarradas
			for k in 4:
				var y := -14.0 + k * 9.0
				var pts2 := PackedVector2Array()
				for i in 9:
					var t := float(i) / 8.0
					pts2.append(c + Vector2(lerpf(-44, 42, t), y + sin(t * 8.0 + k * 1.7) * 3.5 + t * k * 2.0) * u)
				_pau(ci, pts2, 5.5 - k * 0.6, Color(0.42, 0.27, 0.15).darkened(k * 0.06), u, 3)
			_pau(ci, P.call([[-6, -22], [-4, 0], [-2, 24]]), 6.0, Color(0.4, 0.34, 0.16), u)
			return true
		"veneno_timbo":
			# a cuia com o caldo leitoso do timbó amassado e um pedaço de raiz
			load("res://scripts/world/olaria.gd").icone(ci, "vasilha_barro", c + Vector2(0, 10) * u, s * 0.95)
			var lq := PackedVector2Array()
			for k in 20:
				var a := TAU * k / 20.0
				lq.append(c + Vector2(cos(a) * 30.0, sin(a) * 6.0 - 12.0) * u)
			_poly(ci, lq, Color(0.88, 0.88, 0.8))
			ci.draw_arc(c + Vector2(-8, -13) * u, 8.0 * u, PI, PI * 1.7, 8, Color(1, 1, 1, 0.8), 2.0 * u, true)
			_pau(ci, P.call([[8, -14], [22, -30], [34, -38]]), 5.0, Color(0.42, 0.27, 0.15), u, 2)
			return true
		"lenha":
			# duas achas rachadas: a casca escura de um lado, a madeira clara rachada do outro
			_madeira(ci, c + Vector2(-40, 26) * u, c + Vector2(30, -8) * u, 18.0, 10.0, Color(0.78, 0.62, 0.42), u, true)
			_madeira(ci, c + Vector2(-30, 4) * u, c + Vector2(40, -30) * u, 16.0, 9.0, Color(0.74, 0.58, 0.38), u, true)
			return true
		"tabua":
			_madeira(ci, c + Vector2(-44, 22) * u, c + Vector2(40, -14) * u, 34.0, 8.0, Color(0.72, 0.55, 0.34), u)
			return true
		"ripa":
			_madeira(ci, c + Vector2(-44, 30) * u, c + Vector2(42, -30) * u, 10.0, 5.0, Color(0.74, 0.57, 0.36), u)
			return true
		"pino":
			# os pinos de madeira: rachados da ripa, com a ponta afinada
			for k in 2:
				var x := -12.0 + k * 24.0
				var pn: PackedVector2Array = P.call([[x - 7, -38], [x + 7, -38], [x + 6, 22], [x, 40], [x - 6, 22]])
				_poly(ci, pn, Color(0.76, 0.6, 0.38))
				ci.draw_line(c + Vector2(x - 2, -34) * u, c + Vector2(x - 1, 20) * u, Color(0.6, 0.45, 0.27), 1.2 * u, true)
				_poly(ci, P.call([[x - 7, -38], [x + 7, -38], [x + 6, -33], [x - 6, -33]]), Color(0.86, 0.72, 0.5))
				ci.draw_polyline(pn + PackedVector2Array([pn[0]]), ink, 1.6 * u, true)
			return true
		"banda":
			# a banda da vaca (meia carcaça): a carne vermelha, as costelas brancas, a capa
			# de gordura e o osso da perna na ponta
			var bd: PackedVector2Array = P.call([[-46, -6], [-36, -28], [0, -34], [36, -26], [46, -6], [40, 16], [10, 30], [-26, 28], [-44, 14]])
			_poly(ci, bd, Color(0.64, 0.13, 0.1))
			_poly(ci, P.call([[-36, -28], [0, -34], [36, -26], [30, -20], [0, -26], [-30, -21]]), Color(0.94, 0.88, 0.72))
			for k in 6:
				var x := -26.0 + k * 10.0
				ci.draw_line(c + Vector2(x, -18) * u, c + Vector2(x + 4, 18) * u, Color(0.95, 0.9, 0.8), 3.2 * u, true)
				ci.draw_line(c + Vector2(x + 2, -18) * u, c + Vector2(x + 6, 18) * u, Color(0.45, 0.06, 0.05, 0.6), 1.2 * u, true)
			ci.draw_line(c + Vector2(40, 8) * u, c + Vector2(52, 24) * u, Color(0.93, 0.89, 0.8), 8.0 * u, true)
			ci.draw_polyline(bd + PackedVector2Array([bd[0]]), ink, 2.0 * u, true)
			return true
		"arco_fogo":
			# o arco de fogo: o arco de galho com a corda de cipó dando a volta na vareta,
			# a vareta em pé e a tábua (a base) embaixo com o furinho preto
			_madeira(ci, c + Vector2(-40, 34) * u, c + Vector2(40, 34) * u, 12.0, 5.0, Color(0.74, 0.57, 0.36), u)
			ci.draw_circle(c + Vector2(2, 34) * u, 4.0 * u, Color(0.1, 0.06, 0.04))
			_pau(ci, P.call([[2, 32], [2, -30]]), 4.0, Color(0.7, 0.55, 0.34), u)
			var arc := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				arc.append(c + Vector2(lerpf(-44, 40, t), -6.0 - sin(t * PI) * 20.0) * u)
			_pau(ci, arc, 4.5, Color(0.42, 0.29, 0.17), u, 2)
			ci.draw_polyline(P.call([[-44, -6], [-2, -4], [6, 2], [40, -6]]), Color(0.5, 0.44, 0.22), 2.0 * u, true)
			return true
		"cama":
			# a cama: o estrado de galhos em quatro pés, o colchão de capim e as folhas por cima
			for q in [[-40, 8], [36, 8], [-30, 20], [44, 18]]:
				_pau(ci, P.call([[q[0], q[1]], [q[0], q[1] + 18]]), 4.0, Color(0.42, 0.29, 0.17), u)
			_pau(ci, P.call([[-46, 6], [42, 6]]), 4.5, Color(0.45, 0.31, 0.18), u)
			_pau(ci, P.call([[-36, 18], [50, 16]]), 4.5, Color(0.45, 0.31, 0.18), u)
			var col: PackedVector2Array = P.call([[-44, 4], [40, 4], [52, 14], [-34, 16], [-38, 8]])
			col = P.call([[-46, 2], [-40, -8], [42, -8], [52, 2], [48, 14], [-36, 14]])
			_poly(ci, col, Color(0.8, 0.7, 0.42))
			for k in 9:
				var x := -36.0 + k * 9.0
				ci.draw_line(c + Vector2(x, -6) * u, c + Vector2(x + 6, 12) * u, Color(0.6, 0.5, 0.28, 0.7), 1.2 * u, true)
			for k in 5:
				var y := -6.0 + k * 3.5
				ci.draw_line(c + Vector2(-30 + k * 2, y) * u, c + Vector2(30 + k * 3, y + 1) * u, Color(0.36, 0.5, 0.2), 2.6 * u, true)
			var tv := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				tv.append(c + Vector2(36 + cos(a) * 11.0, -8 + sin(a) * 6.0) * u)
			_poly(ci, tv, Color(0.84, 0.75, 0.48))
			ci.draw_polyline(tv + PackedVector2Array([tv[0]]), ink, 1.4 * u, true)
			ci.draw_polyline(col + PackedVector2Array([col[0]]), ink, 1.8 * u, true)
			return true
		"osso":
			# o osso da canela: a haste lisa e as duas pontas largas (as juntas), branco-amarelado
			var corpo: PackedVector2Array = P.call([[-30, 18], [26, -22], [30, -14], [-24, 26]])
			_poly(ci, corpo, Color(0.9, 0.86, 0.74))
			for q in [[-32, 26], [-38, 16], [30, -24], [36, -14]]:
				var bc := c + Vector2(q[0], q[1]) * u
				var cc := PackedVector2Array()
				for k in 16:
					var a := TAU * k / 16.0
					cc.append(bc + Vector2(cos(a) * 11.0, sin(a) * 10.0) * u)
				_poly(ci, cc, Color(0.92, 0.88, 0.77))
				ci.draw_polyline(cc + PackedVector2Array([cc[0]]), ink, 1.8 * u, true)
			_poly(ci, corpo, Color(0.9, 0.86, 0.74))
			ci.draw_line(c + Vector2(-22, 16) * u, c + Vector2(20, -17) * u, Color(1, 1, 0.95, 0.8), 2.5 * u, true)
			ci.draw_line(c + Vector2(-24, 26) * u, c + Vector2(30, -14) * u, ink, 1.8 * u, true)
			ci.draw_line(c + Vector2(-30, 18) * u, c + Vector2(26, -22) * u, ink, 1.8 * u, true)
			return true
		"anzol_osso":
			# o anzol em J de osso, com a farpa e o furinho/entalhe onde amarra a linha
			var jc := c + Vector2(6, 14) * u
			var pts := PackedVector2Array()
			pts.append(c + Vector2(-10, -42) * u)
			for k in 17:
				var a := PI - PI * k / 16.0          # a curva do J: da esquerda, por baixo, à direita
				pts.append(jc + Vector2(cos(a) * 16.0, -sin(a) * -16.0) * u)
			pts.append(c + Vector2(22, -6) * u)
			ci.draw_polyline(pts, ink, 11.0 * u, true)
			ci.draw_polyline(pts, Color(0.9, 0.85, 0.72), 8.0 * u, true)
			var hl := PackedVector2Array()
			for q in pts:
				hl.append(q + Vector2(-1.5, -1.5) * u)
			ci.draw_polyline(hl, Color(1, 1, 0.95, 0.7), 2.0 * u, true)
			var farpa: PackedVector2Array = P.call([[20, -4], [14, 4], [24, 2]])
			_poly(ci, farpa, Color(0.9, 0.85, 0.72))
			ci.draw_polyline(farpa, ink, 1.5 * u, true)
			ci.draw_line(c + Vector2(-14, -36) * u, c + Vector2(-6, -36) * u, ink, 2.0 * u, true)
			ci.draw_polyline(P.call([[-10, -42], [-8, -50], [2, -56]]), Color(0.75, 0.66, 0.46), 1.6 * u, true)
			return true
		"anzol_forquilha":
			# o galhinho em V: o lado comprido para a linha e o curtinho apontado (a farpa)
			_pau(ci, P.call([[-2, 40], [-8, 0], [-14, -40]]), 6.0, Color(0.5, 0.36, 0.2), u, 1)
			_pau(ci, P.call([[-2, 40], [10, 22], [18, 8]]), 5.0, Color(0.5, 0.36, 0.2), u)
			var ponta: PackedVector2Array = P.call([[15, 10], [24, -2], [20, 12]])
			_poly(ci, ponta, Color(0.85, 0.72, 0.5))
			ci.draw_polyline(ponta, ink, 1.4 * u, true)
			for k in 4:
				ci.draw_line(c + Vector2(-16, -34 + k * 3) * u, c + Vector2(-10, -36 + k * 3) * u, Color(0.75, 0.66, 0.46), 1.6 * u, true)
			ci.draw_polyline(P.call([[-14, -40], [-10, -48], [0, -54]]), Color(0.75, 0.66, 0.46), 1.6 * u, true)
			return true
		"isca_carne":
			# os pedacinhos de carne crua cortados para a isca
			for q in [[-18, 6, 0.3], [6, 12, -0.5], [20, -8, 0.8], [-4, -12, 1.4], [-24, -14, -0.2]]:
				var o := c + Vector2(q[0], q[1]) * u
				var rr := float(q[2])
				var cb := PackedVector2Array([o + Vector2(-9, -6).rotated(rr) * u, o + Vector2(9, -7).rotated(rr) * u, o + Vector2(10, 6).rotated(rr) * u, o + Vector2(-8, 8).rotated(rr) * u])
				_poly(ci, cb, Color(0.68, 0.12, 0.1))
				ci.draw_line(o + Vector2(-9, -6).rotated(rr) * u, o + Vector2(9, -7).rotated(rr) * u, Color(0.95, 0.88, 0.75), 2.4 * u, true)
				ci.draw_polyline(cb + PackedVector2Array([cb[0]]), ink, 1.4 * u, true)
			return true
		"couro_vaca", "couro_boi":
			# o couro esticado: a forma do bicho aberto, o pelo por cima (malhado na vaca,
			# castanho no boi), o lado de dentro aparecendo na borda
			var cv: PackedVector2Array = P.call([[-30, -36], [-10, -30], [10, -30], [30, -36], [36, -20], [46, -12], [38, 0], [38, 22], [46, 32], [28, 36], [10, 30], [-10, 30], [-28, 36], [-46, 32], [-38, 22], [-38, 0], [-46, -12], [-36, -20]])
			var pelo := Color(0.85, 0.82, 0.76) if id == "couro_vaca" else Color(0.45, 0.3, 0.18)
			_poly(ci, cv, Color(0.9, 0.84, 0.74))
			var dentro := PackedVector2Array()
			for q in cv:
				dentro.append(c + (q - c) * 0.88)
			_poly(ci, dentro, pelo)
			if id == "couro_vaca":
				for q in [[-14, -10, 12], [16, 6, 10], [-4, 18, 7]]:
					var mc := PackedVector2Array()
					for k in 10:
						var a := TAU * k / 10.0
						mc.append(c + (Vector2(q[0], q[1]) + Vector2(cos(a), sin(a) * 0.8) * float(q[2]) * (0.85 + 0.2 * sin(a * 3.0))) * u)
					_poly(ci, mc, Color(0.3, 0.22, 0.15))
			for k in 14:
				var hx := -26.0 + (k % 7) * 9.0
				var hy := -18.0 + (k / 7) * 30.0
				ci.draw_line(c + Vector2(hx, hy) * u, c + Vector2(hx + 3, hy + 5) * u, pelo.darkened(0.25), 1.0 * u, true)
			ci.draw_polyline(cv + PackedVector2Array([cv[0]]), ink, 1.8 * u, true)
			return true
	return false


static func _item_velho(ci: CanvasItem, id: String, c: Vector2, s: float) -> bool:
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
			_poly(ci, handle, Color(0.55, 0.36, 0.2))
			ci.draw_polyline(handle + PackedVector2Array([handle[0]]), ink, 2.0 * u, true)
			ci.draw_line(c + Vector2(-26, 36) * u, c + Vector2(16, -26) * u, Color(0.7, 0.5, 0.3), 2.0 * u, true)
			var head: PackedVector2Array = P.call([[4, -40], [20, -46], [40, -38], [46, -18], [36, -8], [24, -16], [10, -22]])
			_poly(ci, head, Color(0.5, 0.5, 0.48))
			_poly(ci, P.call([[36, -8], [46, -18], [40, -38], [44, -36], [50, -18], [40, -5]]), Color(0.72, 0.72, 0.68))
			ci.draw_polyline(head + PackedVector2Array([head[0]]), ink, 2.0 * u, true)
			for k in 3:
				var y := -30 + k * 6
				ci.draw_line(c + Vector2(6 + k * 2, y) * u, c + Vector2(22 + k * 2, y - 10) * u, Color(0.45, 0.4, 0.18), 3.0 * u, true)
		"cavadeira":
			# cabo comprido na diagonal e lâmina larga de pedra (como pá) amarrada com cipó
			ci.draw_line(c + Vector2(42, -44) * u, c + Vector2(-14, 18) * u, Color(0.4, 0.26, 0.14), 7.0 * u, true)
			ci.draw_line(c + Vector2(42, -44) * u, c + Vector2(-14, 18) * u, ink, 1.2 * u, true)
			var blade: PackedVector2Array = P.call([[-10, 10], [-22, 22], [-46, 30], [-40, 44], [-30, 46], [-12, 36], [2, 18]])
			_poly(ci, blade, Color(0.58, 0.52, 0.42))
			_poly(ci, P.call([[-46, 30], [-40, 44], [-34, 45], [-42, 30]]), Color(0.74, 0.7, 0.6))
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
			_poly(ci, pts, Color(0.36, 0.35, 0.33))
			for k2 in 4:
				var f2 := 1.0 - k2 * 0.2
				var inner := PackedVector2Array()
				for q in pts:
					inner.append(c + Vector2(-6, -6 - k2 * 2) * u + (q - c - Vector2(0, 4) * u) * f2)
				_poly(ci, inner, Color(0.42, 0.41, 0.38).lightened(k2 * 0.07))
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
			_poly(ci, rp, Color(0.7, 0.54, 0.34))
			_poly(ci, P.call([[-44, 22], [-36, 34], [-32, 32], [-40, 20]]), Color(0.86, 0.72, 0.5))
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
		"enxada":
			# cabo comprido e a lâmina larga atravessada na ponta (como enxada)
			ci.draw_line(c + Vector2(-42, 42) * u, c + Vector2(22, -30) * u, Color(0.4, 0.26, 0.14), 7.0 * u, true)
			flint(ci, P.call([[10, -44], [44, -26], [46, -12], [30, -4], [20, -22], [6, -32]]), Color(0.47, 0.43, 0.35), 37, u, [1, 2])
			for k in 3:
				var pe := c + Vector2(-42, 42).lerp(Vector2(22, -30), 0.82 + k * 0.05) * u
				ci.draw_line(pe + Vector2(-6, -5) * u, pe + Vector2(6, 5) * u, Color(0.45, 0.4, 0.18), 3.0 * u, true)
		"pedra_enxada":
			flint(ci, P.call([[-22, -34], [22, -34], [36, -10], [42, 26], [0, 34], [-42, 26], [-36, -10]]),
				Color(0.47, 0.43, 0.35), 13, u, [3, 4, 5])
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
			_poly(ci, cup, Color(0.5, 0.36, 0.22))
			_poly(ci, P.call([[-30, -10], [30, -10], [28, 0], [-28, 0]]), Color(0.75, 0.82, 0.55))
			ci.draw_polyline(cup + PackedVector2Array([cup[0]]), ink, 2.0 * u, true)
			_poly(ci, P.call([[-4, -40], [10, -30], [2, -16], [-10, -26]]), Color(0.2, 0.4, 0.15))
		"semente_andiroba":
			for k in 3:
				var o := Vector2(-22 + k * 22, 8 - (k % 2) * 16)
				_poly(ci, P.call([[o.x - 16, o.y - 12], [o.x + 14, o.y - 14], [o.x + 16, o.y + 12], [o.x - 14, o.y + 14]]), Color(0.45, 0.29, 0.16))
				ci.draw_line(c + Vector2(o.x - 12, o.y) * u, c + Vector2(o.x + 12, o.y - 2) * u, Color(0.3, 0.19, 0.1), 2.0 * u, true)
		"oleo_andiroba":
			var gar: PackedVector2Array = P.call([[-14, -40], [14, -40], [14, -26], [30, -8], [30, 38], [-30, 38], [-30, -8], [-14, -26]])
			_poly(ci, gar, Color(0.55, 0.42, 0.26))
			_poly(ci, P.call([[-28, 2], [28, 2], [28, 36], [-28, 36]]), Color(0.86, 0.68, 0.22))
			ci.draw_polyline(gar + PackedVector2Array([gar[0]]), ink, 2.0 * u, true)
			_poly(ci, P.call([[-10, -48], [10, -48], [10, -40], [-10, -40]]), Color(0.4, 0.28, 0.16))
		"lamina_faca", "faca":
			if id == "faca":
				ci.draw_line(c + Vector2(-46, 26) * u, c + Vector2(-8, 4) * u, Color(0.55, 0.36, 0.2), 12 * u, true)
				for k in 3:
					ci.draw_line(c + Vector2(-16 + k * 4, -2 + k * 2) * u, c + Vector2(-8 + k * 4, 12 + k * 2) * u, Color(0.7, 0.58, 0.32), 3 * u, true)
			var bl: PackedVector2Array = P.call([[-10, 6], [-4, -6], [44, -34], [12, 10]]) if id == "faca" else P.call([[-40, 18], [-36, 6], [42, -26], [8, 22]])
			_poly(ci, bl, Color(0.46, 0.46, 0.44))
			ci.draw_polyline(bl + PackedVector2Array([bl[0]]), ink, 2.0 * u, true)
		"folha_buriti", "acao_cortar":
			buriti_leaf(ci, c + Vector2(4, 4) * u, s * 0.95)
		"talo_buriti":
			# o talo comprido, verde-claro, com as duas pontas cortadas (fibra clara)
			var a0 := c + Vector2(-44, 34) * u
			var a1 := c + Vector2(44, -30) * u
			ci.draw_line(a0, a1, Color(0.18, 0.28, 0.1), 13 * u, true)
			ci.draw_line(a0, a1, Color(0.42, 0.58, 0.26), 9 * u, true)
			ci.draw_line(a0 + Vector2(0, -2) * u, a1 + Vector2(0, -2) * u, Color(0.62, 0.74, 0.42), 2.5 * u, true)
			for e in [a0, a1]:
				ci.draw_circle(e, 5.5 * u, Color(0.86, 0.8, 0.58))
				ci.draw_arc(e, 5.5 * u, 0, TAU, 12, Color(0.3, 0.36, 0.16), 1.5 * u, true)
		"fibra_buriti":
			# um feixe de fibras claras, amarrado no meio, com as pontas abertas
			for k in 14:
				var o := (k - 6.5) * 2.2
				var pts := PackedVector2Array()
				for i in 9:
					var t := i / 8.0
					var spread := absf(t - 0.5) * 2.0
					pts.append(c + Vector2(lerpf(-44, 44, t), o * (0.35 + spread * 0.9) + sin(t * 9.0 + k) * 1.5) * u)
				ci.draw_polyline(pts, Color(0.86, 0.78, 0.55).darkened(0.12 * (k % 3)), 2.2 * u, true)
			ci.draw_rect(Rect2(c + Vector2(-5, -9) * u, Vector2(10, 18) * u), Color(0.42, 0.33, 0.17))
			ci.draw_rect(Rect2(c + Vector2(-5, -9) * u, Vector2(10, 18) * u), Color(0.15, 0.1, 0.05), false, 1.5 * u)
		"acao_trabalhar":
			# a bancada com as lâminas em pé e o talo sendo puxado em cima delas
			_poly(ci, PackedVector2Array([c + Vector2(-46, 10) * u, c + Vector2(46, 4) * u, c + Vector2(46, 14) * u, c + Vector2(-46, 20) * u]), Color(0.58, 0.42, 0.26))
			ci.draw_rect(Rect2(c + Vector2(-38, 18) * u, Vector2(9, 28) * u), Color(0.38, 0.28, 0.17))
			ci.draw_rect(Rect2(c + Vector2(28, 13) * u, Vector2(9, 32) * u), Color(0.38, 0.28, 0.17))
			for k in 3:
				var bx := -18 + k * 16
				_poly(ci, PackedVector2Array([c + Vector2(bx - 7, 10 - k * 0.6) * u, c + Vector2(bx + 7, 9 - k * 0.6) * u, c + Vector2(bx + 1, -2 - k * 0.6) * u]), Color(0.45, 0.45, 0.43))
			ci.draw_line(c + Vector2(-46, -14) * u, c + Vector2(40, -6) * u, Color(0.2, 0.32, 0.12), 8 * u, true)
			ci.draw_line(c + Vector2(-46, -14) * u, c + Vector2(40, -6) * u, Color(0.45, 0.6, 0.28), 5 * u, true)
			for k in 5:
				ci.draw_line(c + Vector2(-46, -14) * u, c + Vector2(-56, -22 + k * 5) * u, Color(0.86, 0.78, 0.55), 1.6 * u, true)
		"folha_buriti_seca":
			buriti_leaf(ci, c + Vector2(4, 4) * u, s * 0.95, true)
		"acao_derrubar":
			fell_icon(ci, c, s)
		"fruto_buriti":
			# fruto oval com a casca de escamas vermelho-escuras
			for q in [[-14, 8, 1.0], [14, 4, 0.9], [0, -14, 0.95]]:
				var cc := c + Vector2(q[0], q[1]) * u
				var rr := 20.0 * float(q[2]) * u
				var pts := PackedVector2Array()
				for i in 24:
					var a := TAU * i / 24.0
					pts.append(cc + Vector2(cos(a) * rr * 0.85, sin(a) * rr))
				_poly(ci, pts, Color(0.55, 0.16, 0.08))
				for k in 6:
					var o := Vector2(cos(k * 1.1) * rr * 0.45, sin(k * 1.7) * rr * 0.55)
					ci.draw_arc(cc + o, rr * 0.22, PI * 0.1, PI * 0.9, 6, Color(0.82, 0.32, 0.14), 1.6 * u, true)
				ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 1.6 * u, true)
		"fruto_bacaba":
			# um punhado de frutinhos roxos quase pretos
			for q in [[-18, 10], [0, 14], [18, 8], [-10, -6], [10, -8], [0, -22], [-24, -10], [24, -12]]:
				var cc2 := c + Vector2(q[0], q[1]) * u
				ci.draw_circle(cc2, 10.5 * u, Color(0.2, 0.08, 0.16))
				ci.draw_circle(cc2 + Vector2(-3, -3) * u, 3.0 * u, Color(0.55, 0.4, 0.55))
		"taia":
			# a batata (redonda, casca marrom com raizinhas) e o pé do talo pintado
			var bp := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				bp.append(c + Vector2(cos(a) * 34, sin(a) * 26 + 10) * u)
			_poly(ci, bp, Color(0.45, 0.32, 0.2))
			ci.draw_polyline(bp + PackedVector2Array([bp[0]]), ink, 2.0 * u, true)
			for k in 5:
				ci.draw_line(c + Vector2(-20 + k * 10, 34) * u, c + Vector2(-24 + k * 12, 46) * u, Color(0.4, 0.3, 0.2), 1.5 * u, true)
			ci.draw_rect(Rect2(c + Vector2(-6, -40) * u, Vector2(12, 34) * u), Color(0.36, 0.42, 0.3))
			for k in 4:
				ci.draw_circle(c + Vector2(-2 + (k % 2) * 4, -34 + k * 8) * u, 2.5 * u, Color(0.14, 0.15, 0.11))
			for k in 6:
				ci.draw_circle(c + Vector2(-18 + k * 7, 4 + (k % 2) * 8) * u, 1.6 * u, Color(0.6, 0.48, 0.32))
		"goiaba":
			# duas goiabas maduras (amarelas, um pouco de pera) e uma cortada (polpa rosa)
			for q in [[-20, 6, 26.0], [18, 12, 24.0]]:
				var gc := c + Vector2(q[0], q[1]) * u
				var gp := PackedVector2Array()
				for i in 24:
					var a := TAU * i / 24.0
					var r := float(q[2]) * (1.0 + 0.12 * sin(a))
					gp.append(gc + Vector2(cos(a) * r * 0.92, sin(a) * r) * u)
				_poly(ci, gp, Color(0.85, 0.8, 0.3))
				ci.draw_polyline(gp + PackedVector2Array([gp[0]]), ink, 2.0 * u, true)
				ci.draw_circle(gc + Vector2(-7, -9) * u, 5.0 * u, Color(0.95, 0.92, 0.6))
				ci.draw_circle(gc + Vector2(0, float(q[2]) * 0.95) * u, 3.0 * u, Color(0.3, 0.25, 0.12))
			var mc := c + Vector2(0, -26) * u
			ci.draw_circle(mc, 17.0 * u, Color(0.8, 0.76, 0.3))
			ci.draw_circle(mc, 14.0 * u, Color(0.95, 0.5, 0.5))
			ci.draw_circle(mc, 7.0 * u, Color(0.9, 0.38, 0.4))
			for k in 6:
				ci.draw_circle(mc + Vector2(cos(k * 1.05), sin(k * 1.05)) * 9.0 * u, 1.6 * u, Color(0.98, 0.9, 0.75))
		"folha_goiabeira":
			# três folhas ovais com a nervura do meio e as laterais
			for q in [[-0.5, -8.0], [0.0, 0.0], [0.55, 8.0]]:
				var ang := float(q[0]) - PI * 0.5
				var d := Vector2(cos(ang), sin(ang))
				var sd := Vector2(-d.y, d.x)
				var b := c + Vector2(float(q[1]), 38) * u
				var fp := PackedVector2Array()
				for i in 21:
					var t := float(i) / 20.0
					fp.append(b + (d * t * 76.0 + sd * sin(t * PI) * 17.0) * u)
				for i in range(19, 0, -1):
					var t := float(i) / 20.0
					fp.append(b + (d * t * 76.0 - sd * sin(t * PI) * 17.0) * u)
				_poly(ci, fp, Color(0.36, 0.55, 0.2))
				ci.draw_polyline(fp + PackedVector2Array([fp[0]]), ink, 1.8 * u, true)
				ci.draw_line(b, b + d * 76.0 * u, Color(0.7, 0.8, 0.45), 1.6 * u, true)
				for k in range(1, 6):
					var p0 := b + d * (k * 12.0) * u
					ci.draw_line(p0, p0 + (d * 7.0 + sd * 12.0) * u, Color(0.55, 0.7, 0.35), 1.0 * u, true)
					ci.draw_line(p0, p0 + (d * 7.0 - sd * 12.0) * u, Color(0.55, 0.7, 0.35), 1.0 * u, true)
		"cha_goiabeira", "acao_cha":
			# a vasilha de barro com o chá (cor de mate) e o vapor
			var vp := PackedVector2Array(P.call([[-40, -6], [40, -6], [32, 22], [18, 34], [-18, 34], [-32, 22]]))
			_poly(ci, vp, Color(0.66, 0.38, 0.22))
			ci.draw_polyline(vp + PackedVector2Array([vp[0]]), ink, 2.0 * u, true)
			ci.draw_rect(Rect2(c + Vector2(-38, -10) * u, Vector2(76, 7) * u), Color(0.55, 0.42, 0.18))
			ci.draw_line(c + Vector2(-14, -2) * u, c + Vector2(-2, -6) * u, Color(0.36, 0.55, 0.2), 4.0 * u, true)
			for k in 3:
				var x0 := -18.0 + k * 18.0
				var pts := PackedVector2Array()
				for i in 9:
					var t := float(i) / 8.0
					pts.append(c + Vector2(x0 + sin(t * TAU) * 5.0, -16.0 - t * 30.0) * u)
				ci.draw_polyline(pts, Color(0.9, 0.9, 0.9, 0.8), 2.5 * u, true)
		"remedio_cobra":
			# a cuia com a pasta verde-amarelada e a gota
			var cu := PackedVector2Array()
			for i in 13:
				var a2 := PI * i / 12.0
				cu.append(c + Vector2(cos(a2) * 40, sin(a2) * 30 + 2) * u)
			_poly(ci, cu, Color(0.5, 0.3, 0.16))
			_poly(ci, PackedVector2Array([c + Vector2(-38, 2) * u, c + Vector2(38, 2) * u, c + Vector2(30, -8) * u, c + Vector2(-30, -8) * u]), Color(0.72, 0.68, 0.38))
			ci.draw_polyline(cu, ink, 2.0 * u, true)
			ci.draw_line(c + Vector2(-38, 2) * u, c + Vector2(38, 2) * u, ink, 2.0 * u, true)
			# a cruzinha de remédio
			ci.draw_rect(Rect2(c + Vector2(18, -46) * u, Vector2(8, 24) * u), Color(0.85, 0.15, 0.15))
			ci.draw_rect(Rect2(c + Vector2(10, -38) * u, Vector2(24, 8) * u), Color(0.85, 0.15, 0.15))
		"capim_seco":
			# um maço de capim seco amarrado no meio
			for k in 16:
				var o := (k - 7.5) * 2.4
				ci.draw_line(c + Vector2(o * 0.35, 6) * u, c + Vector2(o * 1.6 + sin(k * 1.7) * 4.0, -44) * u, Color(0.84, 0.72, 0.42).darkened(0.1 * (k % 3)), 2.2 * u, true)
				ci.draw_line(c + Vector2(o * 0.35, 6) * u, c + Vector2(o * 0.9, 40) * u, Color(0.78, 0.66, 0.38).darkened(0.1 * (k % 2)), 2.2 * u, true)
			ci.draw_rect(Rect2(c + Vector2(-9, -2) * u, Vector2(18, 10) * u), Color(0.45, 0.36, 0.18))
		"vareta":
			ci.draw_line(c + Vector2(-40, 38) * u, c + Vector2(40, -38) * u, Color(0.35, 0.24, 0.13), 9 * u, true)
			ci.draw_line(c + Vector2(-40, 38) * u, c + Vector2(40, -38) * u, Color(0.6, 0.44, 0.26), 6 * u, true)
			ci.draw_circle(c + Vector2(40, -38) * u, 4.5 * u, Color(0.82, 0.68, 0.48))
		"corda_5", "corda_10", "corda_20", "corda_30", "corda_50", "acao_corda_fazer", "acao_corda_continuar":
			# o rolo de corda de cipó trançado: voltas em elipse (mais voltas, mais comprida)
			var m := 20
			if id.begins_with("corda_"):
				m = int(id.substr(6))
			var voltas := clampi(3 + m / 8, 3, 9)
			var cor := Color(0.55, 0.45, 0.22)
			for k in voltas:
				var rx := 40.0 - k * 2.2
				var ry := 26.0 - k * 1.4
				var off := Vector2(0, 6 - k * 1.2)
				var pts := PackedVector2Array()
				for i in 33:
					var a := TAU * i / 32.0
					pts.append(c + (off + Vector2(cos(a) * rx, sin(a) * ry)) * u)
				ci.draw_polyline(pts, Color(0.22, 0.16, 0.07), 8.5 * u, true)
				ci.draw_polyline(pts, cor.darkened(0.08 * (k % 2)), 6.0 * u, true)
				# a trança: tracinhos inclinados ao longo da volta
				for i in range(0, 32, 2):
					var a2 := TAU * i / 32.0
					var p0 := c + (off + Vector2(cos(a2) * rx, sin(a2) * ry)) * u
					ci.draw_line(p0 + Vector2(-2, -2.5) * u, p0 + Vector2(2, 2.5) * u, Color(0.3, 0.22, 0.1), 1.4 * u, true)
			# a ponta solta saindo do rolo
			ci.draw_line(c + Vector2(30, 10) * u, c + Vector2(46, 36) * u, Color(0.22, 0.16, 0.07), 8.0 * u, true)
			ci.draw_line(c + Vector2(30, 10) * u, c + Vector2(46, 36) * u, cor, 5.5 * u, true)
		"couro_vaca", "couro_boi":
			# o couro aberto (com as pernas) dobrado ao meio: pelo de fora, o lado de dentro claro
			var fora := Color(0.74, 0.7, 0.64) if id == "couro_vaca" else Color(0.42, 0.3, 0.2)
			var pel: PackedVector2Array = P.call([[-40, -26], [-30, -36], [-18, -28], [18, -28], [30, -36], [40, -26], [34, -8], [42, 14], [34, 34], [16, 26], [-16, 26], [-34, 34], [-42, 14], [-34, -8]])
			_poly(ci, pel, fora)
			_poly(ci, P.call([[-30, -18], [30, -18], [26, 18], [-26, 18]]), Color(0.9, 0.82, 0.74))
			for k in 4:
				var yy := -12.0 + k * 9.0
				ci.draw_line(c + Vector2(-24, yy) * u, c + Vector2(24, yy + 2) * u, Color(0.8, 0.62, 0.55), 1.4 * u, true)
			pel.append(pel[0])
			ci.draw_polyline(pel, ink, 2.0 * u, true)
		"folha_babacu":
			# a folha penada verde: a raque e os folíolos dos dois lados
			var raq := Color(0.24, 0.36, 0.14)
			ci.draw_line(c + Vector2(-44, 36) * u, c + Vector2(44, -36) * u, ink, 5.0 * u, true)
			ci.draw_line(c + Vector2(-44, 36) * u, c + Vector2(44, -36) * u, raq, 3.0 * u, true)
			for k in 16:
				var t := float(k) / 15.0
				var p0 := c + Vector2(lerpf(-40, 40, t), lerpf(33, -33, t)) * u
				var comp := 18.0 * sin(PI * (0.1 + t * 0.9)) + 5.0
				for sd in [-1.0, 1.0]:
					var dd: Vector2 = Vector2(0.5, 0.8).normalized() * sd
					ci.draw_line(p0, p0 + (dd + Vector2(0.4, -0.3)).normalized() * comp * u, Color(0.32, 0.55, 0.2).darkened(0.1 * (k % 2)), 2.2 * u, true)
		"coco_babacu":
			# o coco oval de casca marrom, com a pontinha
			for k in 3:
				var cc := c + Vector2(-22 + k * 22, 8 - (k % 2) * 14) * u
				var pts := PackedVector2Array()
				for i in 20:
					var a := TAU * i / 20.0
					pts.append(cc + Vector2(cos(a) * 14, sin(a) * 22).rotated(0.3) * u)
				_poly(ci, pts, Color(0.45, 0.3, 0.16).darkened(0.08 * k))
				pts.append(pts[0])
				ci.draw_polyline(pts, ink, 1.6 * u, true)
				ci.draw_line(cc + Vector2(-4, -12) * u, cc + Vector2(-6, -18) * u, ink, 2.0 * u, true)
		"roldana":
			# a forquilha em V segurando a rodela pela vareta (o eixo), o sulco em volta
			var mad := Color(0.5, 0.36, 0.2)
			ci.draw_line(c + Vector2(0, -46) * u, c + Vector2(0, -30) * u, ink, 9.0 * u, true)
			ci.draw_line(c + Vector2(0, -46) * u, c + Vector2(0, -30) * u, mad, 6.0 * u, true)
			for sd in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(0, -30) * u, c + Vector2(sd * 30, 2) * u, ink, 9.0 * u, true)
				ci.draw_line(c + Vector2(0, -30) * u, c + Vector2(sd * 30, 2) * u, mad, 6.0 * u, true)
			ci.draw_circle(c + Vector2(0, 14) * u, 32.0 * u, Color(0.3, 0.22, 0.14))
			ci.draw_circle(c + Vector2(0, 14) * u, 29.0 * u, Color(0.78, 0.63, 0.42))
			ci.draw_arc(c + Vector2(0, 14) * u, 25.0 * u, 0, TAU, 32, Color(0.45, 0.32, 0.18), 3.0 * u, true)
			for r in [17.0, 10.0]:
				ci.draw_arc(c + Vector2(0, 14) * u, r * u, 0, TAU, 28, Color(0.62, 0.46, 0.28), 1.6 * u, true)
			ci.draw_arc(c + Vector2(0, 14) * u, 32.0 * u, 0, TAU, 36, ink, 2.0 * u, true)
			ci.draw_line(c + Vector2(-34, 14) * u, c + Vector2(34, 14) * u, ink, 6.0 * u, true)
			ci.draw_line(c + Vector2(-34, 14) * u, c + Vector2(34, 14) * u, Color(0.66, 0.52, 0.3), 3.5 * u, true)
		"laco_5", "laco_10":
			# a corda enrolada na mão e a laçada aberta na ponta
			var cor2 := Color(0.55, 0.45, 0.22)
			for k in 4:
				var pts2 := PackedVector2Array()
				for i in 25:
					var a4 := TAU * i / 24.0
					pts2.append(c + Vector2(-18 + cos(a4) * (22 - k * 2), 10 + sin(a4) * (16 - k * 1.5)) * u)
				ci.draw_polyline(pts2, Color(0.22, 0.16, 0.07), 7.5 * u, true)
				ci.draw_polyline(pts2, cor2, 5.0 * u, true)
			var lp := PackedVector2Array()
			for i in 29:
				var a5 := TAU * i / 28.0
				lp.append(c + Vector2(24 + cos(a5) * 20, -18 + sin(a5) * 24) * u)
			ci.draw_polyline(lp, Color(0.22, 0.16, 0.07), 7.5 * u, true)
			ci.draw_polyline(lp, cor2.lightened(0.1), 5.0 * u, true)
			ci.draw_line(c + Vector2(2, 0) * u, c + Vector2(14, 2) * u, cor2, 5.0 * u, true)
		"arco", "acao_atirar":
			# o arco envergado (vareta) com a corda de cipó trançado
			var pa := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				pa.append(c + Vector2(-26 + sin(t * PI) * 34, lerpf(-46, 46, t)) * u)
			ci.draw_polyline(pa, Color(0.36, 0.24, 0.13), 8 * u, true)
			ci.draw_polyline(pa, Color(0.55, 0.38, 0.22), 4 * u, true)
			ci.draw_line(pa[0], pa[16], Color(0.62, 0.55, 0.3), 2.5 * u, true)
			for k in 6:
				var yy := -44.0 + k * 17.6
				ci.draw_line(c + Vector2(-27, yy) * u, c + Vector2(-25, yy + 8) * u, Color(0.4, 0.33, 0.15), 1.5 * u, true)
			if id == "acao_atirar":
				ci.draw_line(c + Vector2(-34, 0) * u, c + Vector2(44, 0) * u, Color(0.6, 0.45, 0.28), 4 * u, true)
				_poly(ci, P.call([[44, -7], [58, 0], [44, 7]]), Color(0.45, 0.45, 0.43))
		"flecha":
			# a vareta com a ponta de pedra amarrada e as penas atrás
			ci.draw_line(c + Vector2(-44, 36) * u, c + Vector2(30, -30) * u, Color(0.6, 0.45, 0.28), 5 * u, true)
			_poly(ci, P.call([[24, -20], [46, -44], [34, -16]]), Color(0.45, 0.45, 0.43))
			ci.draw_polyline(P.call([[24, -20], [46, -44], [34, -16], [24, -20]]), ink, 1.5 * u, true)
			ci.draw_line(c + Vector2(22, -26) * u, c + Vector2(28, -18) * u, Color(0.3, 0.22, 0.1), 5 * u, true)
			_poly(ci, P.call([[-44, 36], [-50, 20], [-36, 26]]), Color(0.85, 0.82, 0.75))
			_poly(ci, P.call([[-44, 36], [-28, 42], [-36, 26]]), Color(0.75, 0.72, 0.65))
		"arco_fogo":
			# o galho curvo e o cipó esticado, com a vareta atravessada
			var pts := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				pts.append(c + Vector2(lerpf(-44, 44, t), 18 - sin(t * PI) * 34) * u)
			ci.draw_polyline(pts, Color(0.5, 0.35, 0.2), 7 * u, true)
			ci.draw_line(pts[0], pts[12], Color(0.55, 0.5, 0.25), 2.5 * u, true)
			ci.draw_line(c + Vector2(-4, -40) * u, c + Vector2(4, 44) * u, Color(0.62, 0.46, 0.28), 6 * u, true)
		"lenha":
			# duas achas rachadas (casca de um lado, madeira clara do outro)
			for k in 2:
				var o := Vector2(-10 + k * 18, -8 + k * 14)
				var poly: PackedVector2Array = P.call([[o.x - 34, o.y + 10], [o.x + 30, o.y - 16], [o.x + 38, o.y - 4], [o.x - 26, o.y + 22]])
				_poly(ci, poly, Color(0.78, 0.6, 0.38))
				ci.draw_line(c + Vector2(o.x - 30, o.y + 18) * u, c + Vector2(o.x + 34, o.y - 8) * u, Color(0.36, 0.25, 0.15), 6 * u, true)
				ci.draw_polyline(poly + PackedVector2Array([poly[0]]), ink, 2.0 * u, true)
		"tela_fibra", "acao_tela":
			# a tela quadrada trançada de fibra clara
			var q0 := c + Vector2(-38, -38) * u
			ci.draw_rect(Rect2(q0, Vector2(76, 76) * u), Color(0.42, 0.33, 0.18, 0.35))
			for k in 9:
				var o := (k * 9.5) * u
				ci.draw_line(q0 + Vector2(o, 0), q0 + Vector2(o, 76 * u), Color(0.86, 0.78, 0.55), 2.2 * u, true)
				ci.draw_line(q0 + Vector2(0, o), q0 + Vector2(76 * u, o), Color(0.8, 0.72, 0.5), 2.2 * u, true)
			ci.draw_rect(Rect2(q0, Vector2(76, 76) * u), Color(0.5, 0.36, 0.2), false, 4.0 * u)
		"carvao", "acao_carvao":
			for q in [[-18, 10, 20.0], [14, 14, 17.0], [0, -12, 19.0], [24, -16, 12.0], [-28, -10, 12.0]]:
				var cc := c + Vector2(q[0], q[1]) * u
				var rr := float(q[2]) * u
				_poly(ci, PackedVector2Array([cc + Vector2(-rr, 0), cc + Vector2(-rr * 0.4, -rr * 0.9), cc + Vector2(rr * 0.6, -rr * 0.7), cc + Vector2(rr, 0.1 * rr), cc + Vector2(rr * 0.3, rr * 0.8), cc + Vector2(-rr * 0.7, rr * 0.6)]), Color(0.08, 0.08, 0.09))
				ci.draw_line(cc + Vector2(-rr * 0.4, -rr * 0.5), cc + Vector2(rr * 0.3, -rr * 0.4), Color(0.35, 0.35, 0.38), 1.5 * u, true)
		"acao_pedrinhas":
			for q in [[-20, 14, 13.0], [8, 18, 11.0], [24, 4, 12.0], [-4, -6, 12.0], [-26, -12, 9.0], [14, -18, 10.0]]:
				ci.draw_circle(c + Vector2(q[0], q[1]) * u, float(q[2]) * u, Color(0.5, 0.48, 0.44))
				ci.draw_arc(c + Vector2(q[0], q[1]) * u, float(q[2]) * u, 0, TAU, 14, ink, 1.5 * u, true)
		"acao_areia":
			balde(ci, c + Vector2(-10, -6) * u, s * 0.75)
			_poly(ci, P.call([[-30, -30], [10, -30], [6, -22], [-26, -22]]), Color(0.82, 0.72, 0.52))
		"acao_vasilha":
			load("res://scripts/world/olaria.gd").icone(ci, "bacia_barro", c, s)
		"acao_agua_filtro":
			balde(ci, c + Vector2(-12, -6) * u, s * 0.7)
			for k in 3:
				ci.draw_line(c + Vector2(14 + k * 6, -10) * u, c + Vector2(18 + k * 6, 38) * u, Color(0.45, 0.65, 0.88), 3.5 * u, true)
		"vasilha_barro", "garrafa_barro", "moringa_barro", "bacia_barro", "filtro_barro":
			load("res://scripts/world/olaria.gd").icone(ci, id, c, s)
		"espeto", "espeto_carne":
			# a vareta comprida, apontada, na diagonal (com o pedaço de carne espetado)
			ci.draw_line(c + Vector2(-42, 40) * u, c + Vector2(40, -38) * u, Color(0.5, 0.34, 0.18), 5.0 * u, true)
			_poly(ci, P.call([[40, -38], [48, -46], [36, -40]]), Color(0.7, 0.55, 0.35))
			if id == "espeto_carne":
				var lump: PackedVector2Array = P.call([[-18, 6], [-10, -10], [8, -16], [20, -6], [16, 12], [0, 18], [-14, 16]])
				_poly(ci, lump, Color(0.66, 0.1, 0.08))
				_poly(ci, P.call([[-10, -10], [8, -16], [20, -6], [6, -8]]), Color(0.92, 0.84, 0.68))
				ci.draw_polyline(lump + PackedVector2Array([lump[0]]), ink, 2.0 * u, true)
		"vasilha_carne", "vasilha_carne_cozida", "vasilha_carne_frita", "vasilha_carne_queimada":
			# a vasilha com os cubos de carne aparecendo por cima da boca (crus, cozidos,
			# fritos ou queimados); a cozida com o vapor
			load("res://scripts/world/olaria.gd").icone(ci, "vasilha_barro", c + Vector2(0, 8) * u, s * 0.95)
			var cc := Color(0.62, 0.1, 0.08)
			match id:
				"vasilha_carne_cozida": cc = Color(0.55, 0.38, 0.3)
				"vasilha_carne_frita": cc = Color(0.58, 0.3, 0.1)
				"vasilha_carne_queimada": cc = Color(0.1, 0.06, 0.04)
			if id == "vasilha_carne_cozida":
				for k in 3:
					var vx := -14.0 + k * 14.0
					ci.draw_polyline(PackedVector2Array([c + Vector2(vx, -34) * u, c + Vector2(vx + 5, -42) * u, c + Vector2(vx - 3, -50) * u, c + Vector2(vx + 3, -58) * u]), Color(0.9, 0.9, 0.92, 0.85), 2.5 * u, true)
			for q in [[-18, -14], [-4, -18], [10, -15], [-11, -24], [4, -27], [18, -22]]:
				var o := c + Vector2(q[0], q[1]) * u
				var cub := PackedVector2Array([o + Vector2(-7, -5) * u, o + Vector2(7, -6) * u, o + Vector2(8, 6) * u, o + Vector2(-6, 7) * u])
				_poly(ci, cub, cc)
				ci.draw_line(o + Vector2(-7, -5) * u, o + Vector2(7, -6) * u, Color(0.9, 0.82, 0.68), 2.0 * u, true)
				ci.draw_polyline(cub + PackedVector2Array([cub[0]]), ink, 1.5 * u, true)
		"coco", "acao_coco":
			coco(ci, c, s, false)
		"massa_coco":
			coco(ci, c, s, true)
		"argila":
			# o torrão de argila molhada: marrom-avermelhado, liso e brilhante, com marcas de dedo
			var pa := PackedVector2Array()
			var rg := RandomNumberGenerator.new()
			rg.seed = 11
			for k in 20:
				var a := TAU * k / 20.0
				var rr := 36.0 * rg.randf_range(0.84, 1.06)
				pa.append(c + Vector2(cos(a) * rr * 1.2, sin(a) * rr * 0.82 + 4) * u)
			_poly(ci, pa, Color(0.56, 0.31, 0.2))
			for k in 3:
				ci.draw_arc(c + Vector2(-14 + k * 14, 4 + (k % 2) * 6) * u, 8.0 * u, PI * 1.1, PI * 1.9, 8, Color(0.4, 0.2, 0.12, 0.8), 2.0 * u, true)
			ci.draw_arc(c + Vector2(-12, -10) * u, 14.0 * u, PI * 1.05, PI * 1.6, 10, Color(1, 0.85, 0.7, 0.55), 3.0 * u, true)
			ci.draw_polyline(pa + PackedVector2Array([pa[0]]), ink, 2.0 * u, true)
		"semente":
			semente_cedro(ci, c, s)
		"quarto_vaca", "quarto_vaca_sujo":
			# o quarto de vaca: a peça grande de carne vermelha com a capa de gordura, o osso
			# saindo na ponta; o sujo com terra
			var qv := PackedVector2Array(P.call([[-44, -8], [-30, -32], [6, -36], [34, -22], [44, 4], [30, 30], [-6, 36], [-36, 22]]))
			_poly(ci, qv, Color(0.66, 0.12, 0.1))
			_poly(ci, P.call([[-30, -32], [6, -36], [34, -22], [26, -18], [2, -26], [-24, -22]]), Color(0.93, 0.86, 0.7))
			for k in 4:
				ci.draw_line(c + Vector2(-26 + k * 15, -10) * u, c + Vector2(-18 + k * 15, 24) * u, Color(0.45, 0.06, 0.05), 2.2 * u, true)
			# o osso
			ci.draw_line(c + Vector2(30, 18) * u, c + Vector2(48, 34) * u, Color(0.92, 0.88, 0.78), 10.0 * u, true)
			ci.draw_circle(c + Vector2(49, 35) * u, 7.0 * u, Color(0.95, 0.92, 0.82))
			ci.draw_arc(c + Vector2(49, 35) * u, 7.0 * u, 0, TAU, 12, ink, 1.5 * u, true)
			if id == "quarto_vaca_sujo":
				for q in [[-24, 6], [-4, 18], [16, -4], [-14, -12], [24, 14], [4, 2]]:
					ci.draw_circle(c + Vector2(q[0], q[1]) * u, 6.5 * u, Color(0.42, 0.31, 0.18, 0.92))
			ci.draw_polyline(qv + PackedVector2Array([qv[0]]), ink, 2.0 * u, true)
		"linha_pesca", "acao_linha_fazer":
			# o rolinho de linha fina (muitas voltas finas)
			for k in 7:
				var pts2 := PackedVector2Array()
				for i in 33:
					var a := TAU * i / 32.0
					pts2.append(c + Vector2(cos(a) * (30.0 - k * 1.5), sin(a) * (20.0 - k) + 4 - k * 1.4) * u)
				ci.draw_polyline(pts2, Color(0.66, 0.5, 0.3).darkened(0.1 * (k % 2)), 2.4 * u, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(26, 8) * u, c + Vector2(38, 26) * u, c + Vector2(44, 40) * u]), Color(0.6, 0.45, 0.26), 2.0 * u, true)
			if id == "acao_linha_fazer":
				ci.draw_arc(c + Vector2(44, 40) * u, 5.0 * u, -PI * 0.2, PI * 1.1, 10, ink, 2.2 * u, true)
		"vara_pesca":
			# o galho comprido na diagonal, a linha descendo da ponta, a boia e o anzol
			ci.draw_line(c + Vector2(-44, 44) * u, c + Vector2(38, -42) * u, ink, 7.5 * u, true)
			ci.draw_line(c + Vector2(-44, 44) * u, c + Vector2(38, -42) * u, Color(0.55, 0.4, 0.22), 5.0 * u, true)
			ci.draw_line(c + Vector2(-40, 40) * u, c + Vector2(-28, 28) * u, Color(0.3, 0.2, 0.1), 7.0 * u, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(38, -42) * u, c + Vector2(40, -10) * u, c + Vector2(38, 24) * u]), Color(0.75, 0.66, 0.48), 1.6 * u, true)
			ci.draw_circle(c + Vector2(40, -2) * u, 5.0 * u, Color(0.88, 0.82, 0.64))
			ci.draw_arc(c + Vector2(40, -2) * u, 5.0 * u, 0, TAU, 12, ink, 1.4 * u, true)
			ci.draw_arc(c + Vector2(34, 26) * u, 5.0 * u, -PI * 0.1, PI * 1.2, 10, Color(0.85, 0.82, 0.75), 2.0 * u, true)
		"peixe_tucunare", "peixe_pacu", "peixe_traira", "peixe_piranha", "peixe_curimata":
			peixe(ci, id, c, s)
		"vasilha_peixe_frito", "vasilha_peixe_queimado":
			load("res://scripts/world/olaria.gd").icone(ci, "vasilha_barro", c + Vector2(0, 8) * u, s * 0.95)
			peixe(ci, "peixe_queimado" if id == "vasilha_peixe_queimado" else "peixe_frito", c + Vector2(0, -22) * u, s * 0.7)
		"carne_crua", "carne_assar", "carne_assada", "carne_queimada", "carne_suja":
			# um pedaço de carne: vermelha crua (com a capa de gordura), dourada assada,
			# preta queimada, com terra se suja
			var cor := Color(0.66, 0.1, 0.08)
			if id == "carne_assada":
				cor = Color(0.55, 0.3, 0.12)
			elif id == "carne_queimada":
				cor = Color(0.12, 0.07, 0.05)
			var pts := [[-40, -6], [-30, -24], [-4, -30], [26, -26], [42, -10], [40, 12], [20, 26], [-12, 28], [-36, 16]]
			var lump: PackedVector2Array = P.call(pts)
			_poly(ci, lump, cor)
			_poly(ci, P.call([[-30, -24], [-4, -30], [26, -26], [42, -10], [30, -16], [-2, -20], [-26, -16]]), Color(0.92, 0.84, 0.68) if id in ["carne_crua", "carne_assar", "carne_suja"] else cor.lightened(0.25))
			for k in 3:
				ci.draw_line(c + Vector2(-24 + k * 18, -4) * u, c + Vector2(-16 + k * 18, 18) * u, cor.darkened(0.3), 2.0 * u, true)
			if id == "carne_suja":
				for q in [[-20, 6], [8, 14], [22, -2], [-6, -8]]:
					ci.draw_circle(c + Vector2(q[0], q[1]) * u, 6.0 * u, Color(0.4, 0.3, 0.18, 0.9))
			ci.draw_polyline(lump + PackedVector2Array([lump[0]]), ink, 2.0 * u, true)
		"moringa_agua", "moringa_limpa", "acao_encher_cabaca":
			load("res://scripts/world/olaria.gd").icone(ci, "moringa_barro", c + Vector2(-6, 2) * u, s * 0.92)
			# a gota de água (do rio: meio barrenta; filtrada: azul clarinha com o brilho)
			var gc := c + Vector2(30, -18) * u
			_poly(ci, PackedVector2Array([gc + Vector2(0, -16) * u, gc + Vector2(9, 2) * u, gc + Vector2(6, 9) * u, gc + Vector2(0, 11) * u, gc + Vector2(-6, 9) * u, gc + Vector2(-9, 2) * u]), Color(0.5, 0.55, 0.42) if id == "moringa_agua" else Color(0.35, 0.62, 0.92))
			ci.draw_circle(gc + Vector2(-2.5, 3) * u, 2.5 * u, Color(0.8, 0.92, 1.0))
		"acao_modelar":
			# a mesa redonda do torno e o pote em cima
			_poly(ci, P.call([[-44, 22], [44, 22], [40, 32], [-40, 32]]), Color(0.6, 0.42, 0.25))
			ci.draw_line(c + Vector2(0, 32) * u, c + Vector2(0, 48) * u, Color(0.4, 0.28, 0.16), 6 * u, true)
			load("res://scripts/world/olaria.gd").icone(ci, "moringa_barro", c + Vector2(0, -8) * u, s * 0.62)
		"argila_limpa", "acao_limpar", "acao_despejar_argila":
			# bola de argila (lisa, alaranjada); limpar: com pedrinhas saindo; despejar: o balde
			if id == "acao_despejar_argila":
				balde(ci, c + Vector2(-14, -10) * u, s * 0.7)
				_poly(ci, P.call([[-2, 6], [10, 4], [16, 20], [2, 24]]), Color(0.58, 0.29, 0.16))
			var bc := c + (Vector2(14, 18) if id == "acao_despejar_argila" else Vector2(0, 6)) * u
			var br := (22.0 if id == "acao_despejar_argila" else 32.0) * u
			ci.draw_circle(bc, br, Color(0.62, 0.31, 0.17))
			ci.draw_circle(bc + Vector2(-0.3, -0.35) * br, br * 0.4, Color(0.74, 0.42, 0.26))
			ci.draw_arc(bc, br, 0, TAU, 32, ink, 2.0 * u, true)
			if id == "acao_limpar":
				for q in [[26, -30, 5.0], [36, -18, 4.0], [18, -40, 3.5]]:
					ci.draw_circle(c + Vector2(q[0], q[1]) * u, float(q[2]) * u, Color(0.45, 0.43, 0.4))
				ci.draw_line(c + Vector2(-30, -26) * u, c + Vector2(-14, -40) * u, Color(0.36, 0.24, 0.13), 2.5 * u, true)
		"acao_abrir", "acao_agua", "acao_misturar", "acao_pegar_barro", "acao_fibra":
			# o monte de terra (barro, nos últimos passos) com a cova no meio
			var mud := id in ["acao_misturar", "acao_pegar_barro"]
			var mc := Color(0.33, 0.24, 0.16) if not mud else Color(0.27, 0.22, 0.17)
			var mound := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				mound.append(c + Vector2(lerpf(-46, 46, t), 40 - sin(t * PI) * 30) * u)
			_poly(ci, mound, mc)
			ci.draw_polyline(mound, ink, 2.0 * u, true)
			if id != "acao_pegar_barro":
				_poly(ci, P.call([[-18, 14], [0, 18], [18, 14], [10, 10], [-10, 10]]), Color(0.16, 0.11, 0.07))
			if id == "acao_agua":
				_poly(ci, P.call([[-14, 13], [14, 13], [8, 16], [-8, 16]]), Color(0.35, 0.5, 0.62))
				for k in 3:
					var dx := -6.0 + k * 6.0
					ci.draw_line(c + Vector2(dx + 8, -44) * u, c + Vector2(dx, 4) * u, Color(0.45, 0.65, 0.85), 3.5 * u, true)
				ci.draw_line(c + Vector2(22, 16) * u, c + Vector2(36, 34) * u, Color(0.2, 0.14, 0.09), 3 * u, true)
			elif id == "acao_fibra":
				for k in 6:
					ci.draw_line(c + Vector2(-26 + k * 4, -34 + k * 2) * u, c + Vector2(-8 + k * 5, 10) * u, Color(0.86, 0.78, 0.55), 2 * u, true)
			elif id == "acao_pegar_barro":
				balde(ci, c + Vector2(26, -14) * u, s * 0.55)
			else:
				# a enxada batendo
				ci.draw_line(c + Vector2(40, -46) * u, c + Vector2(-2, 4) * u, Color(0.4, 0.26, 0.14), 6 * u, true)
				flint(ci, P.call([[-14, -2], [6, 0], [8, 14], [-6, 18]]), Color(0.47, 0.43, 0.35), 37, u, [1])
		"ponta_pedra", "furador":
			if id == "furador":
				ci.draw_line(c + Vector2(-44, 30) * u, c + Vector2(4, -4) * u, Color(0.55, 0.36, 0.2), 13 * u, true)
				for k in 4:
					ci.draw_line(c + Vector2(-6 + k * 4, -8 + k * 3) * u, c + Vector2(4 + k * 4, 6 + k * 3) * u, Color(0.7, 0.58, 0.32), 3 * u, true)
			var tip: PackedVector2Array = P.call([[-2, -2], [10, -18], [46, -40], [22, 6], [8, 10]]) if id == "furador" else P.call([[-34, 20], [-30, -6], [40, -34], [10, 22]])
			_poly(ci, tip, Color(0.42, 0.42, 0.4))
			ci.draw_polyline(tip + PackedVector2Array([tip[0]]), ink, 2.0 * u, true)
		"pino":
			for k in 2:
				var o := Vector2(-14 + k * 26, 0)
				var body: PackedVector2Array = P.call([[o.x - 7, -40], [o.x + 7, -40], [o.x + 7, 26], [o.x, 44], [o.x - 7, 26]])
				_poly(ci, body, Color(0.66, 0.5, 0.32))
				ci.draw_line(c + Vector2(o.x - 2, -36) * u, c + Vector2(o.x - 2, 24) * u, Color(0.5, 0.36, 0.2), 2.0 * u, true)
				ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, 2.0 * u, true)
				_poly(ci, P.call([[o.x - 7, -40], [o.x + 7, -40], [o.x + 7, -34], [o.x - 7, -34]]), Color(0.78, 0.62, 0.42))
		"tabua", "ripa":
			var w := 26.0 if id == "tabua" else 9.0
			var pts := PackedVector2Array([c + Vector2(-44, -w) * u, c + Vector2(44, -w - 8) * u, c + Vector2(44, w - 8) * u, c + Vector2(-44, w) * u])
			_poly(ci, pts, Color(0.6, 0.44, 0.28))
			for k in 3:
				var y := -w + (k + 1) * w * 0.5
				ci.draw_line(c + Vector2(-40, y) * u, c + Vector2(40, y - 8) * u, Color(0.45, 0.31, 0.18), 1.5 * u, true)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
		"banda":
			var pts := PackedVector2Array()
			for k in 13:
				var a := PI * k / 12.0
				pts.append(c + Vector2(cos(a) * 44.0, -sin(a) * 34.0 + 14.0) * u)
			_poly(ci, pts, Color(0.36, 0.26, 0.17))
			var inner := PackedVector2Array()
			for q in pts:
				inner.append(c + (q - c - Vector2(0, 14) * u) * 0.82 + Vector2(0, 14) * u)
			_poly(ci, inner, Color(0.78, 0.62, 0.42))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
		"hematita", "magnetita", "goetita", "silex", "malaquita", "calcopirita":
			_mineral(ci, id, c, u)
		"lasca_silex":
			var sh: PackedVector2Array = P.call([[-36, 18], [-10, -30], [8, -38], [34, -6], [10, 30], [-20, 34]])
			_poly(ci, sh, Color(0.36, 0.37, 0.4))
			_poly(ci, P.call([[-10, -30], [8, -38], [34, -6], [14, -2]]), Color(0.55, 0.56, 0.6))
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
	_poly(ci, pts, base)
	# luz em cima
	var hi := PackedVector2Array()
	for q in pts:
		hi.append(c + (q - c) * 0.55 + Vector2(-6, -10) * u)
	_poly(ci, hi, base.lightened(0.18))
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
	_poly(ci, body, Color(0.46, 0.36, 0.25))
	for k in 7:
		var t := (k + 1) / 8.0
		ci.draw_line(c + Vector2(lerpf(-34, 34, t), -18) * u, c + Vector2(lerpf(-29, 29, t), 42) * u, Color(0.3, 0.23, 0.15), 1.5 * u, true)
	# boca (elipse escura) e as duas ripas altas com o furo da alça
	_poly(ci, P.call([[-34, -18], [-20, -24], [20, -24], [34, -18], [20, -13], [-20, -13]]), Color(0.2, 0.15, 0.1))
	for sx in [-1.0, 1.0]:
		var ear: PackedVector2Array = P.call([[30 * sx, -32], [38 * sx, -32], [38 * sx, -10], [30 * sx, -10]])
		_poly(ci, ear, Color(0.44, 0.34, 0.23))
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
	_poly(ci, pts, base.darkened(0.25))
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
		_poly(ci, PackedVector2Array([a, b, ib, ia]), col)
		ci.draw_polyline(PackedVector2Array([ia, ib]), base.darkened(0.45), 1.0 * u, true)
		_poly(ci, PackedVector2Array([ia, ib, cen]), base.lerp(base.lightened(0.3), rng.randf() * 0.6))
	# fio: beirada clara (afiada)
	for ei in edge:
		var e0: Vector2 = pts[int(ei) % n]
		var e1: Vector2 = pts[(int(ei) + 1) % n]
		ci.draw_line(e0, e1, base.lightened(0.6), 3.0 * u, true)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)


## Folha de buriti em leque: talo curvo e a "mão" aberta de lâminas pregueadas
## (vinco claro e escuro alternando) com as pontas caindo.
static func buriti_leaf(ci: CanvasItem, c: Vector2, s: float, seca := false) -> void:
	var u := s / 100.0
	var hub := c + Vector2(-2, -4) * u
	# talo: do canto de baixo até a mão, levemente curvo
	var pet := PackedVector2Array()
	for k in 9:
		var t := k / 8.0
		pet.append(c + Vector2(lerpf(-46, -2, t), lerpf(46, -4, t) + sin(t * PI) * 6.0) * u)
	ci.draw_polyline(pet, Color(0.25, 0.17, 0.08) if seca else Color(0.2, 0.3, 0.1), 7.5 * u, true)
	ci.draw_polyline(pet, Color(0.6, 0.45, 0.26) if seca else Color(0.42, 0.58, 0.24), 4.0 * u, true)
	# as lâminas (de trás para a frente)
	var n := 19
	for k in n:
		var t := k / float(n - 1)
		var a := lerpf(-2.75, 0.55, t)
		var L := (40.0 + 8.0 * sin(t * PI)) * u
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var droop := Vector2(0, 1) * (6.0 + 10.0 * absf(cos(a))) * u
		var base := hub + dir * 5.0 * u
		var mid := hub + dir * L * 0.65
		var tip := hub + dir * L + droop
		var w := 3.6 * u
		var light := k % 2 == 0
		var col := Color(0.3, 0.55, 0.18) if light else Color(0.16, 0.36, 0.1)
		if seca:
			col = Color(0.62, 0.45, 0.24) if light else Color(0.45, 0.31, 0.15)
		var poly := PackedVector2Array([base - side * 1.0 * u, mid - side * w, tip, mid + side * w, base + side * 1.0 * u])
		_poly(ci, poly, col)
		# a ponta rasgada em duas (como a folha de verdade)
		ci.draw_line(tip, tip + dir * 5.0 * u + side * 2.5 * u + droop * 0.3, col.darkened(0.15), 1.6 * u, true)
		ci.draw_line(tip, tip + dir * 5.0 * u - side * 2.5 * u + droop * 0.3, col.darkened(0.15), 1.6 * u, true)
		ci.draw_line(base, mid, col.lightened(0.25), 1.0 * u, true)
	# o centro da mão (onde o talo abre)
	ci.draw_circle(hub, 5.0 * u, Color(0.4, 0.28, 0.14) if seca else Color(0.3, 0.42, 0.16))
	ci.draw_circle(hub + Vector2(-1, -1) * u, 2.5 * u, Color(0.6, 0.46, 0.28) if seca else Color(0.5, 0.64, 0.3))


## Derrubar: o toco cortado com o machado cravado e o tronco caído na frente.
static func fell_icon(ci: CanvasItem, c: Vector2, s: float) -> void:
	var u := s / 100.0
	var ink := Color(0.1, 0.07, 0.04)
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in arr:
			out.append(c + Vector2(p[0], p[1]) * u)
		return out
	# chão (capim)
	_poly(ci, P.call([[-50, 34], [50, 30], [50, 44], [-50, 44]]), Color(0.24, 0.36, 0.14))
	for k in 9:
		var x := -46 + k * 11
		ci.draw_line(c + Vector2(x, 36) * u, c + Vector2(x + 3, 28) * u, Color(0.36, 0.52, 0.2), 2.0 * u, true)
	# tronco caído (deitado, da esquerda para a direita, atrás)
	var lg: PackedVector2Array = P.call([[-18, 16], [46, 6], [48, 26], [-16, 36]])
	_poly(ci, lg, Color(0.47, 0.44, 0.4))
	_poly(ci, P.call([[-18, 16], [46, 6], [46, 12], [-18, 22]]), Color(0.6, 0.57, 0.52))
	for k in 5:
		var x := -6 + k * 11
		ci.draw_line(c + Vector2(x, 15 - k * 1.8) * u, c + Vector2(x + 1, 33 - k * 1.8) * u, Color(0.36, 0.33, 0.3), 1.6 * u, true)
	ci.draw_polyline(lg + PackedVector2Array([lg[0]]), ink, 1.8 * u, true)
	# a ponta cortada do tronco caído (madeira clara)
	_ellipse(ci, c + Vector2(-17, 26) * u, Vector2(6, 10) * u, Color(0.86, 0.74, 0.52), ink, u)
	# o toco
	var st: PackedVector2Array = P.call([[-44, 0], [-20, 0], [-18, 38], [-46, 38]])
	_poly(ci, st, Color(0.42, 0.39, 0.35))
	_poly(ci, P.call([[-24, 0], [-20, 0], [-18, 38], [-22, 38]]), Color(0.32, 0.29, 0.26))
	ci.draw_polyline(st + PackedVector2Array([st[0]]), ink, 1.8 * u, true)
	_ellipse(ci, c + Vector2(-32, 0) * u, Vector2(12, 5) * u, Color(0.88, 0.76, 0.54), ink, u)
	ci.draw_arc(c + Vector2(-32, 0) * u, 6.0 * u, 0, TAU, 16, Color(0.7, 0.56, 0.36), 1.2 * u, true)
	# o machado cravado no toco
	ci.draw_line(c + Vector2(-30, -2) * u, c + Vector2(-8, -38) * u, Color(0.25, 0.15, 0.07), 7.0 * u, true)
	ci.draw_line(c + Vector2(-30, -2) * u, c + Vector2(-8, -38) * u, Color(0.6, 0.4, 0.22), 4.0 * u, true)
	var head: PackedVector2Array = P.call([[-40, -6], [-30, -14], [-22, -6], [-30, 2]])
	_poly(ci, head, Color(0.5, 0.5, 0.47))
	ci.draw_polyline(head + PackedVector2Array([head[0]]), ink, 1.6 * u, true)
	for k in 3:
		ci.draw_line(c + Vector2(-32 + k * 2, -10 + k * 2) * u, c + Vector2(-25 + k * 2, -12 + k * 2) * u, Color(0.68, 0.56, 0.3), 1.6 * u, true)


## O olho (botão de olhar o que dá para fazer): branco amendoado, íris, pupila e brilho.
static func eye(ci: CanvasItem, c: Vector2, s: float, lit := false) -> void:
	var u := s / 100.0
	var n := 28
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := i / float(n)
		pts.append(c + Vector2(lerpf(-46, 46, t), -sin(t * PI) * 26.0) * u)
	for i in range(n - 1, 0, -1):
		var t := i / float(n)
		pts.append(c + Vector2(lerpf(-46, 46, t), sin(t * PI) * 22.0) * u)
	ci.draw_circle(c, 52.0 * u, Color(0.04, 0.04, 0.03, 0.55))
	if lit:
		ci.draw_circle(c, 52.0 * u, Color(1.0, 0.8, 0.3, 0.35))
	_poly(ci, pts, Color(0.97, 0.95, 0.9))
	ci.draw_circle(c + Vector2(0, -1) * u, 18.0 * u, Color(0.33, 0.22, 0.1))
	ci.draw_circle(c + Vector2(0, -1) * u, 14.0 * u, Color(0.47, 0.33, 0.14))
	ci.draw_circle(c + Vector2(0, -1) * u, 7.5 * u, Color(0.03, 0.02, 0.02))
	ci.draw_circle(c + Vector2(-5, -7) * u, 3.6 * u, Color(1, 1, 1, 0.95))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.05, 0.04, 0.03), 4.0 * u, true)
	# cílios em cima
	for k in 5:
		var t := 0.2 + k * 0.15
		var p := c + Vector2(lerpf(-46, 46, t), -sin(t * PI) * 26.0) * u
		var d := (p - c).normalized()
		ci.draw_line(p, p + d * 9.0 * u, Color(0.05, 0.04, 0.03), 3.0 * u, true)


static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, fill: Color, ink: Color, u: float) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	_poly(ci, pts, fill)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 1.4 * u, true)


## Um peixe de lado (a cabeça para a direita), com a cor e o desenho de cada espécie.
## "peixe_frito" / "peixe_queimado": dourado ou preto (na vasilha).
static func peixe(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	var u := s / 100.0
	var ink := Color(0.12, 0.08, 0.05)
	var cores := {
		"peixe_tucunare": [Color(0.33, 0.42, 0.16), Color(0.92, 0.8, 0.36), 0.36],
		"peixe_pacu": [Color(0.34, 0.38, 0.38), Color(0.85, 0.74, 0.58), 0.62],
		"peixe_traira": [Color(0.3, 0.24, 0.14), Color(0.66, 0.57, 0.42), 0.26],
		"peixe_piranha": [Color(0.45, 0.48, 0.47), Color(0.86, 0.26, 0.14), 0.55],
		"peixe_curimata": [Color(0.44, 0.48, 0.5), Color(0.9, 0.9, 0.87), 0.34],
		"peixe_frito": [Color(0.55, 0.32, 0.1), Color(0.82, 0.58, 0.26), 0.38],
		"peixe_queimado": [Color(0.08, 0.05, 0.03), Color(0.2, 0.13, 0.08), 0.38],
	}
	var e: Array = cores.get(id, cores["peixe_curimata"])
	var costa: Color = e[0]
	var barriga: Color = e[1]
	var hh: float = 70.0 * float(e[2])
	# o corpo: elipse pontuda, as costas em cima e a barriga clara embaixo
	var corpo := PackedVector2Array()
	var cima := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		var x := lerpf(-30, 42, t)
		var f := pow(sin(PI * clampf(t * 0.94 + 0.03, 0.0, 1.0)), 0.75)
		corpo.append(c + Vector2(x, -hh * 0.5 * f) * u)
		cima.append(c + Vector2(x, -hh * 0.5 * f) * u)
	for i in range(24, -1, -1):
		var t := float(i) / 24.0
		var x := lerpf(-30, 42, t)
		var f := pow(sin(PI * clampf(t * 0.94 + 0.03, 0.0, 1.0)), 0.75)
		corpo.append(c + Vector2(x, hh * 0.5 * f) * u)
		cima.append(c + Vector2(x, hh * 0.05 * f) * u)
	# o rabo e as nadadeiras
	var rabo := PackedVector2Array([c + Vector2(-27, 0) * u, c + Vector2(-46, -hh * 0.42) * u, c + Vector2(-40, 0) * u, c + Vector2(-46, hh * 0.42) * u])
	var fin := costa.darkened(0.15)
	if id == "peixe_piranha":
		fin = Color(0.6, 0.22, 0.12)
	_poly(ci, rabo, fin)
	ci.draw_polyline(rabo + PackedVector2Array([rabo[0]]), ink, 1.8 * u, true)
	var dors := PackedVector2Array([c + Vector2(-8, -hh * 0.46) * u, c + Vector2(14, -hh * 0.5) * u, c + Vector2(-2, -hh * 0.5 - 14) * u])
	_poly(ci, dors, fin)
	ci.draw_polyline(dors + PackedVector2Array([dors[0]]), ink, 1.5 * u, true)
	_poly(ci, corpo, barriga)
	_poly(ci, cima, costa)
	match id:
		"peixe_tucunare":
			for bx in [-4.0, 10.0, 24.0]:
				ci.draw_line(c + Vector2(bx, -hh * 0.45) * u, c + Vector2(bx - 2, hh * 0.15) * u, Color(0.12, 0.12, 0.06, 0.85), 4.5 * u, true)
			ci.draw_circle(c + Vector2(-25, -2) * u, 4.5 * u, Color(0.1, 0.08, 0.04))
			ci.draw_arc(c + Vector2(-25, -2) * u, 5.5 * u, 0, TAU, 12, Color(0.95, 0.65, 0.2), 1.6 * u, true)
		"peixe_traira":
			for q in [[-14, -6], [0, -9], [14, -5], [-4, 2], [22, -1], [8, 4]]:
				ci.draw_circle(c + Vector2(q[0], q[1]) * u, 3.2 * u, Color(0.16, 0.12, 0.06, 0.8))
		"peixe_curimata", "peixe_pacu", "peixe_piranha":
			for k in 4:
				ci.draw_arc(c + Vector2(-12 + k * 12, 0) * u, 6.0 * u, -PI * 0.4, PI * 0.4, 6, Color(1, 1, 1, 0.25), 1.2 * u, true)
		"peixe_frito":
			for k in 3:
				ci.draw_line(c + Vector2(-10 + k * 14, -hh * 0.35) * u, c + Vector2(-16 + k * 14, hh * 0.3) * u, Color(0.35, 0.18, 0.05), 2.4 * u, true)
	ci.draw_polyline(corpo + PackedVector2Array([corpo[0]]), ink, 2.0 * u, true)
	# a guelra e o olho
	ci.draw_arc(c + Vector2(30, 0) * u, hh * 0.32 * u, PI * 0.6, PI * 1.4, 8, ink.lightened(0.15), 1.6 * u, true)
	ci.draw_circle(c + Vector2(34, -hh * 0.12) * u, 3.6 * u, Color(0.95, 0.92, 0.8) if id != "peixe_queimado" else Color(0.2, 0.15, 0.1))
	ci.draw_circle(c + Vector2(34.6, -hh * 0.12) * u, 2.0 * u, ink)
	if id == "peixe_piranha":
		for k in 3:
			_poly(ci, PackedVector2Array([c + Vector2(38 + k * 1.6, hh * 0.08) * u, c + Vector2(39.6 + k * 1.6, hh * 0.08) * u, c + Vector2(38.8 + k * 1.6, hh * 0.08 - 3) * u]), Color(1, 1, 1))


## O coco-da-baía. Inteiro: a casca de fibra (verde-oliva amarelando para marrom, com
## as três quinas e o "umbigo" do cabinho). Aberto (a massa): as duas metades com a casca
## grossa marrom de fibra, a parede dura escura e a massa branca por dentro, com a água.
static func coco(ci: CanvasItem, c: Vector2, s: float, aberto: bool) -> void:
	var u := s / 100.0
	var ink := Color(0.12, 0.08, 0.05)
	if not aberto:
		var pts := PackedVector2Array()
		for k in 36:
			var a := TAU * k / 36.0
			# oval com a ponta para cima e uma quina de cada lado
			var r := Vector2(34.0, 44.0) * (1.0 + 0.06 * cos(3.0 * a))
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y * (1.0 + 0.12 * sin(a))) * u)
		_poly(ci, pts, Color(0.5, 0.5, 0.2))
		# a parte de cima marrom (secando): o mesmo contorno, cortado embaixo
		var top := PackedVector2Array()
		for q in pts:
			if q.y < c.y - 14.0 * u:
				top.append(q)
		_poly(ci, top, Color(0.55, 0.4, 0.2, 0.75))
		for k in 7:
			var x := -24.0 + k * 8.0
			var pl := PackedVector2Array()
			for i in 9:
				var t := float(i) / 8.0
				var y := lerpf(-40.0, 40.0, t)
				pl.append(c + Vector2(x * sqrt(maxf(0.0, 1.0 - pow(y / 46.0, 2.0))) + sin(t * 9.0 + k) * 1.2, y) * u)
			ci.draw_polyline(pl, Color(0.3, 0.26, 0.1, 0.45), 1.2 * u, true)
		# o brilho e o cabinho
		ci.draw_arc(c + Vector2(-10, -6) * u, 20.0 * u, PI * 1.05, PI * 1.45, 10, Color(1, 1, 0.85, 0.45), 4.0 * u, true)
		_poly(ci, PackedVector2Array([c + Vector2(-6, -44) * u, c + Vector2(6, -44) * u, c + Vector2(4, -52) * u, c + Vector2(-4, -52) * u]), Color(0.36, 0.25, 0.12))
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.0 * u, true)
		return
	# a metade de trás: virada para baixo, mostrando a casca marrom peluda e os três
	# "olhinhos" do coco
	var ob := c + Vector2(-20, -16) * u
	var dome := PackedVector2Array()
	for k in 25:
		var a := PI + PI * k / 24.0
		dome.append(ob + Vector2(cos(a) * 30.0, sin(a) * 26.0) * u)
	for k in 13:
		var a := PI * k / 12.0
		dome.append(ob + Vector2(cos(a) * 30.0, sin(a) * 9.0) * u)
	_poly(ci, dome, Color(0.42, 0.28, 0.14))
	_fibras(ci, ob + Vector2(0, -10) * u, Vector2(26, 18) * u, 18, 5)
	for q in [[-6, -14], [4, -15], [-1, -6]]:
		ci.draw_circle(ob + Vector2(q[0], q[1]) * u, 3.2 * u, Color(0.16, 0.1, 0.05))
	ci.draw_polyline(dome + PackedVector2Array([dome[0]]), ink, 2.0 * u, true)
	# a metade da frente, de boca para cima: o bojo de casca de fibra por fora
	var o := c + Vector2(8, 6) * u
	var R := 42.0
	var ry := 15.0
	var bojo := PackedVector2Array()
	for k in 25:
		var a := PI * k / 24.0                  # de 0 a PI: a borda da frente e o fundo redondo
		bojo.append(o + Vector2(cos(a) * R, sin(a) * 40.0) * u)
	for k in 25:
		var a := PI + PI * k / 24.0
		bojo.append(o + Vector2(cos(a) * R, sin(a) * ry) * u)
	_poly(ci, bojo, Color(0.47, 0.31, 0.15))
	_fibras(ci, o + Vector2(0, 18) * u, Vector2(36, 18) * u, 30, 9)
	# a boca: a fibra cortada (marrom-clara), a casca dura escura e a massa branca grossa
	var anel := func(f: float, cor: Color) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in 36:
			var a := TAU * k / 36.0
			pts.append(o + Vector2(cos(a) * R * f, sin(a) * ry * f) * u)
		_poly(ci, pts, cor)
		return pts
	var borda: PackedVector2Array = anel.call(1.0, Color(0.66, 0.5, 0.3))
	anel.call(0.8, Color(0.22, 0.13, 0.06))
	anel.call(0.72, Color(0.97, 0.95, 0.9))
	# o fundo da cavidade: a parede de dentro (sombra em cima) e a água de coco brilhando
	var fundo := PackedVector2Array()
	for k in 36:
		var a := TAU * k / 36.0
		fundo.append(o + Vector2(cos(a) * R * 0.52, sin(a) * ry * 0.52 + 1.5) * u)
	_poly(ci, fundo, Color(0.8, 0.82, 0.8))
	var sombra := PackedVector2Array()
	for k in 19:
		var a := PI + PI * k / 18.0
		sombra.append(o + Vector2(cos(a) * R * 0.52, sin(a) * ry * 0.52 + 1.5) * u)
	for k in 19:
		var a := TAU - PI * k / 18.0
		sombra.append(o + Vector2(cos(a) * R * 0.5, sin(a) * ry * 0.15 + 1.5) * u)
	_poly(ci, sombra, Color(0.62, 0.64, 0.62))
	ci.draw_arc(o + Vector2(-6, 3) * u, 9.0 * u, PI * 0.15, PI * 0.75, 8, Color(1, 1, 1, 0.95), 2.2 * u, true)
	ci.draw_polyline(borda + PackedVector2Array([borda[0]]), ink, 1.6 * u, true)
	ci.draw_polyline(bojo, ink, 2.0 * u, true)


## Fiapos de fibra de coco (traços curtos claros e escuros) dentro de uma elipse.
static func _fibras(ci: CanvasItem, c: Vector2, r: Vector2, n: int, seed_: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for k in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf())
		var p := c + Vector2(cos(a) * r.x, sin(a) * r.y) * d
		var ang := rng.randf_range(-0.5, 0.5) + PI * 0.5
		var L := rng.randf_range(0.18, 0.32) * r.y
		var col := Color(0.62, 0.45, 0.25, 0.8) if k % 2 == 0 else Color(0.26, 0.16, 0.07, 0.7)
		ci.draw_line(p, p + Vector2(cos(ang), sin(ang)) * L, col, maxf(1.0, r.y * 0.04), true)


## A semente do cedrinho (Cedrela): o caroço achatado na ponta de uma asa fina e larga,
## castanho-clara com as nervuras (voa girando como hélice). Duas, cruzadas.
static func semente_cedro(ci: CanvasItem, c: Vector2, s: float) -> void:
	var u := s / 100.0
	var ink := Color(0.22, 0.13, 0.06)
	for k in 2:
		var o := c + Vector2(-6 + k * 12, -4 + k * 10) * u
		var rot := -0.6 + k * 1.0
		var asa := PackedVector2Array()
		# a asa: começa no caroço, alarga e termina arredondada
		for i in 13:
			var t := float(i) / 12.0
			var x := lerpf(14.0, -40.0, t)
			var w := 4.0 + 10.0 * sin(t * PI * 0.92)
			asa.append(o + Vector2(x, -w).rotated(rot) * u)
		for i in range(12, -1, -1):
			var t := float(i) / 12.0
			var x := lerpf(14.0, -40.0, t)
			var w := 3.0 + 6.0 * sin(t * PI * 0.92)
			asa.append(o + Vector2(x, w).rotated(rot) * u)
		_poly(ci, asa, Color(0.8, 0.66, 0.44))
		for i in 6:
			var t := 0.2 + i * 0.13
			var x2 := lerpf(14.0, -40.0, t)
			ci.draw_line(o + Vector2(x2 + 4.0, -1.0).rotated(rot) * u, o + Vector2(x2 - 3.0, -8.0 * sin(t * PI)).rotated(rot) * u, Color(0.58, 0.43, 0.25, 0.6), 1.0 * u, true)
		ci.draw_polyline(asa + PackedVector2Array([asa[0]]), ink, 1.4 * u, true)
		var car := PackedVector2Array()
		for i in 14:
			var a := TAU * i / 14.0
			car.append(o + Vector2(14.0 + cos(a) * 9.0, sin(a) * 6.0).rotated(rot) * u)
		_poly(ci, car, Color(0.48, 0.3, 0.15))
		ci.draw_polyline(car + PackedVector2Array([car[0]]), ink, 1.5 * u, true)
