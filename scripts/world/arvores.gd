extends Node3D
## Árvores do mundo: Cedrinho (Erisma uncinatum), madeira da Amazônia muito usada para
## tábuas, ripas, forro e mata-junta.
##
## Modelo construído aqui mesmo, em código (sem arquivo 3D): tronco reto e cilíndrico,
## mais fino em cima, com pequenas sapopemas na base e casca fissurada; galhos grossos no
## alto; copa larga com folhas que balançam. As plantas pequenas usam um modelo de muda.
##
## CICLO DE VIDA (segue o calendário do jogo):
## - De 15 de agosto a 30 de setembro cada árvore adulta solta, aos poucos, 25 a 60
##   sementes (fruto seco com asa). O vento leva a maioria a 10-60 m, algumas a mais de
##   100 m, mais para o oeste. As sementes FICAM VISÍVEIS no chão.
## - 100 dias depois de cair, a semente brota (se o chão for bom e tiver espaço). Na
##   natureza só umas 2 em 10 pegam; o resto apodrece ou é comido e some.
## - O jogador pode pegar sementes do chão, guardar na mochila, soltar ou plantar.
##   Semente plantada pelo jogador pega bem mais (8 em 10), também em 100 dias.
## - A planta cresce com os anos: broto, muda, arvoreta, jovem, adulta. Em 1º de janeiro
##   algumas morrem (mais as pequenas e as que estão na sombra).
## - As grandes envelhecem (ou pegam doença, raio): SECAM de pé, sem folhas; de 6 a 18
##   meses depois CAEM e o tronco fica deitado no chão uns anos (vai ser madeira).
## - Mundo novo: árvores salpicadas, mudas e jovens em volta, e já algumas secas e
##   caídas. Tudo fica salvo no mundo (arvores.json).

const MundoSim := preload("res://scripts/mundo_sim.gd")

const VARIANTS := 3            # modelos diferentes, para a floresta não parecer clonada
const CHUNK := 64.0            # metros de cada bloco (para o celular desenhar só o que está perto)
const VIEW_DIST := 190.0       # até onde as árvores aparecem
const SMALL_VIEW := 70.0       # até onde as mudas aparecem
const SEED_VIEW := 45.0        # até onde as sementes no chão aparecem
const TRUNK_HIT := 0.75        # raio do tronco (árvore de tamanho 1) para o jogador não atravessar
const START_TREES := 130       # árvores no começo: salpicadas pelo mapa
const SAFETY_MAX := 8000       # só para o celular não travar se a mata crescer demais em muitos anos
const SAPLING_MAX_H := 2.5     # abaixo dessa altura (m) usa o modelo de muda
const GROW_T := 18.0           # anos: quanto maior, mais devagar a árvore cresce
const ADULT_H := 12.0          # a partir dessa altura (m) a árvore solta sementes
const WIND_TO := PI            # para onde o vento leva as sementes (PI = oeste, -x)
const GERM_DAYS := 100         # dias entre a semente cair e brotar
const WILD_CHANCE := 0.2       # chance de uma semente do chão brotar
const PLANTED_CHANCE := 0.8    # chance de uma semente plantada pelo jogador brotar
const SEED_KG := 0.002

enum { ALIVE, DRY, FALLEN }

## Planta: [x, z, nasceu (dia), altura_max (m), variante, estado, dia_do_estado, ângulo_da_queda]
## Semente: [x, z, caiu (dia), brota (dia), plantada (0/1), altura_max, variante]
## (os dias contam a partir do começo do mundo; plantas antigas têm dia negativo)
var plants: Array = []
var seeds: Array = []
var last_day := 0
var trees: Array = []              # compatibilidade: as plantas
var _grid := {}                    # Vector2i (célula de 8 m) -> troncos [x, z, raio]
var _meshes: Array = []            # [tronco, copa] por variante
var _tree_h: Array = []            # altura do modelo de cada variante (m)
var _sapling: Array = []           # [caule, folhas] da muda (1 m de altura)
var _seed_mesh: Mesh
var _bark: Material
var _bark_dead: Material
var _leaves: Material
var _seed_mat: Material
var _instances: Array = []
var _seed_nodes: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()


# ================== MONTAGEM ==================

## jogo = o nó do jogo3d (usa height_at, _rockiness, CELL e sim).
func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9173
	_make_materials()
	for v in VARIANTS:
		var m := _make_tree(seed_ * 7 + v * 101 + 3)
		_meshes.append(m)
		_tree_h.append((m[1] as Mesh).get_aabb().end.y)
	_sapling = _make_sapling()
	_seed_mesh = _make_seed()
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate(seed_)
	trees = plants
	_rebuild()


## Chamado pelo jogo todo quadro: quando vira o dia, roda o ciclo das árvores.
func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	while last_day < day:
		last_day += 1
		_process_day(last_day)
	_rebuild()   # a altura muda um pouquinho todo dia; redesenha uma vez por dia de jogo


## Altura (m) de uma planta num dia (árvore morta para de crescer).
func height_of(p: Array, day: int) -> float:
	var d := day if int(p[5]) == ALIVE else mini(day, int(p[6]))
	var age := maxf(0.0, (d - float(p[2])) / 365.25)
	return float(p[3]) * pow(1.0 - exp(-age / GROW_T), 1.3) + 0.12 * minf(age * 4.0, 1.0)


static func date_of(day: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(MundoSim.start_unix() + day * 86400)


static func _doy(m: int, d: int) -> int:
	var days := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	return days[m - 1] + d


func _process_day(day: int) -> void:
	var d := date_of(day)
	var doy := _doy(int(d.month), int(d.day))
	# temporada das sementes: 15 de agosto a 30 de setembro
	if doy >= _doy(8, 15) and doy <= _doy(9, 30):
		_drop_seeds(day)
	# sementes que completaram 100 dias: brotam ou somem
	var keep := []
	for sd in seeds:
		if int(sd[3]) > day:
			keep.append(sd)
			continue
		var chance := PLANTED_CHANCE if int(sd[4]) == 1 else WILD_CHANCE
		if _rng.randf() < chance and plants.size() < SAFETY_MAX and _ground_ok(sd[0], sd[1]) and not _crowded(sd[0], sd[1], day):
			plants.append([sd[0], sd[1], day, sd[5], sd[6], ALIVE, 0, 0.0])
	seeds = keep
	# árvores secas caem; troncos caídos apodrecem
	var alive := []
	for p in plants:
		var st := int(p[5])
		if st == DRY and day >= int(p[6]) + _hash_days(p, 180, 540):
			p[5] = FALLEN
			p[6] = day
			p[7] = _rng.randf() * TAU
		elif st == FALLEN and day >= int(p[6]) + _hash_days(p, 2500, 3600):
			continue   # o tronco caído virou terra
		alive.append(p)
	plants = alive
	if int(d.month) == 1 and int(d.day) == 1:
		_yearly(day)
	trees = plants


## Um número de dias que é sempre o mesmo para a mesma planta (sem precisar guardar).
func _hash_days(p: Array, lo: int, hi: int) -> int:
	return lo + absi(hash(Vector2(p[0], p[1]))) % (hi - lo)


## Cada árvore adulta solta 25 a 60 sementes por ano, espalhadas pela temporada.
func _drop_seeds(day: int) -> void:
	var season_days := 47.0
	for p in plants:
		if int(p[5]) != ALIVE:
			continue
		var h := height_of(p, day)
		if h < ADULT_H:
			continue
		var per_year := lerpf(25.0, 60.0, clampf((h - ADULT_H) / 14.0, 0.0, 1.0))
		var n := int(per_year / season_days + _rng.randf())
		for k in n:
			var dist := 8.0 + absf(_rng.randfn(0.0, 22.0))
			if _rng.randf() < 0.12:
				dist += _rng.randf_range(40.0, 110.0)
			var ang := WIND_TO + _rng.randfn(0.0, 0.9)
			var x := float(p[0]) + cos(ang) * dist
			var z := float(p[1]) + sin(ang) * dist
			if x < 2.0 or z < 2.0 or x > MundoSim.W * _jogo.CELL - 2.0 or z > MundoSim.H * _jogo.CELL - 2.0:
				continue
			seeds.append([x, z, day, day + GERM_DAYS, 0, _rng.randf_range(20.0, 29.0), _rng.randi() % VARIANTS])


func _yearly(day: int) -> void:
	var survivors := []
	for p in plants:
		if int(p[5]) != ALIVE:
			survivors.append(p)
			continue
		var h := height_of(p, day)
		var age := (day - float(p[2])) / 365.25
		var live := 0.97
		if age < 1.0:
			live = 0.45
		elif age < 5.0:
			live = 0.75
		elif h < ADULT_H:
			live = 0.9
		if h < ADULT_H and _shaded(p, day):
			live *= 0.6   # na sombra de uma árvore grande quase não cresce
		if _rng.randf() >= live:
			continue
		# as grandes envelhecem: secam de pé (velhice, doença, raio)
		if h >= ADULT_H:
			var lifespan := float(_hash_days(p, 90, 160))
			var dry_chance := 0.008 + (0.25 if age > lifespan else 0.0)
			if _rng.randf() < dry_chance:
				p[5] = DRY
				p[6] = day
		survivors.append(p)
	plants = survivors


## Está debaixo da copa de uma árvore bem maior?
func _shaded(p: Array, day: int) -> bool:
	var h := height_of(p, day)
	for q in plants:
		if q == p or int(q[5]) == FALLEN:
			continue
		var hq := height_of(q, day)
		if hq < h * 2.0 or hq < 8.0:
			continue
		var r := hq * 0.3
		if Vector2(float(q[0]) - float(p[0]), float(q[1]) - float(p[1])).length_squared() < r * r:
			return true
	return false


func _ground_ok(x: float, z: float) -> bool:
	var sim = _jogo.sim
	var cell: float = _jogo.CELL
	if x < 4.0 or z < 4.0 or x > MundoSim.W * cell - 4.0 or z > MundoSim.H * cell - 4.0:
		return false
	var ci := int(z / cell) * MundoSim.W + int(x / cell)
	if sim.bed[ci] > 0.3 or sim.wat[ci] > 0.03 or sim.deposit[ci] > 0.1:
		return false
	var h: float = _jogo.height_at(x, z)
	if _jogo._rockiness(h) > 0.3:
		return false
	var slope := absf(_jogo.height_at(x + 2.0, z) - _jogo.height_at(x - 2.0, z)) + absf(_jogo.height_at(x, z + 2.0) - _jogo.height_at(x, z - 2.0))
	return slope <= 2.6


## Tem planta colada (ou o tronco de uma árvore) bem ali?
func _crowded(x: float, z: float, day: int) -> bool:
	for p in plants:
		if int(p[5]) == FALLEN:
			continue
		var dx := float(p[0]) - x
		var dz := float(p[1]) - z
		var min_d := 1.5 + height_of(p, day) * 0.08
		if dx * dx + dz * dz < min_d * min_d:
			return true
	return false


# ================== SEMENTES E O JOGADOR ==================

## Índice da semente mais perto (a até 'r' metros), ou -1.
func nearest_seed(pos: Vector3, r: float) -> int:
	var best := -1
	var bd := r * r
	for i in seeds.size():
		var sd: Array = seeds[i]
		var d := Vector2(float(sd[0]) - pos.x, float(sd[1]) - pos.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func take_seed(i: int) -> void:
	if i >= 0 and i < seeds.size():
		seeds.remove_at(i)
		_rebuild_seeds()


## Põe uma semente no chão (soltar) ou na terra (plantar). Brota em 100 dias.
func put_seed(x: float, z: float, planted: bool) -> void:
	var day := last_day
	seeds.append([x, z, day, day + GERM_DAYS, 1 if planted else 0, _rng.randf_range(20.0, 29.0), _rng.randi() % VARIANTS])
	_rebuild_seeds()


## Dá para plantar aqui?
func can_plant(x: float, z: float) -> bool:
	return _ground_ok(x, z)


# ================== MUNDO NOVO ==================

## Árvores salpicadas; em volta das maiores, mudas e jovens; algumas secas e caídas.
func _generate(seed_: int) -> void:
	var sim = _jogo.sim
	var cell: float = _jogo.CELL
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ if seed_ != 0 else randi()
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.012
	forest.fractal_octaves = 3
	var spawn := Vector2((sim.spawn.x + 0.5) * cell, (sim.spawn.y + 0.5) * cell)
	var day := last_day
	var tries := 0
	var adults := []
	while adults.size() < START_TREES and tries < 30000:
		tries += 1
		var x := rng.randf_range(4.0, MundoSim.W * cell - 4.0)
		var z := rng.randf_range(4.0, MundoSim.H * cell - 4.0)
		var f := forest.get_noise_2d(x, z) * 0.5 + 0.5
		if rng.randf() > 0.35 + f * 0.65:
			continue
		if Vector2(x, z).distance_to(spawn) < 18.0 or not _ground_ok(x, z):
			continue
		var far := true
		for a in adults:
			if Vector2(float(a[0]) - x, float(a[1]) - z).length_squared() < 22.0 * 22.0:
				far = false
				break
		if not far:
			continue
		# tamanho de agora: 6 em 10 jovens, 3 em 10 médias, 1 em 10 grandes
		var roll := rng.randf()
		var h_now := rng.randf_range(7.0, 13.0) if roll < 0.6 else (rng.randf_range(13.0, 19.0) if roll < 0.9 else rng.randf_range(20.0, 27.0))
		var h_max := maxf(rng.randf_range(20.0, 29.0), h_now + 1.0)
		adults.append([x, z, day - _age_for(h_now, h_max) * 365.25, h_max, rng.randi() % VARIANTS, ALIVE, 0, 0.0])
	# algumas das grandes já estão secas, e outras já caíram
	var big := adults.filter(func(a): return height_of(a, day) >= 16.0)
	big.shuffle()
	for i in mini(big.size(), 5):
		var a: Array = big[i]
		if i < 2:
			a[5] = DRY
			a[6] = day - rng.randi_range(30, 150)
		else:
			a[5] = FALLEN
			a[6] = day - rng.randi_range(100, 900)
			a[7] = rng.randf() * TAU
	plants = adults.duplicate()
	# a mata já vinha se renovando: algumas mudas e jovens em volta das maiores
	for a in adults:
		if int(a[5]) != ALIVE or height_of(a, day) < ADULT_H:
			continue
		for k in rng.randi_range(1, 4):
			var dist := 8.0 + absf(rng.randfn(0.0, 22.0))
			var ang := WIND_TO + rng.randfn(0.0, 0.9)
			var x := float(a[0]) + cos(ang) * dist
			var z := float(a[1]) + sin(ang) * dist
			if Vector2(x, z).distance_to(spawn) < 12.0 or not _ground_ok(x, z) or _crowded(x, z, day):
				continue
			var age := rng.randf_range(0.3, 10.0)
			plants.append([x, z, day - age * 365.25, rng.randf_range(20.0, 29.0), rng.randi() % VARIANTS, ALIVE, 0, 0.0])


## Quantos anos leva para chegar à altura h (quando a altura máxima é h_max).
func _age_for(h: float, h_max: float) -> float:
	var r := clampf(h / h_max, 0.0, 0.995)
	return -GROW_T * log(1.0 - pow(r, 1.0 / 1.3))


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 2, "dia": last_day, "plantas": plants, "sementes": seeds}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	var v := int(d.get("versao", 0))
	if v == 1:
		# formato antigo: plantas sem estado; sementes esperando a chuva
		plants = []
		for p in d.get("plantas", []):
			plants.append([p[0], p[1], p[2], p[3], p[4], ALIVE, 0, 0.0])
		seeds = []
		for sd in d.get("sementes", []):
			seeds.append([sd[0], sd[1], float(sd[2]) - GERM_DAYS, sd[2], 0, sd[3], sd[4]])
	elif v == 2:
		plants = d.get("plantas", [])
		seeds = d.get("sementes", [])
	else:
		return false
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true


# ================== DESENHO ==================

## Monta (ou remonta) os blocos de instâncias com o tamanho de hoje.
func _rebuild() -> void:
	for n in _instances:
		n.queue_free()
	_instances.clear()
	_grid.clear()
	var day := last_day
	var crowns := {}  # Vector3i(chunk x, chunk z, variante) -> [Transform3D]  árvores vivas (tronco + copa)
	var dry := {}     # árvores secas de pé e troncos caídos (só tronco, casca escura)
	var small := {}   # Vector2i(chunk) -> [Transform3D]  mudas
	for p in plants:
		var x := float(p[0])
		var z := float(p[1])
		var h := height_of(p, day)
		var y: float = _jogo.height_at(x, z) - 0.1
		var rot := fmod(x * 12.9898 + z * 78.233, TAU)
		var ck := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		var st := int(p[5])
		if st == ALIVE and h < SAPLING_MAX_H:
			if not small.has(ck):
				small[ck] = []
			small[ck].append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(h, h, h)), Vector3(x, y, z)))
			continue
		var v := int(p[4]) % VARIANTS
		var s: float = h / float(_tree_h[v])
		var key := Vector3i(ck.x, ck.y, v)
		var xf: Transform3D
		if st == FALLEN:
			# deitada no chão, na direção em que caiu
			var ang := float(p[7])
			var fall := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, PI * 0.5)
			xf = Transform3D(fall.scaled(Vector3(s, s, s)), Vector3(x, y + 0.35 * s, z))
		else:
			xf = Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, y - 0.05, z))
			var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
			if not _grid.has(gk):
				_grid[gk] = []
			_grid[gk].append(Vector3(x, z, TRUNK_HIT * s + 0.3))
		var target := crowns if st == ALIVE else dry
		if not target.has(key):
			target[key] = []
		target[key].append(xf)
	for key in crowns:
		_add_mm(_meshes[key.z][0], crowns[key], _bark, VIEW_DIST)
		_add_mm(_meshes[key.z][1], crowns[key], _leaves, VIEW_DIST)
	for key in dry:
		_add_mm(_meshes[key.z][0], dry[key], _bark_dead, VIEW_DIST)
	for key in small:
		_add_mm(_sapling[0], small[key], _bark, SMALL_VIEW)
		_add_mm(_sapling[1], small[key], _leaves, SMALL_VIEW)
	_rebuild_seeds()


## Sementes no chão: o fruto com a asinha, marrom.
func _rebuild_seeds() -> void:
	for n in _seed_nodes:
		n.queue_free()
	_seed_nodes.clear()
	var by_chunk := {}
	for sd in seeds:
		var x := float(sd[0])
		var z := float(sd[1])
		var ck := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		if not by_chunk.has(ck):
			by_chunk[ck] = []
		var rot := fmod(x * 31.7 + z * 17.3, TAU)
		var b := Basis(Vector3.UP, rot) * Basis(Vector3.FORWARD, 0.25)
		by_chunk[ck].append(Transform3D(b, Vector3(x, _jogo.height_at(x, z) + 0.02, z)))
	for key in by_chunk:
		var n := _add_mm(_seed_mesh, by_chunk[key], _seed_mat, SEED_VIEW)
		_instances.erase(n)
		_seed_nodes.append(n)


func _add_mm(mesh: Mesh, xfs: Array, mat: Material, dist: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = dist
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	_instances.append(mmi)
	return mmi


## O jogador não atravessa os troncos: empurra a posição para fora.
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


## Fruto do Cedrinho caído no chão: corpinho com uma asa comprida
## (um pouco maior que o de verdade, para dar para achar no chão).
func _make_seed() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
		for v in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(v)
	# corpinho (semente): losango gordinho
	var c := Vector3(0, 0.025, 0)
	var pts := [Vector3(0.05, 0.02, 0), Vector3(0, 0.02, 0.03), Vector3(-0.04, 0.02, 0), Vector3(0, 0.02, -0.03)]
	for i in 4:
		tri.call(c + Vector3(0, 0.02, 0), pts[i], pts[(i + 1) % 4], Vector3.UP)
		tri.call(Vector3(0, 0.0, 0), pts[(i + 1) % 4], pts[i], Vector3.DOWN)
	# asa: lâmina fina e comprida, um pouco curvada
	var w := [Vector3(-0.02, 0.025, -0.015), Vector3(-0.2, 0.04, -0.035), Vector3(-0.24, 0.045, 0.01), Vector3(-0.02, 0.025, 0.015)]
	tri.call(w[0], w[1], w[2], Vector3.UP)
	tri.call(w[0], w[2], w[3], Vector3.UP)
	return st.commit()


## Muda (1 m de altura; a instância é esticada para a altura de verdade):
## caulezinho fino e alguns cachinhos de folhas no alto.
func _make_sapling() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var SEG := 5
	for ri in 2:
		var y := float(ri)
		var r := 0.018 if ri == 0 else 0.008
		for si in SEG + 1:
			var a := TAU * si / SEG
			st.set_normal(Vector3(cos(a), 0, sin(a)))
			st.set_uv(Vector2(float(si) / SEG, y))
			st.add_vertex(Vector3(cos(a) * r, y, sin(a) * r))
	for si in SEG:
		st.add_index(si)
		st.add_index(si + SEG + 1)
		st.add_index(si + 1)
		st.add_index(si + 1)
		st.add_index(si + SEG + 1)
		st.add_index(si + SEG + 2)
	st.generate_tangents()
	var stem := st.commit()
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var ci := 0
	for k in 7:
		var y := rng.randf_range(0.45, 1.0)
		var p := Vector3(rng.randf_range(-0.12, 0.12), y, rng.randf_range(-0.12, 0.12))
		var size := rng.randf_range(0.28, 0.42)
		var yaw := rng.randf() * TAU
		var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.9, -0.3))
		var ax := bs.x * size * 0.5
		var ay := bs.y * size * 0.5
		var quad := [p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay]
		var uvq := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for vi in 4:
			cs.set_color(Color(1, 1, 1))
			cs.set_normal(Vector3(p.x, 0.8, p.z).normalized())
			cs.set_uv(uvq[vi])
			cs.add_vertex(quad[vi])
		for idx in [0, 1, 2, 0, 2, 3]:
			cs.add_index(ci + idx)
		ci += 4
	return [stem, cs.commit()]


# ================== MATERIAIS ==================

func _make_materials() -> void:
	# casca: cinza-amarronzada, com fissuras compridas no sentido do tronco
	var bn := FastNoiseLite.new()
	bn.seed = 5
	bn.frequency = 0.05
	bn.fractal_octaves = 4
	bn.noise_type = FastNoiseLite.TYPE_CELLULAR
	bn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([Color(0.07, 0.055, 0.045), Color(0.17, 0.14, 0.11), Color(0.27, 0.23, 0.19)])
	var alb := NoiseTexture2D.new()
	alb.width = 256
	alb.height = 512
	alb.seamless = true
	alb.noise = bn
	alb.color_ramp = ramp
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 512
	nrm.seamless = true
	nrm.noise = bn
	nrm.as_normal_map = true
	nrm.bump_strength = 10.0
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = alb
	bark.normal_enabled = true
	bark.normal_texture = nrm
	bark.normal_scale = 1.2
	bark.roughness = 0.95
	bark.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_bark = bark
	var dead: StandardMaterial3D = bark.duplicate()
	dead.albedo_color = Color(0.62, 0.6, 0.58)
	_bark_dead = dead
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.45, 0.3, 0.17)
	sm.roughness = 0.9
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_seed_mat = sm

	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = sh
	lm.set_shader_parameter("leaf_tex", _leaf_texture())
	_leaves = lm


const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
varying float sway_h;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y - 10.0, 0.0);
	float t = TIME * 1.1 + wp.x * 0.05 + wp.z * 0.04;
	VERTEX.x += sin(t) * 0.025 * h;
	VERTEX.z += cos(t * 0.8) * 0.02 * h;
	VERTEX += NORMAL * sin(TIME * 3.0 + wp.x * 0.7 + wp.y * 0.3) * 0.05;
}
void fragment() {
	vec4 c = texture(leaf_tex, UV);
	if (c.a < 0.45) { discard; }
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.18, 0.28, 0.08);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""


## Textura de um cacho de folhas (folhas simples, ovais, verde-escuras), desenhada aqui.
func _leaf_texture() -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for k in 140:
		var cx := rng.randf_range(20, S - 20)
		var cy := rng.randf_range(20, S - 20)
		# mais folhas no meio do cacho
		var to_c := Vector2(S * 0.5 - cx, S * 0.5 - cy)
		if to_c.length() > S * 0.46 and rng.randf() < 0.7:
			continue
		var ang := rng.randf() * TAU
		var L := rng.randf_range(16, 28)
		var Wd := L * rng.randf_range(0.36, 0.46)
		var base := Color(0.07, 0.17, 0.05).lerp(Color(0.16, 0.29, 0.08), rng.randf())
		var dirv := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dirv.y, dirv.x)
		var r := int(L) + 2
		for py in range(maxi(0, int(cy) - r), mini(S, int(cy) + r)):
			for px in range(maxi(0, int(cx) - r), mini(S, int(cx) + r)):
				var d := Vector2(px - cx, py - cy)
				var u := d.dot(dirv) / L
				var v := d.dot(perp) / Wd
				var q := u * u + v * v
				if q <= 1.0:
					var shade := 0.82 + 0.25 * (1.0 - q) - absf(v) * 0.1
					var col := base * shade
					if absf(v) < 0.08 and absf(u) < 0.85:
						col = col.lightened(0.18)   # nervura do meio
					col.a = 1.0
					img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ================== MODELO DA ÁRVORE ==================

## Devolve [malha do tronco e galhos, malha da copa].
func _make_tree(seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var H := rng.randf_range(22.0, 28.0)          # altura do tronco até a copa
	var r0 := rng.randf_range(0.42, 0.52)         # raio do tronco no chão
	var lean := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_axis := func(h: float) -> Vector3:
		var t := h / H
		return Vector3(lean.x * t * t + sin(h * 0.21) * 0.08, h, lean.y * t * t + cos(h * 0.17) * 0.08)
	# tronco, com sapopemas na base
	var SEG := 14
	var RINGS := 22
	var fin_phase := rng.randf() * TAU
	var fins := 5
	for ri in RINGS + 1:
		var h := H * pow(float(ri) / RINGS, 1.35)
		var c: Vector3 = trunk_axis.call(h)
		var taper := lerpf(r0, r0 * 0.42, h / H)
		var flare := 1.0 + 0.55 * exp(-h * 1.4)
		for si in SEG + 1:
			var a := TAU * si / SEG
			var fin := pow(maxf(0.0, cos(a * fins + fin_phase)), 8.0) * maxf(0.0, 1.0 - h / 1.8) * 1.1
			var r := taper * flare + fin
			var pos := c + Vector3(cos(a) * r, 0, sin(a) * r)
			st.set_normal(Vector3(cos(a), 0.15, sin(a)).normalized())
			st.set_uv(Vector2(float(si) / SEG * 2.0, h / 3.0))
			st.add_vertex(pos)
	for ri in RINGS:
		for si in SEG:
			var a := ri * (SEG + 1) + si
			var b := a + SEG + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	var vbase := (RINGS + 1) * (SEG + 1)

	# galhos grossos no alto, saindo do tronco para fora e para cima
	var tips: Array[Vector3] = []
	var nb := rng.randi_range(5, 7)
	for bi in nb:
		var h0 := H * rng.randf_range(0.66, 0.9)
		var start: Vector3 = trunk_axis.call(h0)
		var ang := TAU * bi / nb + rng.randf_range(-0.3, 0.3)
		var up := rng.randf_range(0.55, 0.9)
		var length := rng.randf_range(4.5, 7.0)
		var dirv := Vector3(cos(ang), up, sin(ang)).normalized()
		var tip := start + dirv * length
		tips.append(tip)
		vbase = _branch(st, vbase, start, tip, r0 * 0.38, r0 * 0.12)
		# um galho menor saindo do meio
		var mid := start.lerp(tip, 0.55)
		var side := Vector3(cos(ang + 0.9), up + 0.2, sin(ang + 0.9)).normalized()
		var tip2 := mid + side * length * 0.45
		tips.append(tip2)
		vbase = _branch(st, vbase, mid, tip2, r0 * 0.16, r0 * 0.06)
	tips.append(trunk_axis.call(H))
	st.generate_tangents()
	var trunk := st.commit()

	# copa: cachos de folhas (cartões cruzados) em volta da ponta dos galhos e em cima
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Vector3 = trunk_axis.call(H)
	var crown_c := top + Vector3(0, 2.0, 0)
	var crown_r := Vector3(rng.randf_range(7.0, 9.0), rng.randf_range(3.2, 4.2), rng.randf_range(7.0, 9.0))
	var ci := 0
	for k in 95:
		var p: Vector3
		if k < tips.size() * 5:
			var tip: Vector3 = tips[k % tips.size()]
			p = tip + Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(-0.6, 1.6), rng.randf_range(-2.2, 2.2))
		else:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-1, 1)).normalized()
			p = crown_c + d * crown_r * rng.randf_range(0.55, 1.0)
		var outward := (p - crown_c) / crown_r
		outward = (outward + Vector3(0, 0.6, 0)).normalized()
		var size := rng.randf_range(2.6, 3.8)
		var tint := Color(1, 1, 1).lerp(Color(0.8, 0.95, 0.75), rng.randf())
		for q in 2:
			var yaw := rng.randf() * TAU + q * PI * 0.5
			var tilt := rng.randf_range(-0.5, 0.5)
			var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
			var ax := bs.x * size * 0.5
			var ay := bs.y * size * 0.5
			var quad := [p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay]
			var uvq := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for vi in 4:
				cs.set_color(tint)
				cs.set_normal(outward)
				cs.set_uv(uvq[vi])
				cs.add_vertex(quad[vi])
			cs.add_index(ci)
			cs.add_index(ci + 1)
			cs.add_index(ci + 2)
			cs.add_index(ci)
			cs.add_index(ci + 2)
			cs.add_index(ci + 3)
			ci += 4
	var crown := cs.commit()
	return [trunk, crown]


## Um galho como um cilindro afinando, de 'a' até 'b'. Devolve o próximo índice livre.
func _branch(st: SurfaceTool, vbase: int, a: Vector3, b: Vector3, ra: float, rb: float) -> int:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var SEG := 7
	var RINGS := 4
	for ri in RINGS + 1:
		var t := float(ri) / RINGS
		var c := a.lerp(b, t) + up * sin(t * PI) * 0.25
		var r := lerpf(ra, rb, t)
		for si in SEG + 1:
			var ang := TAU * si / SEG
			var n := (side * cos(ang) + up * sin(ang)).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(float(si) / SEG, t * 2.0))
			st.add_vertex(c + n * r)
	for ri in RINGS:
		for si in SEG:
			var i0 := vbase + ri * (SEG + 1) + si
			var i1 := i0 + SEG + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i1 + 1)
	return vbase + (RINGS + 1) * (SEG + 1)
