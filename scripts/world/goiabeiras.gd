extends Node3D
## Goiabeira (Psidium guajava): árvore baixa (3 a 5 m) da beira da mata e das clareiras.
## O tronco se divide baixo em 2 ou 3 galhos tortos, com a casca lisa que solta em
## placas (cor de cobre com manchas cinza-esverdeadas); as folhas são ovais, verde-claras,
## com as nervuras marcadas. Flores brancas em setembro e outubro; goiabas verdes em
## novembro e dezembro; maduras (amarelas) de janeiro a abril. As folhas dão o chá que o
## povo usa para desarranjo da barriga (alivia a diarreia e as cólicas; não mata a
## infecção). Cada pé dá goiabas e folhas uma vez por dia.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const Bacabas := preload("res://scripts/world/bacabas.gd")
const COUNT := 70
const CHUNK := 64.0
const VIEW := 160.0
const FRUTA_VIEW := 45.0
const VARIANTES := 3
const R_TRONCO := 0.16          # colisão do tronco (m, escala 1)

## Cada pé: {x, z, s (tamanho), v (variante), seed, fr (dia em que pegaram as goiabas),
## fo (dia em que pegaram as folhas)}
var items: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _nodes: Array = []
var _frutas: Array = []
var _estacao := ""
var _dia := -1
static var _meshes: Array = []
static var _pontos: Array = []    # por variante: onde ficam as goiabas (copa de baixo)
static var _flores: Array = []    # por variante: onde ficam as flores
static var _mat: StandardMaterial3D
static var _fmat: StandardMaterial3D
static var _fruta_mesh: Mesh


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 4471
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild()


# ================== ÉPOCA ==================

static func mes(day: int) -> int:
	return Bacabas.month_of(day)


## "flor", "verde", "madura" ou "" (sem nada).
static func estacao(day: int) -> String:
	var m := mes(day)
	if m >= 1 and m <= 4:
		return "madura"
	if m >= 11:
		return "verde"
	if m == 9 or m == 10:
		return "flor"
	return ""


# ================== ONDE NASCEM ==================

func _generate() -> void:
	var cell: float = _jogo.CELL
	var wx := MundoSim.W * cell
	var wz := MundoSim.H * cell
	var tries := 0
	# em grupinhos (os bichos comem a goiaba e espalham as sementes perto)
	while items.size() < COUNT and tries < COUNT * 40:
		tries += 1
		var cx := _rng.randf_range(20.0, wx - 20.0)
		var cz := _rng.randf_range(20.0, wz - 20.0)
		if not _bom(cx, cz):
			continue
		_novo(cx, cz, -2000)
		for k in _rng.randi_range(1, 3):
			var a := _rng.randf() * TAU
			var d := _rng.randf_range(5.0, 12.0)
			var x := cx + cos(a) * d
			var z := cz + sin(a) * d
			if items.size() < COUNT and _bom(x, z):
				_novo(x, z, -2000)


func _novo(x: float, z: float, nasc: int) -> void:
	items.append({"x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "s": snappedf(_rng.randf_range(0.8, 1.15), 0.01),
		"v": _rng.randi() % VARIANTES, "seed": _rng.randi() % 100000, "fr": -1, "fo": -1, "nasc": nasc})


## Terra firme, fora da praia e da água, longe dos troncos das outras árvores.
func _bom(x: float, z: float) -> bool:
	var cell: float = _jogo.CELL
	var cl := Vector2i(int(x / cell), int(z / cell))
	if cl.x < 1 or cl.y < 1 or cl.x >= MundoSim.W - 1 or cl.y >= MundoSim.H - 1:
		return false
	if _jogo.sim.water_at(cl) > 0.02:
		return false
	var sd: Dictionary = _jogo.sim.soil_data(cl)
	if not sd.is_empty() and float(sd.sand) > 0.5:
		return false
	if _jogo.height_at(x, z) < MundoSim.SEA * _jogo.HS + 1.0:
		return false
	for it in items:
		if Vector2(float(it.x) - x, float(it.z) - z).length() < 4.0:
			return false
	var arv = _jogo._arvores
	if arv:
		for p in arv.plants:
			if absf(float(p[0]) - x) < 3.0 and absf(float(p[1]) - z) < 3.0:
				return false
	return true


func nearest(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in items.size():
		var p: Dictionary = items[i]
		var d := Vector2(float(p.x) - pos.x, float(p.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func point_of(i: int) -> Vector3:
	var p: Dictionary = items[i]
	return Vector3(float(p.x), _jogo.ground_at(float(p.x), float(p.z)), float(p.z))


## Tem goiaba madura para pegar hoje?
func tem_goiaba(i: int, day: int) -> bool:
	return i >= 0 and i < items.size() and estacao(day) == "madura" and int(items[i].get("fr", -1)) != day


func tem_folha(i: int, day: int) -> bool:
	return i >= 0 and i < items.size() and int(items[i].get("fo", -1)) != day


## Pega as goiabas maduras do pé (devolve quantas).
func pegar_goiabas(i: int, day: int) -> int:
	if not tem_goiaba(i, day):
		return 0
	items[i]["fr"] = day
	_frutas_rebuild()
	return 3 + int(float(items[i].s) > 1.0) + (int(items[i].seed) % 2)


func pegar_folhas(i: int, day: int) -> int:
	if not tem_folha(i, day):
		return 0
	items[i]["fo"] = day
	return 5


## Uma vez por dia: troca as goiabas (verdes, maduras, nenhuma) conforme o mês e, bem de
## vez em quando, nasce um pé novo perto de outro (semente espalhada pelos bichos).
func dia(day: int) -> void:
	if day == _dia:
		return
	_dia = day
	if _rng.randf() < 0.03 and not items.is_empty():
		var o: Dictionary = items[_rng.randi() % items.size()]
		var a := _rng.randf() * TAU
		var x := float(o.x) + cos(a) * _rng.randf_range(6.0, 18.0)
		var z := float(o.z) + sin(a) * _rng.randf_range(6.0, 18.0)
		if _bom(x, z):
			_novo(x, z, day)
			_rebuild()
			return
	_frutas_rebuild()


func push_out(p: Vector3) -> Vector3:
	for it in items:
		var r := R_TRONCO * float(it.s)
		var dx := p.x - float(it.x)
		var dz := p.z - float(it.z)
		if absf(dx) > r or absf(dz) > r:
			continue
		var l := sqrt(dx * dx + dz * dz)
		if l < r:
			var n := Vector2(dx, dz) / l if l > 0.001 else Vector2(1, 0)
			p.x = float(it.x) + n.x * r
			p.z = float(it.z) + n.y * r
	return p


# ================== DESENHO ==================

static func _tubo(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, rng: RandomNumberGenerator) -> void:
	var lados := 7
	var eixo := (b - a).normalized()
	var u := eixo.cross(Vector3.UP if absf(eixo.y) < 0.95 else Vector3.RIGHT).normalized()
	var w := eixo.cross(u)
	var segs := maxi(2, int((b - a).length() / 0.35))
	for i in segs:
		for k in lados:
			var q := []
			for e in [[i, k], [i, k + 1], [i + 1, k + 1], [i + 1, k]]:
				var t := float(e[0]) / segs
				var an := TAU * float(e[1]) / lados
				var r := lerpf(ra, rb, t)
				var c := a.lerp(b, t)
				q.append([c + (u * cos(an) + w * sin(an)) * r, t, an])
			for idx in [0, 2, 1, 0, 3, 2]:
				var v: Array = q[idx]
				# a casca lisa que solta em placas: cobre, com manchas cinza-esverdeadas
				var c3: Vector3 = v[0]
				var m := sin(c3.y * 7.0 + cos(float(v[2]) * 2.0) * 1.6 + c3.x * 3.0) * cos(c3.y * 3.3 - float(v[2]) * 1.3 + c3.z * 4.0)
				var col := Color(0.42, 0.27, 0.18)
				if m > 0.35:
					col = Color(0.36, 0.37, 0.29)
				elif m < -0.5:
					col = Color(0.55, 0.38, 0.26)
				st.set_color(col.darkened(rng.randf() * 0.06))
				st.add_vertex(v[0])


## A folha: oval, com a ponta, um pouco dobrada no meio (a nervura).
static func _folha(st: SurfaceTool, c: Vector3, dir: Vector3, up: Vector3, L: float, col: Color) -> void:
	var side := dir.cross(up).normalized()
	var w := L * 0.28
	var b := c
	var m1 := c + dir * L * 0.35 + side * w + up * L * 0.05
	var m2 := c + dir * L * 0.35 - side * w + up * L * 0.05
	var m3 := c + dir * L * 0.7 + side * w * 0.75 + up * L * 0.02
	var m4 := c + dir * L * 0.7 - side * w * 0.75 + up * L * 0.02
	var mid := c + dir * L * 0.5 - up * L * 0.02
	var tip := c + dir * L
	var claro := col.lightened(0.08)
	for tri in [[b, m1, mid], [b, mid, m2], [m1, m3, mid], [mid, m4, m2], [m3, tip, mid], [mid, tip, m4]]:
		for k in 3:
			st.set_color(claro if k == 0 else col)
			st.add_vertex(tri[k])


static func _variante(v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + v * 131
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pontos := []
	var flores := []
	# o tronco curto, que se divide baixo em 2 ou 3 galhos tortos
	var forq := Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.55, 0.9), rng.randf_range(-0.08, 0.08))
	_tubo(st, Vector3(0, -0.1, 0), forq, 0.13, 0.1, rng)
	var nb := 2 + int(rng.randf() < 0.6)
	var a0 := rng.randf() * TAU
	var pontas := []
	for b in nb:
		var ang := a0 + TAU * b / nb + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(ang), 0, sin(ang))
		var p1 := forq + d * rng.randf_range(0.4, 0.7) + Vector3.UP * rng.randf_range(0.9, 1.3)
		var p2 := p1 + d * rng.randf_range(0.3, 0.6) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.9, 1.4), rng.randf_range(-0.3, 0.3))
		_tubo(st, forq, p1, 0.085, 0.06, rng)
		_tubo(st, p1, p2, 0.06, 0.03, rng)
		pontas.append(p2)
		# um galho do lado, mais baixo
		var lado := Vector3(-d.z, 0, d.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p3 := p1 + (d * 0.5 + lado).normalized() * rng.randf_range(0.7, 1.1) + Vector3.UP * rng.randf_range(0.2, 0.5)
		_tubo(st, p1, p3, 0.045, 0.02, rng)
		pontas.append(p3)
		var p4 := p2.lerp(p1, 0.45) + (d - lado * 0.6).normalized() * rng.randf_range(0.5, 0.8) + Vector3.UP * 0.25
		_tubo(st, p2.lerp(p1, 0.45), p4, 0.035, 0.015, rng)
		pontas.append(p4)
	# a copa: tufos de folhas nas pontas dos galhos (e um por cima de tudo)
	var topo := Vector3.ZERO
	for p in pontas:
		topo += p
	topo = topo / pontas.size() + Vector3.UP * 0.6
	pontas.append(topo)
	for p in pontas:
		var c: Vector3 = p
		var R := rng.randf_range(0.85, 1.2)
		for k in 300:
			# pontos numa bola achatada em volta da ponta do galho (mais na casca de fora)
			var u := rng.randf() * TAU
			var h := rng.randf_range(-0.55, 1.0)
			var rr := sqrt(1.0 - h * h) * R * pow(rng.randf(), 0.35)
			var pos := c + Vector3(cos(u) * rr, h * R * 0.55, sin(u) * rr)
			var fora := (pos - c).normalized()
			var dir := (fora + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 0.2), rng.randf_range(-0.6, 0.6))).normalized()
			var up := (Vector3.UP + fora * 0.4).normalized()
			if absf(dir.dot(up)) > 0.9:
				up = Vector3.RIGHT
			var col := Color(0.16, 0.3, 0.09).lerp(Color(0.27, 0.4, 0.13), rng.randf()).darkened(0.3 * (0.5 - h * 0.5))
			_folha(st, pos, dir, up, rng.randf_range(0.14, 0.2), col)
			# as goiabas penduradas na parte de baixo e de fora da copa
			if h < -0.1 and rr > R * 0.7 and rng.randf() < 0.07:
				pontos.append(pos + Vector3.DOWN * 0.05)
			if rr > R * 0.6 and rng.randf() < 0.02:
				flores.append(pos + fora * 0.03)
	st.generate_normals()
	_pontos.append(pontos)
	_flores.append(flores)
	return st.commit()


static func _assets() -> void:
	if not _meshes.is_empty():
		return
	for v in VARIANTES:
		_meshes.append(_variante(v))
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.85
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fmat = StandardMaterial3D.new()
	_fmat.vertex_color_use_as_albedo = true
	_fmat.roughness = 0.55
	# a goiaba: redonda, um pouquinho de pera, com o "umbigo" (a coroinha) embaixo
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.09
	sm.radial_segments = 10
	sm.rings = 6
	_fruta_mesh = sm


func _rebuild() -> void:
	_assets()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	var by := {}
	for p in items:
		var k := [floori(float(p.x) / CHUNK), floori(float(p.z) / CHUNK), int(p.v) % VARIANTES]
		if not by.has(k):
			by[k] = []
		by[k].append(p)
	for k in by:
		var lst: Array = by[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[int(k[2])]
		mm.instance_count = lst.size()
		for i in lst.size():
			mm.set_instance_transform(i, _xf(lst[i]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.visibility_range_end = VIEW
		add_child(mi)
		_nodes.append(mi)
	_estacao = "?"
	_frutas_rebuild()


func _xf(p: Dictionary) -> Transform3D:
	var s := float(p.s)
	var x := float(p.x)
	var z := float(p.z)
	return Transform3D(Basis(Vector3.UP, float(int(p.seed) % 628) / 100.0).scaled(Vector3(s, s, s)), Vector3(x, _jogo.ground_at(x, z), z))


## As goiabas (verdes ou amarelas) e as flores brancas, conforme o mês.
func _frutas_rebuild() -> void:
	if _jogo == null:
		return
	var day := int(_jogo.sim.elapsed_days())
	var est := estacao(day)
	for n in _frutas:
		if is_instance_valid(n):
			n.free()
	_frutas.clear()
	_estacao = est
	if est == "":
		return
	var grupos := {}                     # um pedaço do mapa por vez (a distância de ver)
	for p in items:
		var gk := Vector2i(floori(float(p.x) / CHUNK), floori(float(p.z) / CHUNK))
		if not grupos.has(gk):
			grupos[gk] = [[], []]
		var tr: Array = grupos[gk][0]
		var cores: Array = grupos[gk][1]
		if est == "madura" and int(p.get("fr", -1)) == day:
			continue                     # já pegaram as maduras de hoje
		var xf := _xf(p)
		var lst: Array = _flores[int(p.v) % VARIANTES] if est == "flor" else _pontos[int(p.v) % VARIANTES]
		var r2 := RandomNumberGenerator.new()
		r2.seed = int(p.seed)
		for q in lst:
			if est == "madura" and r2.randf() < 0.25:
				continue
			var sc := r2.randf_range(0.8, 1.15) * (0.35 if est == "flor" else (0.75 if est == "verde" else 1.0))
			tr.append(xf * Transform3D(Basis(Vector3(r2.randf(), r2.randf(), r2.randf()).normalized(), r2.randf_range(-0.4, 0.4)).scaled(Vector3(sc, sc, sc)), q))
			var c := Color(0.97, 0.96, 0.9)
			if est == "verde":
				c = Color(0.34, 0.5, 0.16).lerp(Color(0.45, 0.58, 0.2), r2.randf())
			elif est == "madura":
				c = Color(0.86, 0.8, 0.28).lerp(Color(0.72, 0.74, 0.25), r2.randf())
			cores.append(c)
	for gk in grupos:
		_frutas_chunk(grupos[gk][0], grupos[gk][1], est)


func _frutas_chunk(tr: Array, cores: Array, est: String) -> void:
	if tr.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _fruta_mesh
	mm.instance_count = tr.size()
	for i in tr.size():
		mm.set_instance_transform(i, tr[i])
		mm.set_instance_color(i, cores[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _fmat
	mi.visibility_range_end = FRUTA_VIEW if est != "flor" else 30.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_frutas.append(mi)


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "goiabeiras": items}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("goiabeiras", [])
	for it in items:
		it["v"] = int(it.get("v", 0))
		it["seed"] = int(it.get("seed", 0))
		it["fr"] = int(it.get("fr", -1))
		it["fo"] = int(it.get("fo", -1))
	return true
