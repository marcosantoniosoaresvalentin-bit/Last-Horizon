extends RefCounted
## Vaca selvagem (gado zebu asselvajado) feita de malha, sem arquivo de modelo: corpo
## comprido e fundo, o cupim (corcova) em cima da cernelha, a barbela (pele solta)
## pendurada no pescoço, cabeça comprida de focinho largo e úmido (preto), orelhas
## compridas e caídas, chifres curtos virados para cima e para trás, pernas finas com
## joelho e jarrete, cascos pretos fendidos, rabo comprido com a vassoura preta na
## ponta e, nas fêmeas, o úbere. O pelo é curto e liso (textura em projeção nos 3
## eixos); a cor de cada uma vem nas cores dos vértices: branca (com o pescoço e as
## pernas acinzentados), cinza, vermelha, parda ou malhada.
##
## Olha para +X. Peças com pivô para animar:
##   corpo / cabeca (pivô na base do pescoço) / orelha_e, orelha_d / rabo (base)
##   pata_fe, pata_fd, pata_te, pata_td (ombro/quadril), cada uma com "baixo"
##   (joelho/jarrete).

const PRETO := Color(0.06, 0.055, 0.05)
const CASCO := Color(0.1, 0.09, 0.08)
const CHIFRE := Color(0.32, 0.3, 0.26)
const ROSA := Color(0.72, 0.52, 0.5)

const CORES := {
	"branca": [Color(0.66, 0.64, 0.6), Color(0.42, 0.42, 0.41)],
	"cinza": [Color(0.55, 0.55, 0.53), Color(0.32, 0.32, 0.32)],
	"vermelha": [Color(0.29, 0.14, 0.08), Color(0.19, 0.09, 0.05)],
	"parda": [Color(0.32, 0.24, 0.17), Color(0.2, 0.15, 0.11)],
	"malhada": [Color(0.76, 0.74, 0.7), Color(0.07, 0.065, 0.06)],
}

static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.85
		_mat.metallic_specular = 0.12
		_mat.albedo_texture = _load_tex("res://texturas/pelo_vaca.imagem", Color(0.92, 0.92, 0.92))
		_mat.normal_enabled = true
		_mat.normal_texture = _load_tex("res://texturas/pelo_vaca_n.imagem", Color(0.5, 0.5, 1.0))
		_mat.normal_scale = 0.8
		_mat.uv1_triplanar = true
		_mat.uv1_triplanar_sharpness = 4.0
		_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


static func _load_tex(path: String, fallback: Color) -> Texture2D:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(fallback)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Monta a vaca. s = tamanho (1 adulta; uns 0,45 o bezerro novo), cor (CORES), touro
## (cupim e pescoço maiores, sem úbere), seed (as manchas da malhada).
static func build(s := 1.0, cor := "branca", touro := false, seed := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "vaca"
	var c: Array = CORES.get(cor, CORES.branca)
	var base: Color = c[0]
	var esc: Color = c[1]
	var malhada := cor == "malhada"
	var bezerro := s < 0.7
	# a cor de cada ponto: escurece no pescoço/cupim (zebu) e nas pernas; manchas na malhada
	var pinta := func(p: Vector3, parte: String) -> Color:
		var col := base
		if malhada:
			var m := sin(p.x * 7.3 + float(seed) * 1.7) * cos(p.z * 9.1 + p.y * 5.2 + float(seed)) + sin(p.y * 6.1 - p.x * 3.3 + float(seed) * 0.4) * 0.6
			if m > 0.35:
				col = esc
		elif parte == "corpo":
			var frente := clampf((p.x - 0.15) / 0.5, 0.0, 1.0) * (0.55 if touro else 0.3)
			col = base.lerp(esc, frente)
		elif parte == "pescoco":
			col = base.lerp(esc, 0.6 if touro else 0.35)
		elif parte == "perna":
			col = base.lerp(esc, clampf((0.5 - p.y) / 0.5, 0.0, 1.0) * 0.6)
		return col
	var corpo := Node3D.new()
	corpo.name = "corpo"
	root.add_child(corpo)
	_mesh(corpo, _body(pinta, touro, not touro and not bezerro))
	# cabeça e pescoço (pivô na base do pescoço, na frente do cupim)
	var cab := Node3D.new()
	cab.name = "cabeca"
	cab.position = Vector3(0.56, 1.0, 0)
	corpo.add_child(cab)
	_mesh(cab, _head(pinta, touro, bezerro))
	for k in 2:
		var sd := -1.0 if k == 0 else 1.0
		var ore := Node3D.new()
		ore.name = "orelha_e" if k == 0 else "orelha_d"
		ore.position = Vector3(0.5, 0.06, sd * 0.1)
		cab.add_child(ore)
		_mesh(ore, _ear(sd, pinta))
	var rabo := Node3D.new()
	rabo.name = "rabo"
	rabo.position = Vector3(-0.8, 1.13, 0)
	corpo.add_child(rabo)
	_mesh(rabo, _tail(pinta))
	for k in 4:
		var front := k < 2
		var side := -1.0 if k % 2 == 0 else 1.0
		var leg := Node3D.new()
		leg.name = ["pata_fe", "pata_fd", "pata_te", "pata_td"][k]
		leg.position = Vector3(0.44 if front else -0.6, 0.98, side * (0.15 if front else 0.16))
		corpo.add_child(leg)
		_mesh(leg, _limb(0.5, 0.12 if front else 0.15, 0.052, pinta, front, true))
		var low := Node3D.new()
		low.name = "baixo"
		low.position = Vector3(0.0 if front else -0.05, -0.5, 0)
		leg.add_child(low)
		_mesh(low, _limb(0.43, 0.05, 0.038, pinta, front, false))
		_mesh(low, _hoof())
	root.scale = Vector3.ONE * s
	return root


static func _mesh(parent: Node3D, m: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material()
	parent.add_child(mi)


## Tubo por anéis: [centro, raio de cima, raio de baixo, raio de lado]; o anel é uma
## elipse com a metade de cima e a de baixo de alturas diferentes (barriga funda).
static func _loft(st: SurfaceTool, rings: Array, segs: int, colf: Callable, eixo := "x") -> void:
	var pts := []
	for r in rings:
		var c: Vector3 = r[0]
		var row := []
		for k in segs + 1:
			var a := TAU * k / segs
			var up := cos(a)
			var ry := float(r[1]) if up >= 0.0 else float(r[2])
			var off: Vector3
			if eixo == "x":
				off = Vector3(0, up * ry, sin(a) * float(r[3]))
			else:
				off = Vector3(up * ry, 0, sin(a) * float(r[3]))
			row.append(c + off)
		pts.append(row)
	for ri in rings.size() - 1:
		for k in segs:
			var q := [pts[ri][k], pts[ri + 1][k], pts[ri + 1][k + 1], pts[ri][k + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = q[idx]
				st.set_color(colf.call(v))
				st.add_vertex(v)


static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


## Corpo: anca com os ossos da garupa, lombo reto, a barriga funda e redonda no meio,
## o peito; o cupim em cima da cernelha; o úbere entre as pernas de trás (vaca).
static func _body(pinta: Callable, touro: bool, ubere: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var n := 34
	for i in n + 1:
		var u := float(i) / n                  # 0 = rabo, 1 = peito
		var x := lerpf(-0.86, 0.74, u)
		var top := 1.23 + 0.05 * u
		# o cupim: parte do lombo, subindo em cima da cernelha
		top += (0.2 if touro else 0.1) * exp(-pow((x - 0.36) / 0.13, 2.0))
		var bot := lerpf(0.8, 0.74, u) - 0.12 * sin(PI * clampf((u - 0.08) / 0.78, 0.0, 1.0))
		var w := 0.21 + 0.09 * sin(PI * clampf(u * 1.05, 0.0, 1.0))
		# as pontas fechando redondas (a garupa atrás, o peito na frente)
		var e := 1.0
		if u < 0.12:
			e = sqrt(sin(PI * 0.5 * u / 0.12))
		elif u > 0.9:
			e = sqrt(cos(PI * 0.5 * (u - 0.9) / 0.1))
		e = maxf(e, 0.03)
		var cy := (top + bot) * 0.5
		if u < 0.12:
			cy = lerpf(1.06, cy, e)            # a ponta de trás fecha no alto (onde nasce o rabo)
		rings.append([Vector3(x, cy, 0), (top - cy) * e, (cy - bot) * e, w * e])
	_loft(st, rings, 26, func(p: Vector3) -> Color: return pinta.call(p, "corpo"))
	if ubere:
		_ellip(st, Vector3(-0.42, 0.68, 0), Vector3(0.12, 0.08, 0.1), func(_p: Vector3) -> Color: return ROSA)
		for k in 4:
			var tp := Vector3(-0.47 + (k / 2) * 0.1, 0.6, (k % 2 - 0.5) * 0.09)
			_cone(st, tp + Vector3(0, 0.03, 0), tp - Vector3(0, 0.05, 0), 0.016, ROSA.darkened(0.1))
	return _commit(st)


## Pescoço, barbela, cabeça comprida, focinho largo e preto, olhos, chifres.
static func _head(pinta: Callable, touro: bool, bezerro: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# pescoço: da base (no peito) para a frente, subindo um pouco
	var rings := []
	for i in 9:
		var u := float(i) / 8.0
		var c := Vector3(u * 0.42, 0.02 + u * 0.06, 0)
		var g := 1.2 if touro else 1.0
		rings.append([c, lerpf(0.24, 0.13, u) * g, lerpf(0.26, 0.14, u) * g, lerpf(0.17, 0.11, u) * g])
	_loft(st, rings, 18, func(p: Vector3) -> Color: return pinta.call(p, "pescoco"))
	# a barbela: pele solta pendurada do pescoço até o peito (bem grande no zebu)
	var bb := 0.24 if touro else 0.16
	for i in 10:
		var u0 := float(i) / 10.0
		var u1 := float(i + 1) / 10.0
		var a0 := Vector3(lerpf(-0.06, 0.42, u0), lerpf(-0.22, -0.08, u0), 0)
		var a1 := Vector3(lerpf(-0.06, 0.42, u1), lerpf(-0.22, -0.08, u1), 0)
		var h0 := bb * sin(PI * clampf(u0 * 1.1, 0.0, 1.0))
		var h1 := bb * sin(PI * clampf(u1 * 1.1, 0.0, 1.0))
		for sd in [-0.012, 0.012]:
			var q := [a0 + Vector3(0, 0, sd), a1 + Vector3(0, 0, sd), a1 + Vector3(0.02, -h1, sd), a0 + Vector3(0.02, -h0, sd)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(pinta.call(q[idx], "pescoco"))
				st.add_vertex(q[idx])
	# cabeça: da nuca ao focinho, comprida e descendo
	var nuca := Vector3(0.46, 0.08, 0)
	var foc := Vector3(0.95, -0.25, 0)
	var d := (foc - nuca).normalized()
	var hr := []
	for i in 11:
		var u := float(i) / 10.0
		var c2 := nuca.lerp(foc, u)
		var ry := lerpf(0.12, 0.075, u) + 0.02 * sin(PI * u)
		var rz := lerpf(0.105, 0.085, u) - 0.025 * sin(PI * clampf(u * 1.4, 0.0, 1.0))
		hr.append([c2, ry, ry * 0.9, rz])
	# o loft ao longo da direção da cabeça
	var ring_pts := []
	for r in hr:
		var c3: Vector3 = r[0]
		var nrm := Vector3(-d.y, d.x, 0)       # "para cima" da cabeça
		var row := []
		for k in 17:
			var a := TAU * k / 16.0
			var up := cos(a)
			var ry2 := float(r[1]) if up >= 0.0 else float(r[2])
			row.append(c3 + nrm * up * ry2 + Vector3(0, 0, sin(a) * float(r[3])))
		ring_pts.append(row)
	for ri in ring_pts.size() - 1:
		var u := float(ri) / 10.0
		for k in 16:
			var q2 := [ring_pts[ri][k], ring_pts[ri + 1][k], ring_pts[ri + 1][k + 1], ring_pts[ri][k + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var col: Color = pinta.call(q2[idx], "pescoco") if u < 0.75 else (pinta.call(q2[idx], "pescoco") as Color).lerp(PRETO, clampf((u - 0.75) / 0.2, 0.0, 1.0))
				st.set_color(col)
				st.add_vertex(q2[idx])
	# o focinho: largo, úmido e preto, com as narinas
	_ellip(st, foc + d * 0.01, Vector3(0.05, 0.075, 0.095), func(_p: Vector3) -> Color: return PRETO)
	for sd in [-1.0, 1.0]:
		_ellip(st, foc + d * 0.045 + Vector3(0, 0.0, sd * 0.04), Vector3(0.012, 0.02, 0.014), func(_p: Vector3) -> Color: return Color(0.02, 0.02, 0.02))
		# olhos grandes dos lados
		var ol := nuca + d * 0.12 + Vector3(0, 0.035, sd * 0.1)
		_ellip(st, ol, Vector3(0.022, 0.02, 0.012), func(_p: Vector3) -> Color: return Color(0.03, 0.025, 0.02))
		# chifres curtos: saem do alto da cabeça, para os lados, curvando para cima e para trás
		if not bezerro:
			var hb := nuca + Vector3(0.0, 0.1, sd * 0.07)
			var L := 0.2 if touro else 0.15
			var h1 := hb + Vector3(-0.02, 0.05, sd * 0.07)
			var h2 := h1 + Vector3(-0.05, L * 0.55, sd * 0.03)
			_cone(st, hb, h1, 0.035 if touro else 0.028, CHIFRE)
			_cone(st, h1, h2, 0.026 if touro else 0.02, CHIFRE.darkened(0.4))
	# a testa e a nuca
	_ellip(st, nuca + Vector3(0.02, 0.06, 0), Vector3(0.1, 0.07, 0.1), func(p: Vector3) -> Color: return pinta.call(p, "pescoco"))
	return _commit(st)


## Orelha comprida e caída (zebu): folha que pende para o lado e para baixo.
static func _ear(sd: float, pinta: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 6
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var w0 := 0.045 * sin(PI * clampf(u0 * 0.9 + 0.1, 0.0, 1.0)) + 0.01
		var w1 := 0.045 * sin(PI * clampf(u1 * 0.9 + 0.1, 0.0, 1.0)) + 0.01
		var c0 := Vector3(0.02 * u0, -0.13 * u0, sd * 0.13 * u0)
		var c1 := Vector3(0.02 * u1, -0.13 * u1, sd * 0.13 * u1)
		var q := [c0 + Vector3(-w0, 0, 0), c1 + Vector3(-w1, 0, 0), c1 + Vector3(w1, 0, 0), c0 + Vector3(w0, 0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(pinta.call(q[idx], "pescoco"))
			st.add_vertex(q[idx])
		# o lado de dentro, mais rosado
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color((pinta.call(q[idx], "pescoco") as Color).lerp(ROSA, 0.35))
			st.add_vertex(q[idx] + Vector3(0, 0, -sd * 0.004))
	return _commit(st)


## Rabo comprido e fino, pendurado, com a vassoura de pelo preto na ponta.
static func _tail(pinta: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var n := 10
	for i in n + 1:
		var u := float(i) / n
		var c := Vector3(-0.04 - 0.05 * u, -u * 0.7, 0)
		var r := lerpf(0.045, 0.018, u)
		rings.append([c, r, r, r])
	_loft(st, rings, 8, func(p: Vector3) -> Color: return pinta.call(p, "corpo"), "y")
	# a vassoura
	for k in 26:
		var a := TAU * k / 26.0
		var b0 := Vector3(-0.09, -0.66, 0)
		var t := b0 + Vector3(cos(a) * 0.035 - 0.01, -0.2 - 0.03 * sin(float(k) * 1.3), sin(a) * 0.035)
		_cone(st, b0, t, 0.012, PRETO)
	return _commit(st)


## Pedaço de perna descendo (pivô em cima): coxa/braço grosso, canela fina.
static func _limb(L: float, r0: float, r1: float, pinta: Callable, front: bool, upper: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for i in 7:
		var u := float(i) / 6.0
		var r := lerpf(r0, r1, pow(u, 0.7 if upper else 1.0))
		# o joelho/jarrete: um pouco mais grosso no fim
		if not upper and u < 0.15:
			r *= 1.25
		var c := Vector3(0, -u * L, 0)
		if upper and not front:
			c.x = -0.05 * sin(PI * u)          # a coxa de trás curva para trás
		# a coxa (atrás) e o braço (na frente) são largos de lado e finos de frente
		var lx := 1.15
		if upper:
			lx = lerpf(1.7 if not front else 1.35, 1.1, u)
		rings.append([c, r * lx, r * lx, r * 0.85])
	_loft(st, rings, 10, func(p: Vector3) -> Color: return pinta.call(p + Vector3(0, 0.5 if upper else 0.0, 0), "perna"), "y")
	return _commit(st)


## Casco preto fendido em dois.
static func _hoof() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sd in [-1.0, 1.0]:
		_ellip(st, Vector3(0.02, -0.455, sd * 0.022), Vector3(0.05, 0.035, 0.022), func(_p: Vector3) -> Color: return CASCO)
	# a quartela (pelo escuro logo em cima do casco)
	_ellip(st, Vector3(0.0, -0.41, 0), Vector3(0.04, 0.04, 0.038), func(_p: Vector3) -> Color: return CASCO.lightened(0.15))
	return _commit(st)


static func _ellip(st: SurfaceTool, c: Vector3, r: Vector3, colf: Callable) -> void:
	var la := 7
	var lo := 12
	for i in la:
		for j in lo:
			var q := []
			for dd in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + dd[0]) / la
				var ph := TAU * float(j + dd[1]) / lo
				q.append(c + Vector3(sin(th) * cos(ph) * r.x, cos(th) * r.y, sin(th) * sin(ph) * r.z))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(colf.call(q[k]))
				st.add_vertex(q[k])


static func _cone(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP)
	if s1.length() < 0.1:
		s1 = d.cross(Vector3.RIGHT)
	s1 = s1.normalized()
	var s2 := d.cross(s1).normalized()
	for k in 7:
		var a0 := TAU * k / 7
		var a1 := TAU * (k + 1) / 7
		for v in [a + (s1 * cos(a0) + s2 * sin(a0)) * r, a + (s1 * cos(a1) + s2 * sin(a1)) * r, b]:
			st.set_color(col)
			st.add_vertex(v)


## A pose de cada quadro: "andar", "correr", "pastar", "deitar", "parado".
## fase: o passo; t: o tempo (rabo, orelhas, mastigar).
static func pose(root: Node3D, modo: String, fase: float, t: float) -> void:
	var corpo: Node3D = root.get_node("corpo")
	var cab: Node3D = corpo.get_node("cabeca")
	var rabo: Node3D = corpo.get_node("rabo")
	var legs := []
	for nm in ["pata_fe", "pata_fd", "pata_te", "pata_td"]:
		legs.append(corpo.get_node(nm))
	var off := [0.0, PI, PI * 0.5, PI * 1.5]       # andar de vaca: as 4 patas uma de cada vez
	corpo.position = Vector3.ZERO
	corpo.rotation = Vector3.ZERO
	cab.rotation = Vector3.ZERO
	for k in 4:
		(legs[k] as Node3D).rotation = Vector3.ZERO
		(legs[k] as Node3D).get_node("baixo").rotation = Vector3.ZERO
	# o rabo espantando mosca e as orelhas mexendo (sempre)
	rabo.rotation = Vector3(sin(t * 1.7) * 0.25 + sin(t * 4.3) * 0.08 * maxf(0.0, sin(t * 0.4)), 0, -0.12)
	for nm in ["orelha_e", "orelha_d"]:
		var o: Node3D = cab.get_node(nm)
		o.rotation = Vector3(0, 0, 0.15 * maxf(0.0, sin(t * 0.9 + (1.0 if nm == "orelha_d" else 0.0)) - 0.7) * 3.0)
	match modo:
		"andar", "correr":
			var amp := 0.32 if modo == "andar" else 0.6
			if modo == "correr":
				off = [0.0, PI, PI, 0.0]            # trote: diagonal
			for k in 4:
				var ph: float = fase + off[k]
				var leg: Node3D = legs[k]
				leg.rotation.z = sin(ph) * amp
				var lift := maxf(0.0, cos(ph))
				# a frente dobra o joelho para trás; atrás o jarrete para a frente
				leg.get_node("baixo").rotation.z = lift * (0.8 if k < 2 else -0.6) * (1.0 if modo == "andar" else 1.4)
			corpo.position.y = absf(sin(fase * (1.0 if modo == "andar" else 2.0))) * (0.015 if modo == "andar" else 0.05)
			cab.rotation.z = -0.2 + sin(fase * 2.0) * 0.05
		"pastar":
			# cabeça lá embaixo, arrancando o capim (o focinho puxa de lado), pastos curtos
			cab.rotation.z = -1.26 + sin(t * 2.3) * 0.03
			cab.rotation.y = sin(t * 0.6) * 0.18 + sin(t * 7.0) * 0.03
			var p2 := fase
			for k in 4:
				var leg2: Node3D = legs[k]
				leg2.rotation.z = sin(p2 + off[k]) * 0.08
			corpo.rotation.z = -0.03
		"deitar":
			# deitada de peito, as patas dobradas debaixo do corpo, ruminando
			corpo.position.y = -0.58
			corpo.rotation.x = 0.06
			for k in 4:
				var leg3: Node3D = legs[k]
				if k < 2:
					leg3.rotation.z = 1.4
					leg3.get_node("baixo").rotation.z = -2.6
				else:
					leg3.rotation.z = -1.3
					leg3.get_node("baixo").rotation.z = 2.4
				leg3.rotation.x = (0.25 if k % 2 == 0 else -0.25)
			cab.rotation.z = 0.08 + sin(t * 0.3) * 0.04
			cab.rotation.y = sin(t * 0.2) * 0.4
			cab.rotation.x = sin(t * 5.0) * 0.015            # mastigando
			corpo.position.y += sin(t * 1.0) * 0.006
		_:
			cab.rotation.z = -0.15 + sin(t * 0.5) * 0.06
			cab.rotation.y = sin(t * 0.35) * 0.3
			cab.rotation.x = sin(t * 4.0) * 0.012             # ruminando em pé
