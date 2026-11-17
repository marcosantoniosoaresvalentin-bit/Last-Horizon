extends RefCounted
## Machado na mão e a animação de cortar árvore.
##
## O personagem só tem animações de parado/andando/correndo, então o golpe do
## machado é feito em código: depois da animação normal, os dois braços levantam
## o machado por cima da cabeça e descem com força no tronco.


## Modelo 3D do machado de pedra, como os antigos: um galho como cabo, uma pedra
## lascada encaixada perto da ponta e amarrada com cipó (voltas em cima e embaixo
## da pedra e cruzando por cima dela). O cabo vai de y = 0 (ponta de baixo) até
## 0,64 m; a pedra fica perto de y = 0,52 e o fio aponta para +Z.
static func axe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_haft(st, rng)
	_stone(st, rng)
	_lashing(st, rng)
	st.generate_normals()
	return st.commit()


## Cabo: galho torto com casca, nós e a ponta cortada clara.
static func _haft(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var rings := 18
	var sides := 9
	var top_y := 0.64
	var pts := []
	for i in rings + 1:
		var t := float(i) / rings
		var y := t * top_y
		# curvinha natural do galho
		var c := Vector3(sin(t * 2.6) * 0.012 - 0.006, y, cos(t * 1.9) * 0.006)
		var r := lerpf(0.019, 0.016, t)
		if absf(t - 0.33) < 0.04:
			r += 0.004       # um nó no galho
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			var bump := rng.randf_range(-0.0015, 0.0015)
			ring.append(c + Vector3(cos(a), 0, sin(a)) * (r + bump))
		pts.append(ring)
	for i in rings:
		for k in sides:
			var k2 := (k + 1) % sides
			var shade := rng.randf_range(0.92, 1.06)
			var bark := Color(0.2, 0.13, 0.075) * shade
			if (k + i) % 5 == 0:
				bark = Color(0.13, 0.09, 0.05)   # fissura escura da casca
			bark.a = 1.0
			_quad(st, pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k], bark)
	# pontas cortadas (madeira clara)
	var wood := Color(0.6, 0.46, 0.28)
	for end in [0, rings]:
		var ring: Array = pts[end]
		var c := Vector3.ZERO
		for p in ring:
			c += p
		c /= ring.size()
		for k in sides:
			var k2 := (k + 1) % sides
			st.set_color(wood)
			if end == 0:
				st.add_vertex(c); st.add_vertex(ring[k]); st.add_vertex(ring[k2])
			else:
				st.add_vertex(c); st.add_vertex(ring[k2]); st.add_vertex(ring[k])


## Pedra lascada: grossa atrás, afinando até o fio; facetas irregulares de lascamento.
static func _stone(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var cy := 0.52
	var cols := 7      # de trás (z = -0.045) até o fio (z = 0.16)
	var rows := 6      # ao longo da altura
	var grid := []
	for i in cols + 1:
		var u := float(i) / cols
		var z := lerpf(-0.045, 0.16, u)
		# formato de gota: nuca estreita e arredondada, fio largo
		var half_h := lerpf(0.028, 0.07, pow(u, 0.7)) + sin(u * PI) * 0.006
		var thick := lerpf(0.026, 0.002, pow(u, 0.8))  # afina até o fio
		var col := []
		for j in rows + 1:
			var v := float(j) / rows * 2.0 - 1.0
			var y := cy + v * half_h * (1.0 - 0.18 * u * v * v) + rng.randf_range(-0.003, 0.003)
			var bulge := thick * (1.0 - 0.55 * v * v)
			var jit := rng.randf_range(-0.006, 0.006) * (1.0 - u * 0.7)
			# fio curvo (mais para fora no meio) e nuca arredondada
			var zz := z - 0.028 * v * v * u - 0.02 * v * v * (1.0 - u) * (1.0 - u)
			col.append([Vector3(bulge + jit, y, zz + rng.randf_range(-0.003, 0.003) * (1.0 - u)),
				Vector3(-bulge - jit * 0.7, y, zz + rng.randf_range(-0.003, 0.003) * (1.0 - u))])
		grid.append(col)
	var base := Color(0.13, 0.135, 0.12)      # basalto escuro, meio esverdeado
	for side in 2:
		for i in cols:
			for j in rows:
				var a: Vector3 = grid[i][j][side]
				var b: Vector3 = grid[i + 1][j][side]
				var c: Vector3 = grid[i + 1][j + 1][side]
				var d: Vector3 = grid[i][j + 1][side]
				# cada lasca com um tom; perto do fio a pedra é mais clara (gasta de amolar)
				var tone := rng.randf_range(0.85, 1.15)
				var col := base * tone
				if rng.randf() < 0.25:
					col = col.lerp(Color(0.2, 0.15, 0.1), 0.5)   # manchas de ferrugem da pedra
				col = col.lerp(Color(0.3, 0.3, 0.28), smoothstep(0.65, 1.0, float(i) / cols))
				col.a = 1.0
				if side == 0:
					_quad(st, a, b, c, d, col)
				else:
					_quad(st, d, c, b, a, col)
	# bordas: em cima, embaixo, a nuca e o fio
	var edge_c := Color(0.34, 0.34, 0.31)
	for i in cols:
		for j in [0, rows]:
			var a0: Vector3 = grid[i][j][0]
			var a1: Vector3 = grid[i][j][1]
			var b0: Vector3 = grid[i + 1][j][0]
			var b1: Vector3 = grid[i + 1][j][1]
			if j == 0:
				_quad(st, a1, b1, b0, a0, base * 0.9)
			else:
				_quad(st, a0, b0, b1, a1, base * 0.9)
	for j in rows:
		var n0: Vector3 = grid[0][j][0]
		var n1: Vector3 = grid[0][j][1]
		var m0: Vector3 = grid[0][j + 1][0]
		var m1: Vector3 = grid[0][j + 1][1]
		_quad(st, n0, m0, m1, n1, base * 0.85)
		var e0: Vector3 = grid[cols][j][0]
		var e1: Vector3 = grid[cols][j][1]
		var f0: Vector3 = grid[cols][j + 1][0]
		var f1: Vector3 = grid[cols][j + 1][1]
		_quad(st, e1, f1, f0, e0, edge_c)


## Amarração de cipó: voltas apertadas no cabo, embaixo e em cima da pedra, e um
## "X" cruzando por cima da pedra dos dois lados.
static func _lashing(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var vine := Color(0.17, 0.19, 0.08)
	var r := 0.0042
	# voltas embaixo da pedra
	_helix(st, 0.455, 0.478, 0.0225, 3.2, r, vine, rng)
	# voltas em cima da pedra
	_helix(st, 0.565, 0.588, 0.021, 3.0, r, vine.darkened(0.08), rng)
	# o "X" por cima da pedra, dos dois lados
	for sx in [1.0, -1.0]:
		var x: float = sx * 0.03
		var path1 := [Vector3(x * 0.8, 0.47, -0.022), Vector3(x, 0.50, 0.0), Vector3(x * 0.95, 0.535, 0.022), Vector3(x * 0.8, 0.572, 0.012)]
		var path2 := [Vector3(x * 0.8, 0.47, 0.016), Vector3(x, 0.505, 0.022), Vector3(x * 0.95, 0.54, 0.0), Vector3(x * 0.8, 0.572, -0.02)]
		_tube(st, path1, r, vine.lightened(0.05), rng)
		_tube(st, path2, r, vine, rng)
	# pontinha do cipó solta, depois do nó
	_tube(st, [Vector3(0.02, 0.45, 0.012), Vector3(0.03, 0.43, 0.03), Vector3(0.028, 0.415, 0.05)], r * 0.8, vine.darkened(0.15), rng)


static func _helix(st: SurfaceTool, y0: float, y1: float, rad: float, turns: float, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var path := []
	var n := int(turns * 12)
	for i in n + 1:
		var t := float(i) / n
		var a := t * turns * TAU
		path.append(Vector3(cos(a) * rad - 0.004, lerpf(y0, y1, t), sin(a) * rad * 1.15))
	_tube(st, path, r, col, rng)


## Tubo seguindo um caminho (o cipó).
static func _tube(st: SurfaceTool, path: Array, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var sides := 5
	var rings := []
	for i in path.size():
		var p: Vector3 = path[i]
		var d: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var a := d.cross(Vector3.UP)
		if a.length() < 0.1:
			a = d.cross(Vector3.RIGHT)
		a = a.normalized()
		var b := d.cross(a).normalized()
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(p + (a * cos(ang) + b * sin(ang)) * r)
		rings.append(ring)
	for i in rings.size() - 1:
		var c := col * rng.randf_range(0.85, 1.12)
		c.a = 1.0
		for k in sides:
			var k2 := (k + 1) % sides
			_quad(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2], c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


static func axe_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Pose do machado, aplicada por cima da animação normal do personagem.
##  - carregando: o machado na mão direita, mão fechada no cabo, apontando para baixo.
##  - golpe: as duas mãos fechadas no cabo; o machado vai para trás do ombro direito
##    e vem de lado, na horizontal, batendo na lateral do tronco.
## Os braços são colocados com cinemática inversa (ombro, cotovelo e pulso), para as
## mãos ficarem exatamente em cima do cabo.
class ChopPose extends SkeletonModifier3D:
	const SWING_TIME := 0.8       # segundos por machadada
	const HIT_AT := 0.55          # momento da machadada em que a lâmina bate no tronco
	const GRIP_LOW := 0.03        # mão esquerda: bem na ponta do cabo (só no golpe)
	const GRIP_HIGH := 0.115      # mão direita: quase na ponta, deixando lugar para a esquerda
	var player: Node3D            # para saber para onde o personagem está virado
	var axe: Node3D               # o machado
	var holding := false          # machado equipado
	var swinging := false         # dando uma machadada agora
	var ready_pose := false            # duas mãos no cabo, esperando o próximo toque
	var phase := 0.0
	var _b := {}

	func _bone(n: String) -> int:
		if not _b.has(n):
			_b[n] = get_skeleton().find_bone(n) if get_skeleton() else -1
		return _b[n]

	## Ângulo do golpe (graus): 0 = machado apontando para a frente (no tronco);
	## negativo = para o lado direito/trás (preparando).
	static func swing_angle(p: float) -> float:
		if p < 0.4:
			return lerpf(-25.0, -118.0, smoothstep(0.0, 1.0, p / 0.4))   # leva o machado para trás do ombro
		if p < HIT_AT:
			var t := (p - 0.4) / (HIT_AT - 0.4)
			return lerpf(-118.0, 0.0, t * t)                              # vem com força, de lado
		if p < 0.65:
			return lerpf(0.0, -9.0, (p - HIT_AT) / (0.65 - HIT_AT))       # tranco da batida
		return lerpf(-9.0, -25.0, smoothstep(0.0, 1.0, (p - 0.65) / 0.35))

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or player == null:
			return
		if axe:
			axe.visible = holding
		if not holding:
			return
		var to_skel := sk.global_transform.affine_inverse()
		var tb := to_skel.basis
		var up: Vector3 = (tb * Vector3.UP).normalized()
		var fwd: Vector3 = (tb * -player.global_transform.basis.z).normalized()
		var right: Vector3 = (tb * player.global_transform.basis.x).normalized()
		if swinging or ready_pose:
			_two_hands(sk, up, fwd, right, swing_angle(phase) if swinging else -25.0)
		else:
			_carry(sk, up, fwd, right)
		_close_fingers(sk, "Right")
		if swinging or ready_pose:
			_close_fingers(sk, "Left")

	# ---------- carregando com uma mão ----------
	func _carry(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3) -> void:
		var hb := _bone("RightHand")
		if hb < 0:
			return
		# antebraço um pouco dobrado, como quem segura peso
		_rot_global(sk, "RightForeArm", right, deg_to_rad(20.0))
		var hand := sk.get_bone_global_pose(hb)
		# cabo apontando para baixo e um pouco para a frente; o fio para a frente
		var handle := (fwd * 0.72 - up * 0.69).normalized()
		# o fio do machado virado para baixo
		var edge := (-up - handle * (-up).dot(handle)).normalized()
		# a mão fecha em volta do cabo: o cabo atravessa a palma (eixo X da mão)
		var palm := right.cross(handle).normalized()      # palma virada para dentro
		_set_hand(sk, hb, handle, palm)
		hand = sk.get_bone_global_pose(hb)
		var grip := _grip_point(hand)
		_place_axe(sk, grip - handle * GRIP_HIGH, handle, edge)

	# ---------- golpe com as duas mãos ----------
	func _two_hands(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3, ang_deg: float) -> void:
		var a := deg_to_rad(ang_deg)
		# direção do cabo: horizontal, girando em volta do corpo (levemente para baixo na batida)
		var dir := (fwd * cos(a) - right * sin(a)).normalized()
		var lift := 0.18 * clampf(-ang_deg / 118.0, 0.0, 1.0)
		dir = (dir + up * (lift - 0.12)).normalized()
		# para onde a lâmina vai (o fio aponta para o lado do movimento)
		var edge := (-fwd * sin(a) - right * cos(a)).normalized()
		edge = (edge - dir * edge.dot(dir)).normalized()
		var chest := up * (1.08 + lift * 0.6) + fwd * 0.08
		var base := chest + (fwd * cos(a * 0.75) - right * sin(a * 0.75)).normalized() * 0.2 - right * 0.04
		# o tronco gira junto com o machado
		_rot_global(sk, "Spine1", up, a * 0.22)
		_rot_global(sk, "Spine2", up, a * 0.12)
		# mão direita mais perto da cabeça, esquerda na ponta; palmas uma de cada lado
		var r_grip := base + dir * GRIP_HIGH
		var l_grip := base + dir * GRIP_LOW
		_hand_on(sk, "Right", r_grip, dir, edge, up, right)
		_hand_on(sk, "Left", l_grip, -dir, -edge, up, -right)
		_place_axe(sk, base, dir, edge)

	## Põe uma mão fechada no cabo: braço por cinemática inversa até o pulso certo.
	func _hand_on(sk: Skeleton3D, side: String, grip: Vector3, along: Vector3, palm: Vector3, up: Vector3, out: Vector3) -> void:
		var hb := _bone(side + "Hand")
		if hb < 0:
			return
		var basis := _hand_basis(side, along, palm)
		# do pulso até o meio da mão fechada
		var wrist := grip - basis.y * 0.075 - basis.z * 0.03
		var sh := sk.get_bone_global_pose(_bone(side + "Arm")).origin
		var pole := sh - up * 0.8 + out * 0.5
		_ik(sk, side + "Arm", side + "ForeArm", side + "Hand", wrist, pole)
		var g := sk.get_bone_global_pose(hb)
		g.basis = basis.scaled(g.basis.get_scale())
		sk.set_bone_global_pose(hb, g)

	## Orientação da mão segurando o cabo: o cabo atravessa a palma pelo eixo X
	## (na mão direita o X vai do mindinho para o indicador; na esquerda é o contrário).
	func _hand_basis(side: String, along: Vector3, palm: Vector3) -> Basis:
		var x := along if side == "Right" else -along
		var z := (palm - x * palm.dot(x)).normalized()
		var y := z.cross(x).normalized()
		return Basis(x, y, z)

	func _set_hand(sk: Skeleton3D, hb: int, handle: Vector3, palm: Vector3) -> void:
		var g := sk.get_bone_global_pose(hb)
		g.basis = _hand_basis("Right", handle, palm).scaled(g.basis.get_scale())
		sk.set_bone_global_pose(hb, g)

	func _grip_point(hand: Transform3D) -> Vector3:
		var b := hand.basis.orthonormalized()
		return hand.origin + b.y * 0.075 + b.z * 0.03

	## Cinemática inversa de dois ossos (ombro-cotovelo-pulso).
	func _ik(sk: Skeleton3D, upper: String, lower: String, end: String, target: Vector3, pole: Vector3) -> void:
		var ub := _bone(upper)
		var lb := _bone(lower)
		var eb := _bone(end)
		if ub < 0 or lb < 0 or eb < 0:
			return
		var gu := sk.get_bone_global_pose(ub)
		var gl := sk.get_bone_global_pose(lb)
		var ge := sk.get_bone_global_pose(eb)
		var s := gu.origin
		var la := (gl.origin - s).length()
		var lb_len := (ge.origin - gl.origin).length()
		var to_t := target - s
		var d := clampf(to_t.length(), 0.05, la + lb_len - 0.002)
		var dir := to_t.normalized()
		var cos_a := clampf((la * la + d * d - lb_len * lb_len) / (2.0 * la * d), -1.0, 1.0)
		var sin_a := sqrt(1.0 - cos_a * cos_a)
		var pd := pole - s
		pd = (pd - dir * pd.dot(dir))
		if pd.length() < 0.001:
			pd = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
		pd = pd.normalized()
		var elbow := s + (dir * cos_a + pd * sin_a) * la
		var q1 := Quaternion((gl.origin - s).normalized(), (elbow - s).normalized())
		gu.basis = Basis(q1) * gu.basis
		sk.set_bone_global_pose(ub, gu)
		gl = sk.get_bone_global_pose(lb)
		ge = sk.get_bone_global_pose(eb)
		var tgt := s + dir * d
		var q2 := Quaternion((ge.origin - gl.origin).normalized(), (tgt - gl.origin).normalized())
		gl.basis = Basis(q2) * gl.basis
		sk.set_bone_global_pose(lb, gl)

	func _rot_global(sk: Skeleton3D, bone: String, axis: Vector3, ang: float) -> void:
		var b := _bone(bone)
		if b < 0:
			return
		var g := sk.get_bone_global_pose(b)
		g.basis = Basis(axis, ang) * g.basis
		sk.set_bone_global_pose(b, g)

	## Dedos fechados em volta do cabo (cada falange dobra no próprio eixo X).
	func _close_fingers(sk: Skeleton3D, side: String) -> void:
		for f in ["Index", "Middle", "Ring", "Pinky"]:
			var angs := [1.15, 1.35, 0.9]
			for k in 3:
				var b := _bone("%sHand%s%d" % [side, f, k + 1])
				if b < 0:
					continue
				sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(Vector3.RIGHT, angs[k]))
		for k in 3:
			var b := _bone("%sHandThumb%d" % [side, k + 1])
			if b < 0:
				continue
			sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(Vector3.RIGHT, [0.35, 0.5, 0.4][k]))

	## Machado: base do cabo em "base", cabo apontando para "handle", fio para "edge"
	## (tudo no espaço do esqueleto).
	func _place_axe(sk: Skeleton3D, base: Vector3, handle: Vector3, edge: Vector3) -> void:
		if axe == null:
			return
		var y := handle.normalized()
		var z := (edge - y * edge.dot(y)).normalized()
		var x := y.cross(z).normalized()
		var gx := sk.global_transform * Transform3D(Basis(x, y, z), base)
		gx.basis = gx.basis.orthonormalized()
		axe.global_transform = gx

	## Onde a lâmina está (no mundo): para mostrar as lascas e o corte no tronco.
	func blade_point() -> Vector3:
		if axe == null:
			return Vector3.ZERO
		return axe.global_transform * Vector3(0, 0.52, 0.16)
