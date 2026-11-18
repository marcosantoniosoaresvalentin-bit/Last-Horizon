extends Node3D
## Cupins: colônias com cupinzeiro de terra no chão, que crescem, soltam revoada e
## fundam colônias novas, procuram madeira em volta e a comem aos poucos.
##
## Onde nascem: chão firme (fora da água e da praia), perto de argila (o barro do
## cupinzeiro), com umidade média (nem encharcado nem seco demais).
## População (0 a 1): cresce com a madeira que acham e o solo úmido; cai na seca forte e
## sem comida. Colônia grande, no começo das chuvas (setembro a novembro), solta a
## revoada: um casal funda uma colônia nova a 20 a 70 m, em chão bom.
## Madeira: toras soltas e rachadas, galhos no chão, forquilhas, toras apoiadas, estacas
## fincadas, tocos e a madeira das construções que estiverem até uns 12 a 28 m (cresce
## com a colônia). Na madeira aparecem os túneis de barro (galerias) e o pó; o estrago
## ("cupim" de 0 a 1, guardado na própria madeira) vai subindo até ela se desfazer.
## Árvores vivas: só as que já estão fracas (morrendo, velhas, com a raiz no encharcado
## ou na seca forte) e perto do cupinzeiro; aí ela morre bem mais rápido.
## Veneno de timbó: tratar a madeira mata os cupins dela e protege por uns 2 anos.
## (Os cupinzeiros vão ser comida do tamanduá: ver colonies e eat_colony.)

const MAX_COLONIES := 40
const START := 9
const REACH_MIN := 12.0
const REACH_MAX := 28.0
const PROTECT_DAYS := 730
const TIMBO_START := 26

var colonies: Array = []        # {x, z, nasc, pop}
var timbos: Array = []          # pés de timbó: {x, z, nasc, colhido (dia ou -1)}
var stump_dmg := {}             # "x,z" do toco -> estrago
var last_day := 0
var _jogo: Node
var _arv: Node
var _rng := RandomNumberGenerator.new()
var _nodes: Array = []
var _soil_mat: StandardMaterial3D
var _mud_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 6161
	last_day = int(jogo.sim.elapsed_days())
	_soil_mat = StandardMaterial3D.new()
	_soil_mat.vertex_color_use_as_albedo = true
	_soil_mat.vertex_color_is_srgb = true
	_soil_mat.roughness = 1.0
	_mud_mat = _soil_mat.duplicate()
	_mud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.vertex_color_is_srgb = true
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 0.7
	if save_path == "" or not _load(save_path):
		_generate()
	_rebuild()


# ================== ONDE NASCEM ==================

func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(x / _jogo.CELL), int(z / _jogo.CELL))


## Nota do lugar para cupinzeiro (0 a 1): perto de argila, umidade média, chão firme.
func _site_score(x: float, z: float) -> float:
	var sim = _jogo.sim
	var c := _cell(x, z)
	if c.x < 2 or c.y < 2 or c.x >= sim.W - 2 or c.y >= sim.H - 2:
		return 0.0
	var i: int = c.y * sim.W + c.x
	if float(sim.ter[i]) < sim.SEA + 1.4 or float(sim.wat[i]) > 0.01 or float(sim.bed[i]) > 0.3:
		return 0.0
	var clay := 0.0
	for o in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var j: int = clampi(c.y + o.y, 0, sim.H - 1) * sim.W + clampi(c.x + o.x, 0, sim.W - 1)
		clay = maxf(clay, float(sim.clay[j]) * 1.4 + float(sim.deposit[j]))
	var moist: float = float(sim.ground_water(c))         # água no solo, 0 a 1
	var wet_ok := 1.0 - absf(moist - 0.45) * 1.4
	var slope := absf(_jogo.height_at(x + 2, z) - _jogo.height_at(x - 2, z)) + absf(_jogo.height_at(x, z + 2) - _jogo.height_at(x, z - 2))
	return clampf(clampf(clay, 0.0, 1.0) * 0.7 + 0.3, 0.0, 1.0) * clampf(wet_ok, 0.0, 1.0) * (1.0 if slope < 1.2 else 0.3)


func _generate() -> void:
	var W: float = _jogo.sim.W * _jogo.CELL
	var H: float = _jogo.sim.H * _jogo.CELL
	var tries := 0
	while colonies.size() < START and tries < 4000:
		tries += 1
		var x := _rng.randf_range(10, W - 10)
		var z := _rng.randf_range(10, H - 10)
		if _site_score(x, z) < 0.55 + _rng.randf() * 0.3 or _too_close(x, z, 40.0):
			continue
		colonies.append({"x": x, "z": z, "nasc": last_day - _rng.randi_range(200, 4000), "pop": _rng.randf_range(0.3, 0.9)})
	# timbó: arbusto-cipó da beira da mata, em chão úmido
	tries = 0
	while timbos.size() < TIMBO_START and tries < 4000:
		tries += 1
		var x := _rng.randf_range(10, W - 10)
		var z := _rng.randf_range(10, H - 10)
		var c := _cell(x, z)
		var sim = _jogo.sim
		var i: int = c.y * sim.W + c.x
		if float(sim.ter[i]) < sim.SEA + 1.4 or float(sim.wat[i]) > 0.01 or float(sim.ground_water(c)) < 0.35:
			continue
		timbos.append({"x": x, "z": z, "nasc": last_day - 800, "colhido": -1})


func _too_close(x: float, z: float, d: float) -> bool:
	for c in colonies:
		if Vector2(float(c.x) - x, float(c.z) - z).length() < d:
			return true
	return false


# ================== DIA A DIA ==================

func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	var n := 0
	while last_day < day and n < 120:
		last_day += 1
		_day(last_day)
		n += 1
	last_day = day
	_rebuild()


static func _month(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


func reach(c: Dictionary) -> float:
	return lerpf(REACH_MIN, REACH_MAX, clampf(float(c.pop), 0.0, 1.0))


func _day(day: int) -> void:
	var wet: float = _jogo.sim.wetness()
	var month := _month(day)
	var targets := _wood_list()
	var born := []
	var keep := []
	for c in colonies:
		var cp := Vector2(float(c.x), float(c.z))
		var R := reach(c)
		var food := 0.0
		for t in targets:
			var d: float = cp.distance_to(t.p)
			if d > R or _treated(t, day):
				continue
			var bite := float(c.pop) * 0.006 * (1.0 - d / R * 0.6) * float(t.soft) * lerpf(0.6, 1.3, wet)
			_damage(t, bite, day)
			food += bite
		# árvores fracas em volta
		if _rng.randf() < 0.05:
			_attack_trees(c, day, wet)
		# cresce com comida e chuva; a seca forte e a fome derrubam
		var grow := 0.0025 * (0.4 + wet) + food * 0.6 - (0.002 if wet < 0.1 else 0.0) - (0.0012 if food <= 0.0 else 0.0)
		c.pop = clampf(float(c.pop) + grow * (1.0 - float(c.pop) * 0.6), 0.0, 1.0)
		if float(c.pop) <= 0.01 and day - int(c.nasc) > 120:
			continue          # a colônia morreu (o cupinzeiro fica vazio e some)
		# revoada: começo das chuvas, colônia forte
		if month >= 9 and month <= 11 and float(c.pop) > 0.7 and _rng.randf() < 0.01 and colonies.size() + born.size() < MAX_COLONIES:
			for k in 6:
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(20.0, 70.0)
				var x := float(c.x) + cos(a) * r
				var z := float(c.z) + sin(a) * r
				if _site_score(x, z) > 0.5 and not _too_close(x, z, 15.0):
					born.append({"x": x, "z": z, "nasc": day, "pop": 0.02})
					c.pop = float(c.pop) * 0.85
					break
		keep.append(c)
	keep.append_array(born)
	colonies = keep
	# o timbó colhido volta a crescer em uns 5 meses
	for t in timbos:
		if int(t.colhido) >= 0 and day - int(t.colhido) > 150:
			t.colhido = -1


## Toda madeira do mundo que dá para comer: {p (xz), obj, kind, soft (o quanto é fácil)}
func _wood_list() -> Array:
	var out := []
	for fl in _arv.free_logs:
		out.append({"p": Vector2(float(fl.pos[0]), float(fl.pos[2])), "obj": fl, "kind": "tora", "soft": 0.6 if fl.has("sec") else 0.45})
	var gal = _jogo._galhos
	if gal:
		for g in gal.items:
			out.append({"p": Vector2(float(g.x), float(g.z)), "obj": g, "kind": "galho", "soft": 1.6})
	var ap = _jogo._apoios
	if ap:
		for f in ap.forks:
			out.append({"p": Vector2(float(f.x), float(f.z)), "obj": f, "kind": "forquilha", "soft": 1.2})
		for r in ap.rested:
			var c: Vector3 = _jogo._apoios.info(ap.rested.find(r)).center
			out.append({"p": Vector2(c.x, c.z), "obj": r.log, "kind": "apoiada", "soft": 0.5})
	var bu = _jogo._buracos
	if bu:
		for po in bu.posts:
			out.append({"p": Vector2(float(po.x), float(po.z)), "obj": po.log, "kind": "estaca", "soft": 0.8})     # a parte enterrada apodrece rápido
	for st in _arv.stumps:
		out.append({"p": Vector2(float(st[0]), float(st[1])), "obj": st, "kind": "toco", "soft": 0.7})
	for g in _jogo._chao:
		if str(g.id) in ["tabua", "ripa", "galho", "rodela", "balde", "forquilha"]:
			out.append({"p": Vector2(float(g.x), float(g.z)), "obj": g, "kind": "chao", "soft": 1.4})
	return out


func _key(t: Dictionary) -> String:
	if t.kind == "toco":
		return "%.1f,%.1f" % [float(t.obj[0]), float(t.obj[1])]
	return ""


func dmg_of(t: Dictionary) -> float:
	if t.kind == "toco":
		return float(stump_dmg.get(_key(t), 0.0))
	return float((t.obj as Dictionary).get("cupim", 0.0))


func _treated(t: Dictionary, day: int) -> bool:
	if t.kind == "toco":
		return false
	return day - int((t.obj as Dictionary).get("veneno", -100000)) < PROTECT_DAYS


func _damage(t: Dictionary, v: float, day: int) -> void:
	var d := dmg_of(t) + v
	if t.kind == "toco":
		stump_dmg[_key(t)] = d
	else:
		(t.obj as Dictionary)["cupim"] = d
	if d >= 1.0:
		_destroy(t)


## A madeira se desfez: some do mundo (vira pó e terra).
func _destroy(t: Dictionary) -> void:
	match str(t.kind):
		"tora":
			_arv.free_logs.erase(t.obj)
			_arv._rebuild_logs()
		"galho":
			var gi: int = _jogo._galhos.items.find(t.obj)
			if gi >= 0:
				_jogo._galhos.take(gi)
		"forquilha":
			var fi: int = _jogo._apoios.forks.find(t.obj)
			if fi >= 0:
				# a tora que estava em cima cai no chão
				for ri in range(_jogo._apoios.rested.size() - 1, -1, -1):
					var r: Dictionary = _jogo._apoios.rested[ri]
					if int(r.a) == fi or int(r.b) == fi:
						var c: Vector3 = _jogo._apoios.info(ri).center
						var fl: Dictionary = _jogo._apoios.take_rested(ri)
						_arv.drop_log(fl, c, float(fl.get("yaw", 0.0)))
				_jogo._apoios.take_fork(fi)
		"apoiada":
			for ri in _jogo._apoios.rested.size():
				if _jogo._apoios.rested[ri].log == t.obj:
					_jogo._apoios.take_rested(ri)
					break
		"estaca":
			var bu = _jogo._buracos
			for pi in bu.posts.size():
				if bu.posts[pi].log == t.obj:
					bu.posts.remove_at(pi)
					bu._rebuild()
					break
		"toco":
			_arv.stumps.erase(t.obj)
			stump_dmg.erase(_key(t))
			_arv._rebuild()
		"chao":
			var i: int = _jogo._chao.find(t.obj)
			if i >= 0:
				(_jogo._chao[i].node as Node3D).queue_free()
				_jogo._chao.remove_at(i)


func _attack_trees(c: Dictionary, day: int, wet: float) -> void:
	var cp := Vector2(float(c.x), float(c.z))
	var R := reach(c) * 0.6
	for p in _arv.plants:
		if int(p[5]) == 2:
			continue
		var d := cp.distance_to(Vector2(float(p[0]), float(p[1])))
		if d > R:
			continue
		var h: float = _arv.height_of(p, day)
		if h < 2.0:
			continue
		# só árvore fraca: já morrendo (morre mais rápido), muito velha, ou a raiz sofrendo
		var weak := 0.0
		if int(p[5]) == 1:
			weak = 1.0
		else:
			var age := (day - float(p[2])) / 365.25
			if age > 80.0:
				weak = 0.5
			var gw: float = _jogo.sim.ground_water(_cell(float(p[0]), float(p[1])))
			if gw > 0.9 or (wet < 0.08 and gw < 0.15):
				weak = maxf(weak, 0.4)
		if weak <= 0.0 or _rng.randf() > weak * float(c.pop) * 0.5:
			continue
		if int(p[5]) == 0:
			p[5] = 1                 # começa a morrer (secando por dentro)
			p[6] = day
		else:
			p[6] = int(p[6]) - 25    # já morrendo: anda mais rápido
		p.resize(maxi(p.size(), 12))
		p[11] = day                  # marca de cupim (galerias no tronco)
		break


# ================== VENENO ==================

## Madeira infestada (ou não) mais perto do ponto, para tratar com veneno.
func nearest_wood(pos: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for t in _wood_list():
		if t.kind == "toco":
			continue
		var d: float = (t.p as Vector2).distance_to(Vector2(pos.x, pos.z))
		if d < bd:
			bd = d
			best = t
	return best


func treat(t: Dictionary) -> void:
	(t.obj as Dictionary)["veneno"] = last_day
	(t.obj as Dictionary)["cupim"] = minf(dmg_of(t), 0.95)     # o estrago fica, mas para
	_rebuild()


## Timbó perto (com raiz para colher), ou -1.
func nearest_timbo(pos: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for i in timbos.size():
		var t: Dictionary = timbos[i]
		if int(t.colhido) >= 0:
			continue
		var d := Vector2(float(t.x) - pos.x, float(t.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func harvest_timbo(i: int) -> void:
	timbos[i].colhido = last_day
	_rebuild()


## Para o tamanduá (futuro): come parte da colônia.
func eat_colony(i: int, amount: float) -> void:
	colonies[i].pop = maxf(0.0, float(colonies[i].pop) - amount)


# ================== NA TELA ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in colonies:
		_mound(st, c)
	_add(st, _soil_mat)
	# galerias de barro na madeira
	var mud := SurfaceTool.new()
	mud.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for t in _wood_list():
		var d := dmg_of(t)
		if d <= 0.02:
			continue
		any = true
		_galleries(mud, t, d)
	for p in _arv.plants:
		if p.size() >= 12 and p[11] != null and int(p[5]) != 2:
			any = true
			_tree_galleries(mud, p)
	if any:
		_add(mud, _mud_mat)
	var tb := SurfaceTool.new()
	tb.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in timbos:
		_timbo(tb, t)
	_add(tb, _leaf_mat)


func _add(st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	_nodes.append(mi)


## Cupinzeiro: monte de barro avermelhado, cheio de calombos, com torrinhas em cima.
func _mound(st: SurfaceTool, c: Dictionary) -> void:
	var x := float(c.x)
	var z := float(c.z)
	var gy: float = _jogo.height_at(x, z)
	var pop := float(c.pop)
	var age := clampf((last_day - float(c.nasc)) / 1500.0, 0.05, 1.0)
	var H := lerpf(0.25, 1.7, age * (0.5 + pop * 0.5))
	var R := H * 0.55 + 0.15
	var rng := RandomNumberGenerator.new()
	rng.seed = int(x * 31.0 + z * 17.0)
	var col := Color(0.2, 0.12, 0.075) if pop > 0.01 else Color(0.19, 0.16, 0.12)
	var rings := 8
	var secs := 14
	var pts := []
	for r in rings + 1:
		var t := float(r) / rings
		var row := []
		var rad := R * pow(1.0 - t, 0.75) + 0.02
		for k in secs:
			var a := TAU * k / secs
			var bump := 1.0 + 0.18 * sin(a * 3.0 + rng.randf() * 0.3 + t * 5.0) + rng.randf_range(-0.08, 0.08)
			row.append(Vector3(x + cos(a) * rad * bump, gy - 0.08 + t * H, z + sin(a) * rad * bump))
		pts.append(row)
	for r in rings:
		for k in secs:
			var k2 := (k + 1) % secs
			var q := [pts[r][k], pts[r][k2], pts[r + 1][k2], pts[r + 1][k]]
			var cc := col.darkened(rng.randf_range(0.0, 0.15) + (0.15 if r == 0 else 0.0))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for idx in tri:
					st.set_color(cc)
					st.add_vertex(q[idx])
	# torrinhas e calombos
	for k in int(3 + H * 4):
		var a := rng.randf() * TAU
		var hh := rng.randf_range(0.2, 0.75)
		var rr := R * (1.0 - hh) * rng.randf_range(0.6, 1.0)
		var base := Vector3(x + cos(a) * rr, gy + hh * H * 0.9, z + sin(a) * rr)
		_cone(st, base, rng.randf_range(0.05, 0.12) * (0.5 + H * 0.4), rng.randf_range(0.12, 0.3) * (0.5 + H * 0.5), col.darkened(rng.randf() * 0.1))


static func _cone(st: SurfaceTool, base: Vector3, r: float, h: float, col: Color) -> void:
	var secs := 7
	for k in secs:
		var a0 := TAU * k / secs
		var a1 := TAU * (k + 1) / secs
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var top := base + Vector3(0, h, 0)
		for v in [p0, p1, top]:
			st.set_color(col)
			st.add_vertex(v)


## Túneis de barro em cima da madeira: tiras tortas que saem do chão e sobem pela
## madeira; quanto mais estrago, mais túneis e mais grossos (e o pó em volta).
func _galleries(st: SurfaceTool, t: Dictionary, d: float) -> void:
	var p: Vector2 = t.p
	var gy: float = _jogo.height_at(p.x, p.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.x * 13.0 + p.y * 7.0)
	var top := 0.15
	var len := 0.6
	var dir := Vector2(1, 0)
	match str(t.kind):
		"tora", "apoiada":
			var fl: Dictionary = t.obj
			top = _arv.free_log_max_radius(fl) * 2.0 + (0.7 if t.kind == "apoiada" else 0.0)
			len = _arv.free_log_length(fl)
			var yaw := float(fl.get("yaw", 0.0))
			dir = Vector2(cos(yaw), -sin(yaw))
			if t.kind == "apoiada":
				var ri: int = -1
				for k in _jogo._apoios.rested.size():
					if _jogo._apoios.rested[k].log == fl:
						ri = k
				if ri >= 0:
					var inf: Dictionary = _jogo._apoios.info(ri)
					dir = Vector2(inf.dir.x, inf.dir.z).normalized()
		"estaca":
			top = 1.2
			len = 0.2
		"forquilha":
			top = 0.6
		"galho", "chao":
			top = 0.08
		"toco":
			top = 0.5
	var n := int(2 + d * 8)
	var col := Color(0.17, 0.1, 0.06)
	if t.kind == "tora":
		# deitada no chão: túneis largos que sobem de um lado, passam por cima e descem
		var fl2: Dictionary = t.obj
		var r: float = _arv.free_log_max_radius(fl2) + 0.012
		var perp := Vector3(-dir.y, 0, dir.x)
		var ax := Vector3(dir.x, 0, dir.y)
		for k in n:
			var along := rng.randf_range(-0.42, 0.42) * len
			var a0 := rng.randf_range(-1.6, -1.2)
			var a1 := lerpf(-0.2, 1.4, clampf(d * 1.3 + rng.randf() * 0.3, 0.0, 1.0))
			var w := 0.018 + d * 0.025
			var segs := 8
			var prev := Vector3.ZERO
			for s in segs + 1:
				var u := float(s) / segs
				var ang := lerpf(a0, a1, u)
				along += rng.randf_range(-0.02, 0.02)
				var c: Vector3 = Vector3(p.x, gy + r - 0.012, p.y) + ax * along + perp * (cos(ang) * r) + Vector3.UP * (sin(ang) * r)
				if s > 0:
					var sd := ax * w
					var bulge: Vector3 = (c - Vector3(p.x, gy + r, p.y) - ax * along).normalized() * 0.006
					for v in [prev - sd, c - sd, c + sd + bulge, prev - sd, c + sd + bulge, prev + sd + bulge]:
						st.set_color(col.darkened(rng.randf() * 0.15))
						st.add_vertex(v)
				prev = c
		n = 0
	for k in n:
		var along := rng.randf_range(-0.45, 0.45) * len
		var side := rng.randf_range(-1.0, 1.0)
		var c0 := Vector3(p.x + dir.x * along + dir.y * side * 0.05, gy, p.y + dir.y * along - dir.x * side * 0.05)
		var w := 0.015 + d * 0.02
		var segs := 6
		var prev := c0
		for s in segs:
			var u := float(s + 1) / segs
			var nxt := c0 + Vector3(rng.randf_range(-0.03, 0.03) + dir.x * u * 0.15, top * u * (0.4 + d * 0.6), rng.randf_range(-0.03, 0.03) + dir.y * u * 0.15)
			var side3 := Vector3(-dir.y, 0, dir.x) * w
			for v in [prev - side3, nxt - side3, nxt + side3, prev - side3, nxt + side3, prev + side3]:
				st.set_color(col.darkened(rng.randf() * 0.15))
				st.add_vertex(v + Vector3.UP * 0.005)
			prev = nxt
	# pó de madeira (serragem dos cupins) no chão
	for k in int(d * 6):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.1, 0.4)
		var c := Vector3(p.x + cos(a) * r, gy + 0.005, p.y + sin(a) * r)
		var s := rng.randf_range(0.03, 0.07)
		for v in [c + Vector3(-s, 0, -s), c + Vector3(s, 0, -s), c + Vector3(0, 0.01, s)]:
			st.set_color(Color(0.62, 0.48, 0.32))
			st.add_vertex(v)


## Galerias subindo pelo tronco de uma árvore atacada.
func _tree_galleries(st: SurfaceTool, p: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(p[0]) * 11.0 + float(p[1]) * 5.0)
	for k in 6:
		var ang := rng.randf() * TAU
		var hmax := rng.randf_range(0.8, 2.4)
		var prev: Vector3 = _arv.trunk_point(p, 0.0, ang, 0.01)
		for s in 8:
			var y := hmax * float(s + 1) / 8.0
			ang += rng.randf_range(-0.12, 0.12)
			var nxt: Vector3 = _arv.trunk_point(p, y, ang, 0.012)
			var side := Vector3(-sin(ang), 0, cos(ang)) * 0.014
			for v in [prev - side, nxt - side, nxt + side, prev - side, nxt + side, prev + side]:
				st.set_color(Color(0.17, 0.1, 0.06))
				st.add_vertex(v)
			prev = nxt


## Timbó: moita de cipó de folhas compostas (folíolos ovais, verde-escuro), meio
## trepando; colhido, fica só o toquinho até brotar de novo.
func _timbo(st: SurfaceTool, t: Dictionary) -> void:
	var x := float(t.x)
	var z := float(t.z)
	var gy: float = _jogo.height_at(x, z)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(x * 7.0 + z * 3.0)
	var cut := int(t.colhido) >= 0
	var stems := 3 if cut else 9
	for k in stems:
		var a := rng.randf() * TAU
		var h := rng.randf_range(0.08, 0.14) if cut else rng.randf_range(0.6, 1.3)
		var lean := Vector3(cos(a), 0, sin(a)) * h * 0.4
		var base := Vector3(x, gy, z) + Vector3(cos(a), 0, sin(a)) * 0.05
		var tip := base + Vector3(0, h, 0) + lean
		var side := Vector3(-sin(a), 0, cos(a)) * 0.008
		for v in [base - side, tip - side, tip + side, base - side, tip + side, base + side]:
			st.set_color(Color(0.33, 0.24, 0.14))
			st.add_vertex(v)
		if cut:
			continue
		# folhas: pares de folíolos ao longo do caule
		for j in 5:
			var u := 0.35 + j * 0.13
			var c := base.lerp(tip, u)
			for sgn in [-1.0, 1.0]:
				var out: Vector3 = Vector3(-sin(a), 0.2, cos(a)).normalized() * float(sgn)
				var l := rng.randf_range(0.07, 0.11)
				var w := l * 0.45
				var fwd := (tip - base).normalized()
				var p0 := c
				var p1 := c + out * l * 0.5 + fwd * w
				var p2 := c + out * l
				var p3 := c + out * l * 0.5 - fwd * w
				var col := Color(0.18, 0.36, 0.12).darkened(rng.randf() * 0.2)
				for v in [p0, p1, p2, p0, p2, p3]:
					st.set_color(col)
					st.add_vertex(v)


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "colonias": colonies, "timbos": timbos, "tocos": stump_dmg}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	colonies = d.get("colonias", [])
	timbos = d.get("timbos", [])
	stump_dmg = d.get("tocos", {})
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
