extends Node3D
## Capim alto em touceiras (mais alto que a grama do chão), em manchas pelo mapa.
## Fica verde a maior parte do mês e seca numa época (do dia 18 ao 30): aí fica cor de
## palha e dá para colher (vira maços de capim seco: a isca do fogo e a liga do barro).
## Colhida, a touceira fica rente ao chão e volta a crescer em uns 10 dias.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const COUNT := 520
const CHUNK := 48.0
const VIEW := 55.0
const SECA_DE := 18             # do dia 18 ao fim do mês o capim seca
const REBROTA := 10             # dias para voltar a crescer depois de colhido
const MACOS := 2                # maços de capim seco por touceira

## Cada touceira: {x, z, s (tamanho), seed, corte (dia em que foi colhida, -1)}
var items: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _chunks := {}
var _dia := -1
static var _mesh: ArrayMesh
static var _mat: StandardMaterial3D


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 7717
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild()


func _generate() -> void:
	var cell: float = _jogo.CELL
	var w: float = MundoSim.W * cell
	var h: float = MundoSim.H * cell
	var tries := 0
	while items.size() < COUNT and tries < COUNT * 8:
		tries += 1
		var x := _rng.randf_range(6.0, w - 6.0)
		var z := _rng.randf_range(6.0, h - 6.0)
		if not _bom(x, z):
			continue
		# em manchas (o capim gosta do aberto)
		var n := _rng.randi_range(4, 9)
		for k in n:
			var px := clampf(x + _rng.randf_range(-3.0, 3.0), 3.0, w - 3.0)
			var pz := clampf(z + _rng.randf_range(-3.0, 3.0), 3.0, h - 3.0)
			if _bom(px, pz):
				items.append({"x": snappedf(px, 0.01), "z": snappedf(pz, 0.01), "s": snappedf(_rng.randf_range(0.85, 1.25), 0.01), "seed": _rng.randi() % 100000, "corte": -1})


## Chão bom para o capim: seco, fora da praia.
func _bom(x: float, z: float) -> bool:
	var cell: float = _jogo.CELL
	var cl := Vector2i(int(x / cell), int(z / cell))
	if _jogo.sim.water_at(cl) > 0.02:
		return false
	var sd: Dictionary = _jogo.sim.soil_data(cl)
	if not sd.is_empty() and float(sd.sand) > 0.55:
		return false
	return _jogo.height_at(x, z) > MundoSim.SEA * _jogo.HS + 0.6


func _dia_agora() -> int:
	return int(_jogo.sim.elapsed_days())


## Quanto seco (0 verde, 1 palha) no dia: vai amarelando do dia 16 ao 19.
func seco_de(day: int) -> float:
	var dm := day % 30
	return clampf(float(dm - (SECA_DE - 2)) / 3.0, 0.0, 1.0)


## Colhida e ainda crescendo de novo?
func cortado(p: Dictionary) -> bool:
	return int(p.get("corte", -1)) >= 0 and _dia_agora() - int(p.corte) < REBROTA


## Touceira mais perto (ou -1).
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


## Dá para colher agora (seca e crescida)?
func colhivel(i: int) -> bool:
	return i >= 0 and not cortado(items[i]) and seco_de(_dia_agora()) >= 0.99


func point_of(i: int) -> Vector3:
	var p: Dictionary = items[i]
	return Vector3(float(p.x), _jogo.height_at(float(p.x), float(p.z)), float(p.z))


func colher(i: int) -> void:
	items[i].corte = _dia_agora()
	_rebuild()


## Uma vez por dia: a cor muda (verde, amarelando, palha) e o colhido rebrota.
func dia(day: int) -> void:
	if day == _dia:
		return
	_dia = day
	_rebuild()


# ================== DESENHO ==================

## A touceira: umas 30 folhas compridas e finas saindo do mesmo pé, abertas e curvadas.
static func _clump_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for b in 30:
		var ang := TAU * b / 30.0 + rng.randf_range(-0.3, 0.3)
		var lean := rng.randf_range(0.1, 0.6)
		var L := rng.randf_range(0.6, 1.15)
		var w0 := rng.randf_range(0.02, 0.034)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var segs := 5
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in segs + 1:
			var t := float(k) / segs
			var c := dir * (lean * L * t * t * 0.8 + 0.03) + Vector3.UP * (L * t - lean * L * t * t * 0.35)
			var w := w0 * (1.0 - t * 0.9)
			var l := c - side * w
			var r := c + side * w
			if k > 0:
				for v in [prev_l, prev_r, r, prev_l, r, l]:
					st.set_uv(Vector2(0, t))
					st.add_vertex(v)
			prev_l = l
			prev_r = r
	st.generate_normals()
	_mesh = st.commit()
	return _mesh


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.9
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
	var day := _dia_agora()
	var sec := seco_de(day)
	var verde := Color(0.3, 0.5, 0.16)
	var palha := Color(0.62, 0.51, 0.3)
	for k in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _clump_mesh()
		var lst: Array = by[k]
		mm.instance_count = lst.size()
		for i in lst.size():
			var p: Dictionary = lst[i]
			var s := float(p.s)
			var hy := s
			var col := verde.lerp(palha, sec)
			if cortado(p):
				# colhido: só o toco rente ao chão, rebrotando verde
				var g := float(day - int(p.corte)) / REBROTA
				hy = s * lerpf(0.12, 0.6, g)
				col = verde.lerp(palha, 0.35).lerp(verde, g)
			var tone := float(int(p.seed) % 100) / 100.0
			col = col.darkened(tone * 0.15)
			var x := float(p.x)
			var z := float(p.z)
			var b := Basis(Vector3.UP, float(int(p.seed) % 628) / 100.0).scaled(Vector3(s, hy, s))
			mm.set_instance_transform(i, Transform3D(b, Vector3(x, _jogo.height_at(x, z) - 0.03, z)))
			mm.set_instance_color(i, col)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _material()
		mi.visibility_range_end = VIEW
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[k] = mi


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "capins": items}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("capins", [])
	return true
