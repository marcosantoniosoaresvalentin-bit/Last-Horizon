extends Node3D
## Jararaca-taia (Dracontium, da família do taioba): planta da sombra da mata amazônica.
## Uma folha só, grande e recortada, em cima de um talo alto e grosso todo pintado de
## manchas (parece a pele da jararaca: daí o nome); embaixo da terra, uma batata. O povo
## da mata usa a batata contra picada de cobra. Arrancada, a planta vai embora; ela se
## espalha sozinha devagar (brota do lado das outras, na sombra).

const MundoSim := preload("res://scripts/mundo_sim.gd")
const COUNT := 90
const CHUNK := 48.0
const VIEW := 50.0

## Cada planta: {x, z, s (tamanho), seed, nasc}
var items: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _chunks := {}
var _dia := -1
static var _mesh: ArrayMesh
static var _mat: StandardMaterial3D


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9137
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild()


func _generate() -> void:
	var arv = _jogo._arvores
	if arv == null or arv.plants.is_empty():
		return
	var tries := 0
	while items.size() < COUNT and tries < COUNT * 12:
		tries += 1
		var p: Array = arv.plants[_rng.randi() % arv.plants.size()]
		var a := _rng.randf() * TAU
		var x := float(p[0]) + cos(a) * _rng.randf_range(1.5, 5.0)
		var z := float(p[1]) + sin(a) * _rng.randf_range(1.5, 5.0)
		if _bom(x, z):
			items.append({"x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "s": snappedf(_rng.randf_range(0.8, 1.2), 0.01), "seed": _rng.randi() % 100000, "nasc": -400})


## Chão da mata: seco, fora da praia, não colado em outra taia.
func _bom(x: float, z: float) -> bool:
	var cell: float = _jogo.CELL
	var cl := Vector2i(int(x / cell), int(z / cell))
	if _jogo.sim.water_at(cl) > 0.02:
		return false
	var sd: Dictionary = _jogo.sim.soil_data(cl)
	if not sd.is_empty() and float(sd.sand) > 0.5:
		return false
	if _jogo.height_at(x, z) < MundoSim.SEA * _jogo.HS + 0.8:
		return false
	for it in items:
		if Vector2(float(it.x) - x, float(it.z) - z).length() < 2.5:
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


## Arranca: devolve quantas batatas (1 ou 2, a planta grande dá 2).
func arrancar(i: int) -> int:
	var n := 2 if float(items[i].s) > 1.05 else 1
	items.remove_at(i)
	_rebuild()
	return n


## Uma vez por dia: brota uma nova do lado das que existem (devagar).
func dia(day: int) -> void:
	if day == _dia:
		return
	_dia = day
	var novas := []
	for it in items:
		if _rng.randf() < 0.004:
			var a := _rng.randf() * TAU
			var d := _rng.randf_range(3.0, 12.0)
			var x := float(it.x) + cos(a) * d
			var z := float(it.z) + sin(a) * d
			if _bom(x, z):
				novas.append({"x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "s": snappedf(_rng.randf_range(0.8, 1.2), 0.01), "seed": _rng.randi() % 100000, "nasc": day})
	if not novas.is_empty():
		items.append_array(novas)
		_rebuild()


# ================== DESENHO ==================

## O talo pintado (verde-acinzentado com manchas escuras e claras) e a folha grande em
## cima: três braços, cada um recortado em folíolos compridos, em guarda-chuva.
static func planta_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var H := 1.05
	var lean := Vector3(0.06, 0, 0.03)
	var segs := 10
	var sides := 7
	var verde := Color(0.36, 0.42, 0.3)
	var escuro := Color(0.14, 0.15, 0.11)
	var claro := Color(0.62, 0.62, 0.5)
	for i in segs:
		for k in sides:
			var q := []
			for e in [[i, k], [i, k + 1], [i + 1, k + 1], [i + 1, k]]:
				var t := float(e[0]) / segs
				var a := TAU * float(e[1]) / sides
				var r := lerpf(0.028, 0.016, t)
				var c := lean * t * t + Vector3.UP * H * t
				q.append([c + Vector3(cos(a) * r, 0, sin(a) * r), t, a])
			for idx in [0, 2, 1, 0, 3, 2]:
				var v: Array = q[idx]
				# as manchas da "pele de cobra"
				var m := sin(float(v[1]) * 38.0 + cos(float(v[2]) * 3.0) * 2.0) * cos(float(v[2]) * 2.0 + float(v[1]) * 13.0)
				var col := verde
				if m > 0.45:
					col = escuro
				elif m < -0.6:
					col = claro
				st.set_color(col)
				st.add_vertex(v[0])
	# a folha: três braços saindo do topo, cada um com folíolos
	var top := lean + Vector3.UP * H
	var folha := Color(0.2, 0.36, 0.14)
	for b in 3:
		var ang := TAU * b / 3.0 + 0.3
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var nf := 5
		for f in nf:
			var t := (float(f) + 0.5) / nf
			var base := top + dir * (0.08 + t * 0.42) + Vector3.UP * (0.05 - t * t * 0.18)
			for sg in [-1.0, 1.0]:
				var fd: Vector3 = (dir * 0.45 + side * float(sg)).normalized()
				var L := 0.24 - t * 0.08
				var w := 0.045
				var tip: Vector3 = base + fd * L + Vector3.UP * (-0.05 * L / 0.24)
				var mid: Vector3 = base + fd * L * 0.45
				var pts := [base, mid + fd.cross(Vector3.UP).normalized() * w, tip, mid - fd.cross(Vector3.UP).normalized() * w]
				for idx in [0, 1, 2, 0, 2, 3]:
					st.set_color(folha.darkened(0.08 * (f % 2)))
					st.add_vertex(pts[idx])
		# o nervo do braço
		var p0 := top
		var p1 := top + dir * 0.55 + Vector3.UP * -0.12
		var w2 := side * 0.008
		for v in [p0 - w2, p1 - w2, p1 + w2, p0 - w2, p1 + w2, p0 + w2]:
			st.set_color(Color(0.3, 0.38, 0.22))
			st.add_vertex(v)
	st.generate_normals()
	_mesh = st.commit()
	return _mesh


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.8
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


func _ck(p: Dictionary) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.z) / CHUNK))


func _rebuild() -> void:
	for k in _chunks:
		if is_instance_valid(_chunks[k]):
			_chunks[k].free()
	_chunks.clear()
	var by := {}
	for p in items:
		var k := _ck(p)
		if not by.has(k):
			by[k] = []
		by[k].append(p)
	for k in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = planta_mesh()
		var lst: Array = by[k]
		mm.instance_count = lst.size()
		for i in lst.size():
			var p: Dictionary = lst[i]
			var s := float(p.s)
			var x := float(p.x)
			var z := float(p.z)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(int(p.seed) % 628) / 100.0).scaled(Vector3(s, s, s)), Vector3(x, _jogo.ground_at(x, z) - 0.02, z)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _material()
		mi.visibility_range_end = VIEW
		add_child(mi)
		_chunks[k] = mi


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "taias": items}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("taias", [])
	return true
