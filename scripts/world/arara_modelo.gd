extends Node3D
## Arara-canindé (Ara ararauna) feita em código: costas e asas azuis, peito e barriga
## amarelo-alaranjados, testa verde, rosto branco com risquinhos pretos, babador preto
## embaixo do bico, bico preto e curvo, cauda comprida azul (amarelada por baixo).
## Uns 85 cm do bico à ponta da cauda e 1 m de asa aberta.
## Frente = -Z. Modos: "fly" (bate as asas), "glide" (asas abertas paradas),
## "perch" (pousada, de pé e com as asas fechadas), "nest" (só a cabeça para fora do oco).

const BLUE := Color(0.06, 0.36, 0.78)
const BLUE_D := Color(0.04, 0.22, 0.52)
const YELLOW := Color(0.98, 0.70, 0.08)
const GREEN := Color(0.30, 0.62, 0.18)
const WHITE := Color(0.93, 0.92, 0.88)
const BLACK := Color(0.05, 0.05, 0.06)
const GREY := Color(0.30, 0.30, 0.32)

var mode := "perch"
var flap_speed := 3.6          # batidas por segundo
var _t := 0.0
var _body: Node3D
var _head: Node3D
var _tail: Node3D
var _wings := []               # [{arm, hand, side}]
var _mat: StandardMaterial3D
var _hide_in_nest := []        # o que some quando ela está dentro do oco
static var _meshes := {}


func _ready() -> void:
	_t = randf() * 10.0
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.6
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _meshes.is_empty():
		_meshes = {"body": _body_mesh(), "head": _head_mesh(), "tail": _tail_mesh(),
			"arm_r": _arm_mesh(1.0), "arm_l": _arm_mesh(-1.0), "hand_r": _hand_mesh(1.0), "hand_l": _hand_mesh(-1.0),
			"foot": _foot_mesh()}
	_body = Node3D.new()
	add_child(_body)
	_add(_body, "body")
	_hide_in_nest.append(_body.get_child(0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.05, -0.15)
	_head.scale = Vector3(1.25, 1.25, 1.25)
	_body.add_child(_head)
	_add(_head, "head")
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.0, 0.16)
	_body.add_child(_tail)
	_add(_tail, "tail")
	_hide_in_nest.append(_tail)
	for side in [1.0, -1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.045 * side, 0.04, -0.07)
		_body.add_child(arm)
		_add(arm, "arm_r" if side > 0 else "arm_l")
		var hand := Node3D.new()
		hand.position = Vector3(0.2 * side, 0, 0.02)
		arm.add_child(hand)
		_add(hand, "hand_r" if side > 0 else "hand_l")
		_wings.append({"arm": arm, "hand": hand, "side": side})
		_hide_in_nest.append(arm)
	for side in [1.0, -1.0]:
		var f := MeshInstance3D.new()
		f.mesh = _meshes.foot
		f.material_override = _mat
		f.position = Vector3(0.03 * side, -0.07, 0.0)
		_body.add_child(f)
		_hide_in_nest.append(f)
	_pose(0.0)


func _add(n: Node3D, key: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = _mat
	n.add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	_pose(delta)


func _pose(_delta: float) -> void:
	for n in _hide_in_nest:
		n.visible = mode != "nest"
	match mode:
		"nest":
			# dentro do oco: só a cabeça aparece na boca, olhando em volta
			_body.rotation = Vector3.ZERO
			_head.rotation = Vector3(sin(_t * 0.5) * 0.15, sin(_t * 0.31) * 0.5, 0)
		"fly", "glide":
			_body.rotation = Vector3(0.05, 0, 0)
			_head.rotation = Vector3(-0.05, 0, 0)
			_tail.rotation = Vector3(0.06, 0, 0)
			var ph := _t * TAU * flap_speed
			# batida: desce forte, sobe dobrando a mão; planando fica aberta, um pouco para cima
			var flap := sin(ph) * 0.85 + 0.15 if mode == "fly" else 0.12
			var fold := maxf(0.0, cos(ph)) * 0.55 if mode == "fly" else 0.0
			for w in _wings:
				var s: float = w.side
				w.arm.position.x = 0.045 * s
				w.arm.basis = Basis(Vector3.BACK, flap * s) * Basis(Vector3.UP, 0.08 * s)
				w.hand.basis = Basis(Vector3.BACK, (flap * 0.35 - fold * 0.4) * s) * Basis(Vector3.UP, -fold * 0.5 * s)
		"perch":
			# pousada: corpo em pé, cauda para baixo, asas fechadas encostadas no corpo
			_body.rotation = Vector3(0.95, 0, 0)
			_head.rotation = Vector3(-0.85 + sin(_t * 0.7) * 0.06, sin(_t * 0.37) * 0.6 * float(int(_t * 0.25) % 2), 0)
			_tail.rotation = Vector3(0.12, 0, 0)
			for w in _wings:
				var s: float = w.side
				# braço apontando para trás, asa em pé encostada no lado do corpo
				w.arm.basis = Basis(Vector3.UP, -1.42 * s) * Basis(Vector3.RIGHT, 1.4)
				w.arm.position.x = 0.068 * s
				w.hand.basis = Basis(Vector3.UP, -0.12 * s).scaled(Vector3(1.0, 1.0, 0.4))   # penas recolhidas


# ================== MALHAS ==================

## Tubo deformado ao longo de Z: anéis [z, largura, altura, y], com a cor de cada vértice
## escolhida por cor_fn(p, n).
static func _loft(st: SurfaceTool, rings: Array, cor_fn: Callable, sides := 12) -> void:
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
				var ring_i := i if idx in [0, 1] else i + 1
				var c := Vector3(0, float(rings[ring_i][3]), p.z)
				var n := (p - c).normalized()
				st.set_normal(n)
				st.set_color(cor_fn.call(p, n))
				st.add_vertex(p)


func _body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[-0.17, 0.02, 0.025, 0.04], [-0.14, 0.05, 0.055, 0.035], [-0.08, 0.072, 0.075, 0.02],
		[0.0, 0.07, 0.075, 0.0], [0.08, 0.055, 0.055, 0.0], [0.15, 0.03, 0.03, 0.01], [0.18, 0.012, 0.012, 0.012]]
	_loft(st, rings, func(p: Vector3, n: Vector3) -> Color:
		# costas azuis, peito e barriga amarelos (a linha entre os dois é um pouco embaixo do meio)
		var t := smoothstep(-0.35, 0.05, n.y)
		var c := YELLOW.lerp(BLUE, t)
		if p.z > 0.12:
			c = c.lerp(BLUE_D, 0.6)      # sobre a cauda
		return c)
	return st.commit()


func _head_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[0.05, 0.02, 0.025, 0.0], [0.03, 0.04, 0.045, 0.01], [-0.0, 0.048, 0.052, 0.015],
		[-0.035, 0.045, 0.05, 0.015], [-0.06, 0.035, 0.04, 0.012], [-0.075, 0.02, 0.025, 0.012]]
	_loft(st, rings, func(p: Vector3, n: Vector3) -> Color:
		var c := BLUE
		if n.y > 0.35 and p.z < -0.02:
			c = GREEN                                  # testa verde
		elif absf(n.x) > 0.55 and p.z < 0.0 and n.y > -0.4:
			# rosto branco (pele nua) com risquinhos pretos de penas
			c = WHITE
			if int(floor((p.y + 0.05) * 140.0)) % 3 == 0 and p.z < -0.03:
				c = BLACK
			if p.z > -0.035 and p.z < -0.02 and n.y > 0.05 and n.y < 0.35:
				c = Color(0.85, 0.75, 0.2)             # olho (íris amarela)
		elif n.y < -0.4 and p.z < -0.01:
			c = BLACK                                  # babador preto embaixo do bico
		return c)
	# bico: grande, preto, curvado para baixo (de cima) e a parte de baixo menor
	var beak := []
	for k in 7:
		var t := float(k) / 6.0
		var z := -0.07 - t * 0.055
		var y := 0.005 - t * t * 0.055
		var w := 0.022 * (1.0 - t * 0.85)
		beak.append([z, w, w * 1.15, y])
	for i in beak.size() - 1:
		_cone_seg(st, beak[i], beak[i + 1], BLACK)
	_cone_seg(st, [-0.07, 0.016, 0.012, -0.025], [-0.1, 0.006, 0.006, -0.035], Color(0.12, 0.12, 0.13))
	return st.commit()


static func _cone_seg(st: SurfaceTool, a: Array, b: Array, col: Color, sides := 8) -> void:
	for k in sides:
		var a0 := float(k) / sides * TAU
		var a1 := float(k + 1) / sides * TAU
		var q := [Vector3(cos(a0) * float(a[1]), float(a[3]) + sin(a0) * float(a[2]), float(a[0])),
			Vector3(cos(a1) * float(a[1]), float(a[3]) + sin(a1) * float(a[2]), float(a[0])),
			Vector3(cos(a1) * float(b[1]), float(b[3]) + sin(a1) * float(b[2]), float(b[0])),
			Vector3(cos(a0) * float(b[1]), float(b[3]) + sin(a0) * float(b[2]), float(b[0]))]
		for idx in [0, 2, 1, 0, 3, 2]:
			var ang := a0 if idx in [0, 3] else a1
			st.set_normal(Vector3(cos(ang), sin(ang), 0))
			st.set_color(col)
			st.add_vertex(q[idx])


func _tail_mesh() -> ArrayMesh:
	# penas compridas e estreitas, em leque fechado; ponta fina
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in 5:
		var off := (float(f) - 2.0) * 0.012
		var L := 0.46 - absf(float(f) - 2.0) * 0.06
		var pts := []
		for k in 9:
			var t := float(k) / 8.0
			var w := 0.028 * (1.0 - t * 0.75) + 0.004
			pts.append([Vector3(off - w, -0.004 * f + t * t * -0.02, t * L), Vector3(off + w, -0.004 * f + t * t * -0.02, t * L)])
		for k in 8:
			var q := [pts[k][0], pts[k][1], pts[k + 1][1], pts[k + 1][0]]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.UP)
				# por cima azul, ficando mais escura na ponta; por baixo o material mostra o mesmo
				var t := float(k) / 8.0
				st.set_color(BLUE.lerp(BLUE_D, t * 0.7) if f != 2 else BLUE.lerp(Color(0.1, 0.3, 0.6), t))
				st.add_vertex(q[idx])
	return st.commit()


## Braço da asa (parte de dentro): sai do ombro para o lado (+X na direita).
func _arm_mesh(side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.2
	var n := 6
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var c0 := 0.17 - t0 * 0.03
		var c1 := 0.17 - t1 * 0.03
		var q := [Vector3(t0 * L * side, 0, -0.04), Vector3(t1 * L * side, 0, -0.04),
			Vector3(t1 * L * side, -0.004, c1 - 0.04), Vector3(t0 * L * side, -0.004, c0 - 0.04)]
		for idx in [0, 2, 1, 0, 3, 2]:
			var p: Vector3 = q[idx]
			st.set_normal(Vector3.UP)
			# frente da asa (coberteiras) azul-clara; atrás as penas de voo mais escuras
			var back := clampf((p.z + 0.04) / 0.15, 0.0, 1.0)
			st.set_color(BLUE.lerp(BLUE_D, back * 0.8))
			st.add_vertex(p)
	return st.commit()


## Mão da asa: as penas primárias compridas, com as pontas separadas ("dedos").
func _hand_mesh(side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# base coberta
	var base := [Vector3(0, 0, -0.04), Vector3(0.1 * side, 0, -0.035), Vector3(0.1 * side, -0.003, 0.08), Vector3(0, -0.003, 0.1)]
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_color(BLUE)
		st.add_vertex(base[idx])
	# 7 primárias em leque, a de fora mais curta
	for f in 7:
		var u := float(f) / 6.0
		var root := Vector3((0.05 + u * 0.05) * side, -0.002, -0.03 + u * 0.12)
		var ang := lerpf(-0.1, 0.55, u)
		var dir := Vector3(cos(ang) * side, 0, sin(ang)).normalized()
		var L := lerpf(0.25, 0.14, u * u)
		var w := 0.034
		var perp := Vector3(-dir.z * side, 0, dir.x * side) * side
		var q := [root - perp * w, root + perp * w, root + dir * L + perp * w * 0.4, root + dir * L - perp * w * 0.4]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_color(BLUE_D.lerp(Color(0.08, 0.12, 0.25), 0.4))
			st.add_vertex(q[idx])
	return st.commit()


func _foot_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone_seg(st, [0.0, 0.009, 0.009, 0.0], [0.0, 0.008, 0.008, -0.04], GREY)
	# dois dedos para a frente e dois para trás (pé de papagaio)
	for d in [Vector3(0.012, -0.045, -0.035), Vector3(-0.012, -0.045, -0.035), Vector3(0.01, -0.045, 0.03), Vector3(-0.01, -0.045, 0.03)]:
		_cone_seg(st, [-0.0, 0.005, 0.005, -0.04], [d.z, 0.003, 0.003, d.y], GREY, 5)
	return st.commit()
