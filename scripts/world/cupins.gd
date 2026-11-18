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
const TIMBO_DAYS := 45          # o veneno de timbó (rotenona) se desfaz rápido no sol e na chuva
const OLEO_DAYS := 730          # o óleo de andiroba entra na madeira e espanta o cupim por anos
const ANDIROBA_START := 16
const TIMBO_START := 26

var colonies: Array = []        # {x, z, nasc, pop}
var timbos: Array = []          # pés de timbó: {x, z, nasc, colhido (dia ou -1)}
var andirobas: Array = []       # andirobeiras: {x, z, sem (sementes no chão)}
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
	_soil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	_gen_andirobas()


## Andirobeiras: árvores grandes de chão úmido (beira de rio, baixada). Debaixo delas
## caem os ouriços (frutos redondos) que abrem e soltam as sementes.
func _gen_andirobas() -> void:
	var cands := []
	for p in _arv.plants:
		if int(p[5]) != 0 or _arv.height_of(p, last_day) < 8.0:
			continue
		var gw: float = _jogo.sim.ground_water(_cell(float(p[0]), float(p[1])))
		if gw >= 0.3:
			cands.append(p)
	cands.shuffle()
	for p in cands:
		if andirobas.size() >= ANDIROBA_START:
			break
		var ok := true
		for a in andirobas:
			if Vector2(float(a.x) - float(p[0]), float(a.z) - float(p[1])).length() < 25.0:
				ok = false
				break
		if ok:
			andirobas.append({"x": float(p[0]), "z": float(p[1]), "sem": _rng.randi_range(3, 7)})


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
	# andiroba: os frutos caem na época das chuvas (janeiro a junho)
	if month <= 6:
		for a in andirobas:
			if int(a.sem) < 10 and _rng.randf() < 0.12:
				a.sem = int(a.sem) + 1
	# o timbó colhido volta a crescer em uns 5 meses
	for t in timbos:
		if int(t.colhido) >= 0 and day - int(t.colhido) > 150:
			t.colhido = -1


## Toda madeira do mundo que dá para comer: {p (xz), obj, kind, soft (o quanto é fácil)}
func _wood_list() -> Array:
	var out := []
	for fl in _arv.free_logs:
		out.append({"p": Vector2(float(fl.pos[0]), float(fl.pos[2])), "obj": fl, "kind": "tora", "soft": 0.6 if fl.has("sec") else 0.45})
	var co = _jogo._constr
	if co:
		for pc in co.pieces:
			out.append({"p": Vector2(float(pc.p[0]), float(pc.p[2])), "obj": pc.log, "kind": "estrutura", "soft": 0.5})
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
	var o: Dictionary = t.obj
	return day - int(o.get("veneno", -100000)) < TIMBO_DAYS or day - int(o.get("oleo", -100000)) < OLEO_DAYS


## Dias de proteção que ainda faltam (o maior dos dois).
func protect_left(t: Dictionary) -> int:
	if t.kind == "toco":
		return 0
	var o: Dictionary = t.obj
	return maxi(0, maxi(TIMBO_DAYS - (last_day - int(o.get("veneno", -100000))), OLEO_DAYS - (last_day - int(o.get("oleo", -100000)))))


func oiled(t: Dictionary) -> bool:
	return t.kind != "toco" and last_day - int((t.obj as Dictionary).get("oleo", -100000)) < OLEO_DAYS


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
		"estrutura":
			# peça da construção: some (o que estava apoiado nela fica, sem cair — por enquanto)
			var co = _jogo._constr
			if co:
				for pc in co.pieces:
					if pc.log == t.obj:
						co.remove_piece(pc)
						break
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


## kind "veneno" (timbó: mata os cupins na hora, protege pouco) ou "oleo" (andiroba).
func treat(t: Dictionary, kind := "veneno") -> void:
	(t.obj as Dictionary)[kind] = last_day
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


## Andirobeira com sementes no chão perto, ou -1.
func nearest_andiroba(pos: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for i in andirobas.size():
		var a: Dictionary = andirobas[i]
		if int(a.sem) <= 0:
			continue
		for sp in _seed_spots(a):
			var d := Vector2(sp.x - pos.x, sp.z - pos.z).length()
			if d < bd:
				bd = d
				best = i
	return best


func take_seeds(i: int) -> int:
	var n := int(andirobas[i].sem)
	andirobas[i].sem = 0
	_rebuild()
	return n


## Onde estão os montinhos de frutos e sementes debaixo da andirobeira.
func _seed_spots(a: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(a.x) * 3.0 + float(a.z) * 5.0)
	var out := []
	for k in 3:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(1.2, 3.0)
		out.append(Vector3(float(a.x) + cos(ang) * r, 0, float(a.z) + sin(ang) * r))
	return out


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
	var sd := SurfaceTool.new()
	sd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anyseed := false
	for a in andirobas:
		if int(a.sem) > 0:
			anyseed = true
			_seeds(sd, a)
	if anyseed:
		_add(sd, _soil_mat)
	_bugs_dirty = true


func _add(st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	_nodes.append(mi)


## Altura e raio da base do cupinzeiro (cresce com a idade e o tamanho da colônia).
func _mound_size(c: Dictionary) -> Vector2:
	var age := clampf((last_day - float(c.nasc)) / 1500.0, 0.05, 1.0)
	var H := lerpf(0.25, 1.7, age * (0.5 + float(c.pop) * 0.5))
	return Vector2(H, H * 0.55 + 0.15)


## Ponto na superfície do cupinzeiro: ângulo a em volta, t de 0 (pé) a 1 (topo).
func _mound_pt(c: Dictionary, a: float, t: float, out := 0.0) -> Vector3:
	var x := float(c.x)
	var z := float(c.z)
	var sz := _mound_size(c)
	var ph := fmod(x * 0.37 + z * 0.73, TAU)
	var bump := 1.0 + 0.16 * sin(a * 3.0 + t * 5.0 + ph) + 0.06 * sin(a * 7.0 + ph * 2.0 + t * 11.0) + 0.035 * sin(a * 13.0 - t * 7.0 + ph)
	var rad := (sz.y * pow(1.0 - t, 0.75) + 0.02) * bump + out
	return Vector3(x + cos(a) * rad, float(c.get("gy", _jogo.height_at(x, z))) - 0.08 + t * sz.x, z + sin(a) * rad)


## Buracos do cupinzeiro (as entradas): [ângulo, altura t, raio do buraco].
func _mound_holes(c: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(c.x) * 53.0 + float(c.z) * 29.0)
	var H := _mound_size(c).x
	var out := []
	for k in int(3 + H * 5):
		out.append([rng.randf() * TAU, rng.randf_range(0.06, 0.75), rng.randf_range(0.018, 0.04) * (0.7 + H * 0.4)])
	return out


## Cupinzeiro: monte de barro avermelhado, cheio de calombos, com torrinhas em cima
## e os buracos por onde os cupins entram e saem.
func _mound(st: SurfaceTool, c: Dictionary) -> void:
	var x := float(c.x)
	var z := float(c.z)
	c["gy"] = _jogo.height_at(x, z)
	var gy := float(c.gy)
	var pop := float(c.pop)
	var sz := _mound_size(c)
	var H := sz.x
	var R := sz.y
	var rng := RandomNumberGenerator.new()
	rng.seed = int(x * 31.0 + z * 17.0)
	var col := Color(0.2, 0.12, 0.075) if pop > 0.01 else Color(0.19, 0.16, 0.12)
	var rings := 10
	var secs := 18
	var pts := []
	for r in rings + 1:
		var t := float(r) / rings
		var row := []
		for k in secs:
			row.append(_mound_pt(c, TAU * k / secs, t))
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
		var base := _mound_pt(c, a, hh, -0.03)
		_cone(st, base, rng.randf_range(0.05, 0.12) * (0.5 + H * 0.4), rng.randf_range(0.12, 0.3) * (0.5 + H * 0.5), col.darkened(rng.randf() * 0.1))
	# buracos: borda de barro mais clara levantada e o fundo escuro
	if pop > 0.01:
		for h in _mound_holes(c):
			_hole(st, c, float(h[0]), float(h[1]), float(h[2]), col)


func _hole(st: SurfaceTool, c: Dictionary, a: float, t: float, hr: float, col: Color) -> void:
	var P := _mound_pt(c, a, t, 0.004)
	var Pa := _mound_pt(c, a + 0.02, t)
	var Pt := _mound_pt(c, a, minf(t + 0.02, 1.0))
	var n := (Pa - P).cross(Pt - P).normalized()
	if n.dot(Vector3(cos(a), 0, sin(a))) < 0.0:
		n = -n
	var u := (Pt - P).normalized()
	var v := n.cross(u).normalized()
	var segs := 10
	var dark := Color(0.012, 0.008, 0.005)
	var rim := col.lightened(0.04)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var i0 := P + (u * cos(a0) * 1.15 + v * sin(a0)) * hr
		var i1 := P + (u * cos(a1) * 1.15 + v * sin(a1)) * hr
		var o0 := P + (u * cos(a0) * 1.15 + v * sin(a0)) * hr * 1.35 + n * 0.004
		var o1 := P + (u * cos(a1) * 1.15 + v * sin(a1)) * hr * 1.35 + n * 0.004
		var deep := P - n * hr * 0.8
		# fundo (cone para dentro)
		for w in [i0, i1, deep]:
			st.set_color(dark)
			st.add_vertex(w)
		# beiradinha
		for w in [o0, o1, i1, o0, i1, i0]:
			st.set_color(rim)
			st.add_vertex(w)


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


## Debaixo da andirobeira: ouriços redondos (uns fechados, outros abertos em 4 gomos)
## e as sementes soltas, marrons e meio quadradas.
func _seeds(st: SurfaceTool, a: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(a.x) * 11.0 + float(a.z) * 7.0)
	var n := int(a.sem)
	var spots := _seed_spots(a)
	for k in n:
		var sp: Vector3 = spots[k % spots.size()]
		var p := sp + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var gy: float = _jogo.height_at(p.x, p.z)
		# ouriço (fruto) de uns 9 cm
		var fc := Vector3(p.x, gy + 0.04, p.z)
		var col := Color(0.34, 0.24, 0.13)
		for i in 4:
			for j in 8:
				var q := []
				for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var th := PI * float(i + d[0]) / 4.0
					var ph := TAU * float(j + d[1]) / 8.0
					q.append(fc + Vector3(sin(th) * cos(ph), cos(th) * 0.9, sin(th) * sin(ph)) * 0.045)
				var cc := col.darkened(0.25) if j % 2 == 0 else col
				for idx in [0, 2, 1, 0, 3, 2]:
					st.set_color(cc)
					st.add_vertex(q[idx])
		# 2 sementes soltas do lado (uns 4 cm, cantos retos)
		for m in 2:
			var ang := rng.randf() * TAU
			var sc := Vector3(p.x + cos(ang) * 0.09, gy + 0.015, p.z + sin(ang) * 0.09)
			_box(st, sc, Vector3(0.022, 0.016, 0.018), rng.randf() * TAU, Color(0.32, 0.2, 0.11).darkened(rng.randf() * 0.15))


static func _box(st: SurfaceTool, c: Vector3, h: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var faces := [[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var q := []
		for d in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			q.append(c + b * ((n + u * float(d[0]) * 0.8 + v * float(d[1]) * 0.8) * h))
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col.darkened(0.1) if n.y < 0.5 else col)
			st.add_vertex(q[idx])


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "colonias": colonies, "timbos": timbos, "andirobas": andirobas, "tocos": stump_dmg}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	colonies = d.get("colonias", [])
	timbos = d.get("timbos", [])
	andirobas = d.get("andirobas", [])
	if andirobas.is_empty():
		_gen_andirobas()        # mundo de versão antiga: as andirobeiras aparecem agora
	stump_dmg = d.get("tocos", {})
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true


# ================== OS CUPINS ANDANDO ==================
# Só perto do jogador: operários (claros, de cabeça redonda), soldados (cabeça
# alaranjada grande com as pinças pretas) e, na época da revoada, as aleluias (escuras,
# de asas compridas). Andam em volta do cupinzeiro, entram e saem pelos buracos, vão
# em fila até a madeira que estão comendo e andam em cima dela.

const BUG_NEAR := 30.0          # só desenha os cupins até essa distância do jogador
const BUG_MAX := 650

var _bugs: Array = []           # {path: PackedVector3Array, len, s, v, dir, kind, ph}
var _bug_mm: Array = []         # um MultiMeshInstance3D por tipo
var _bug_center := Vector3(1e9, 0, 1e9)
var _bugs_dirty := true
var _bug_t := 0.0
var _bug_frame := 0


func _process(delta: float) -> void:
	if _jogo == null or _jogo._player == null:
		return
	var pp: Vector3 = _jogo._player.position
	_bug_t += delta
	if _bugs_dirty or Vector2(pp.x - _bug_center.x, pp.z - _bug_center.z).length() > 8.0 or _bug_t > 20.0:
		_bugs_dirty = false
		_bug_t = 0.0
		_bug_center = pp
		_make_bugs(pp)
	if _bugs.is_empty():
		return
	var idx := [0, 0, 0]
	_bug_frame += 1
	for b in _bugs:
		var k := int(b.kind)
		# os longe do jogador andam de 3 em 3 quadros (economiza no celular)
		if bool(b.far) and (_bug_frame + int(b.ph * 10.0)) % 3 != 0:
			idx[k] += 1
			continue
		var dt := delta * (3.0 if bool(b.far) else 1.0)
		var L := float(b.len)
		# anda, para um pouquinho, anda de novo (como formiga)
		var go := 0.55 + 0.45 * sin(_bug_t * 2.3 + float(b.ph))
		b.s = float(b.s) + float(b.v) * float(b.dir) * dt * clampf(go * 1.6, 0.0, 1.0)
		if bool(b.loop):
			b.s = fposmod(float(b.s), L)
		elif float(b.s) > L:
			b.s = L
			b.dir = -1
		elif float(b.s) < 0.0:
			b.s = 0.0
			b.dir = 1
		var tr := _along(b.path, b.cum, float(b.s), int(b.dir))
		(_bug_mm[k] as MultiMeshInstance3D).multimesh.set_instance_transform(idx[k], tr)
		idx[k] += 1


## Posição e direção no caminho (distância s), com as distâncias acumuladas cum.
func _along(path: PackedVector3Array, cum: PackedFloat32Array, s: float, dir: int) -> Transform3D:
	var i := clampi(cum.bsearch(s) - 1, 0, path.size() - 2)
	var A := path[i]
	var B := path[i + 1]
	var l := cum[i + 1] - cum[i]
	var f := clampf((s - cum[i]) / maxf(l, 0.0001), 0.0, 1.0)
	var p := A.lerp(B, f)
	var fwd := (B - A).normalized() * float(dir)
	if fwd.length() < 0.5:
		fwd = Vector3.FORWARD
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var side := fwd.cross(up).normalized()
	up = side.cross(fwd).normalized()
	# o bicho olha para +x no modelo
	return Transform3D(Basis(fwd, up, side), p)


func _path_len(path: PackedVector3Array) -> float:
	var L := 0.0
	for i in path.size() - 1:
		L += path[i].distance_to(path[i + 1])
	return L


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, _jogo.height_at(x, z) + 0.004, z)


func _make_bugs(pp: Vector3) -> void:
	_bugs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pp.x) * 7 + int(pp.z) * 13
	var month := _month(last_day)
	var swarm := month >= 9 and month <= 11
	var woods := _wood_list()
	for c in colonies:
		var pop := float(c.pop)
		if pop <= 0.01:
			continue
		var cp := Vector3(float(c.x), 0, float(c.z))
		if Vector2(cp.x - pp.x, cp.z - pp.z).length() > BUG_NEAR + 3.0:
			continue
		if not c.has("gy"):
			c["gy"] = _jogo.height_at(cp.x, cp.z)
		var sz := _mound_size(c)
		var holes := _mound_holes(c)
		# 1) em volta do pé do cupinzeiro (uma volta inteira, alguns de cada lado)
		for k in int(20 + pop * 45):
			var path := PackedVector3Array()
			var a0 := rng.randf() * TAU
			var rr := sz.y * rng.randf_range(1.02, 1.25)
			for q in 25:
				var a := a0 + TAU * q / 24.0
				var w := rr + 0.03 * sin(a * 9.0 + k)
				path.append(_ground(cp.x + cos(a) * w, cp.z + sin(a) * w))
			_add_bug(path, rng, 1 if rng.randf() < 0.15 else 0, true)
		# 2) saindo e entrando pelos buracos: descem pelo barro até o chão
		for h in holes:
			for k in 5:
				var path := PackedVector3Array()
				var a := float(h[0]) + rng.randf_range(-0.05, 0.05)
				var t := float(h[1])
				var steps := 8
				for q in steps + 1:
					var tt := t * (1.0 - float(q) / steps)
					path.append(_mound_pt(c, a + sin(q * 1.3 + k) * 0.06, tt, 0.006))
				var gp := _mound_pt(c, a, 0.0, 0.0)
				var out := Vector3(cos(a), 0, sin(a))
				for q in 4:
					var d := 0.1 * (q + 1)
					path.append(_ground(gp.x + out.x * d + out.z * sin(q + k) * 0.04, gp.z + out.z * d - out.x * sin(q + k) * 0.04))
				_add_bug(path, rng, 1 if k == 4 and rng.randf() < 0.5 else 0, false)
		# 3) em fila até a madeira que estão comendo, e andando em cima dela
		var R := reach(c)
		for t in woods:
			var d := dmg_of(t)
			if d <= 0.02 or _treated(t, last_day):
				continue
			var wp: Vector2 = t.p
			var dist := Vector2(wp.x - cp.x, wp.y - cp.z).length()
			if dist > R or Vector2(wp.x - pp.x, wp.y - pp.z).length() > BUG_NEAR:
				continue
			var top := _wood_top(t)
			var trail := PackedVector3Array()
			var dir2 := (wp - Vector2(cp.x, cp.z)).normalized()
			var start := Vector2(cp.x, cp.z) + dir2 * sz.y * 1.05
			var n := clampi(int(dist / 0.25), 4, 80)
			var side := Vector2(-dir2.y, dir2.x)
			var ph := rng.randf() * 10.0
			for q in n + 1:
				var f := float(q) / n
				var p2 := start.lerp(wp, f) + side * sin(f * 9.0 + ph) * 0.12 * sin(f * PI)
				trail.append(_ground(p2.x, p2.y))
			for k in clampi(int(8 + d * 24 * pop), 8, 40):
				_add_bug(trail, rng, 1 if rng.randf() < 0.12 else 0, false)
			# em cima da madeira: vão e voltam no comprido
			if not top.is_empty():
				for k in int(6 + d * 18):
					var path := PackedVector3Array()
					var A: Vector3 = top.a
					var B: Vector3 = top.b
					var off: Vector3 = top.side * rng.randf_range(-1.0, 1.0)
					for q in 9:
						var f := float(q) / 8.0
						path.append(A.lerp(B, f) + off + top.side * sin(f * 7.0 + k) * 0.15)
					_add_bug(path, rng, 0, false)
		# 4) revoada: aleluias saindo pelos buracos de cima e andando no barro
		if swarm and pop > 0.5:
			for h in holes:
				if float(h[1]) < 0.35:
					continue
				for k in 4:
					var path := PackedVector3Array()
					var a := float(h[0])
					for q in 6:
						path.append(_mound_pt(c, a + rng.randf_range(-0.3, 0.3), clampf(float(h[1]) + rng.randf_range(-0.15, 0.1), 0.0, 0.95), 0.008))
					_add_bug(path, rng, 2, false)
		if _bugs.size() >= BUG_MAX:
			break
	_fill_mm()


## Linha de cima da madeira (para os cupins andarem nela): {a, b, side}, ou {}.
func _wood_top(t: Dictionary) -> Dictionary:
	match str(t.kind):
		"tora":
			var fl: Dictionary = t.obj
			var L: float = _arv.free_log_length(fl)
			var yaw := float(fl.get("yaw", 0.0))
			var ax := Vector3(cos(yaw), 0, -sin(yaw))
			var r: float = _arv.free_log_radius(fl)
			var c := Vector3(float(fl.pos[0]), float(fl.pos[1]) + r + 0.004, float(fl.pos[2]))
			var w: float = _arv.free_log_max_radius(fl) * 0.35
			return {"a": c - ax * L * 0.45, "b": c + ax * L * 0.45, "side": Vector3(-ax.z, 0, ax.x) * w}
		"estaca", "toco", "forquilha":
			var p: Vector2 = t.p
			var g: float = _jogo.height_at(p.x, p.y)
			var h := 0.9 if t.kind == "estaca" else (0.45 if t.kind == "toco" else 0.5)
			var rr := 0.07
			return {"a": Vector3(p.x + rr, g, p.y), "b": Vector3(p.x + rr * 0.6, g + h, p.y + rr * 0.6), "side": Vector3(0, 0, 0.03)}
	return {}


func _add_bug(path: PackedVector3Array, rng: RandomNumberGenerator, kind: int, loop: bool) -> void:
	if _bugs.size() >= BUG_MAX or path.size() < 2:
		return
	var cum := PackedFloat32Array([0.0])
	for i in path.size() - 1:
		cum.append(cum[i] + path[i].distance_to(path[i + 1]))
	var L := cum[cum.size() - 1]
	var far := Vector2(path[0].x - _bug_center.x, path[0].z - _bug_center.z).length() > 12.0
	_bugs.append({"path": path, "cum": cum, "far": far, "len": L, "s": rng.randf() * L, "v": rng.randf_range(0.025, 0.05) * (0.7 if kind == 1 else 1.0),
		"dir": 1 if rng.randf() < 0.5 else -1, "kind": kind, "ph": rng.randf() * TAU, "loop": loop})


func _fill_mm() -> void:
	if _bug_mm.is_empty():
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for k in 3:
			var mi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _bug_mesh(k)
			mi.multimesh = mm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_bug_mm.append(mi)
	var n := [0, 0, 0]
	for b in _bugs:
		n[int(b.kind)] += 1
	for k in 3:
		var mm: MultiMesh = (_bug_mm[k] as MultiMeshInstance3D).multimesh
		mm.instance_count = n[k]
		# a caixa de visibilidade cobre a área toda dos cupins
		(_bug_mm[k] as MultiMeshInstance3D).custom_aabb = AABB(_bug_center - Vector3(BUG_NEAR + 30, 30, BUG_NEAR + 30), Vector3(BUG_NEAR + 30, 30, BUG_NEAR + 30) * 2.0)
		for i in n[k]:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))


## O bicho (olhando para +x, em metros, um pouco maior que o de verdade para dar
## para ver no celular): 0 operário, 1 soldado, 2 aleluia (com asas).
static func _bug_mesh(kind: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var S := 2.4                 # escala (operário de verdade: uns 5 mm)
	var body := Color(0.82, 0.72, 0.55) if kind == 0 else (Color(0.8, 0.7, 0.52) if kind == 1 else Color(0.22, 0.14, 0.08))
	var head := Color(0.72, 0.5, 0.25) if kind == 0 else (Color(0.85, 0.45, 0.12) if kind == 1 else Color(0.16, 0.1, 0.06))
	# abdômen, tórax, cabeça (bolinhas achatadas)
	_blob(st, Vector3(-0.0022, 0.0013, 0) * S, Vector3(0.0028, 0.0013, 0.0018) * S, body)
	_blob(st, Vector3(0.0012, 0.0012, 0) * S, Vector3(0.0012, 0.001, 0.0012) * S, body.darkened(0.08))
	if kind == 1:
		_blob(st, Vector3(0.0036, 0.0014, 0) * S, Vector3(0.0019, 0.0013, 0.0014) * S, head)
		# pinças pretas
		for sd in [-1.0, 1.0]:
			_seg(st, Vector3(0.0052, 0.0013, 0.0006 * sd) * S, Vector3(0.0075, 0.0012, 0.0002 * sd) * S, 0.00035 * S, Color(0.05, 0.03, 0.02))
	else:
		_blob(st, Vector3(0.0029, 0.0013, 0) * S, Vector3(0.0011, 0.001, 0.0011) * S, head)
	# antenas
	for sd in [-1.0, 1.0]:
		_seg(st, Vector3(0.0036 if kind != 1 else 0.0045, 0.0018, 0.0005 * sd) * S, Vector3(0.0058 if kind != 1 else 0.0064, 0.0024, 0.0018 * sd) * S, 0.00018 * S, head.darkened(0.2))
	# 6 pernas
	for i in 3:
		var x := (0.0006 + 0.0007 * (i - 1)) * S
		for sd in [-1.0, 1.0]:
			var knee := Vector3(x + 0.0004 * (i - 1) * S, 0.0018 * S, 0.0019 * sd * S)
			_seg(st, Vector3(x, 0.0011 * S, 0.0005 * sd * S), knee, 0.00018 * S, body.darkened(0.15))
			_seg(st, knee, Vector3(x + 0.0012 * (i - 1) * S, 0.0, 0.0032 * sd * S), 0.00016 * S, body.darkened(0.15))
	if kind == 2:
		# quatro asas compridas, meio transparentes (cinza claro), deitadas sobre o corpo
		for sd in [-1.0, 1.0]:
			for w in 2:
				var root := Vector3(0.0012, 0.0026 + w * 0.0002, 0.0004 * sd) * S
				var tip := Vector3(-0.011, 0.0028 + w * 0.0002, (0.0018 + w * 0.0006) * sd) * S
				var mid1 := root.lerp(tip, 0.5) + Vector3(0, 0, 0.0013 * sd) * S
				var mid2 := root.lerp(tip, 0.5) - Vector3(0, 0, 0.0002 * sd) * S
				for v in [root, mid1, tip, root, tip, mid2]:
					st.set_color(Color(0.78, 0.76, 0.72))
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color) -> void:
	var la := 5
	var lo := 8
	for i in la:
		for j in lo:
			var q := []
			for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + d[0]) / la
				var ph := TAU * float(j + d[1]) / lo
				q.append(c + Vector3(sin(th) * cos(ph) * r.x, cos(th) * r.y, sin(th) * sin(ph) * r.z))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.add_vertex(q[k])


static func _seg(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP)
	if s1.length() < 0.1:
		s1 = d.cross(Vector3.RIGHT)
	s1 = s1.normalized() * w
	var s2 := d.cross(s1).normalized() * w
	for side in [s1, s2]:
		for v in [a - side, b - side, b + side, a - side, b + side, a + side]:
			st.set_color(col)
			st.add_vertex(v)
