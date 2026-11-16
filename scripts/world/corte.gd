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


## Pose do golpe, aplicada por cima da animação normal do personagem.
## swing: 0 = parado, 1 = no meio do golpe (a fase vai de 0 a 1 a cada machadada).
class ChopPose extends SkeletonModifier3D:
	var player: Node3D            # para saber para onde o personagem está virado
	var axe: Node3D               # o machado (fica na mão direita)
	var chopping := false
	var phase := 0.0
	var holding := false          # machado equipado
	var _b := {}

	func _bone(n: String) -> int:
		if not _b.has(n):
			_b[n] = get_skeleton().find_bone(n) if get_skeleton() else -1
		return _b[n]

	## Ângulo dos braços (graus, para a frente a partir de pendurado) ao longo de uma machadada.
	static func arm_angle(p: float) -> float:
		if p < 0.55:
			return lerpf(55.0, 170.0, smoothstep(0.0, 1.0, p / 0.55))        # levanta por cima da cabeça
		if p < 0.7:
			var t := (p - 0.55) / 0.15
			return lerpf(170.0, 62.0, t * t)                                  # desce com força
		return lerpf(62.0, 55.0, (p - 0.7) / 0.3)                              # tranco e prepara a próxima

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or player == null:
			return
		var to_skel := sk.global_transform.basis.orthonormalized().inverse()
		var right: Vector3 = (to_skel * player.global_transform.basis.x).normalized()
		var fwd: Vector3 = (to_skel * -player.global_transform.basis.z).normalized()
		if chopping:
			var ang := deg_to_rad(arm_angle(phase))
			# os dois braços juntos, mãos fechando no cabo
			_rotate(sk, "RightArm", right, ang, fwd, -0.32)
			_rotate(sk, "LeftArm", right, ang, fwd, 0.32)
			# o corpo acompanha: estica para trás ao levantar, dobra na pancada
			var bend := 0.0
			if phase < 0.55:
				bend = lerpf(0.1, -0.12, phase / 0.55)
			elif phase < 0.75:
				bend = lerpf(-0.12, 0.32, clampf((phase - 0.55) / 0.15, 0.0, 1.0))
			else:
				bend = lerpf(0.32, 0.1, (phase - 0.75) / 0.25)
			_rotate(sk, "Spine1", right, bend, fwd, 0.0)
		elif holding:
			# carregando o machado: braço direito um pouco à frente
			_rotate(sk, "RightForeArm", right, deg_to_rad(22.0), fwd, 0.0)
		_place_axe(sk, right)

	func _rotate(sk: Skeleton3D, bone: String, axis: Vector3, ang: float, fwd: Vector3, inward: float) -> void:
		var b := _bone(bone)
		if b < 0:
			return
		var g := sk.get_bone_global_pose(b)
		var r := Basis(axis, ang)
		if inward != 0.0:
			r = Basis(fwd, inward) * r
		g.basis = r * g.basis
		sk.set_bone_global_pose(b, g)

	func _place_axe(sk: Skeleton3D, right: Vector3) -> void:
		if axe == null:
			return
		axe.visible = holding or chopping
		if not axe.visible:
			return
		var hand := _bone("RightHand")
		var arm := _bone("RightForeArm")
		if hand < 0 or arm < 0:
			return
		var ph := sk.get_bone_global_pose(hand).origin
		var pa := sk.get_bone_global_pose(arm).origin
		var along := (ph - pa).normalized()
		# o cabo sai da mão um pouco mais à frente que o braço; o fio aponta para onde o golpe vai
		var handle := along.rotated(right, deg_to_rad(30.0)).normalized()
		var edge := handle.rotated(right, deg_to_rad(-90.0)).normalized()
		var x := handle.cross(edge).normalized()
		var basis := Basis(x, handle, edge)
		var grip := ph + along * 0.06
		var gx := sk.global_transform * Transform3D(basis, grip)
		gx.basis = gx.basis.orthonormalized()
		axe.global_transform = gx
