extends Node3D
## Coqueiro (Cocos nucifera, o coco-da-baía): a palmeira das praias.
##
## - Cresce na areia da beira do mar: tronco fino e cinza, curvado e inclinado (para o
##   lado do mar), com os anéis das folhas que caíram e a base engrossada; no alto a copa
##   de folhas penadas compridas caídas para os lados e os cachos de coco (verdes e alguns
##   já amarelando) bem embaixo das folhas.
## - Dá coco o ano todo: de vez em quando um coco cai e fica no chão (dura uns meses e às
##   vezes brota, virando um coqueiro novo).
## - O coco se pega do chão; aberto com a faca dá a água (sede) e a massa branca (fome).

const MundoSim := preload("res://scripts/mundo_sim.gd")
const Babacus := preload("res://scripts/world/babacus.gd")
const START_PALMS := 130
const MAX_PALMS := 260
const ADULT_DAYS := 365 * 6        # dá coco a partir dos 6 anos
const TRUNK_R := 0.15
const VIEW := 260.0
const CHAO_VIEW := 60.0
const VARIANTS := 3
const CURVA := [0.5, 1.0, 1.6]     # quanto o tronco curva (m), por variante
const COCO_DIA := 0.07             # chance de um coqueiro adulto soltar um coco por dia
const COCO_DAYS := 150             # o coco no chão dura uns 5 meses
const COCO_MAX := 500

var palms: Array = []              # {x, z, nasc, hmax, var, rot}
var cocos: Array = []              # cocos no chão: [x, z, giro, dia]
var last_day := 0
var _jogo: Node
var _arv: Node
var _rng := RandomNumberGenerator.new()
var _crowns: Array = []
var _trunks: Array = []
var _cacho_mesh: ArrayMesh
var _coco_mesh: ArrayMesh
var _mat: StandardMaterial3D
var _nodes: Array = []
var _grid := {}


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9133
	last_day = int(jogo.sim.elapsed_days())
	_make_assets()
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild()


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	var n := 0
	while last_day < day and n < 400:
		last_day += 1
		n += 1
		_process_day(last_day)
	last_day = day
	_rebuild()


func is_adult(p: Dictionary, day := -1) -> bool:
	if day < 0:
		day = last_day
	return day - int(p.nasc) >= ADULT_DAYS


## A altura do tronco (o novo ainda sem tronco: só as folhas saindo da areia).
func trunk_h(p: Dictionary, day := -1) -> float:
	if day < 0:
		day = last_day
	var age := float(day - int(p.nasc)) / 365.0
	if age < 3.0:
		return 0.0
	return minf(0.6 + (age - 3.0) * 0.8, float(p.hmax))


## Areia da praia: pouco acima do mar e com o mar perto.
func _spot_ok(x: float, z: float) -> bool:
	var c := Vector2i(int(x / _jogo.CELL), int(z / _jogo.CELL))
	if c.x < 2 or c.y < 2 or c.x >= MundoSim.W - 2 or c.y >= MundoSim.H - 2:
		return false
	if _arv._in_sea(x, z):
		return false
	var acima: float = _jogo.height_at(x, z) - MundoSim.SEA * _jogo.HS
	if acima < 0.7 or acima > 4.5:
		return false
	if float(_jogo.sim.wat[c.y * MundoSim.W + c.x]) > 0.02:
		return false
	var mar := false
	for k in 12:
		var a := TAU * k / 12.0
		for d in [8.0, 16.0, 26.0]:
			if _arv._in_sea(x + cos(a) * d, z + sin(a) * d):
				mar = true
				break
		if mar:
			break
	if not mar:
		return false
	for p in palms:
		if Vector2(float(p.x) - x, float(p.z) - z).length() < 3.5:
			return false
	return true


## Para que lado fica o mar (o coqueiro tomba para lá).
func _lado_mar(x: float, z: float) -> float:
	var s := Vector2.ZERO
	for k in 16:
		var a := TAU * k / 16.0
		if _arv._in_sea(x + cos(a) * 20.0, z + sin(a) * 20.0):
			s += Vector2(cos(a), sin(a))
	return s.angle() if s.length() > 0.01 else _rng.randf() * TAU


func _new_palm(x: float, z: float, born: int) -> Dictionary:
	# o tronco curva para o mar (um pouco para o lado, cada um de um jeito)
	return {"x": x, "z": z, "nasc": born, "hmax": _rng.randf_range(8.0, 18.0), "var": _rng.randi() % VARIANTS,
		"rot": -_lado_mar(x, z) + _rng.randf_range(-0.6, 0.6)}


func _generate() -> void:
	var W: float = MundoSim.W * _jogo.CELL
	var H: float = MundoSim.H * _jogo.CELL
	var tries := 0
	var nz := FastNoiseLite.new()
	nz.seed = _rng.randi()
	nz.frequency = 0.01
	while palms.size() < START_PALMS and tries < 30000:
		tries += 1
		var x := _rng.randf_range(8.0, W - 8.0)
		var z := _rng.randf_range(8.0, H - 8.0)
		if nz.get_noise_2d(x, z) * 0.5 + 0.5 < 0.35 + _rng.randf() * 0.4:
			continue                                 # em grupos (os coqueirais)
		if not _spot_ok(x, z):
			continue
		var age := _rng.randi_range(200, 365 * 3) if _rng.randf() < 0.15 else _rng.randi_range(ADULT_DAYS, 365 * 60)
		palms.append(_new_palm(x, z, last_day - age))
	for p in palms:
		if is_adult(p):
			for k in _rng.randi_range(0, 3):
				_soltar_coco(p, last_day - _rng.randi_range(0, 90))


func _soltar_coco(p: Dictionary, day: int) -> void:
	if cocos.size() >= COCO_MAX:
		return
	# cai embaixo da copa (que fica para o lado onde o tronco curva)
	var topo := _topo_local(p)
	var b := Basis(Vector3.UP, float(p.rot))
	var t: Vector3 = b * Vector3(topo.x, 0, 0)
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(0.3, 2.6)
	cocos.append([snappedf(float(p.x) + t.x + cos(a) * d, 0.01), snappedf(float(p.z) + t.z + sin(a) * d, 0.01), snappedf(_rng.randf() * TAU, 0.01), day])


func _process_day(day: int) -> void:
	cocos = cocos.filter(func(c): return day - int(c[3]) < COCO_DAYS)
	for p in palms:
		if is_adult(p, day) and _rng.randf() < COCO_DIA:
			_soltar_coco(p, day)
	# um coco esquecido na areia às vezes brota
	if palms.size() < MAX_PALMS and not cocos.is_empty() and _rng.randf() < 0.01:
		var c: Array = cocos[_rng.randi() % cocos.size()]
		if _spot_ok(float(c[0]), float(c[1])):
			palms.append(_new_palm(float(c[0]), float(c[1]), day))


# ================== PEGAR ==================

func coco_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in cocos.size():
		var c: Array = cocos[i]
		var d := Vector2(float(c[0]) - pos.x, float(c[1]) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func take_coco(i: int) -> void:
	if i >= 0 and i < cocos.size():
		cocos.remove_at(i)
		_rebuild()


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


# ================== NA TELA ==================

## Onde fica o alto do tronco (em relação ao pé, antes de girar): a curva para +x.
func _topo_local(p: Dictionary) -> Vector3:
	return Vector3(float(CURVA[int(p.var)]), trunk_h(p), 0)


func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_grid.clear()
	var crowns := []
	var trunks := []
	for v in VARIANTS:
		crowns.append([])
		trunks.append([])
	var cachos := []
	for p in palms:
		var x := float(p.x)
		var z := float(p.z)
		var gy: float = _jogo.ground_at(x, z)
		var rot := Basis(Vector3.UP, float(p.rot))
		var th := trunk_h(p)
		var v := int(p.var)
		if th <= 0.0:
			# o coqueiro novo: as folhas saindo da areia
			var s := clampf(0.25 + float(last_day - int(p.nasc)) / (365.0 * 3.0) * 0.6, 0.25, 0.85)
			crowns[v].append(Transform3D(rot.scaled(Vector3.ONE * s), Vector3(x, gy - 0.05, z)))
			continue
		trunks[v].append(Transform3D(rot.scaled(Vector3(1.0, th, 1.0)), Vector3(x, gy - 0.1, z)))
		var topo: Vector3 = Vector3(x, gy - 0.1, z) + rot * _topo_local(p)
		var s2 := clampf(0.8 + th / 40.0, 0.8, 1.15)
		crowns[v].append(Transform3D(rot.scaled(Vector3.ONE * s2), topo))
		if is_adult(p):
			cachos.append(Transform3D(rot, topo))
		var k2 := Vector2i(floori(x / 8.0), floori(z / 8.0))
		if not _grid.has(k2):
			_grid[k2] = []
		_grid[k2].append(Vector3(x, z, TRUNK_R + 0.25))
	for v in VARIANTS:
		_add_mm(_crowns[v], crowns[v], VIEW, true)
		_add_mm(_trunks[v], trunks[v], VIEW, true)
	_add_mm(_cacho_mesh, cachos, 140.0, true)
	var cx := []
	for c in cocos:
		var gc: float = _jogo.ground_at(float(c[0]), float(c[1]))
		cx.append(Transform3D(Basis(Vector3.UP, float(c[2])) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(float(c[0]), gc + 0.08, float(c[1]))))
	_add_mm(_coco_mesh, cx, CHAO_VIEW, false)


func _add_mm(mesh: Mesh, xs: Array, view: float, shadow: bool) -> void:
	if xs.is_empty():
		return
	# em pedaços de 64 m: a distância de ver conta de cada pedaço (não do mapa inteiro)
	var grupos := {}
	for t in xs:
		var o: Vector3 = (t as Transform3D).origin
		var k := Vector2i(floori(o.x / 64.0), floori(o.z / 64.0))
		if not grupos.has(k):
			grupos[k] = []
		grupos[k].append(t)
	for k in grupos:
		var lst: Array = grupos[k]
		var c := Vector3((k.x + 0.5) * 64.0, 0.0, (k.y + 0.5) * 64.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = lst.size()
		for i in lst.size():
			var t2: Transform3D = lst[i]
			mm.set_instance_transform(i, Transform3D(t2.basis, t2.origin - c))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.position = c
		if view > 0.0:
			mi.visibility_range_end = view
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_nodes.append(mi)


# ================== MODELOS ==================

func _make_assets() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.85
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	for v in VARIANTS:
		rng.seed = 4400 + v * 37
		_crowns.append(_coroa(rng, 17 + v))
		_trunks.append(_tronco(float(CURVA[v])))
	rng.seed = 991
	_cacho_mesh = _cachos(rng)
	_coco_mesh = _coco()


## A copa: folhas penadas compridas, as de fora bem caídas e as do meio mais em pé.
func _coroa(rng: RandomNumberGenerator, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verde := Color(0.3, 0.5, 0.18)
	for i in n:
		var az := TAU * i / n + rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(az), 0, sin(az))
		var elev := lerpf(1.05, 0.15, float(i % 4) / 3.0) + rng.randf_range(-0.1, 0.1)
		var cor := verde.darkened(rng.randf_range(0.0, 0.18))
		if i % 7 == 3:
			cor = Color(0.6, 0.55, 0.28)               # uma folha velha amarelando
		Babacus._folha(st, dir * 0.12, dir, elev, rng.randf_range(4.0, 5.2), cor, rng)
	st.generate_normals()
	return st.commit()


## O tronco: 1 m de altura (o resto é a escala) e a curva em metros: fino, cinza, com os
## anéis bem marcados e o pé engrossado.
func _tronco(curva: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lados := 10
	var anel := 24
	for j in anel:
		var y0 := float(j) / anel
		var y1 := float(j + 1) / anel
		var r0 := TRUNK_R * (1.0 + 0.7 * pow(1.0 - y0, 6.0) - y0 * 0.15)
		var r1 := TRUNK_R * (1.0 + 0.7 * pow(1.0 - y1, 6.0) - y1 * 0.15)
		# a curva: sobe reto no começo e vai entortando (x vai de 0 a 1)
		var x0 := y0 * y0 * curva
		var x1 := y1 * y1 * curva
		var cor := Color(0.46, 0.42, 0.36).darkened(0.1 * float(j % 2) + 0.05 * sin(j * 1.7))
		for k in lados:
			var a0 := TAU * k / lados
			var a1 := TAU * (k + 1) / lados
			var q := [Vector3(x0 + cos(a0) * r0, y0, sin(a0) * r0), Vector3(x0 + cos(a1) * r0, y0, sin(a1) * r0),
				Vector3(x1 + cos(a1) * r1, y1, sin(a1) * r1), Vector3(x1 + cos(a0) * r1, y1, sin(a0) * r1)]
			for jj in [0, 2, 1, 0, 3, 2]:
				st.set_color(cor)
				st.add_vertex(q[jj])
	st.generate_normals()
	return st.commit()


## Os cachos embaixo da copa: cocos grandes, verdes e alguns amarelando.
func _cachos(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.2, 0.32)
		var c := Vector3(cos(a) * r, -0.25 - rng.randf() * 0.25, sin(a) * r)
		var cor := Color(0.36, 0.48, 0.14) if rng.randf() < 0.7 else Color(0.72, 0.58, 0.18)
		Babacus._ovo(st, c, Vector3(0.11, 0.13, 0.11), cor.darkened(rng.randf_range(0.0, 0.15)))
	st.generate_normals()
	return st.commit()


## O coco caído: grande, oval, a casca (o "bucho") marrom de fibra.
func _coco() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Babacus._ovo(st, Vector3.ZERO, Vector3(0.1, 0.13, 0.1), Color(0.5, 0.38, 0.2))
	st.generate_normals()
	return st.commit()


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"palms": palms, "cocos": cocos, "last_day": last_day}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not d.has("palms"):
		return false
	palms = d.palms
	cocos = d.get("cocos", [])
	last_day = maxi(int(d.get("last_day", last_day)), 0)
	return true
