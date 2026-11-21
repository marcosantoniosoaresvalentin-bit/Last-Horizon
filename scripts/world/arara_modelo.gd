extends Node3D
## Arara-canindé (Ara ararauna) feita em código, pena por pena nas asas e na cauda.
## Por cima: azul-turquesa (asas e cauda azul mais escuro na ponta); por baixo das asas e
## da cauda: amarelo-oliva. Peito, barriga e lados do pescoço amarelo-alaranjados;
## testa verde; rosto de pele branca com linhas de peninhas pretas; babador preto;
## bico preto enorme e curvo. Uns 85 cm do bico à ponta da cauda, 1 m de asa aberta.
## Frente = -Z. Modos: "fly" (bate as asas), "glide" (planando), "perch" (pousada,
## em pé e com as asas fechadas), "chao" (no chão comendo, bicando), "nest" (dentro do
## oco: só a cabeça aparece).

const BLUE := Color(0.05, 0.42, 0.80)
const BLUE_D := Color(0.03, 0.22, 0.55)
const BLUE_TIP := Color(0.03, 0.12, 0.35)
const YELLOW := Color(1.0, 0.72, 0.06)
const UNDER := Color(0.62, 0.55, 0.12)       # amarelo-oliva embaixo das asas e da cauda
const GREEN := Color(0.32, 0.60, 0.16)
const BLACK := Color(0.04, 0.04, 0.05)
const GREY := Color(0.32, 0.32, 0.34)

var mode := "perch"
var flap_speed := 3.4
var _t := 0.0
var _body: Node3D
var _head: Node3D
var _tail: Node3D
var _wings := []
var _hide_in_nest := []
static var _m := {}           # malhas e materiais (iguais para todas)


func _ready() -> void:
	_t = randf() * 10.0
	if _m.is_empty():
		_build_shared()
	_body = Node3D.new()
	add_child(_body)
	var bm := _mi(_body, _m.body, _m.smooth)
	_hide_in_nest.append(bm)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.075, -0.13)
	_body.add_child(_head)
	_mi(_head, _m.head, _m.face_mat)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.0, 0.14)
	_body.add_child(_tail)
	_mi(_tail, _m.tail, _m.feather)
	_hide_in_nest.append(_tail)
	for side in [1.0, -1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.05 * side, 0.045, -0.06)
		_body.add_child(arm)
		_mi(arm, _m.arm_r if side > 0 else _m.arm_l, _m.feather)
		var hand := Node3D.new()
		hand.position = Vector3(0.19 * side, 0, 0.0)
		arm.add_child(hand)
		_mi(hand, _m.hand_r if side > 0 else _m.hand_l, _m.feather)
		_wings.append({"arm": arm, "hand": hand, "side": side})
		_hide_in_nest.append(arm)
		var f := _mi(_body, _m.foot, _m.smooth)
		f.position = Vector3(0.03 * side, -0.075, 0.02)
		_hide_in_nest.append(f)
	_pose()


func _mi(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	_pose()


func _pose() -> void:
	for n in _hide_in_nest:
		n.visible = mode != "nest"
	match mode:
		"nest":
			_body.rotation = Vector3.ZERO
			_head.rotation = Vector3(sin(_t * 0.5) * 0.15, sin(_t * 0.31) * 0.5, 0)
		"fly", "glide":
			_body.rotation = Vector3(0.04, 0, 0)
			_head.rotation = Vector3(-0.08, 0, 0)
			_tail.rotation = Vector3(0.05, 0, 0)
			var ph := _t * TAU * flap_speed
			var flap := sin(ph) * 0.8 + 0.12 if mode == "fly" else 0.1
			var fold := maxf(0.0, cos(ph)) * 0.5 if mode == "fly" else 0.0
			for w in _wings:
				var s: float = w.side
				w.arm.position = Vector3(0.05 * s, 0.045, -0.06)
				w.arm.basis = Basis(Vector3.BACK, flap * s) * Basis(Vector3.UP, 0.05 * s)
				w.hand.basis = Basis(Vector3.BACK, (flap * 0.3 - fold * 0.35) * s) * Basis(Vector3.UP, -fold * 0.45 * s)
		"chao":
			# no chão comendo: corpo mais deitado, cabeça descendo e bicando a semente
			_body.rotation = Vector3(0.45, 0, 0)
			var bica := maxf(0.0, sin(_t * 3.1)) * float(int(_t * 0.4) % 3 != 0)
			_head.rotation = Vector3(0.35 + bica * 0.7, sin(_t * 0.45) * 0.4 * (1.0 - bica), 0)
			_tail.rotation = Vector3(-0.15, 0, 0)
			for w in _wings:
				var s2: float = w.side
				w.arm.position = Vector3(0.045 * s2, 0.065, -0.07)
				w.arm.basis = Basis(Vector3.UP, -1.5 * s2) * Basis(Vector3.RIGHT, -0.7) * Basis().scaled(Vector3(1.0, 1.0, 0.28))
				w.hand.basis = Basis(Vector3.UP, 0.03 * s2) * Basis().scaled(Vector3(1.0, 1.0, 0.3))
		"perch":
			# em pé no galho: corpo inclinado, cauda caída, asas fechadas sobre as costas
			_body.rotation = Vector3(0.95, 0, 0)
			_head.rotation = Vector3(-0.9 + sin(_t * 0.7) * 0.06, sin(_t * 0.37) * 0.6 * float(int(_t * 0.25) % 2), 0)
			_tail.rotation = Vector3(0.1, 0, 0)
			for w in _wings:
				var s: float = w.side
				# asas fechadas deitadas por cima das costas (lado azul para cima e para fora),
				# as primárias cruzando em cima da cauda
				w.arm.position = Vector3(0.045 * s, 0.065, -0.07)
				# (penas recolhidas: a asa fica uma faixa estreita, tudo apontando para trás)
				w.arm.basis = Basis(Vector3.UP, -1.5 * s) * Basis(Vector3.RIGHT, -0.7) * Basis().scaled(Vector3(1.0, 1.0, 0.28))
				w.hand.basis = Basis(Vector3.UP, 0.03 * s) * Basis().scaled(Vector3(1.0, 1.0, 0.3))


# ================== MALHAS ==================

static func _build_shared() -> void:
	var smooth := StandardMaterial3D.new()
	smooth.vertex_color_use_as_albedo = true
	smooth.vertex_color_is_srgb = true
	smooth.roughness = 0.55
	var feather := StandardMaterial3D.new()
	feather.albedo_texture = _feather_tex()
	feather.vertex_color_use_as_albedo = true
	feather.vertex_color_is_srgb = true
	feather.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	feather.alpha_scissor_threshold = 0.45
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	feather.roughness = 0.5
	feather.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var face := StandardMaterial3D.new()          # cabeça: cor por vértice x linhas do rosto
	face.albedo_texture = _face_tex()
	face.vertex_color_use_as_albedo = true
	face.vertex_color_is_srgb = true
	face.roughness = 0.6
	_m = {"smooth": smooth, "feather": feather, "face_mat": face,
		"body": _body_mesh(), "head": _head_mesh(), "tail": _tail_mesh(),
		"arm_r": _arm_mesh(1.0), "arm_l": _arm_mesh(-1.0), "hand_r": _hand_mesh(1.0), "hand_l": _hand_mesh(-1.0),
		"foot": _foot_mesh()}


## Pena: nervura no meio, farpas inclinadas e ponta arredondada (branca: a cor vem
## da cor de cada pena).
static func _feather_tex() -> ImageTexture:
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / (h - 1)                    # 0 base, 1 ponta
		var half := 0.5 * sqrt(clampf((1.0 - t) / 0.12, 0.0, 1.0)) * minf(1.0, 0.55 + t * 2.0)
		half *= 0.92 + 0.08 * sin(t * 40.0)
		for x in w:
			var u := (float(x) + 0.5) / w - 0.5
			var a := clampf((half - absf(u)) * w * 0.7, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
				continue
			var barb := 0.92 + 0.08 * sin((absf(u) * 3.0 + t * 1.0) * 160.0)
			var edge := 1.0 - 0.18 * smoothstep(0.25, 0.5, absf(u) / maxf(half * 2.0, 0.01))
			var c := barb * edge
			if absf(u) < 0.025:
				c *= 0.72                                 # nervura
			img.set_pixel(x, y, Color(c, c, c, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Linhas de peninhas pretas do rosto (o resto é branco: a cor vem da cabeça).
## Mapeada de lado na cabeça: u = frente (0) para trás (1), v = de cima (0) para baixo (1).
static func _face_tex() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	for y in s:
		for x in s:
			var z := lerpf(-0.075, 0.05, float(x) / s)
			var yy := lerpf(0.07, -0.06, float(y) / s)
			# 4 linhas curvas embaixo e na frente do olho (olho em z=-0.028, y=0.022)
			if z > -0.064 and z < -0.006:
				for k in 4:
					var ly := 0.008 - k * 0.0085 - (z + 0.03) * (z + 0.03) * 4.0
					if absf(yy - ly) < 0.0018 and fmod((z + 1.0) * 420.0, 1.0) < 0.62:
						img.set_pixel(x, y, Color(0.06, 0.06, 0.07))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _loft(st: SurfaceTool, rings: Array, cor_fn: Callable, sides := 18, uv_fn := Callable()) -> void:
	var pts := []
	for r in rings:
		var ring := []
		for k in sides:
			var a := float(k) / sides * TAU
			ring.append(Vector3(cos(a) * float(r[1]), float(r[3]) + sin(a) * float(r[2]), float(r[0])))
		pts.append(ring)
	for i in rings.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var q := [pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k]]
			for idx in [0, 2, 1, 0, 3, 2]:
				var p: Vector3 = q[idx]
				var ri := i if idx in [0, 1] else i + 1
				var c := Vector3(0, float(rings[ri][3]), p.z)
				var n := (p - c).normalized()
				st.set_normal(n)
				st.set_color(cor_fn.call(p, n))
				if uv_fn.is_valid():
					st.set_uv(uv_fn.call(p))
				st.add_vertex(p)
	# tampas
	for end in [0, rings.size() - 1]:
		var c := Vector3(0, float(rings[end][3]), float(rings[end][0]))
		for k in sides:
			var k2 := (k + 1) % sides
			var tri := [c, pts[end][k], pts[end][k2]] if end == 0 else [c, pts[end][k2], pts[end][k]]
			for v in tri:
				st.set_normal(Vector3(0, 0, -1 if end == 0 else 1))
				st.set_color(cor_fn.call(v, Vector3(0, 0, -1 if end == 0 else 1)))
				if uv_fn.is_valid():
					st.set_uv(uv_fn.call(v))
				st.add_vertex(v)


static func _body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# pescoço grosso, peito fundo, afinando até a base da cauda
	var rings := [[-0.155, 0.032, 0.035, 0.075], [-0.13, 0.045, 0.05, 0.065], [-0.095, 0.062, 0.07, 0.04],
		[-0.05, 0.072, 0.08, 0.018], [0.0, 0.07, 0.076, 0.008], [0.05, 0.06, 0.062, 0.006], [0.1, 0.042, 0.042, 0.008],
		[0.145, 0.022, 0.02, 0.01]]
	_loft(st, rings, func(p: Vector3, n: Vector3) -> Color:
		var t := smoothstep(-0.3, 0.15, n.y + (0.25 if p.z > 0.06 else 0.0))
		var c := YELLOW.lerp(BLUE, t)
		if p.z < -0.135 and n.y < -0.3:
			c = BLACK.lerp(c, smoothstep(-0.85, -0.5, n.y))    # babador continua no pescoço
		return c)
	return st.commit()


static func _head_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[0.045, 0.026, 0.03, -0.005], [0.03, 0.045, 0.048, 0.003], [0.005, 0.054, 0.058, 0.01],
		[-0.025, 0.052, 0.056, 0.012], [-0.05, 0.042, 0.046, 0.008], [-0.068, 0.028, 0.034, 0.004]]
	var uvf := func(p: Vector3) -> Vector2:
		return Vector2(inverse_lerp(-0.075, 0.05, p.z), inverse_lerp(0.07, -0.06, p.y))
	_loft(st, rings, func(p: Vector3, n: Vector3) -> Color:
		var c := BLUE
		if n.z < -0.98 or (absf(n.x) > 0.42 and p.z < -0.004 and n.y > -0.5 and n.y < 0.45):
			c = Color(0.96, 0.93, 0.9)                             # rosto: pele branca
		elif n.y > 0.3 and p.z < 0.0:
			c = GREEN.lerp(BLUE, smoothstep(-0.02, 0.02, p.z))     # testa verde
		elif n.y < -0.5 and p.z < -0.02:
			c = BLACK                                              # babador (faixa estreita embaixo do bico)
		elif absf(n.x) > 0.5 and n.y < 0.3:
			c = YELLOW.lerp(BLUE, smoothstep(-0.02, 0.03, p.z))    # bochecha atrás do rosto
		return c, 24, uvf)
	# olho: bolinha preta com a íris amarela-clara em volta
	for s in [1.0, -1.0]:
		_ball(st, Vector3(0.047 * s, 0.022, -0.028), 0.0085, Color(0.95, 0.88, 0.55))
		_ball(st, Vector3(0.052 * s, 0.022, -0.029), 0.005, BLACK)
	# bico de cima: grosso, curvado para baixo, a ponta em gancho
	var up := []
	for k in 9:
		var t := float(k) / 8.0
		var a := t * 2.1
		up.append([-0.06 - sin(a) * 0.046, 0.026 - (1.0 - cos(a)) * 0.036, 0.028 * (1.0 - t * 0.85), 0.031 * (1.0 - t * 0.8)])
	for i in up.size() - 1:
		_ring_seg(st, up[i], up[i + 1], Color(0.025, 0.025, 0.03))
	# bico de baixo: menor, largo, encaixado embaixo
	var lo := [[-0.06, -0.02, 0.024, 0.016], [-0.08, -0.025, 0.018, 0.013], [-0.095, -0.03, 0.009, 0.008]]
	for i in lo.size() - 1:
		_ring_seg(st, lo[i], lo[i + 1], Color(0.04, 0.04, 0.045))
	return st.commit()


## Anel [z, y, largura, altura] até o próximo (tubo achatado).
static func _ring_seg(st: SurfaceTool, a: Array, b: Array, col: Color, sides := 10) -> void:
	st.set_uv(Vector2(0.99, 0.01))
	for k in sides:
		var a0 := float(k) / sides * TAU
		var a1 := float(k + 1) / sides * TAU
		var q := [Vector3(cos(a0) * float(a[2]), float(a[1]) + sin(a0) * float(a[3]), float(a[0])),
			Vector3(cos(a1) * float(a[2]), float(a[1]) + sin(a1) * float(a[3]), float(a[0])),
			Vector3(cos(a1) * float(b[2]), float(b[1]) + sin(a1) * float(b[3]), float(b[0])),
			Vector3(cos(a0) * float(b[2]), float(b[1]) + sin(a0) * float(b[3]), float(b[0]))]
		for idx in [0, 2, 1, 0, 3, 2]:
			var ang := a0 if idx in [0, 3] else a1
			st.set_normal(Vector3(cos(ang), sin(ang), 0))
			st.set_color(col)
			st.add_vertex(q[idx])


static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	st.set_uv(Vector2(0.99, 0.01))
	var lat := 5
	var lon := 8
	for i in lat:
		var t0 := float(i) / lat * PI
		var t1 := float(i + 1) / lat * PI
		for j in lon:
			var p0 := float(j) / lon * TAU
			var p1 := float(j + 1) / lon * TAU
			var v := [Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0)), Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1)),
				Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1)), Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(v[idx])
				st.set_color(col)
				st.add_vertex(c + v[idx] * r)


## Uma pena (carta com a textura): da raiz, na direção dir, comprimento L, largura W.
## Duas camadas: por cima a cor de cima, logo embaixo a cor de baixo.
static func _feather(st: SurfaceTool, root: Vector3, dir: Vector3, L: float, W: float, top: Color, under: Color, up := Vector3.UP) -> void:
	var d := dir.normalized()
	var side := d.cross(up).normalized() * W * 0.5
	var nrm := side.cross(d).normalized()
	if nrm.dot(up) < 0.0:
		nrm = -nrm
	for layer in 2:
		var off := -nrm * 0.0025 * layer
		var col := top if layer == 0 else under
		var q := [root - side + off, root + side + off, root + side + d * L + off, root - side + d * L + off]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm if layer == 0 else -nrm)
			st.set_color(col)
			st.set_uv(uv[idx])
			st.add_vertex(q[idx])


static func _tail_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 12 penas em degrau: as do meio compridas (quase meio metro), as de fora curtas
	var order := [5, 6, 4, 7, 3, 8, 2, 9, 1, 10, 0, 11]
	for k in order:
		var c := float(k) - 5.5
		var L := 0.48 - absf(c) * 0.04 - (absf(c) - 0.5) * (absf(c) - 0.5) * 0.004
		var root := Vector3(c * 0.006, 0.004 * absf(c), 0.0)
		var dir := Vector3(c * 0.012, -0.03, 1.0)
		var top := BLUE.lerp(BLUE_TIP, 0.25 + absf(c) * 0.03)
		_feather(st, root, dir, L, 0.05, top, UNDER)
	# coberteiras em cima da base da cauda
	for k in 6:
		var c := float(k) - 2.5
		_feather(st, Vector3(c * 0.012, 0.012, -0.02), Vector3(c * 0.05, 0.02, 1.0), 0.11, 0.045, BLUE, BLUE)
	return st.commit()


## Braço da asa: secundárias (as penas de voo de dentro) e as coberteiras por cima.
static func _arm_mesh(side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.19
	for k in 9:
		var t := (float(k) + 0.5) / 9.0
		var root := Vector3(t * L * side, 0.0, -0.01)
		var dir := Vector3(0.12 * side * t, 0.0, 1.0)
		_feather(st, root, dir, 0.17 - t * 0.01, 0.048, BLUE_D.lerp(BLUE, 0.3), UNDER)
	# coberteiras: duas fileiras mais curtas e mais claras por cima
	for row in 2:
		for k in 8:
			var t := (float(k) + 0.5) / 8.0
			var root := Vector3(t * L * side, 0.006 + row * 0.003, -0.03 - row * 0.012)
			_feather(st, root, Vector3(0.1 * side, 0.0, 1.0), 0.1 - row * 0.03, 0.045, BLUE.lerp(Color(0.1, 0.5, 0.85), row * 0.3), UNDER.lerp(YELLOW, 0.3))
	return st.commit()


## Mão da asa: 10 primárias compridas em leque estreito, a ponta da asa fica fina.
static func _hand_mesh(side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 10:
		var u := float(k) / 9.0                  # 0 = perto do corpo, 1 = ponta da asa
		var root := Vector3((0.01 + u * 0.08) * side, 0.0, -0.015 + (1.0 - u) * 0.01)
		var ang := lerpf(1.25, 0.25, u)          # de dentro: para trás; de fora: para o lado
		var dir := Vector3(cos(ang) * side, 0.0, sin(ang))
		var L := lerpf(0.2, 0.3, sin(u * PI * 0.75))
		_feather(st, root, dir, L, 0.052, BLUE_D.lerp(BLUE_TIP, u * 0.6), UNDER.darkened(0.15))
	# coberteiras da mão
	for k in 5:
		var u := float(k) / 4.0
		_feather(st, Vector3((0.005 + u * 0.06) * side, 0.006, -0.03), Vector3(side * 0.6, 0.0, 0.8), 0.09, 0.045, BLUE, UNDER)
	return st.commit()


static func _foot_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ball(st, Vector3(0, -0.01, 0), 0.012, GREY)
	for d in [Vector3(0.012, -0.03, -0.03), Vector3(-0.012, -0.03, -0.03), Vector3(0.01, -0.03, 0.025), Vector3(-0.01, -0.03, 0.025)]:
		for k in 4:
			_ball(st, d * (float(k + 1) / 4.0), 0.006, GREY)
	return st.commit()
