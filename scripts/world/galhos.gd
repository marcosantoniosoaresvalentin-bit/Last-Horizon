extends Node3D
## Galhos caídos no chão.
##
## - Árvores que estão morrendo soltam galhos secos, que caem perto delas.
## - Os galhos da copa de uma árvore derrubada também podem ser cortados com o
##   machado e caem no chão.
## - Galho grande não dá para pegar: primeiro corta com o machado em 2 pedaços.
##   Depois cada pedaço pode ser pego (vira 1 "galho" na mochila).

const MAX := 160
const PER_TREE := 3
const CUT_HITS := 2

## Cada galho: {x, z, yaw, len (m), r (grossura), inteiro (precisa cortar), seco}
var items: Array = []
var last_day := 0
var _jogo: Node
var _arv: Node
var _nodes: Array = []
var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _cuts := {}                 # índice -> machadadas já dadas


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9907
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild()


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	while last_day < day:
		last_day += 1
		_drop_from_dying()
	_rebuild()


func _dying_trees() -> Array:
	var out := []
	for p in _arv.plants:
		if int(p[5]) == 1 and _arv.height_of(p, last_day) > 6.0:
			out.append(p)
	return out


func _near_count(x: float, z: float, r: float) -> int:
	var n := 0
	for g in items:
		if Vector2(float(g.x) - x, float(g.z) - z).length() < r:
			n += 1
	return n


## Árvore secando solta um galho de vez em quando (cai em volta dela).
func _drop_from_dying() -> void:
	if items.size() >= MAX:
		return
	for p in _dying_trees():
		if _rng.randf() > 0.015:
			continue
		if _near_count(float(p[0]), float(p[1]), 8.0) >= PER_TREE:
			continue
		_drop_near(p)


func _drop_near(p: Array) -> void:
	var h: float = _arv.height_of(p, last_day)
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(1.5, 2.0 + h * 0.2)
	var x := clampf(float(p[0]) + cos(a) * d, 2.0, 638.0)
	var z := clampf(float(p[1]) + sin(a) * d, 2.0, 478.0)
	add(x, z, _rng.randf() * TAU, _rng.randf_range(1.6, 2.8), _rng.randf_range(0.04, 0.07), true)


func _generate() -> void:
	for p in _dying_trees():
		for k in _rng.randi_range(1, PER_TREE):
			_drop_near(p)


## Põe um galho no chão. inteiro = grande (precisa cortar antes de pegar).
func add(x: float, z: float, yaw: float, length: float, r: float, seco := true, inteiro := true) -> void:
	items.append({"x": x, "z": z, "yaw": yaw, "len": length, "r": r, "inteiro": inteiro, "seco": seco})


# ================== CORTAR E PEGAR ==================

## Galho no chão mais perto. inteiro=true: só os grandes (cortar); false: só os pedaços (pegar).
func nearest(pos: Vector3, reach: float, inteiro: bool) -> int:
	var best := -1
	var bd := reach
	for i in items.size():
		var g: Dictionary = items[i]
		if bool(g.inteiro) != inteiro:
			continue
		var d := Vector2(float(g.x) - pos.x, float(g.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func point_of(i: int) -> Vector3:
	var g: Dictionary = items[i]
	return Vector3(float(g.x), _jogo.surface_at(float(g.x), float(g.z)) + float(g.r), float(g.z))


## Uma machadada no galho grande. Na segunda ele se parte em 2 pedaços.
func chop(i: int) -> bool:
	_cuts[i] = int(_cuts.get(i, 0)) + 1
	if int(_cuts[i]) < CUT_HITS:
		return false
	_cuts.clear()
	var g: Dictionary = items[i]
	items.remove_at(i)
	var dir := Vector2(cos(float(g.yaw)), sin(float(g.yaw)))
	var half := float(g.len) * 0.5
	for k in [-1.0, 1.0]:
		var c: Vector2 = Vector2(float(g.x), float(g.z)) + dir * k * (half * 0.5 + 0.08)
		add(c.x, c.y, float(g.yaw) + _rng.randf_range(-0.25, 0.25), half, float(g.r), bool(g.seco), false)
	_rebuild()
	return true


func take(i: int) -> void:
	items.remove_at(i)
	_cuts.clear()
	_rebuild()


# ================== DESENHO ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if items.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in items:
		_branch_geo(st, g)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.visibility_range_end = 90.0
	add_child(mi)
	_nodes.append(mi)


## Galho deitado no chão: torto, afinando, com um ou dois galhinhos; pedaço cortado
## tem a ponta clara do corte.
func _branch_geo(st: SurfaceTool, g: Dictionary) -> void:
	var x := float(g.x)
	var z := float(g.z)
	var yaw := float(g.yaw)
	var length := float(g.len)
	var r := float(g.r)
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-dir.z, 0, dir.x)
	var hsh := absi(hash(Vector2(x, z)))
	var bark := Color(0.3, 0.24, 0.17) if bool(g.seco) else Color(0.28, 0.2, 0.12)
	var pts := []
	var segs := 6
	for k in segs + 1:
		var t := float(k) / segs
		var p := Vector3(x, 0, z) + dir * (t - 0.5) * length + side * sin(t * 3.0 + float(hsh % 7)) * 0.06
		var rr := r * lerpf(1.0, 0.55, t)
		p.y = _jogo.surface_at(p.x, p.z) + rr * 0.9
		pts.append([p, rr])
	for k in segs:
		_tube(st, pts[k][0], pts[k + 1][0], float(pts[k][1]), float(pts[k + 1][1]), bark.darkened(0.06 * (k % 2)))
	# galhinhos saindo do galho
	var twigs := 2 if bool(g.inteiro) else 1
	for k in twigs:
		var t := 0.35 + 0.3 * k
		var base: Vector3 = (pts[int(t * segs)][0] as Vector3)
		var sgn := 1.0 if (hsh >> k) % 2 == 0 else -1.0
		var tip := base + (dir * 0.25 + side * sgn * 0.45).normalized() * length * 0.28
		tip.y = _jogo.surface_at(tip.x, tip.z) + 0.03
		_tube(st, base, tip, r * 0.4, r * 0.15, bark)
	# pontas cortadas (madeira clara) nos pedaços
	if not bool(g.inteiro):
		var wood := Color(0.62, 0.5, 0.33)
		for e in [[pts[0][0], -dir, pts[0][1]], [pts[segs][0], dir, pts[segs][1]]]:
			var c: Vector3 = e[0]
			var n: Vector3 = e[1]
			var rr: float = e[2]
			var a := n.cross(Vector3.UP).normalized()
			var b := n.cross(a).normalized()
			for k in 8:
				var a0 := TAU * k / 8.0
				var a1 := TAU * (k + 1) / 8.0
				st.set_color(wood)
				st.add_vertex(c)
				st.add_vertex(c + (a * cos(a0) + b * sin(a0)) * rr)
				st.add_vertex(c + (a * cos(a1) + b * sin(a1)) * rr)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var s2 := d.cross(s1).normalized()
	st.set_color(col)
	var n := 6
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := s1 * cos(a0) + s2 * sin(a0)
		var o1 := s1 * cos(a1) + s2 * sin(a1)
		for v in [a + o0 * ra, b + o0 * rb, b + o1 * rb, a + o0 * ra, b + o1 * rb, a + o1 * ra]:
			st.add_vertex(v)


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "galhos": items}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("galhos", [])
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
