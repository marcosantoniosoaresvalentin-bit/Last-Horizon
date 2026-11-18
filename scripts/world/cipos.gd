extends Node3D
## Cipó-titica (Heteropsis flexuosa): trepadeira amazônica que sobe nas árvores.
##
## Ciclo de vida (contado em dias do calendário do jogo):
##  - Semente cai no chão; brota em 2 a 3 meses se o solo estiver úmido e houver
##    uma árvore perto para servir de apoio (senão morre).
##  - Muda: roseta de folhinhas no chão, perto do tronco.
##  - Jovem: sobe pelo tronco em espiral, devagar (uns 2 m por ano no melhor caso),
##    mais rápido com solo úmido e na época quente e chuvosa; quase para na seca.
##  - Adulta (passou de ~4 m de altura): solta raízes aéreas, as "titicas", que
##    descem do alto até o chão. Raiz que chegou no chão está madura e pode ser colhida.
##  - Flores (setembro a novembro): insetos polinizam. Frutos laranja (dezembro a
##    fevereiro): aves e bichos pequenos comem e soltam as sementes por perto.
##  - Se a árvore de apoio morre ou é derrubada, a titica morre junto. Seca forte
##    mata mudas.
## Coleta: o jogador puxa as raízes que quiser e pode até arrancar o pé inteiro
## (aí a planta acaba). Raiz colhida volta a crescer se o pé ficar.

const MAX_PLANTS := 320
const START_PLANTS := 70
const ADULT_H := 4.0            # m de altura no tronco para começar a soltar raízes
const GERM_MIN := 60
const GERM_MAX := 95
const VIEW := 85.0

var plants: Array = []          # cada uma é um Dictionary (veja _new_plant)
var seeds: Array = []           # [x, z, dia que caiu, dia que brota]
var last_day := 0
var _jogo: Node
var _arv: Node
var _rng := RandomNumberGenerator.new()
var _nodes: Array = []
var _mat: StandardMaterial3D
var _tree_cache := {}           # chave da árvore -> planta da árvore (refeito todo dia)


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 5501
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.roughness = 0.6
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate()
	plants = plants.filter(func(pl): return not _arv._in_sea(float(pl.x), float(pl.z)))   # nada de cipó no mar
	_rebuild()


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	while last_day < day:
		last_day += 1
		_process_day(last_day)
	_rebuild()


# ================== VIDA ==================

func _new_plant(x: float, z: float, host, born: int) -> Dictionary:
	return {"x": x, "z": z, "host": [float(host[0]), float(host[1])] if host != null else null,
		"born": born, "climb": 0.0, "a0": _rng.randf() * TAU, "roots": [], "dead": -1,
		"vigor": _rng.randf_range(0.8, 1.2)}


## Árvore boa para apoio mais perto (grande o bastante e em pé).
func _host_near(x: float, z: float, r: float) -> Variant:
	var best = null
	var bd := r
	for p in _arv.plants:
		if int(p[5]) == 2:
			continue
		if _arv.height_of(p, last_day) < 6.0:
			continue
		var d := Vector2(float(p[0]) - x, float(p[1]) - z).length()
		if d < bd:
			bd = d
			best = p
	return best


func _host_of(pl: Dictionary) -> Variant:
	if pl.host == null:
		return null
	var k := Vector2(float(pl.host[0]), float(pl.host[1]))
	if _tree_cache.has(k):
		return _tree_cache[k]
	return null


func _water_at(x: float, z: float) -> float:
	var cell := Vector2i(int(x / _jogo.CELL), int(z / _jogo.CELL))
	return float(_jogo.sim.ground_water(cell))


static func _month_of(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


func _process_day(day: int) -> void:
	_tree_cache.clear()
	for p in _arv.plants:
		if int(p[5]) != 2:
			_tree_cache[Vector2(float(p[0]), float(p[1]))] = p
	var month := _month_of(day)
	var wet: float = _jogo.sim.wetness()
	var keep := []
	for pl in plants:
		if int(pl.dead) >= 0:
			if day - int(pl.dead) < 60:
				keep.append(pl)      # seca e some em uns dois meses
			continue
		var host = _host_of(pl)
		if host == null:
			pl.dead = day            # a árvore de apoio caiu ou morreu
			keep.append(pl)
			continue
		var water := _water_at(float(pl.x), float(pl.z))
		var climb := float(pl.climb)
		# seca forte mata a muda pequena
		if climb < 0.6 and water < 0.12 and _rng.randf() < 0.01:
			pl.dead = day
			keep.append(pl)
			continue
		# cresce devagar: umidade, calor/chuva da estação e o vigor de cada planta
		var grow := 0.0065 * float(pl.vigor) * clampf(water * 1.6, 0.0, 1.0) * lerpf(0.25, 1.0, wet)
		var host_h: float = _arv.height_of(host, day)
		var top := minf(host_h * 0.72, 18.0)
		pl.climb = minf(climb + grow, top)
		# adulta: solta raízes aéreas que descem até o chão
		var roots: Array = pl.roots
		if climb >= ADULT_H:
			var want := clampi(int(2 + (climb - ADULT_H) * 0.9), 2, 9)
			if roots.size() < want and _rng.randf() < 0.012:
				var at := _rng.randf_range(maxf(ADULT_H * 0.8, climb * 0.55), climb)
				roots.append([_rng.randf_range(-0.6, 0.6), at, 0.0, -1])   # [ângulo, altura, comprimento, dia colhida]
			for rt in roots:
				if int(rt[3]) >= 0:
					if day - int(rt[3]) > 120:
						rt[3] = -1            # raiz nova no lugar da colhida
						rt[2] = 0.0
					continue
				rt[2] = minf(float(rt[2]) + 0.02 * clampf(water * 1.6, 0.2, 1.0), float(rt[1]))
			# frutos (dezembro a fevereiro): aves e bichos pequenos comem e espalham as sementes
			if (month == 12 or month <= 2) and _day_of_month(day) == 15:
				_disperse(pl, day)
		keep.append(pl)
	plants = keep
	# sementes que caíram: brotam se o solo está úmido e tem árvore perto
	var still := []
	for sd in seeds:
		if int(sd[3]) > day:
			still.append(sd)
			continue
		if plants.size() >= MAX_PLANTS:
			continue
		var x := float(sd[0])
		var z := float(sd[1])
		var host = _host_near(x, z, 5.0)
		if host != null and _water_at(x, z) > 0.25 and _rng.randf() < 0.3:
			var pos := _beside(host)
			plants.append(_new_plant(pos.x, pos.y, host, day))
	seeds = still


## Cipós adultos vivos (dão fruto).
func adult_plants() -> Array:
	var out := []
	for pl in plants:
		if int(pl.dead) < 0 and float(pl.climb) >= ADULT_H and _host_of(pl) != null:
			out.append(pl)
	return out


## Caiu uma semente aqui (brota em 2 a 3 meses se tiver árvore perto).
func drop_seed(x: float, z: float, day: int) -> void:
	if seeds.size() > 400:
		return
	seeds.append([clampf(x, 2.0, 638.0), clampf(z, 2.0, 478.0), day, day + _rng.randi_range(GERM_MIN, GERM_MAX)])


static func _day_of_month(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.day)


## Frutos da estação: quantos sai depende da polinização (insetos) e do tamanho da planta.
func _disperse(pl: Dictionary, day: int) -> void:
	var fruits := int(clampf(float(pl.climb) / 3.0, 1.0, 6.0) * _rng.randf_range(0.5, 1.2))
	# árvores por perto onde uma ave pode pousar (10 a 60 m)
	var perches := []
	for p in _arv.plants:
		if int(p[5]) == 2 or _arv.height_of(p, day) < 6.0:
			continue
		var d := Vector2(float(p[0]) - float(pl.x), float(p[1]) - float(pl.z)).length()
		if d > 10.0 and d < 60.0:
			perches.append(p)
	for k in fruits:
		var x: float
		var z: float
		if _rng.randf() < 0.65 and not perches.is_empty():
			# ave: come o fruto e solta a semente embaixo da árvore onde pousa
			var tr: Array = perches[_rng.randi() % perches.size()]
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.5, 4.0)
			x = float(tr[0]) + cos(a) * r
			z = float(tr[1]) + sin(a) * r
		else:
			# pequeno mamífero: leva o fruto para perto (5 a 15 m)
			var a := _rng.randf() * TAU
			var dist := _rng.randf_range(5.0, 15.0)
			x = float(pl.x) + cos(a) * dist
			z = float(pl.z) + sin(a) * dist
		seeds.append([clampf(x, 2.0, 638.0), clampf(z, 2.0, 478.0), day, day + _rng.randi_range(GERM_MIN, GERM_MAX)])


## Lugar no pé de uma árvore (encostado no tronco) para a muda.
func _beside(host: Array) -> Vector2:
	var a := _rng.randf() * TAU
	var r: float = _arv.trunk_radius(host) + 0.15
	return Vector2(float(host[0]) + cos(a) * r, float(host[1]) + sin(a) * r)


func _generate() -> void:
	# cipós salpicados em árvores grandes, em todas as fases (mudas, jovens e adultos)
	var hosts := []
	for p in _arv.plants:
		if int(p[5]) == 0 and _arv.height_of(p, last_day) >= 8.0:
			hosts.append(p)
	if hosts.is_empty():
		return
	for i in START_PLANTS:
		var host: Array = hosts[_rng.randi() % hosts.size()]
		var pos := _beside(host)
		var age := _rng.randf_range(0.0, 1.0)
		var pl := _new_plant(pos.x, pos.y, host, last_day - int(age * 3000))
		var host_h: float = _arv.height_of(host, last_day)
		pl.climb = minf(pow(age, 1.3) * 16.0, host_h * 0.72)
		if float(pl.climb) >= ADULT_H:
			var n := clampi(int(2 + (float(pl.climb) - ADULT_H) * 0.9), 2, 9)
			for k in n:
				var at := _rng.randf_range(maxf(ADULT_H * 0.8, float(pl.climb) * 0.55), float(pl.climb))
				var grown := _rng.randf()
				pl.roots.append([_rng.randf_range(-0.6, 0.6), at, at if grown > 0.35 else at * grown, -1])
		plants.append(pl)


# ================== COLETA ==================

## Titica adulta perto do jogador com raiz madura (ou {}).
func harvest_target(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for pl in plants:
		if int(pl.dead) >= 0 and float(last_day - int(pl.dead)) > 30.0:
			continue          # já secou
		var d := Vector2(float(pl.x) - pos.x, float(pl.z) - pos.z).length()
		if d < bd:
			bd = d
			best = pl
	return best


## Raízes que ainda estão na planta (qualquer tamanho).
func _free_roots(pl: Dictionary) -> Array:
	var out := []
	for rt in pl.roots:
		if int(rt[3]) < 0 and float(rt[2]) > 0.2:
			out.append(rt)
	return out


func mature_roots(pl: Dictionary) -> Array:
	var out := []
	for rt in pl.roots:
		if int(rt[3]) < 0 and float(rt[2]) >= float(rt[1]) - 0.3:
			out.append(rt)
	return out


## Lugares para puxar: cada raiz pendurada (pega na altura da mão) e o próprio pé
## (o caule perto do chão: arrancando ele, a planta acaba).
## [{kind: "raiz"/"caule", i (índice da raiz), pos (no mundo), top (de onde cai)}]
func pull_spots(pl: Dictionary) -> Array:
	var out := []
	var host = _host_of(pl)
	var x := float(pl.x)
	var z := float(pl.z)
	var gy: float = _jogo.height_at(x, z)
	if host != null and float(pl.climb) >= 0.6 and int(pl.dead) < 0:
		var a0 := float(pl.a0)
		for i in pl.roots.size():
			var rt: Array = pl.roots[i]
			if int(rt[3]) >= 0 or float(rt[2]) <= 0.2:
				continue
			var at := float(rt[1])
			var length := float(rt[2])
			var ang := a0 + at * 0.32 + float(rt[0])
			if at - length > 1.9:
				continue          # raiz ainda curta, lá no alto: a mão não alcança
			var start: Vector3 = _arv.trunk_point(host, at, ang, 0.03)
			var hy := clampf(1.25, at - length + 0.1, at)
			var t := (at - hy) / maxf(length, 0.01)
			var pos: Vector3 = _arv.trunk_point(host, maxf(hy, 0.0), ang, 0.08 + 0.12 * t)
			pos.y = start.y - length * t
			out.append({"kind": "raiz", "i": i, "pos": pos, "top": start, "len": length})
	# o pé (caule): fica por último quando ainda tem raiz, mas sempre dá para arrancar
	var sp := Vector3(x, gy + 0.15, z)
	if host != null and float(pl.climb) >= 0.6:
		var a0 := float(pl.a0)
		sp = _arv.trunk_point(host, 0.9, a0 + 0.9 * 0.32, 0.03)
	out.append({"kind": "caule", "i": -1, "pos": sp, "top": sp + Vector3(0, minf(float(pl.climb), 6.0), 0), "len": float(pl.climb)})
	return out


## Puxa a raiz i (sai inteira). Devolve o comprimento dela.
func pull_root(pl: Dictionary, i: int) -> float:
	if i < 0 or i >= pl.roots.size():
		return 0.0
	var rt: Array = pl.roots[i]
	var length := float(rt[2])
	rt[3] = last_day
	rt[2] = 0.0
	_rebuild()
	return length


## Arranca o pé inteiro: a planta acaba (o jogador decide se deixa algum para a mata).
func pull_stem(pl: Dictionary) -> void:
	plants.erase(pl)
	_rebuild()


## Mantido para compatibilidade: arranca a maior raiz (ou o pé, se não tiver mais).
func harvest(pl: Dictionary) -> String:
	var free := _free_roots(pl)
	if free.is_empty():
		pull_stem(pl)
		return ""
	var best := 0
	for i in pl.roots.size():
		if pl.roots[i] in free and float(pl.roots[i][2]) > float(pl.roots[best][2]):
			best = i
	pull_root(pl, best)
	return ""


## Fio de cipó comprido (L metros) deitado ao longo de X, centrado na origem, meio
## torto (como cai no chão).
static func strand_mesh(L: float, seed_ := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.4, 0.31, 0.19)
	var n := maxi(8, int(L / 0.15))
	var prev := Vector3.ZERO
	for k in n + 1:
		var t := float(k) / n
		var x := (t - 0.5) * L
		var p := Vector3(x, 0.014, sin(t * L * 2.3 + seed_) * 0.05 + sin(t * 7.0 + seed_ * 0.7) * 0.03)
		if k > 0:
			_tube(st, prev, p, 0.011, col.darkened(0.08 * (k % 2)))
		prev = p
	st.generate_normals()
	return st.commit()


## Rolo de cipó (o que cai no chão para pegar).
static func coil_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.42, 0.33, 0.2)
	var prev := Vector3.ZERO
	var n := 60
	for k in n + 1:
		var t := float(k) / n
		var a := t * TAU * 3.2
		var r := 0.09 + 0.012 * sin(t * 17.0)
		var p := Vector3(cos(a) * r, 0.012 + t * 0.03, sin(a) * r)
		if k > 0:
			_tube(st, prev, p, 0.006, col.darkened(0.08 * (k % 2)))
		prev = p
	_tube(st, prev, prev + Vector3(0.12, -0.02, 0.05), 0.005, col)
	st.generate_normals()
	return st.commit()


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "plantas": plants, "sementes": seeds}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or int(d.get("versao", 0)) != 1:
		return false
	plants = d.get("plantas", [])
	seeds = d.get("sementes", [])
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true


# ================== DESENHO ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	_tree_cache.clear()
	for p in _arv.plants:
		if int(p[5]) != 2:
			_tree_cache[Vector2(float(p[0]), float(p[1]))] = p
	var month := _month_of(last_day)
	var all := {}
	for p in _arv.plants:
		all[Vector2(float(p[0]), float(p[1]))] = p
	for pl in plants:
		var host = _host_of(pl)
		if host == null and pl.host != null:
			# a árvore caiu: se foi derrubada pelo jogador, o cipó fica no toco e na tora
			var t = all.get(Vector2(float(pl.host[0]), float(pl.host[1])))
			if t != null and t.size() > 9 and t[9] is Array:
				_draw_on_felled(pl, t, month)
			continue
		if host == null and int(pl.dead) < 0:
			continue
		_add_mesh(_plant_mesh(pl, host, month), Transform3D.IDENTITY)


func _add_mesh(mesh: ArrayMesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.visibility_range_end = VIEW
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	add_child(mi)
	_nodes.append(mi)
	return mi


## Cipó de árvore derrubada: o pé (até a altura do corte) fica no toco; o resto foi
## junto com a tora e fica agarrado nela (em cada pedaço que ainda está lá).
func _draw_on_felled(pl: Dictionary, tree: Array, month: int) -> void:
	if _arv._falling.has(tree):
		_add_mesh(_plant_mesh(pl, tree, month, 0.0, _arv.CUT_H, false), Transform3D.IDENTITY)
		return
	_add_mesh(_plant_mesh(pl, tree, month, 0.0, _arv.CUT_H, false), Transform3D.IDENTITY)
	var stand: Transform3D = _arv.stand_xf(tree)
	for pc in _arv.log_piece_xfs(tree):
		var lo := maxf(float(pc[0]), _arv.CUT_H)
		var hi := float(pc[1])
		if hi <= lo:
			continue
		var xf: Transform3D = pc[2]
		_add_mesh(_plant_mesh(pl, tree, month, lo, hi, false), xf * stand.affine_inverse())


## Parte do cipó que cai junto com a árvore (desenhada dentro do nó que tomba).
func attach_falling(tree: Array, node: Node3D) -> void:
	var month := _month_of(last_day)
	var stand: Transform3D = _arv.stand_xf(tree)
	var model_from_world := stand.affine_inverse()
	for pl in plants:
		if pl.host == null or absf(float(pl.host[0]) - float(tree[0])) > 0.01 or absf(float(pl.host[1]) - float(tree[1])) > 0.01:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _plant_mesh(pl, tree, month, _arv.CUT_H, 1e9, false)
		mi.material_override = _mat
		# o nó que tomba trabalha nas medidas do modelo da árvore
		mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE), Vector3.ZERO) * model_from_world
		node.add_child(mi)
	_rebuild()


func _plant_mesh(pl: Dictionary, host, month: int, y_lo := 0.0, y_hi := 1e9, with_roots := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dead := int(pl.dead) >= 0
	var dry := clampf(float(last_day - int(pl.dead)) / 40.0, 0.0, 1.0) if dead else 0.0
	var leaf_c := Color(0.13, 0.3, 0.09).lerp(Color(0.42, 0.3, 0.14), dry)
	var stem_c := Color(0.24, 0.27, 0.12).lerp(Color(0.33, 0.24, 0.14), dry)
	var root_c := Color(0.42, 0.36, 0.28)
	var hsh := absi(hash(Vector2(float(pl.x), float(pl.z))))
	var climb := float(pl.climb)
	var x := float(pl.x)
	var z := float(pl.z)
	var gy: float = _jogo.height_at(x, z)
	if climb < 0.6 or host == null:
		# muda: roseta de folhinhas no chão
		var n := 3 + int(climb * 6.0)
		for i in n:
			var a := TAU * i / n + float(hsh % 100) * 0.1
			var base := Vector3(x, gy + 0.02, z)
			var tip := base + Vector3(cos(a) * 0.18, 0.12 + climb * 0.3, sin(a) * 0.18)
			_leaf(st, base.lerp(tip, 0.3), (tip - base).normalized(), Vector3(-sin(a), 0, cos(a)), 0.16 + climb * 0.2, 0.06, leaf_c)
		return st.commit()
	# caule subindo em espiral pela casca, com folhas alternadas coladas no tronco
	var a0 := float(pl.a0)
	var top := minf(climb, y_hi)
	if top <= y_lo + 0.02:
		return st.commit()
	var steps := maxi(2, int((top - y_lo) / 0.22))
	var path := []
	for i in steps + 1:
		var y := lerpf(y_lo, top, float(i) / steps)
		var ang := a0 + y * 0.32 + sin(y * 1.7) * 0.15
		path.append(_arv.trunk_point(host, y, ang, 0.015))
	for i in path.size() - 1:
		_tube(st, path[i], path[i + 1], 0.011, stem_c)
	for i in range(1, path.size(), 1):
		var y := lerpf(y_lo, top, float(i) / steps)
		var ang := a0 + y * 0.32
		var p: Vector3 = path[i]
		var on: Vector3 = _arv.trunk_point(host, y, ang, 0.2) - p
		on.y = 0.0
		on = on.normalized()
		var side := Vector3.UP.cross(on).normalized() * (1.0 if i % 2 == 0 else -1.0)
		var dirl := (Vector3.UP * 0.6 + side * 0.8 + on * 0.25).normalized()
		_leaf(st, p + on * 0.02, dirl, on, 0.24, 0.05, leaf_c.lerp(Color(0.2, 0.38, 0.12), float((hsh + i) % 3) * 0.15))
	if dead or not with_roots:
		return st.commit()
	# raízes aéreas: descem retas do caule até o chão (as titicas)
	for rt in pl.roots:
		if int(rt[3]) >= 0 or float(rt[2]) < 0.05:
			continue
		var at := float(rt[1])
		var ang := a0 + at * 0.32 + float(rt[0])
		var start: Vector3 = _arv.trunk_point(host, at, ang, 0.03)
		var length := float(rt[2])
		var out_dir: Vector3 = _arv.trunk_point(host, at, ang, 1.0) - start
		out_dir.y = 0.0
		out_dir = out_dir.normalized()
		var segs := 5
		var last := start
		for k in segs:
			var t := float(k + 1) / segs
			var y := at - length * t
			# a raiz pende longe do tronco na base (o tronco engrossa embaixo)
			var pt: Vector3 = _arv.trunk_point(host, maxf(y, 0.0), ang, 0.08 + 0.12 * t)
			pt.y = start.y - length * t
			_tube(st, last, pt, 0.0055, root_c.darkened(0.1 * (k % 2)))
			last = pt
	# flores (setembro a novembro) e frutos (dezembro a fevereiro) no alto
	if climb >= ADULT_H:
		var flowering := month >= 9 and month <= 11
		var fruiting := month == 12 or month <= 2
		if flowering or fruiting:
			var n := clampi(int(climb / 3.0), 1, 5)
			for i in n:
				var y := climb * (0.7 + 0.3 * float(i) / n)
				var ang := a0 + y * 0.32 + 1.2
				var p: Vector3 = _arv.trunk_point(host, y, ang, 0.06)
				if flowering:
					_leaf(st, p, Vector3.UP, Vector3(cos(ang), 0, sin(ang)), 0.11, 0.05, Color(0.92, 0.88, 0.7))
				else:
					for k in 5:
						var q := p + Vector3(cos(k * 1.3) * 0.025, -k * 0.022, sin(k * 1.3) * 0.025)
						_blob(st, q, 0.022, Color(0.95, 0.45, 0.12))
	return st.commit()


## Folha da titica: comprida, lisa e de ponta fina (elíptica-lanceolada), com a
## nervura do meio mais clara. Desenhada dos dois lados.
static func _leaf(st: SurfaceTool, base: Vector3, dir: Vector3, normal: Vector3, length: float, width: float, col: Color) -> void:
	# a folha pende um pouco para baixo, como nas aráceas
	var d := (dir - Vector3.UP * 0.35).normalized()
	var side := d.cross(normal).normalized()
	var prof := [[0.0, 0.0], [0.12, 0.55], [0.3, 0.95], [0.55, 1.0], [0.78, 0.7], [0.92, 0.3], [1.0, 0.0]]
	var left := []
	var right := []
	var mid := []
	for q in prof:
		var c := base + d * length * float(q[0]) - normal * 0.015 * sin(float(q[0]) * PI)
		mid.append(c)
		left.append(c + side * width * float(q[1]))
		right.append(c - side * width * float(q[1]))
	var dark := col.darkened(0.12)
	var vein := col.lightened(0.25)
	for i in prof.size() - 1:
		for tri in [[mid[i], left[i], left[i + 1], col], [mid[i], left[i + 1], mid[i + 1], col],
				[mid[i], right[i + 1], right[i], dark], [mid[i], mid[i + 1], right[i + 1], dark]]:
			st.set_color(tri[3])
			for v in [tri[0], tri[1], tri[2]]:
				st.set_normal(normal)
				st.add_vertex(v)
	# nervura central
	for i in prof.size() - 1:
		var a0: Vector3 = mid[i]
		var a1: Vector3 = mid[i + 1]
		var w := side * width * 0.06
		st.set_color(vein)
		for v in [a0 - w, a1 - w, a1 + w, a0 - w, a1 + w, a0 + w]:
			st.set_normal(normal)
			st.add_vertex(v + normal * 0.002)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * r
	var s2 := d.cross(s1).normalized() * r
	st.set_color(col)
	var ring := [s1, s2, -s1, -s2]
	for k in 4:
		var p0: Vector3 = ring[k]
		var p1: Vector3 = ring[(k + 1) % 4]
		for v in [a + p0, b + p0, b + p1, a + p0, b + p1, a + p1]:
			st.set_normal((p0 + p1).normalized())
			st.add_vertex(v)


static func _blob(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	st.set_color(col)
	var pts := [Vector3(r, 0, 0), Vector3(0, r, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, -r, 0), Vector3(0, 0, -r)]
	var faces := [[0, 1, 2], [2, 1, 3], [3, 1, 5], [5, 1, 0], [0, 2, 4], [2, 3, 4], [3, 5, 4], [5, 0, 4]]
	for f in faces:
		for i in f:
			st.set_normal((pts[i] as Vector3).normalized())
			st.add_vertex(c + pts[i])
