extends Node3D
## Galhos caídos no chão.
##
## - Árvores que estão morrendo soltam galhos secos, que caem perto delas.
## - Os galhos da copa de uma árvore derrubada também podem ser cortados com o
##   machado e caem no chão.
## - Galho grande não dá para pegar: primeiro corta com o machado em 2 pedaços.
##   Depois cada pedaço pode ser pego (vira 1 "galho" na mochila).

const GalhoGeo := preload("res://scripts/world/galho_geo.gd")
const MAX := 160
const LEAF_DAYS := 45            # dias até o monte de folhas cortadas sumir
const PER_TREE := 3
const CUT_HITS := 2

## Cada galho: {x, z, yaw, len (m), r (grossura), inteiro (precisa cortar), seco}
var items: Array = []
## Montes de folhas que caíram dos galhos cortados: {x, z, y (chão), yaw, v, ci, s, dia, tint}
var folhas: Array = []
var last_day := 0
var _jogo: Node
var _arv: Node
var _nodes: Array = []
var _mat: StandardMaterial3D
var _wood: StandardMaterial3D
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
	_wood = GalhoGeo.wood_material()
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
	folhas = folhas.filter(func(f): return last_day - int(f.dia) < LEAF_DAYS)
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
	if int(_cuts[i]) < CUT_HITS and not bool(_jogo.teste):
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


## Folhas do galho cortado no chão (cacho de folhas do modelo da árvore, amassado no chão).
func add_leaves(x: float, z: float, y: float, yaw: float, v: int, ci: int, s: float, tint: Color) -> void:
	folhas.append({"x": x, "z": z, "y": y, "yaw": yaw, "v": v, "ci": ci, "s": s, "dia": last_day,
		"tint": [tint.r, tint.g, tint.b, tint.a]})


## Nó de um cacho de folhas no lugar dele (para a animação de queda e para o monte no chão).
func leaves_node(v: int, ci: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _arv.cluster_mesh(v, ci)
	mi.material_override = _arv.leaf_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ================== DESENHO ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	for f in folhas:
		var mi := leaves_node(int(f.v), int(f.ci))
		var aabb: AABB = mi.mesh.get_aabb()
		var sc := float(f.s)
		var b := Basis(Vector3.UP, float(f.yaw)).scaled(Vector3(sc * 0.62, sc * 0.4, sc * 0.62))
		var c := aabb.get_center()
		mi.transform = Transform3D(b, Vector3(float(f.x), float(f.y) + aabb.size.y * sc * 0.12, float(f.z)) - b * c)
		# secam no chão: do verde/amarelo da hora do corte para marrom
		var t0: Array = f.tint
		var age := clampf(float(last_day - int(f.dia)) / 12.0, 0.0, 1.0)
		var col := Color(float(t0[0]), float(t0[1]), float(t0[2])).lerp(Color(0.42, 0.27, 0.12), age)
		col.a = maxf(float(t0[3]), age)
		mi.set_instance_shader_parameter("tint", col)
		mi.visibility_range_end = 90.0
		add_child(mi)
		_nodes.append(mi)
	if items.is_empty():
		return
	var bd := GalhoGeo.Builder.new()
	for g in items:
		_branch_geo(bd, g)
	var mi := MeshInstance3D.new()
	mi.mesh = bd.commit()
	mi.set_surface_override_material(0, _arv.bark_material())
	if mi.mesh.get_surface_count() > 1:
		mi.set_surface_override_material(1, _wood)
	mi.visibility_range_end = 90.0
	add_child(mi)
	_nodes.append(mi)


## Galho deitado no chão: torto, afinando, com um ou dois galhinhos; pedaço cortado
## tem a madeira clara do corte nas pontas.
func _branch_geo(bd, g: Dictionary) -> void:
	var x := float(g.x)
	var z := float(g.z)
	var yaw := float(g.yaw)
	var length := float(g.len)
	var r := float(g.r)
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-dir.z, 0, dir.x)
	var hsh := absi(hash(Vector2(x, z)))
	var pts := []
	var radii := []
	var segs := 8
	for k in segs + 1:
		var t := float(k) / segs
		var p := Vector3(x, 0, z) + dir * (t - 0.5) * length + side * sin(t * 3.0 + float(hsh % 7)) * 0.06
		var rr := r * lerpf(1.0, 0.6, t)
		p.y = _jogo.surface_at(p.x, p.z) + rr * 0.9
		pts.append(p)
		radii.append(rr)
	var piece := not bool(g.inteiro)
	bd.tube(pts, radii, [true, piece], {}, 8)
	# galhinhos saindo do galho
	var twigs := 2 if bool(g.inteiro) else 1
	for k in twigs:
		var t := 0.35 + 0.3 * k
		var base: Vector3 = pts[int(t * segs)]
		var sgn := 1.0 if (hsh >> k) % 2 == 0 else -1.0
		var tip := base + (dir * 0.25 + side * sgn * 0.45).normalized() * length * 0.28
		tip.y = _jogo.surface_at(tip.x, tip.z) + 0.03
		var bp: Array = GalhoGeo.bent_points(base, tip, r * 0.4, r * 0.15, 3, 0.02, hsh + k)
		bd.tube(bp[0], bp[1], [false, false], {}, 5)


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "galhos": items, "folhas": folhas}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("galhos", [])
	folhas = d.get("folhas", [])
	if _jogo.sim.converted:
		# o mundo virou ilha e o chão subiu: as folhas vão junto
		for fo in folhas:
			fo.y = _jogo.surface_at(float(fo.x), float(fo.z))
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
