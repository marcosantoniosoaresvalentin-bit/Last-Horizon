extends RefCounted
## Machado na mão e a animação de cortar árvore.
##
## O personagem só tem animações de parado/andando/correndo, então o golpe do
## machado é feito em código: depois da animação normal, os dois braços levantam
## o machado por cima da cabeça e descem com força no tronco.


## Modelo 3D do machado de pedra: cabo de madeira (+Y a partir da mão) e cabeça
## de pedra lascada amarrada com cipó. O fio da lâmina aponta para +Z.
static func axe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# cabo: um pouco abaixo da mão até 0,62 m
	_box(st, Vector3(0, 0.23, 0), Vector3(0.032, 0.62, 0.032), Color(0.45, 0.29, 0.16))
	# cabeça de pedra: grossa atrás, afinando para o fio
	var stone := Color(0.46, 0.46, 0.44)
	_box(st, Vector3(0, 0.5, 0.02), Vector3(0.05, 0.12, 0.09), stone)
	_box(st, Vector3(0, 0.5, 0.1), Vector3(0.03, 0.15, 0.09), stone.lightened(0.12))
	_box(st, Vector3(0, 0.5, 0.16), Vector3(0.012, 0.17, 0.04), Color(0.68, 0.68, 0.64))
	# amarração de cipó
	_box(st, Vector3(0, 0.44, 0.0), Vector3(0.045, 0.025, 0.045), Color(0.4, 0.36, 0.16))
	_box(st, Vector3(0, 0.56, 0.0), Vector3(0.045, 0.025, 0.045), Color(0.4, 0.36, 0.16))
	st.generate_normals()
	return st.commit()


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	st.set_color(col)
	for f in faces:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var o := c + n * h
		var pa := a * h
		var pb := b * h
		var p0 := o - pa - pb
		var p1 := o + pa - pb
		var p2 := o + pa + pb
		var p3 := o - pa + pb
		for p in [p0, p2, p1, p0, p3, p2]:
			st.add_vertex(p)


static func axe_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
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
	const GRIP_LOW := 0.02        # mão esquerda: na ponta do cabo
	const GRIP_HIGH := 0.2        # mão direita: mais perto da cabeça do machado
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
		var edge := (fwd - handle * fwd.dot(handle)).normalized()
		# a mão fecha em volta do cabo: o cabo atravessa a palma (eixo X da mão)
		var palm := right.cross(handle).normalized()      # palma virada para dentro
		_set_hand(sk, hb, handle, palm)
		hand = sk.get_bone_global_pose(hb)
		var grip := _grip_point(hand)
		_place_axe(sk, grip - handle * 0.3, handle, edge)

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
		return axe.global_transform * Vector3(0, 0.5, 0.17)
