extends Node3D
## Bacaba (Oenocarpus bacaba): palmeira da terra firme amazônica.
##
## Ciclo de vida (contado em dias do calendário do jogo):
##  - Semente (caroço) no chão: brota em uns 2 a 3 meses se o chão estiver úmido.
##    Muito perto da mãe quase nunca vinga (sombra e bicho comendo).
##  - Muda: só um tufo de folhas no chão; fica assim uns 4 anos, sem tronco.
##  - Depois sobe o tronco: liso, cinza, com os anéis das folhas que caíram,
##    uns 50 a 80 cm por ano, até 12 a 20 m.
##  - Adulta (uns 7 anos): solta cachos que parecem vassoura pendurada embaixo das
##    folhas. Os frutos ficam verdes de julho a setembro e maduros (roxo quase preto)
##    de outubro a dezembro.
##  - Os macacos-prego vivem dela: comem os frutos e soltam o caroço longe, onde
##    passam. É assim que a bacaba nasce em lugar novo.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const MAX_PALMS := 460
const START_PALMS := 230
const ROSETTE_DAYS := 1460       # 4 anos sem tronco
const ADULT_DAYS := 2555         # 7 anos: começa a dar cacho
const GERM_MIN := 55
const GERM_MAX := 95
const TRUNK_R := 0.12
const CHUNK := 80.0
const VIEW := 230.0
const CACHO_VIEW := 95.0
const CROWN_VARIANTS := 4

## Casca da bacaba: textura feita de foto de casca lisa e cinza com os anéis das folhas
## (ver tools/textura_bacaba.py), dando a volta inteira no tronco.
const BARK_ALB := "res://texturas/bacaba_casca.imagem"
const BARK_NRM := "res://texturas/bacaba_casca_n.imagem"
const BARK_W := 0.75      # a textura cobre 0,75 m em volta do tronco
const BARK_H := 1.5       # e 1,5 m de altura

## Palmeira: {x, z, nasc (dia), hmax (m), vig, var, morta (dia ou -1)}
var palms: Array = []
var seeds: Array = []            # [x, z, dia que caiu, dia que brota]
var last_day := 0
var _jogo: Node
var _arv: Node
var _rng := RandomNumberGenerator.new()
var _crowns: Array = []          # malhas da copa (variantes)
var _trunk_mesh: ArrayMesh
var _roots_mesh: ArrayMesh
var _cacho_green: ArrayMesh
var _cacho_ripe: ArrayMesh
var _leaf_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _trunk_nodes: Array = []
var _trunk_sig := -1
var _dead_leaf_mat: StandardMaterial3D
var _nodes: Array = []
var _grid := {}                  # Vector2i(8 m) -> [Vector3(x, z, raio)]


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 3301
	last_day = int(jogo.sim.elapsed_days())
	_make_assets(seed_)
	if save_path == "" or not _load(save_path):
		_generate()
	palms = palms.filter(func(p): return not _arv._in_sea(float(p.x), float(p.z)))
	_rebuild()


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	while last_day < day:
		last_day += 1
		_process_day(last_day)
	_rebuild()


static func month_of(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


## Frutos maduros (outubro a dezembro): é quando os macacos comem e espalham.
static func ripe_season(day: int) -> bool:
	return month_of(day) >= 10


static func green_season(day: int) -> bool:
	var m := month_of(day)
	return m >= 7 and m <= 9


# ================== CRESCIMENTO ==================

## Altura do tronco (m). Muda ainda sem tronco: 0.
func trunk_h(p: Dictionary, day := -1) -> float:
	if day < 0:
		day = last_day
	var age := float(day - int(p.nasc))
	if age <= ROSETTE_DAYS:
		return 0.0
	return minf((age - ROSETTE_DAYS) / 365.0 * 0.65 * float(p.vig), float(p.hmax))


## Altura total (até o alto da copa).
func height_of(p: Dictionary, day := -1) -> float:
	return trunk_h(p, day) + crown_scale(p, day) * 3.2


func crown_scale(p: Dictionary, day := -1) -> float:
	if day < 0:
		day = last_day
	var age := float(day - int(p.nasc))
	return clampf(0.12 + age / float(ROSETTE_DAYS) * 0.62, 0.12, 0.74) + clampf((age - ROSETTE_DAYS) / 1500.0, 0.0, 0.26)


func alive(p) -> bool:
	return p is Dictionary and int(p.get("morta", -1)) < 0 and palms.has(p)


func is_adult(p: Dictionary, day := -1) -> bool:
	if day < 0:
		day = last_day
	return int(p.morta) < 0 and day - int(p.nasc) >= ADULT_DAYS and trunk_h(p, day) >= 1.2


func adult_palms() -> Array:
	var out := []
	for p in palms:
		if is_adult(p):
			out.append(p)
	return out


## Ponto na casca do tronco, a y metros do chão (para os macacos subirem).
func trunk_point(p: Dictionary, y: float, ang: float, out := 0.0) -> Vector3:
	var x := float(p.x)
	var z := float(p.z)
	var r := TRUNK_R * (1.0 + 0.5 * maxf(0.0, 1.0 - y / 0.8)) + out
	return Vector3(x + cos(ang) * r, _jogo.height_at(x, z) + y, z + sin(ang) * r)


func _process_day(day: int) -> void:
	var wet: float = _jogo.sim.wetness()
	var keep := []
	for p in palms:
		if int(p.morta) >= 0:
			if day - int(p.morta) < 240:
				keep.append(p)        # palmeira morta: as folhas secam e caem, depois o tronco some
			continue
		var age := day - int(p.nasc)
		var water := _water_at(float(p.x), float(p.z))
		# muda pequena morre fácil na seca forte
		if age < ROSETTE_DAYS and water < 0.12 and _rng.randf() < 0.004 * (1.0 - wet):
			p.morta = day
		# velhice e acidentes (raio, vento): bem raro
		elif age > 365 * 60 and _rng.randf() < 0.0004:
			p.morta = day
		elif _rng.randf() < 0.00003:
			p.morta = day
		keep.append(p)
	palms = keep
	# fruto maduro que cai no pé da mãe (quase nunca vinga ali, mas às vezes rola longe)
	if ripe_season(day) and _rng.randf() < 0.15:
		for p in adult_palms():
			if _rng.randf() < 0.05:
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(0.5, 7.0)
				drop_seed(float(p.x) + cos(a) * d, float(p.z) + sin(a) * d, day)
	# caroços que chegaram no dia de brotar
	var still := []
	for sd in seeds:
		if int(sd[3]) > day:
			still.append(sd)
			continue
		var x := float(sd[0])
		var z := float(sd[1])
		if palms.size() < MAX_PALMS and _water_at(x, z) > 0.2 and _rng.randf() < 0.35 and _spot_ok(x, z, day):
			palms.append(_new_palm(x, z, day))
	seeds = still


## Um macaco (ou o fruto que caiu) deixou um caroço aqui.
func drop_seed(x: float, z: float, day: int) -> void:
	if seeds.size() > 500:
		return
	seeds.append([clampf(x, 2.0, 638.0), clampf(z, 2.0, 478.0), day, day + _rng.randi_range(GERM_MIN, GERM_MAX)])


func _water_at(x: float, z: float) -> float:
	var cell := Vector2i(int(x / _jogo.CELL), int(z / _jogo.CELL))
	return float(_jogo.sim.ground_water(cell))


func _new_palm(x: float, z: float, born: int) -> Dictionary:
	return {"x": x, "z": z, "nasc": born, "hmax": _rng.randf_range(12.0, 20.0), "vig": _rng.randf_range(0.8, 1.2),
		"var": _rng.randi() % CROWN_VARIANTS, "rot": _rng.randf() * TAU, "morta": -1}


## Dá para nascer aqui? Chão bom, sem árvore colada e longe da sombra de bacaba adulta.
func _spot_ok(x: float, z: float, day: int) -> bool:
	if not _arv._ground_ok(x, z):
		return false
	for p in palms:
		var d := Vector2(float(p.x) - x, float(p.z) - z).length()
		if d < (4.5 if is_adult(p, day) else 2.0):
			return false
	for t in _arv.plants:
		if int(t[5]) == 2:
			continue
		if Vector2(float(t[0]) - x, float(t[1]) - z).length() < 1.6 + _arv.height_of(t, day) * 0.06:
			return false
	return true


func _generate() -> void:
	# moitas de bacaba na terra firme: onde o ruído é alto tem mais
	var nz := FastNoiseLite.new()
	nz.seed = _rng.randi()
	nz.frequency = 0.008
	var W: float = MundoSim.W * _jogo.CELL
	var H: float = MundoSim.H * _jogo.CELL
	var tries := 0
	while palms.size() < START_PALMS and tries < 9000:
		tries += 1
		var x := _rng.randf_range(6.0, W - 6.0)
		var z := _rng.randf_range(6.0, H - 6.0)
		if nz.get_noise_2d(x, z) * 0.5 + 0.5 < _rng.randf() * 1.1:
			continue
		# idade: muitas mudas e jovens, adultas de 7 a 60 anos
		var age: int
		var r := _rng.randf()
		if r < 0.3:
			age = _rng.randi_range(30, ROSETTE_DAYS)
		elif r < 0.45:
			age = _rng.randi_range(ROSETTE_DAYS, ADULT_DAYS)
		else:
			age = _rng.randi_range(ADULT_DAYS, 365 * 50)
		if not _spot_ok(x, z, last_day):
			continue
		palms.append(_new_palm(x, z, last_day - age))


# ================== NA TELA ==================

func push_out(p: Vector3) -> Vector3:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for t in _grid.get(k + Vector2i(dx, dz), []):
				var d := Vector2(p.x - t.x, p.z - t.y)
				var l := d.length()
				if l < t.z:
					var n := d / l if l > 0.001 else Vector2(1, 0)
					p.x = t.x + n.x * t.z
					p.z = t.y + n.y * t.z
	return p


func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_grid.clear()
	var chunks := {}     # Vector2i -> {tr: [], cr: {var: []}, dead: [], cg: [], cm: []}
	var green := green_season(last_day)
	var ripe := ripe_season(last_day)
	for p in palms:
		var x := float(p.x)
		var z := float(p.z)
		var c := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		if not chunks.has(c):
			chunks[c] = {"tr": [], "rt": [], "cr": {}, "dead": [], "cg": [], "cm": []}
		var ch: Dictionary = chunks[c]
		var gy: float = _jogo.height_at(x, z)
		var h := trunk_h(p)
		var rot := float(p.get("rot", 0.0))
		var dead := int(p.morta) >= 0
		if h > 0.05:
			var r := TRUNK_R * lerpf(0.75, 1.0, clampf(h / 6.0, 0.0, 1.0))
			ch.tr.append([x, gy, z, h, r, rot])
			if h > 1.0:
				ch.rt.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * clampf(h / 8.0, 0.55, 1.0)), Vector3(x, gy, z)))
			var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
			if not _grid.has(gk):
				_grid[gk] = []
			_grid[gk].append(Vector3(x, z, r + 0.28))
		var s := crown_scale(p)
		var top := Vector3(x, gy + h - 0.05, z)
		if dead:
			if last_day - int(p.morta) < 120:
				ch.dead.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s * 0.8, s)), top))
			continue
		var v := int(p.get("var", 0)) % CROWN_VARIANTS
		if not ch.cr.has(v):
			ch.cr[v] = []
		ch.cr[v].append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), top))
		# cachos pendurados embaixo das folhas
		if is_adult(p) and (green or ripe):
			var n := 1 + int(absf(sin(x * 3.1 + z * 7.7)) * 2.99)
			for k in n:
				var a := rot + k * TAU / n + 0.7
				var b := Basis(Vector3.UP, a)
				var t := Transform3D(b, top + b * Vector3(0.22, -0.35, 0))
				(ch.cm if ripe else ch.cg).append(t)
	# troncos: uma malha por pedaço do mapa (refeita só quando algum tronco cresceu uns 20 cm)
	var sig := 0
	for c in chunks:
		for t in chunks[c].tr:
			sig = hash([sig, snappedf(t[0], 0.01), int(float(t[3]) * 5.0)])
	if sig != _trunk_sig:
		_trunk_sig = sig
		for n in _trunk_nodes:
			if is_instance_valid(n):
				n.queue_free()
		_trunk_nodes.clear()
		for c in chunks:
			if (chunks[c].tr as Array).is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = _trunks_mesh(chunks[c].tr)
			mi.material_override = _trunk_mat
			mi.visibility_range_end = VIEW
			add_child(mi)
			_trunk_nodes.append(mi)
	for c in chunks:
		var ch: Dictionary = chunks[c]
		_add_mm(_roots_mesh, null, ch.rt, 70.0, false)
		for v in ch.cr:
			_add_mm(_crowns[v], _leaf_mat, ch.cr[v], VIEW, true)
		_add_mm(_crowns[0], _dead_leaf_mat, ch.dead, VIEW, true)
		_add_mm(_cacho_green, null, ch.cg, CACHO_VIEW, false)
		_add_mm(_cacho_ripe, null, ch.cm, CACHO_VIEW, false)


func _add_mm(mesh: Mesh, mat: Material, xs: Array, view: float, shadow: bool) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.visibility_range_end = view
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_nodes.append(mi)


# ================== MODELOS ==================

func _make_assets(seed_: int) -> void:
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_texture = _frond_texture()
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.5
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 0.75
	_leaf_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_dead_leaf_mat = _leaf_mat.duplicate()
	_dead_leaf_mat.albedo_color = Color(1.9, 1.35, 0.7)       # folha seca: palha marrom
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_texture = _load_tex(BARK_ALB, Color(0.58, 0.57, 0.52))
	_trunk_mat.albedo_color = Color(0.66, 0.64, 0.59)
	var nt := _load_tex(BARK_NRM, Color(0.5, 0.5, 1.0))
	_trunk_mat.normal_enabled = true
	_trunk_mat.normal_texture = nt
	_trunk_mat.normal_scale = 1.4
	_trunk_mat.roughness = 0.85
	_trunk_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_trunk_mesh = _make_trunk()
	_roots_mesh = _make_roots()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 4401
	for v in CROWN_VARIANTS:
		_crowns.append(_make_crown(rng))
	_cacho_green = _make_cacho(rng, Color(0.33, 0.42, 0.14))
	_cacho_ripe = _make_cacho(rng, Color(0.13, 0.05, 0.12))


## Textura de meia folha: a nervura (raque) do lado esquerdo e os folíolos compridos
## saindo para fora e para a ponta, com vão entre eles.
func _frond_texture() -> ImageTexture:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var step := 9.0
	var y0 := -60.0
	while y0 < h + 10:
		var tone := rng.randf_range(0.82, 1.12)
		var col := Color(0.20 * tone, 0.34 * tone, 0.11 * tone)
		var fwd := rng.randf_range(52.0, 64.0)     # o folíolo aponta para a ponta da folha
		for u in range(0, w):
			var t := float(u) / float(w - 1)
			var cy := y0 + fwd * t + 10.0 * t * t
			var half := lerpf(2.6, 0.7, t)             # mais largo perto da nervura
			for yy in range(int(cy - half - 1), int(cy + half + 2)):
				var y := posmod(yy, h)
				var a := clampf(half + 0.5 - absf(float(yy) - cy), 0.0, 1.0)
				if a <= 0.0:
					continue
				var shade := 1.0 - 0.25 * absf(float(yy) - cy) / maxf(half, 0.5)
				var old := img.get_pixel(u, y)
				var c := Color(col.r * shade, col.g * shade, col.b * shade, maxf(old.a, a))
				img.set_pixel(u, y, c)
		y0 += step
	# nervura central
	for y in h:
		for u in 4:
			img.set_pixel(u, y, Color(0.30, 0.36, 0.14, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _load_tex(path: String, fallback: Color) -> Texture2D:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(fallback)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Troncos de um pedaço do mapa numa malha só, com a textura dando a volta (sem
## esticar: 1,5 m de casca a cada 1,5 m de tronco) e o pé um pouco mais grosso.
func _trunks_mesh(list: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 14
	for t in list:
		var x: float = t[0]
		var gy: float = t[1]
		var z: float = t[2]
		var h: float = t[3]
		var r: float = t[4]
		var rot: float = t[5]
		var rows := [[-0.3, 1.6], [0.04, 1.45], [0.22, 1.12], [minf(0.7, h * 0.5), 1.0], [h + 0.05, 0.86]]
		var vofs := fmod(rot * 3.7, 1.0)
		var reps := maxf(1.0, roundf(TAU * r / BARK_W))
		for i in rows.size() - 1:
			var y0: float = rows[i][0]
			var y1: float = rows[i + 1][0]
			var r0: float = r * float(rows[i][1])
			var r1: float = r * float(rows[i + 1][1])
			for k in sides:
				var a0 := rot + float(k) / sides * TAU
				var a1 := rot + float(k + 1) / sides * TAU
				var u0 := float(k) / sides * reps
				var u1 := float(k + 1) / sides * reps
				var q := [Vector3(x + cos(a0) * r0, gy + y0, z + sin(a0) * r0), Vector3(x + cos(a1) * r0, gy + y0, z + sin(a1) * r0),
					Vector3(x + cos(a1) * r1, gy + y1, z + sin(a1) * r1), Vector3(x + cos(a0) * r1, gy + y1, z + sin(a0) * r1)]
				var uv := [Vector2(u0, vofs - y0 / BARK_H), Vector2(u1, vofs - y0 / BARK_H), Vector2(u1, vofs - y1 / BARK_H), Vector2(u0, vofs - y1 / BARK_H)]
				var nn := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]
				# frente virada para fora (a Godot só desenha a frente)
				for tri in [[0, 1, 2], [0, 2, 3]]:
					var A: Vector3 = q[tri[0]]
					var B: Vector3 = q[tri[1]]
					var C: Vector3 = q[tri[2]]
					var out: Vector3 = nn[tri[0]]
					var ord: Array = tri
					if (C - A).cross(B - A).dot(out) < 0.0:
						ord = [tri[0], tri[2], tri[1]]
					for idx in ord:
						st.set_normal(nn[idx])
						st.set_uv(uv[idx])
						st.add_vertex(q[idx])
	st.generate_tangents()
	return st.commit()


func _make_trunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 16
	var rows := [0.0, 0.08, 0.2, 1.0]
	var rad := [1.7, 1.35, 1.05, 0.85]     # base um pouco grossa, afina para cima
	for i in rows.size() - 1:
		for s in sides:
			var a0 := float(s) / sides * TAU
			var a1 := float(s + 1) / sides * TAU
			var p := [Vector3(cos(a0) * rad[i], rows[i], sin(a0) * rad[i]), Vector3(cos(a1) * rad[i], rows[i], sin(a1) * rad[i]),
				Vector3(cos(a1) * rad[i + 1], rows[i + 1], sin(a1) * rad[i + 1]), Vector3(cos(a0) * rad[i + 1], rows[i + 1], sin(a0) * rad[i + 1])]
			var nrm := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]
			for t in [0, 2, 1, 0, 3, 2]:
				st.set_normal(nrm[t])
				st.add_vertex(p[t])
	return st.commit()


## Cone de raízes no pé: dezenas de raízes finas avermelhadas que saem do tronco
## um pouco acima do chão e descem abrindo em volta (como na bacaba de verdade).
func _make_roots() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	for k in 34:
		var a := rng.randf() * TAU
		var top_h := rng.randf_range(0.12, 0.55)
		var top := Vector3(cos(a) * 0.15, top_h, sin(a) * 0.15)
		var out_r := rng.randf_range(0.2, 0.42) + top_h * 0.3
		var a2 := a + rng.randf_range(-0.15, 0.15)
		var bot := Vector3(cos(a2) * out_r, -0.06, sin(a2) * out_r)
		var mid := top.lerp(bot, 0.5) + Vector3(cos(a), 0, sin(a)) * 0.04
		var col := Color(0.42, 0.22, 0.16).lerp(Color(0.32, 0.27, 0.2), rng.randf())
		var rr := rng.randf_range(0.009, 0.016)
		_tube(st, top, mid, rr, col)
		_tube(st, mid, bot, rr * 0.9, col.darkened(0.15))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	st.set_material(mat)
	return st.commit()


## Copa: 11 a 14 folhas compridas (4 a 5,5 m) saindo do alto do tronco; as de cima
## mais em pé, as de baixo arqueadas. Cada folha tem folíolos pendendo dos dois lados.
func _make_crown(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rng.randi_range(11, 14)
	var golden := 2.39996
	for f in n:
		var k := float(f) / float(n - 1)          # 0 = folha nova (em cima), 1 = folha velha
		var yaw := f * golden + rng.randf_range(-0.2, 0.2)
		var L := rng.randf_range(4.0, 5.4) * lerpf(0.85, 1.0, k)
		var elev := deg_to_rad(lerpf(72.0, 28.0, k) + rng.randf_range(-6.0, 6.0))
		var droop := lerpf(0.10, 0.34, k)          # quanto a folha arqueia para baixo
		var tint := Color(1, 1, 1).lerp(Color(1.25, 1.15, 0.7), clampf((k - 0.85) * 5.0, 0.0, 1.0) * rng.randf())
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var segs := 9
		var pts := []
		for i in segs + 1:
			var t := float(i) / segs
			var s := L * t
			pts.append(dir * s * cos(elev) + Vector3.UP * (s * sin(elev) - droop * s * s / L * 2.2) + Vector3.UP * 0.25)
		for side in [-1.0, 1.0]:
			var prev_in := Vector3.ZERO
			var prev_out := Vector3.ZERO
			for i in segs + 1:
				var t := float(i) / segs
				var tan: Vector3 = (pts[mini(i + 1, segs)] - pts[maxi(i - 1, 0)]).normalized()
				var sidev: Vector3 = tan.cross(Vector3.UP).normalized() * float(side)
				var w: float = 1.0 * sin(clampf(t, 0.06, 1.0) * PI * 0.92 + 0.12) * lerpf(0.55, 1.0, minf(t * 3.0, 1.0))
				var hang: float = deg_to_rad(lerpf(20.0, 55.0, t))      # os folíolos pendem mais na ponta
				var inner: Vector3 = pts[i]
				var outer: Vector3 = inner + (sidev * cos(hang) - Vector3.UP * sin(hang)) * w
				if i > 0:
					var v0 := float(i - 1) / segs * L / 1.4
					var v1 := t * L / 1.4
					var nrm := (prev_out - prev_in).cross(inner - prev_in).normalized()
					if nrm.y < 0.0:
						nrm = -nrm
					var q := [[prev_in, Vector2(0, v0)], [inner, Vector2(0, v1)], [outer, Vector2(1, v1)], [prev_out, Vector2(1, v0)]]
					for idx in [0, 1, 2, 0, 2, 3]:
						st.set_color(tint)
						st.set_normal(nrm)
						st.set_uv(q[idx][1])
						st.add_vertex(q[idx][0])
				prev_in = inner
				prev_out = outer
	# base das folhas: as bainhas abraçando o alto do tronco
	for s in 8:
		var a0 := float(s) / 8.0 * TAU
		var a1 := float(s + 1) / 8.0 * TAU
		var p := [Vector3(cos(a0) * 0.13, -0.25, sin(a0) * 0.13), Vector3(cos(a1) * 0.13, -0.25, sin(a1) * 0.13),
			Vector3(cos(a1) * 0.2, 0.35, sin(a1) * 0.2), Vector3(cos(a0) * 0.2, 0.35, sin(a0) * 0.2)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(1.5, 1.35, 1.1))
			st.set_normal(Vector3(cos(a0), 0.2, sin(a0)).normalized())
			st.set_uv(Vector2(0.01, 0.5))
			st.add_vertex(p[idx])
	return st.commit()


## Cacho: um cabo curto que sai do tronco e dezenas de raminhos finos pendurados
## (como uma vassoura de cabeça para baixo), cheios de frutinhas.
func _make_cacho(rng: RandomNumberGenerator, fruit: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stalk := Color(0.36, 0.36, 0.16) if fruit.g > 0.2 else Color(0.24, 0.12, 0.10)
	# cabo grosso que sai do tronco e faz curva para fora e para baixo
	var p0 := Vector3.ZERO
	var p1 := Vector3(0.22, 0.02, 0)
	var base := Vector3(0.38, -0.12, 0)
	_tube(st, p0, p1, 0.04, stalk)
	_tube(st, p1, base, 0.035, stalk)
	for k in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.02, 0.2)
		var top := base + Vector3(cos(a) * r * 0.7, rng.randf_range(-0.06, 0.04), sin(a) * r)
		_tube(st, base, top, 0.006, stalk)
		var L := rng.randf_range(0.42, 0.78)
		var sway := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.06, 0.2)
		var bot := top + Vector3(0, -L, 0) + sway
		_tube(st, top, bot, 0.0045, stalk)
		# frutinhas bem juntas ao longo do raminho (uns 1,3 cm)
		var berries := rng.randi_range(9, 14)
		for b in berries:
			var t := (float(b) + rng.randf_range(0.2, 0.8)) / float(berries)
			var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.01
			var c := top.lerp(bot, t) + side
			_berry(st, c, 0.0135, fruit.lerp(Color(0.3, 0.3, 0.3), rng.randf() * 0.12))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.55
	st.set_material(mat)
	return st.commit()


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized() * r
	var v := ax.cross(u).normalized() * r
	var ring := [u, v, -u, -v]
	for i in 4:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 4]
		var q := [a + p0, a + p1, b + p1, b + p0]
		var n := (p0 + p1).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(q[idx])


static func _berry(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var v := [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	for f in faces:
		var n: Vector3 = (v[f[0]] + v[f[1]] + v[f[2]]).normalized()
		for i in f:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(c + v[i])


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "palmeiras": palms, "sementes": seeds}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	palms = d.get("palmeiras", [])
	seeds = d.get("sementes", [])
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
