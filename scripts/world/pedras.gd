extends Node3D
## Pedras pequenas soltas no chão.
##
## - Todas dá para pegar (vira "pedra" na mochila).
## - Com uma pedra na mão, dá para modelar a pedra do chão (bater com uma na outra)
##   e fazer as pedras das ferramentas. O que já foi lascado fica salvo na pedra.
## - Pedra que rachou no meio não serve mais para modelar.

const Lascar := preload("res://scripts/world/lascar.gd")
const MundoSim := preload("res://scripts/mundo_sim.gd")
const COUNT := 260
const CHUNK := 48.0
const VIEW := 45.0

## Cada pedra: {x, z, yaw, s (tamanho em m), seed, kind ("" crua), cur (raios, se já lascou),
## spots (lascas já tiradas), rachada}
var items: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _chunks := {}          # Vector2i -> MeshInstance3D
var _hidden := -1          # pedra sendo modelada (desenhada à parte, grande e detalhada)


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 5501
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild_all()


func _generate() -> void:
	var cell: float = _jogo.CELL
	var w: float = MundoSim.W * cell
	var h: float = MundoSim.H * cell
	var tries := 0
	while items.size() < COUNT and tries < COUNT * 6:
		tries += 1
		var x := _rng.randf_range(4.0, w - 4.0)
		var z := _rng.randf_range(4.0, h - 4.0)
		var cl := Vector2i(int(x / cell), int(z / cell))
		if _jogo.sim.water_at(cl) > 0.02:
			continue
		# pedras juntas em grupinhos (onde a terra é mais rasa)
		var n := _rng.randi_range(1, 3)
		for k in n:
			var px := clampf(x + _rng.randf_range(-1.5, 1.5), 2.0, w - 2.0)
			var pz := clampf(z + _rng.randf_range(-1.5, 1.5), 2.0, h - 2.0)
			add(px, pz, _rng.randf() * TAU, _rng.randf_range(0.22, 0.36), _rng.randi())


func add(x: float, z: float, yaw: float, size: float, seed_: int) -> void:
	items.append({"x": x, "z": z, "yaw": yaw, "s": size, "seed": seed_, "kind": "", "spots": 0, "rachada": false})


# ================== PEGAR ==================

func nearest(pos: Vector3, reach: float, workable := false) -> int:
	var best := -1
	var bd := reach
	for i in items.size():
		var p: Dictionary = items[i]
		if workable and bool(p.get("rachada", false)):
			continue
		var d := Vector2(float(p.x) - pos.x, float(p.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func point_of(i: int) -> Vector3:
	var p: Dictionary = items[i]
	return Vector3(float(p.x), _jogo.surface_at(float(p.x), float(p.z)), float(p.z))


func take(i: int) -> void:
	var ck := _ck(items[i])
	items.remove_at(i)
	_rebuild_chunk(ck)


# ================== FORMA ==================

func radii(i: int) -> PackedFloat32Array:
	var p: Dictionary = items[i]
	if p.has("cur") and (p.cur as Array).size() == Lascar.SIZE:
		return PackedFloat32Array(p.cur)
	return Lascar.rock(int(p.seed))


func set_radii(i: int, cur: PackedFloat32Array) -> void:
	var a := []
	for v in cur:
		a.append(snappedf(v, 0.0005))
	items[i].cur = a
	_rebuild_chunk(_ck(items[i]))


## Onde a pedra i está no mundo (centro, deitada no chão, girada).
func xform(i: int) -> Transform3D:
	var p: Dictionary = items[i]
	var s := float(p.s)
	var cur := radii(i)
	var b := Basis(Vector3.UP, float(p.yaw)).scaled(Vector3(s, s, s))
	var y: float = _jogo.surface_at(float(p.x), float(p.z)) - Lascar.bottom(cur) * s - 0.01
	return Transform3D(b, Vector3(float(p.x), y, float(p.z)))


## Esconde a pedra do chão enquanto ela está sendo modelada (desenhada à parte).
func hide_stone(i: int) -> void:
	var old := _hidden
	_hidden = i
	if old >= 0 and old < items.size():
		_rebuild_chunk(_ck(items[old]))
	if i >= 0 and i < items.size():
		_rebuild_chunk(_ck(items[i]))


# ================== DESENHO ==================

func _ck(p: Dictionary) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.z) / CHUNK))


func _rebuild_all() -> void:
	for k in _chunks:
		if is_instance_valid(_chunks[k]):
			_chunks[k].free()
	_chunks.clear()
	var keys := {}
	for p in items:
		keys[_ck(p)] = true
	for k in keys:
		_rebuild_chunk(k)


func _rebuild_chunk(ck: Vector2i) -> void:
	if _chunks.has(ck) and is_instance_valid(_chunks[ck]):
		_chunks[ck].free()
	_chunks.erase(ck)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for i in items.size():
		var p: Dictionary = items[i]
		if i == _hidden or _ck(p) != ck:
			continue
		any = true
		var cur := radii(i)
		var m := Lascar.mesh(cur, Lascar.rock(int(p.seed)), int(p.seed), bool(p.get("rachada", false)))
		st.append_from(m, 0, xform(i))
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Lascar.material()
	mi.visibility_range_end = VIEW
	add_child(mi)
	_chunks[ck] = mi


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "pedras": items}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("pedras", [])
	for p in items:
		if float(p.s) < 0.2 and str(p.get("kind", "")) == "" and not p.has("cur"):
			p.s = float(p.s) * 1.6          # as pedras ficaram maiores numa atualização
	return true
