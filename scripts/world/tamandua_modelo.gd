extends RefCounted
## Tamanduá-bandeira feito de malha (sem arquivo de modelo): focinho comprido em tubo,
## cabeça pequena de orelhas redondas, corpo fundo de pelo grosso cinza-pardo, a faixa
## preta de borda branca que desce do peito e sobe pelo ombro até o meio das costas,
## as patas da frente claras com a pulseira preta e as unhas grandes dobradas para dentro
## (anda apoiado nos nós dos dedos), e o rabo enorme de pelo comprido (bandeira).
##
## O bicho olha para +X. Peças com pivô para animar:
##   corpo / cabeca (pivô no pescoço) / lingua (dentro da cabeça) / rabo (pivô na base)
##   pata_fe, pata_fd, pata_te, pata_td (pivô no ombro/quadril), cada uma com "baixo"
##   (pivô no cotovelo/joelho).

const GREY := Color(0.36, 0.33, 0.29)
const DARK := Color(0.03, 0.025, 0.02)
const CREAM := Color(0.8, 0.76, 0.66)

static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 1.0
		_mat.metallic_specular = 0.05
		# pelo grosso: fios deitados ao longo do corpo (projeção nos 3 eixos, sem UV)
		_mat.albedo_texture = _load_tex("res://texturas/pelo_tamandua.imagem", Color(0.8, 0.8, 0.8))
		_mat.normal_enabled = true
		_mat.normal_texture = _load_tex("res://texturas/pelo_tamandua_n.imagem", Color(0.5, 0.5, 1.0))
		_mat.normal_scale = 1.2
		_mat.uv1_triplanar = true
		_mat.uv1_triplanar_sharpness = 4.0
		_mat.uv1_scale = Vector3(2.4, 2.4, 2.4)
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


## Monta o bicho. s = tamanho (1 adulto, uns 0,4 o filhote recém-nascido).
static func build(s: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "tamandua"
	var corpo := Node3D.new()
	corpo.name = "corpo"
	corpo.position = Vector3(0, 0.0, 0)
	root.add_child(corpo)
	_mesh(corpo, _body())
	# cabeça e focinho (pivô na frente do ombro)
	var cab := Node3D.new()
	cab.name = "cabeca"
	cab.position = Vector3(0.42, 0.55, 0)
	corpo.add_child(cab)
	_mesh(cab, _head())
	var lin := Node3D.new()
	lin.name = "lingua"
	lin.position = Vector3(0.6, -0.13, 0)
	cab.add_child(lin)
	_mesh(lin, _tongue())
	lin.scale = Vector3(0.01, 1, 1)
	# rabo
	var rabo := Node3D.new()
	rabo.name = "rabo"
	rabo.position = Vector3(-0.46, 0.5, 0)
	corpo.add_child(rabo)
	_mesh(rabo, _tail())
	# patas
	for k in 4:
		var front := k < 2
		var side := -1.0 if k % 2 == 0 else 1.0
		var leg := Node3D.new()
		leg.name = ["pata_fe", "pata_fd", "pata_te", "pata_td"][k]
		leg.position = Vector3(0.3 if front else -0.34, 0.5, side * 0.12)
		corpo.add_child(leg)
		var up_len := 0.23
		_mesh(leg, _limb(up_len, 0.105 if front else 0.11, 0.08 if front else 0.075, GREY if front else GREY.darkened(0.2), front, true))
		var low := Node3D.new()
		low.name = "baixo"
		low.position = Vector3(0, -up_len, 0)
		leg.add_child(low)
		_mesh(low, _limb(0.22, 0.075 if front else 0.065, 0.055 if front else 0.045, CREAM if front else DARK.lightened(0.1), front, false))
		_mesh(low, _foot(front, side))
	root.scale = Vector3.ONE * s
	return root


static func _mesh(parent: Node3D, m: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material()
	parent.add_child(mi)


## Anel de uma peça em tubo: centro c, raios ry (alto) e rz (largo), cor por ângulo.
static func _loft(st: SurfaceTool, rings: Array, segs: int, colf: Callable, vertical := false) -> void:
	var pts := []
	for ri in rings.size():
		var r: Array = rings[ri]
		var c: Vector3 = r[0]
		var row := []
		for k in segs + 1:
			var a := TAU * k / segs
			var off := Vector3(cos(a) * float(r[1]), 0, sin(a) * float(r[2])) if vertical else Vector3(0, cos(a) * float(r[1]), sin(a) * float(r[2]))
			row.append([c + off, a])
		pts.append(row)
	for ri in rings.size() - 1:
		for k in segs:
			var q := [pts[ri][k], pts[ri + 1][k], pts[ri + 1][k + 1], pts[ri][k + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Array = q[idx]
				st.set_color(colf.call(v[0], v[1]))
				st.add_vertex(v[0])


static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


## Corpo: anca baixa, peito fundo, a corcunda de pelo no ombro; a faixa preta.
static func _body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var n := 30
	for i in n + 1:
		var u := float(i) / n                 # 0 = anca, 1 = pescoço
		var x := lerpf(-0.52, 0.48, u)
		var ry := 0.2 * sin(PI * clampf(u * 0.92 + 0.08, 0.0, 1.0)) + 0.06 + 0.06 * u
		var rz := 0.17 * sin(PI * clampf(u * 0.9 + 0.1, 0.0, 1.0)) + 0.05
		if u > 0.85:
			ry *= lerpf(1.0, 0.62, (u - 0.85) / 0.15)
			rz *= lerpf(1.0, 0.7, (u - 0.85) / 0.15)
		var cy := 0.5 + 0.03 * u
		rings.append([Vector3(x, cy, 0), ry, rz])
	var colf := func(p: Vector3, a: float) -> Color:
		var h := cos(a)                    # 1 em cima, -1 embaixo
		# a faixa: sai do peito (embaixo, na frente) e sobe para trás pelo ombro,
		# afinando até o meio das costas; borda branca do lado de trás e de cima
		var hu := (h + 1.0) * 0.5
		var xc := lerpf(0.4, -0.12, hu)
		var w := lerpf(0.13, 0.045, hu)
		var d := p.x - xc
		if h > -0.85 and h < 0.985:
			if absf(d) < w:
				return DARK
			if d < 0.0 and d > -w - 0.035:
				return CREAM
		var g := GREY.darkened(0.1 + 0.15 * clampf(-h, 0.0, 1.0))
		return g
	_loft(st, rings, 28, colf)
	# crina: pelo comprido em pé ao longo do lombo
	for i in 44:
		var x := lerpf(-0.45, 0.36, float(i) / 43.0)
		var u := (x + 0.52) / 1.0
		var top := 0.5 + 0.03 * u + 0.2 * sin(PI * clampf(u * 0.92 + 0.08, 0.0, 1.0)) + 0.06 + 0.06 * u
		var hl := 0.07 + 0.04 * sin(float(i) * 1.7)
		for sd in [-1.0, 1.0]:
			var b0 := Vector3(x - 0.016, top - 0.02, sd * 0.02)
			var b1 := Vector3(x + 0.016, top - 0.02, sd * 0.02)
			var t := Vector3(x - 0.06, top + hl, sd * 0.05)
			for v in [b0, b1, t]:
				st.set_color(GREY.darkened(0.3))
				st.add_vertex(v)
	# franja de pelo comprido pendurada embaixo da barriga e no peito
	for i in 52:
		var u := float(i) / 51.0
		var x := lerpf(-0.42, 0.38, u)
		var uu := (x + 0.52) / 1.0
		var ry := 0.2 * sin(PI * clampf(uu * 0.92 + 0.08, 0.0, 1.0)) + 0.06 + 0.06 * uu
		var rz := 0.17 * sin(PI * clampf(uu * 0.9 + 0.1, 0.0, 1.0)) + 0.05
		var cy := 0.5 + 0.03 * uu
		for sd in [-1.0, 1.0]:
			var b0 := Vector3(x - 0.017, cy - ry * 0.75, sd * rz * 0.6)
			var b1 := Vector3(x + 0.017, cy - ry * 0.75, sd * rz * 0.6)
			var t := Vector3(x - 0.05, cy - ry - 0.05 - 0.02 * sin(float(i) * 2.3), sd * rz * 0.75)
			for v in [b0, b1, t]:
				st.set_color(GREY.darkened(0.25))
				st.add_vertex(v)
	return _commit(st)


## Cabeça comprida virando focinho fino, um pouco curvo para baixo; orelhas e olhos.
static func _head() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var n := 12
	for i in n + 1:
		var u := float(i) / n
		var x := u * 0.62
		var r := lerpf(0.085, 0.022, pow(u, 0.6))
		var y := -0.12 * u * u
		rings.append([Vector3(x, y, 0), r, r * 0.92])
	var colf := func(p: Vector3, _a: float) -> Color:
		return GREY.lerp(DARK, clampf((p.x - 0.25) / 0.4, 0.0, 1.0))
	_loft(st, rings, 12, colf)
	# ponta fechada
	var tip: Array = rings[n]
	_ball(st, tip[0] + Vector3(0.008, 0, 0), 0.022, DARK)
	# olhos pequenos
	for sd in [-1.0, 1.0]:
		_ball(st, Vector3(0.11, 0.035, sd * 0.07), 0.011, Color(0.02, 0.02, 0.02))
		# orelha redondinha
		var e := Vector3(0.03, 0.08, sd * 0.06)
		var f := [e, e + Vector3(-0.03, 0.045, sd * 0.01), e + Vector3(0.025, 0.04, sd * 0.012)]
		for v in f:
			st.set_color(GREY.darkened(0.15))
			st.add_vertex(v)
	return _commit(st)


static func _tongue() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for i in 7:
		var u := float(i) / 6.0
		rings.append([Vector3(u * 0.35, -0.04 * u * u, 0), lerpf(0.008, 0.003, u), lerpf(0.008, 0.003, u)])
	_loft(st, rings, 6, func(_p: Vector3, _a: float) -> Color: return Color(0.75, 0.32, 0.38))
	return _commit(st)


## Rabo bandeira: largo no alto e embaixo (pelo comprido), fino de lado; franja embaixo.
static func _tail() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var n := 10
	for i in n + 1:
		var u := float(i) / n
		var x := -u * 0.75
		var ry := 0.05 + 0.1 * sin(PI * clampf(u * 0.8 + 0.2, 0.0, 1.0))
		var rz := lerpf(0.05, 0.025, u)
		rings.append([Vector3(x, -0.06 * u - 0.05 * ry, 0), ry, rz])
	var colf := func(p: Vector3, a: float) -> Color:
		return GREY.darkened(0.25 + 0.15 * clampf(-cos(a), 0.0, 1.0))
	_loft(st, rings, 10, colf)
	# franja de pelo comprido pendurada
	for i in 36:
		var u := float(i) / 35.0
		var x := -u * 0.72
		var ry := 0.05 + 0.1 * sin(PI * clampf(u * 0.8 + 0.2, 0.0, 1.0))
		var y0 := -0.06 * u - 0.05 * ry - ry * 0.9
		for v in [Vector3(x + 0.015, y0 + 0.02, 0), Vector3(x - 0.015, y0 + 0.02, 0), Vector3(x - 0.04, y0 - 0.06, 0)]:
			st.set_color(GREY.darkened(0.4))
			st.add_vertex(v)
	return _commit(st)


## Pedaço de perna descendo (pivô em cima). Na frente embaixo: a pulseira preta.
static func _limb(L: float, r0: float, r1: float, col: Color, front: bool, upper: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for i in 6:
		var u := float(i) / 5.0
		rings.append([Vector3(0, -u * L, 0), lerpf(r0, r1, u), lerpf(r0, r1, u) * 0.85])
	var colf := func(p: Vector3, _a: float) -> Color:
		if front and not upper and p.y < -L * 0.62 and p.y > -L * 0.85:
			return DARK                         # a "pulseira" preta do pulso
		return col
	_loft(st, rings, 8, colf, true)
	return _commit(st)


## Pé: na frente, o punho fechado com as unhas grandes dobradas para dentro;
## atrás, a sola chata.
static func _foot(front: bool, side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if front:
		_ball(st, Vector3(0.015, -0.235, 0), 0.05, CREAM.darkened(0.1))
		for k in 2:
			var b := Vector3(0.03, -0.24, (k - 0.5) * 0.035)
			var t := b + Vector3(0.01, -0.02, -side * 0.06)
			_cone(st, b, t, 0.012, Color(0.85, 0.8, 0.7).darkened(0.3))
	else:
		for v in [Vector3(-0.04, -0.235, -0.045), Vector3(0.1, -0.235, -0.04), Vector3(0.1, -0.235, 0.04),
				Vector3(-0.04, -0.235, -0.045), Vector3(0.1, -0.235, 0.04), Vector3(-0.04, -0.235, 0.045)]:
			st.set_color(DARK)
			st.add_vertex(v)
		_ball(st, Vector3(0.03, -0.215, 0), 0.045, DARK.lightened(0.05))
	return _commit(st)


static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var la := 5
	var lo := 8
	for i in la:
		for j in lo:
			var q := []
			for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + d[0]) / la
				var ph := TAU * float(j + d[1]) / lo
				q.append(c + Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * r)
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.add_vertex(q[k])


static func _cone(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP)
	if s1.length() < 0.1:
		s1 = d.cross(Vector3.RIGHT)
	s1 = s1.normalized()
	var s2 := d.cross(s1).normalized()
	for k in 6:
		var a0 := TAU * k / 6
		var a1 := TAU * (k + 1) / 6
		for v in [a + (s1 * cos(a0) + s2 * sin(a0)) * r, a + (s1 * cos(a1) + s2 * sin(a1)) * r, b]:
			st.set_color(col)
			st.add_vertex(v)


## Pose de cada quadro. st: {modo: "andar"|"comer"|"dormir"|"defesa"|"parado",
## fase (passo), t (tempo), k (0-1 o quanto já está na pose)}
static func pose(root: Node3D, modo: String, fase: float, t: float) -> void:
	var corpo: Node3D = root.get_node("corpo")
	var cab: Node3D = corpo.get_node("cabeca")
	var rabo: Node3D = corpo.get_node("rabo")
	var lin: Node3D = cab.get_node("lingua")
	var legs := []
	for nm in ["pata_fe", "pata_fd", "pata_te", "pata_td"]:
		legs.append(corpo.get_node(nm))
	var off := [0.0, PI, PI, 0.0]          # diagonal: frente-esq com trás-dir
	corpo.position = Vector3.ZERO
	corpo.rotation = Vector3.ZERO
	cab.rotation = Vector3.ZERO
	rabo.rotation = Vector3.ZERO
	lin.scale = Vector3(0.01, 1, 1)
	for k in 4:
		(legs[k] as Node3D).rotation = Vector3.ZERO
		(legs[k] as Node3D).get_node("baixo").rotation = Vector3.ZERO
	match modo:
		"andar", "correr":
			var amp := 0.45 if modo == "andar" else 0.75
			for k in 4:
				var ph: float = fase + off[k]
				var leg: Node3D = legs[k]
				leg.rotation.z = sin(ph) * amp
				var lift := maxf(0.0, cos(ph))
				leg.get_node("baixo").rotation.z = (lift * 0.7) * (1.0 if k < 2 else -1.0)
			corpo.position.y = absf(sin(fase)) * 0.02
			corpo.rotation.x = sin(fase) * 0.03
			# focinho perto do chão, cheirando de um lado para o outro
			cab.rotation.z = -0.55 + sin(t * 1.3) * 0.08
			cab.rotation.y = sin(t * 0.9) * 0.25
			rabo.rotation.z = 0.1 + sin(fase) * 0.05
			rabo.rotation.y = sin(fase * 0.5) * 0.12
		"comer":
			# focinho enfiado no buraco, a pata da frente cavando, a língua entrando e saindo
			cab.rotation.z = -0.95 + sin(t * 2.0) * 0.04
			lin.scale = Vector3(0.2 + 0.8 * absf(sin(t * 9.0)), 1, 1)
			var dig: Node3D = legs[1]
			dig.rotation.z = 0.5 + sin(t * 6.0) * 0.45
			dig.get_node("baixo").rotation.z = 0.6 + sin(t * 6.0 + 1.0) * 0.4
			corpo.rotation.z = -0.08
			rabo.rotation.z = 0.05
		"dormir":
			# deitado de barriga, patas dobradas, cabeça enfiada do lado e o rabo
			# trazido para a frente por cima do corpo, como um cobertor
			corpo.position.y = -0.3
			cab.rotation.y = 1.3
			cab.rotation.z = -0.7
			for k in 4:
				var leg: Node3D = legs[k]
				leg.rotation.z = 1.35 if k < 2 else -1.35
				leg.get_node("baixo").rotation.z = -1.2 if k < 2 else 1.2
			rabo.rotation.y = -2.7
			rabo.rotation.x = 0.5
			rabo.rotation.z = 0.25
			corpo.position.y += sin(t * 1.1) * 0.006      # respirando
		"defesa":
			# em pé nas patas de trás, braços abertos com as unhas para a frente
			corpo.rotation.z = 0.95
			corpo.position = Vector3(0.25, 0.44, 0)
			for k in 2:
				var leg: Node3D = legs[k]
				leg.rotation.z = 1.2 + sin(t * 3.0) * 0.15
				leg.rotation.x = (-0.5 if k == 0 else 0.5)
				leg.get_node("baixo").rotation.z = 0.9
			for k in [2, 3]:
				(legs[k] as Node3D).rotation.z = -0.95
				(legs[k] as Node3D).get_node("baixo").rotation.z = -0.3
			cab.rotation.z = -0.6
			rabo.rotation.z = -0.8
		_:
			cab.rotation.z = -0.35 + sin(t * 0.7) * 0.1
			cab.rotation.y = sin(t * 0.5) * 0.3
			rabo.rotation.z = 0.05
	if modo != "dormir":
		rabo.position.y = 0.5
