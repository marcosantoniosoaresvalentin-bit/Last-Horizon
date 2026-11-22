extends RefCounted
## Vaca: o modelo "Cow" do Farm Animal Pack de Quaternius (CC0, personagem/vaca.glbin),
## com o esqueleto e as animações dele (parada, andando, andando devagar, correndo,
## morrendo). O jogo carrega na hora com GLTFDocument (chega pela atualização).
## Cada vaca ganha a sua cor (branca, cinza, vermelha, parda ou malhada) e o pelo curto
## (textura em projeção nos 3 eixos). Para pastar, o pescoço e a cabeça descem até o chão
## (os ossos são dobrados por cima da animação).
##
## A vaca olha para +X (como os outros bichos do jogo).

const ALTURA := 1.45             # altura da cabeça em pé (m), adulta
const ANIMS := {"parado": "Armature|Idle", "andar": "Armature|WalkSlow", "andar_rapido": "Armature|Walk",
	"correr": "Armature|Run", "morrer": "Armature|Death"}

const CORES := {
	"branca": [Color(0.8, 0.78, 0.74), Color(0.5, 0.5, 0.49), Color(0.72, 0.5, 0.48)],
	"cinza": [Color(0.6, 0.6, 0.58), Color(0.4, 0.4, 0.4), Color(0.6, 0.45, 0.43)],
	"vermelha": [Color(0.34, 0.16, 0.085), Color(0.22, 0.1, 0.055), Color(0.5, 0.33, 0.3)],
	"parda": [Color(0.36, 0.27, 0.19), Color(0.24, 0.17, 0.12), Color(0.52, 0.36, 0.32)],
	"malhada": [Color(0.86, 0.85, 0.82), Color(0.09, 0.085, 0.08), Color(0.8, 0.46, 0.5)],
}

static var _tpl: Node3D = null
static var _escala := 1.0
static var _mats := {}
static var _pelo: Texture2D
static var _pelo_n: Texture2D


static func _template() -> Node3D:
	if _tpl != null:
		return _tpl
	var bytes := FileAccess.get_file_as_bytes("res://personagem/vaca.glbin")
	if bytes.is_empty():
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_buffer(bytes, "", st) != OK:
		return null
	_tpl = doc.generate_scene(st)
	# o tamanho: a altura do modelo vira ALTURA
	var mi: MeshInstance3D = _tpl.find_children("*", "MeshInstance3D", true, false)[0]
	var arm: Node3D = mi.get_parent().get_parent()
	var bb: AABB = mi.get_aabb()
	var alto: float = (arm.transform * bb).size.y
	_escala = ALTURA / maxf(alto, 0.001)
	_suaviza(mi)
	for ap in _tpl.find_children("*", "AnimationPlayer", true, false):
		for n in (ap as AnimationPlayer).get_animation_list():
			if not n.ends_with("Death") and not n.ends_with("Jump"):
				(ap as AnimationPlayer).get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return _tpl


## As faces retas viram superfície lisa: a normal de cada canto é a média das faces que
## se encontram ali (no mesmo lugar), dentro de cada parte da malha.
static func _suaviza(mi: MeshInstance3D) -> void:
	var src: ArrayMesh = mi.mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if nr.size() != vs.size():
			return
		var soma := {}
		var ntri := idx.size() / 3 if not idx.is_empty() else vs.size() / 3
		for f in ntri:
			var i0 := idx[f * 3] if not idx.is_empty() else f * 3
			var i1 := idx[f * 3 + 1] if not idx.is_empty() else f * 3 + 1
			var i2 := idx[f * 3 + 2] if not idx.is_empty() else f * 3 + 2
			var fn := (vs[i2] - vs[i0]).cross(vs[i1] - vs[i0])
			for i in [i0, i1, i2]:
				var key := (vs[i] * 100000.0).round()
				soma[key] = (soma.get(key, Vector3.ZERO) as Vector3) + fn
		for i in vs.size():
			var key2 := (vs[i] * 100000.0).round()
			var nn: Vector3 = soma.get(key2, nr[i])
			if nn.length() > 1e-12:
				nn = nn.normalized()
				if nn.dot(nr[i]) < 0.0:
					nn = -nn                       # (mesmo lado da original)
				nr[i] = nn
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_TANGENT] = null
		var flags: int = src.surface_get_format(si) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		out.surface_set_material(si, src.surface_get_material(si))
	mi.mesh = out


static func _textura(path: String, fallback: Color) -> Texture2D:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(fallback)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## O material de uma parte (0 o pelo claro, 1 as manchas/cascos, 2 o focinho e o úbere).
static func _material(cor: String, parte: int, touro: bool) -> StandardMaterial3D:
	var key := "%s_%d_%s" % [cor, parte, touro]
	if _mats.has(key):
		return _mats[key]
	if _pelo == null:
		_pelo = _textura("res://texturas/pelo_vaca.imagem", Color(0.92, 0.92, 0.92))
		_pelo_n = _textura("res://texturas/pelo_vaca_n.imagem", Color(0.5, 0.5, 1.0))
	var c: Array = CORES.get(cor, CORES.branca)
	var col: Color = c[mini(parte, 2)]
	if touro and parte < 2 and cor != "malhada":
		col = col.darkened(0.18)                  # o touro é mais escuro
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.82 if parte < 2 else 0.55
	m.metallic_specular = 0.15
	if parte < 2:
		m.albedo_texture = _pelo
		m.normal_enabled = true
		m.normal_texture = _pelo_n
		m.normal_scale = 0.7
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3(120.0, 120.0, 120.0)   # (o modelo é pequeno por dentro: escala 1 = 1 cm)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Monta a vaca. s = tamanho (1 adulta; uns 0,45 o bezerro novo), cor (CORES), touro.
static func build(s := 1.0, cor := "branca", touro := false, _seed := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "vaca"
	var tpl := _template()
	if tpl == null:
		return root
	var m: Node3D = tpl.duplicate()
	m.name = "modelo"
	m.rotation.y = PI * 0.5                    # o modelo olha para +Z; o jogo usa +X
	m.scale = Vector3.ONE * _escala
	root.add_child(m)
	var mi: MeshInstance3D = m.find_children("*", "MeshInstance3D", true, false)[0]
	if touro:
		mi.mesh = _malha_boi(mi.mesh)               # sem o úbere
	for k in mi.mesh.get_surface_count():
		mi.set_surface_override_material(k, _material(cor, k, touro))
	var sk0: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + 13
	var bezerro := s < 0.7
	# o cupim: grande no boi; nas vacas pequeno ou nenhum
	var cup := 0.0
	if touro:
		cup = rng.randf_range(1.35, 1.65)
	elif not bezerro and rng.randf() < 0.55:
		cup = rng.randf_range(0.3, 0.55)
	if cup > 0.0:
		_preso(sk0, "Body", _cupim_mesh(cup), _material(cor, 1 if cor != "malhada" else 0, touro), Vector3(0, -0.0125, 0.0418 + 0.0015 * cup))
	# os chifres: sem, pequenos, grandes, ou um menor que o outro (quebrado)
	if not bezerro:
		var tipo := rng.randi() % 4 if not touro else 1 + rng.randi() % 3
		if tipo > 0:
			var tam := rng.randf_range(0.35, 0.55) if tipo == 1 else rng.randf_range(0.85, 1.25)
			var tam_d := tam
			var tam_e := tam
			if tipo == 3:
				tam = rng.randf_range(0.6, 1.1)
				tam_d = tam
				tam_e = tam * rng.randf_range(0.2, 0.45)          # um chifre só, o outro quebrado/pequeno
				if rng.randf() < 0.5:
					var tt := tam_d
					tam_d = tam_e
					tam_e = tt
			var curva := rng.randf_range(-0.4, 0.6)
			for sd in [-1.0, 1.0]:
				var tm: float = tam_d if sd > 0.0 else tam_e
				_preso(sk0, "Head", _chifre_mesh(tm, sd, curva), _mat_chifre(), Vector3(sd * 0.0034, -0.0405, 0.0492))
	# o boi: o saco entre as pernas de trás e o prepúcio na barriga
	if touro:
		var pele := _material(cor, 0 if cor != "malhada" else 1, true)
		_preso(sk0, "Body", _saco_mesh(), pele, Vector3(0, 0.0255, 0.0222))
		_preso(sk0, "Body", _prepucio_mesh(), pele, Vector3(0, 0.009, 0.0206))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.play(ANIMS.parado)
	ap.seek(randf() * 3.0, true)
	root.set_meta("ap", ap)
	root.set_meta("sk", m.find_children("*", "Skeleton3D", true, false)[0])
	root.set_meta("t0", -1.0)
	root.set_meta("anim", "parado")
	root.set_meta("baixa", 0.0)
	root.scale = Vector3.ONE * s
	return root


## A malha do boi: a mesma, sem os triângulos do úbere (a parte cor-de-rosa de trás).
static var _boi_mesh: ArrayMesh = null

static func _malha_boi(src: Mesh) -> ArrayMesh:
	if _boi_mesh != null:
		return _boi_mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(si)
		if si == 2:
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if not idx.is_empty():
				var novo := PackedInt32Array()
				for f in idx.size() / 3:
					var c := (vs[idx[f * 3]] + vs[idx[f * 3 + 1]] + vs[idx[f * 3 + 2]]) / 3.0
					if c.y > -0.02:
						continue                          # o úbere (o focinho fica)
					novo.append_array([idx[f * 3], idx[f * 3 + 1], idx[f * 3 + 2]])
				arr[Mesh.ARRAY_INDEX] = novo
		var flags: int = src.surface_get_format(si) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		out.surface_set_material(si, src.surface_get_material(si))
	_boi_mesh = out
	return out


## Prende uma malha num osso (segue a animação); pos em coordenadas do esqueleto.
static func _preso(sk: Skeleton3D, osso: String, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var bi := sk.find_bone(osso)
	if bi < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = osso
	sk.add_child(ba)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	ba.add_child(mi)
	mi.transform = sk.get_bone_global_rest(bi).affine_inverse() * Transform3D(Basis(), pos)


static var _chifre_mat: StandardMaterial3D

static func _mat_chifre() -> StandardMaterial3D:
	if _chifre_mat == null:
		_chifre_mat = StandardMaterial3D.new()
		_chifre_mat.vertex_color_use_as_albedo = true
		_chifre_mat.roughness = 0.6
	return _chifre_mat


## Malha de poucas faces (combina com o modelo): anéis ao longo de uma linha.
static func _tubo(st: SurfaceTool, pts: Array, raios: Array, cores: Array, lados := 6) -> void:
	var rows := []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var d: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var a := d.cross(Vector3(0.3, 0.2, 1.0).normalized()).normalized()
		var b := d.cross(a).normalized()
		var row := []
		for k in lados:
			var t := TAU * k / lados
			row.append(p + (a * cos(t) + b * sin(t)) * float(raios[i]))
		rows.append(row)
	for i in pts.size() - 1:
		for k in lados:
			var q := [rows[i][k], rows[i + 1][k], rows[i + 1][(k + 1) % lados], rows[i][(k + 1) % lados]]
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_color(cores[i] if j in [0, 3] else cores[i + 1])
				st.add_vertex(q[j])


static func _bola(st: SurfaceTool, c: Vector3, r: Vector3, la := 5, lo := 8) -> void:
	for i in la:
		for j in lo:
			var q := []
			for dd in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + dd[0]) / la
				var ph := TAU * float(j + dd[1]) / lo
				q.append(c + Vector3(sin(th) * cos(ph) * r.x, sin(th) * sin(ph) * r.y, cos(th) * r.z))
			for k in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(q[k])


## O cupim: a corcova em cima da cernelha (alto na frente, caindo para trás).
static func _cupim_mesh(f: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bola(st, Vector3(0, 0.0005, 0.0005 * f), Vector3(0.0042, 0.0072, 0.0068 * f), 5, 10)
	_bola(st, Vector3(0, 0.005, -0.0005), Vector3(0.0036, 0.0055, 0.0035 * f), 4, 8)
	st.generate_normals()
	return st.commit()


## Um chifre: sai do lado da cabeça, vai para fora e curva para cima (curva > 0 para a
## frente, < 0 para trás); base clara e ponta escura.
static func _chifre_mesh(tam: float, sd: float, curva: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.014 * tam
	var pts := []
	var rs := []
	var cs := []
	var n := 6
	for i in n + 1:
		var u := float(i) / n
		var p := Vector3(sd * L * (0.15 + 0.85 * sin(u * PI * 0.5)), -L * curva * u * u * 0.6, L * 0.9 * u * u)
		pts.append(p)
		rs.append(lerpf(0.0016 * (0.6 + 0.4 * tam), 0.0002, pow(u, 0.8)))
		cs.append(Color(0.78, 0.72, 0.6).lerp(Color(0.12, 0.1, 0.08), clampf((u - 0.45) / 0.55, 0.0, 1.0)))
	_tubo(st, pts, rs, cs, 6)
	st.generate_normals()
	return st.commit()


## Volume de pele saindo do corpo (faces retas, igual ao modelo): anéis de cima (dentro
## do corpo) para baixo. aneis: [[centro, meia largura x, meio comprimento y], ...]
static func _volume(aneis: Array, lados := 7) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)          # faces retas (low poly)
	var rows := []
	for r in aneis:
		var c: Vector3 = r[0]
		var row := []
		for k in lados:
			var t := TAU * (float(k) + 0.5) / lados
			row.append(c + Vector3(cos(t) * float(r[1]), sin(t) * float(r[2]), 0))
		rows.append(row)
	for i in rows.size() - 1:
		for k in lados:
			var q := [rows[i][k], rows[i + 1][k], rows[i + 1][(k + 1) % lados], rows[i][(k + 1) % lados]]
			for j in [0, 2, 1, 0, 3, 2]:          # (faces viradas para fora)
				st.add_vertex(q[j])
	# fecha embaixo
	var last: Array = rows[rows.size() - 1]
	var fundo: Vector3 = (aneis[aneis.size() - 1][0] as Vector3) + Vector3(0, 0, -0.0004)
	for k in lados:
		for v in [last[k], last[(k + 1) % lados], fundo]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## O saco: um volume pequeno e redondo entre as coxas, colado no corpo.
static func _saco_mesh() -> ArrayMesh:
	return _volume([
		[Vector3(0, 0, 0.0015), 0.0016, 0.0018],
		[Vector3(0, -0.0002, -0.0012), 0.0021, 0.0022],
		[Vector3(0, -0.0004, -0.0032), 0.0019, 0.0020],
		[Vector3(0, -0.0005, -0.0045), 0.0010, 0.0011],
	], 7)


## A bainha (o "umbigo" do zebu): a barriga desce num volume liso de pele, largo onde
## gruda e arredondado embaixo, com a ponta um pouco para a frente. Fica no fim da
## barriga, antes das coxas.
static func _prepucio_mesh() -> ArrayMesh:
	return _volume([
		[Vector3(0, 0, 0.0018), 0.0030, 0.0080],
		[Vector3(0, -0.0008, -0.0006), 0.0030, 0.0068],
		[Vector3(0, -0.0018, -0.0024), 0.0024, 0.0045],
		[Vector3(0, -0.0026, -0.0036), 0.0016, 0.0026],
		[Vector3(0, -0.0030, -0.0042), 0.0008, 0.0012],
	], 8)


## A pose de cada quadro: "andar", "correr", "pastar", "deitar", "parado".
## fase: o passo (não usado: a animação anda sozinha); t: o tempo.
static func pose(root: Node3D, modo: String, _fase: float, t: float) -> void:
	if not root.has_meta("ap"):
		return
	var ap: AnimationPlayer = root.get_meta("ap")
	var sk: Skeleton3D = root.get_meta("sk")
	var t0 := float(root.get_meta("t0"))
	var dt := clampf(t - t0, 0.0, 0.2) if t0 >= 0.0 else 0.0
	root.set_meta("t0", t)
	# a animação de cada modo
	var anim := "parado"
	var vel := 1.0
	match modo:
		"andar":
			anim = "andar"
		"correr":
			anim = "correr"
			vel = 1.1
		"pastar":
			# pastando: passinhos bem devagar, cabeça no chão
			anim = "andar"
			vel = 0.35
		"deitar":
			anim = "parado"
			vel = 0.6
	if str(root.get_meta("anim")) != anim:
		root.set_meta("anim", anim)
		ap.play(ANIMS[anim], 0.35)
	ap.speed_scale = vel
	# (a animação de andar não mexe no pescoço: volta para o normal antes de dobrar de novo)
	for nm in ["Shoulders", "Neck", "Head"]:
		var bi := sk.find_bone(nm)
		if bi >= 0:
			sk.set_bone_pose_rotation(bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion())
	ap.advance(dt)
	# o pescoço e a cabeça descem para pastar (e um pouco descansando)
	var alvo := 0.0
	if modo == "pastar":
		alvo = 1.0
	elif modo == "deitar":
		alvo = 0.3
	var b := move_toward(float(root.get_meta("baixa")), alvo, dt * 1.2)
	root.set_meta("baixa", b)
	_cascos(sk)
	if b > 0.001:
		_dobra(sk, "Shoulders", 0.85 * b)
		_dobra(sk, "Neck", 1.15 * b + sin(t * 2.1) * 0.03 * b)
		_dobra(sk, "Head", 0.45 * b + sin(t * 6.0) * 0.05 * b)   # arrancando o capim


## Os cascos presos na ponta da canela (no modelo eles eram alvos soltos de IK, presos no
## chão: a perna andava e o casco ficava, esticando a malha como uma mão).
const PES := [["FrontFoot_R", "FrontLowLeg_R"], ["FrontFoot_L", "FrontLowLeg_L"], ["BackFoot_R", "BackLowLeg_R"], ["BackFoot_L", "BackLowLeg_L"]]

static func _cascos(sk: Skeleton3D) -> void:
	for par in PES:
		var fi := sk.find_bone(par[0])
		var li := sk.find_bone(par[1])
		if fi < 0 or li < 0:
			continue
		var rel: Transform3D = sk.get_bone_global_rest(li).affine_inverse() * sk.get_bone_global_rest(fi)
		sk.set_bone_global_pose(fi, sk.get_bone_global_pose(li) * rel)


## Dobra o osso para baixo (gira em volta do eixo de lado do esqueleto) por cima da animação.
static func _dobra(sk: Skeleton3D, nome: String, ang: float) -> void:
	var bi := sk.find_bone(nome)
	if bi < 0:
		return
	var pai := sk.get_bone_parent(bi)
	var pg: Basis = sk.get_bone_global_pose(pai).basis if pai >= 0 else Basis()
	var eixo: Vector3 = (pg.inverse() * Vector3.RIGHT).normalized()
	var q: Quaternion = sk.get_bone_pose_rotation(bi)
	sk.set_bone_pose_rotation(bi, Quaternion(eixo, ang) * q)
