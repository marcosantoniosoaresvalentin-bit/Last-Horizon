extends Node3D
## Árvores do mundo: Cedrinho (Erisma uncinatum), madeira da Amazônia muito usada para
## tábuas, ripas, forro e mata-junta.
##
## Modelo construído aqui mesmo, em código (sem arquivo 3D), em PEDAÇOS: tronco, cada galho
## e o cacho de folhas de cada galho. Assim a árvore pode ir morrendo galho por galho.
##
## CICLO DE VIDA (segue o calendário do jogo):
## - De 15 de agosto a 30 de setembro cada árvore adulta solta, aos poucos, 25 a 60
##   sementes (fruto seco com asa). O vento leva a maioria a 10-60 m, algumas a mais de
##   100 m, mais para o oeste. As sementes ficam visíveis no chão.
## - 100 dias depois de cair, a semente brota (se o chão for bom e tiver espaço). Na
##   natureza só umas 2 em 10 pegam; o resto apodrece e some.
## - O jogador pode pegar sementes do chão, guardar, soltar ou plantar (pega 8 em 10).
## - A planta cresce com os anos: broto, muda, arvoreta, jovem, adulta. Em 1º de janeiro
##   algumas plantas pequenas morrem (mais as que estão na sombra).
## - MORTE DE ÁRVORE GRANDE (velhice, doença, raio) — nunca de repente:
##   1. as folhas amarelam e depois ficam marrons;
##   2. em 3 a 5 meses a copa vai sumindo galho por galho e as folhas secas se acumulam
##      no chão em volta;
##   3. seca, fica DE PÉ, sem folhas, esperando o jogador derrubar (as folhas do chão se
##      desfazem com o tempo);
##   4. se ninguém derrubar, depois de uns 3 a 4 anos os galhos vão caindo um por um;
##   5. por fim o tronco cai e fica deitado no chão, apodrecendo com os anos.
## - Mundo novo: árvores salpicadas, mudas em volta e algumas em cada fase da morte.
## Tudo fica salvo no mundo (arvores.json).

const MundoSim := preload("res://scripts/mundo_sim.gd")

const VARIANTS := 3            # modelos diferentes, para a floresta não parecer clonada
const CHUNK := 64.0            # metros de cada bloco (para o celular desenhar só o que está perto)
const VIEW_DIST := 190.0       # até onde as árvores aparecem
const SMALL_VIEW := 70.0       # até onde as mudas aparecem
const SEED_VIEW := 40.0        # até onde as sementes no chão aparecem
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
const DROWN_COVER := 0.8       # água cobrindo 80% da altura da planta: afogada
const DROWN_DAYS := 4          # dias seguidos afogada até começar a morrer
const DROWN_MAX_H := 8.0       # árvore maior que isso a cheia não mata

enum { ALIVE, DYING, FALLEN }

## Planta: [x, z, nasceu (dia), altura_max (m), variante, estado, dia_do_estado, ângulo_da_queda]
##   DYING: dia_do_estado = dia em que começou a morrer (as fases saem daí)
##   FALLEN: dia_do_estado = dia em que o tronco caiu
## Semente: [x, z, caiu (dia), brota (dia), plantada (0/1), altura_max, variante]
var plants: Array = []
var seeds: Array = []
var last_day := 0
var trees: Array = []              # compatibilidade: as plantas
var _grid := {}                    # Vector2i (célula de 8 m) -> troncos [x, z, raio]
var _models: Array = []            # por variante: {trunk, crown, core, branches[], clusters[], axes[], height}
var _sapling: Array = []           # [caule, folhas] da muda (1 m de altura)
var _seed_mesh: Mesh
var _litter_mesh: Mesh
var _bark: Material
var _bark_dead: Material
var _leaves: Material
var _litter: Material
var _seed_mat: Material
var _instances: Array = []
var _seed_nodes: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _drown := {}                   # Vector2(x, z) -> dias seguidos debaixo d'água


# ================== MONTAGEM ==================

## jogo = o nó do jogo3d (usa height_at, _rockiness, CELL e sim).
func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9173
	_make_materials()
	for v in VARIANTS:
		_models.append(_make_tree(seed_ * 7 + v * 101 + 3))
	_sapling = _make_sapling()
	_seed_mesh = _make_seed()
	_litter_mesh = _make_litter_quad()
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
	_rebuild()   # a altura e as fases mudam um pouquinho todo dia; redesenha uma vez por dia de jogo


## Um número que é sempre o mesmo para a mesma planta (sem precisar guardar).
func _hash_range(p: Array, lo: float, hi: float, salt := 0) -> float:
	var hsh := absi(hash(Vector3(float(p[0]), float(p[1]), salt)))
	return lo + (hsh % 10007) / 10007.0 * (hi - lo)


## Durações da morte de cada árvore (em dias): perder folhas, esperar seca, cair os galhos.
func _dying_days(p: Array) -> float:
	return _hash_range(p, 100.0, 150.0, 1)

func _standing_days(p: Array) -> float:
	return _hash_range(p, 3.0 * 365.0, 4.0 * 365.0, 2)

func _decay_days(p: Array) -> float:
	return _hash_range(p, 1.0 * 365.0, 2.0 * 365.0, 3)


## Altura (m) de uma planta num dia (para de crescer quando começa a morrer).
func height_of(p: Array, day: int) -> float:
	var d := day if int(p[5]) == ALIVE else mini(day, int(p[6]))
	var age := maxf(0.0, (d - float(p[2])) / 365.25)
	return float(p[3]) * pow(1.0 - exp(-age / GROW_T), 1.3) + 0.12 * minf(age * 4.0, 1.0)


## Fases da morte num dia: {leaf (0-1: folhas indo embora), dead (dias seca de pé),
## decay (0-1: galhos caindo)}. Árvore viva: leaf = -1.
func phase_of(p: Array, day: int) -> Dictionary:
	if int(p[5]) != DYING or day < int(p[6]):
		return {"leaf": -1.0, "dead": 0.0, "decay": 0.0}
	var t := float(day - int(p[6]))
	var d1 := _dying_days(p)
	var leaf := clampf(t / d1, 0.0, 1.0)
	var dead := maxf(0.0, t - d1)
	var decay := clampf((dead - _standing_days(p)) / _decay_days(p), 0.0, 1.0)
	return {"leaf": leaf, "dead": dead, "decay": decay}


func _alive_now(p: Array, day: int) -> bool:
	return int(p[5]) == ALIVE or (int(p[5]) == DYING and day < int(p[6]))


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
	_check_flood(day)
	# árvore seca que ninguém derrubou: depois de perder os galhos, o tronco cai sozinho;
	# tronco caído apodrece e some depois de uns anos
	var still := []
	for p in plants:
		var st := int(p[5])
		if st == DYING and phase_of(p, day).decay >= 1.0:
			fell(p, day)
		elif st == FALLEN and day >= int(p[6]) + int(_hash_range(p, 2500.0, 3600.0, 4)):
			continue
		still.append(p)
	plants = still
	if int(d.month) == 1 and int(d.day) == 1:
		_yearly(day)
	trees = plants


## Cheia: planta viva pode ficar com o pé dentro do rio sem problema. Mas se a água subir
## e cobrir quase a planta inteira (muda ou árvore pequena) por alguns dias, ela começa a
## morrer ali dentro d'água, aos poucos, do mesmo jeito que as outras. Árvore grande não.
func _check_flood(day: int) -> void:
	var sim = _jogo.sim
	var cell: float = _jogo.CELL
	var hs: float = _jogo.HS
	var under := {}
	for p in plants:
		if int(p[5]) != ALIVE:
			continue
		var h := height_of(p, day)
		if h > DROWN_MAX_H:
			continue
		var c := Vector2i(int(float(p[0]) / cell), int(float(p[1]) / cell))
		var depth: float = sim.water_at(c) * hs
		if depth < h * DROWN_COVER:
			continue
		var k := Vector2(float(p[0]), float(p[1]))
		var n: int = _drown.get(k, 0) + 1
		if n >= DROWN_DAYS:
			p[5] = DYING
			p[6] = day
		else:
			under[k] = n
	_drown = under


## Derruba a árvore (o jogador vai usar isto para cortar; também quando cai sozinha).
func fell(p: Array, day: int) -> void:
	p[5] = FALLEN
	p[6] = day
	p[7] = _rng.randf() * TAU


## Cada árvore adulta solta 25 a 60 sementes por ano, espalhadas pela temporada.
func _drop_seeds(day: int) -> void:
	var season_days := 47.0
	for p in plants:
		if not _alive_now(p, day):
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
		if h < ADULT_H:
			# plantas pequenas: algumas morrem no ano (somem; são pequenas demais para ver)
			var live := 0.9
			if age < 1.0:
				live = 0.45
			elif age < 5.0:
				live = 0.75
			if _shaded(p, day):
				live *= 0.6   # na sombra de uma árvore grande quase não cresce
			if _rng.randf() >= live:
				continue
		else:
			# as grandes envelhecem (ou pegam doença, raio): começam a morrer em algum dia do ano
			var lifespan := _hash_range(p, 90.0, 160.0, 5)
			var chance := 0.008 + (0.25 if age > lifespan else 0.0)
			if _rng.randf() < chance:
				p[5] = DYING
				p[6] = day + _rng.randi_range(0, 300)
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

## Árvores salpicadas; em volta das maiores, mudas e jovens; algumas em cada fase da morte.
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
	# algumas das grandes já estão em alguma fase da morte, e outras já caíram
	var big := adults.filter(func(a): return height_of(a, day) >= 16.0)
	big.shuffle()
	for i in mini(big.size(), 6):
		var a: Array = big[i]
		a[5] = DYING
		match i:
			0: a[6] = day - int(_dying_days(a) * 0.35)                 # perdendo as folhas
			1: a[6] = day - int(_dying_days(a) * 0.75)                 # quase sem folhas
			2: a[6] = day - int(_dying_days(a) + 200)                  # seca, de pé
			3: a[6] = day - int(_dying_days(a) + _standing_days(a) + _decay_days(a) * 0.5)   # perdendo os galhos
			_:
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
		f.store_string(JSON.stringify({"versao": 3, "dia": last_day, "plantas": plants, "sementes": seeds}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	var v := int(d.get("versao", 0))
	if v == 1:
		plants = []
		for p in d.get("plantas", []):
			plants.append([p[0], p[1], p[2], p[3], p[4], ALIVE, 0, 0.0])
		seeds = []
		for sd in d.get("sementes", []):
			seeds.append([sd[0], sd[1], float(sd[2]) - GERM_DAYS, sd[2], 0, sd[3], sd[4]])
	elif v == 2 or v == 3:
		plants = d.get("plantas", [])
		seeds = d.get("sementes", [])
		if v == 2:
			# na versão 2 a árvore seca caía sozinha; agora ela morre aos poucos e fica de pé
			for p in plants:
				if int(p[5]) == DYING:
					p[6] = int(p[6]) - int(_dying_days(p))
	else:
		return false
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true


# ================== DESENHO ==================

## Monta (ou remonta) tudo com o tamanho e a fase de hoje.
func _rebuild() -> void:
	for n in _instances:
		n.queue_free()
	_instances.clear()
	_grid.clear()
	var day := last_day
	var full := {}    # Vector3i(chunk x, chunk z, variante) -> [Transform3D]  árvores vivas
	var logs := {}    # troncos caídos
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
		var s: float = h / float(_models[v].height)
		var key := Vector3i(ck.x, ck.y, v)
		if st == FALLEN:
			var ang := float(p[7])
			var fall := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, PI * 0.5)
			if not logs.has(key):
				logs[key] = []
			logs[key].append(Transform3D(fall.scaled(Vector3(s, s, s)), Vector3(x, y + 0.35 * s, z)))
			continue
		var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
		if not _grid.has(gk):
			_grid[gk] = []
		_grid[gk].append(Vector3(x, z, TRUNK_HIT * s + 0.3))
		var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, y - 0.05, z))
		if _alive_now(p, day):
			if not full.has(key):
				full[key] = []
			full[key].append(xf)
		else:
			_build_dying(p, v, xf, s, day)
	for key in full:
		_add_mm(_models[key.z].trunk, full[key], _bark, VIEW_DIST)
		_add_mm(_models[key.z].crown, full[key], _leaves, VIEW_DIST)
	for key in logs:
		_add_mm(_models[key.z].core, logs[key], _bark_dead, VIEW_DIST)
	for key in small:
		_add_mm(_sapling[0], small[key], _bark, SMALL_VIEW)
		_add_mm(_sapling[1], small[key], _leaves, SMALL_VIEW)
	_rebuild_seeds()


## Árvore morrendo ou seca: monta peça por peça conforme a fase.
func _build_dying(p: Array, v: int, xf: Transform3D, s: float, day: int) -> void:
	var m: Dictionary = _models[v]
	var ph := phase_of(p, day)
	var leaf: float = ph.leaf
	var decay: float = ph.decay
	var root := Node3D.new()
	root.transform = xf
	add_child(root)
	_instances.append(root)
	var bark_m: Material = _bark if leaf < 0.6 else _bark_dead
	_piece(root, m.core, bark_m)
	# galhos: na fase final vão caindo um por um (e ficam no chão)
	var nb: int = m.branches.size()
	for i in nb:
		var falls_at := _hash_range(p, 0.05, 0.95, 20 + i)
		if decay < falls_at:
			_piece(root, m.branches[i], bark_m)
		else:
			_fallen_branch(root, m, i, s, p)
	# folhas: amarelam, ficam marrons e o cacho de cada galho vai embora
	var yellow := Color(0.62, 0.5, 0.12)
	var brown := Color(0.48, 0.3, 0.13)
	var color := yellow.lerp(brown, clampf((leaf - 0.3) / 0.4, 0.0, 1.0))
	color.a = clampf(leaf / 0.3, 0.0, 1.0)
	for i in m.clusters.size():
		var gone_at := _hash_range(p, 0.3, 1.0, 40 + i)
		if leaf < gone_at:
			var mi := _piece(root, m.clusters[i], _leaves)
			mi.set_instance_shader_parameter("tint", color)
	# folhas secas no chão: vão juntando enquanto cai, depois se desfazem em um ano
	var amount := clampf(leaf * 1.2, 0.0, 1.0)
	if leaf >= 1.0:
		amount = clampf(1.0 - float(ph.dead) / 365.0, 0.0, 1.0)
	if amount > 0.02:
		var y0 := xf.origin.y
		for k in 7:
			var a := _hash_range(p, 0.0, TAU, 60 + k)
			var r := _hash_range(p, 0.5, 6.5, 70 + k)
			var lx := cos(a) * r
			var lz := sin(a) * r
			var wpos := xf.origin + xf.basis * Vector3(lx, 0, lz)
			var gy: float = _jogo.height_at(wpos.x, wpos.z) - y0
			var li := MeshInstance3D.new()
			li.mesh = _litter_mesh
			li.material_override = _litter
			li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			li.position = Vector3(lx, (gy + 0.03) / s, lz)
			var sz := _hash_range(p, 2.5, 4.5, 80 + k)
			li.scale = Vector3(sz, 1, sz)
			li.rotation.y = a
			li.set_instance_shader_parameter("amount", amount)
			root.add_child(li)


func _piece(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = VIEW_DIST
	parent.add_child(mi)
	return mi


## Galho que caiu: deitado no chão, perto do tronco, na direção em que estava.
func _fallen_branch(root: Node3D, m: Dictionary, i: int, s: float, p: Array) -> void:
	var ax: Array = m.axes[i]
	var a: Vector3 = ax[0]
	var b: Vector3 = ax[1]
	var dir := (b - a).normalized()
	var hd := Vector3(dir.x, 0, dir.z)
	if hd.length() < 0.01:
		hd = Vector3(1, 0, 0)
	hd = hd.normalized().rotated(Vector3.UP, _hash_range(p, -0.6, 0.6, 90 + i))
	var q := Quaternion(dir, hd)
	var base := Vector3(a.x, 0, a.z) + hd * _hash_range(p, 1.5, 3.5, 100 + i)
	var bas := Basis(q)
	var mi := _piece(root, m.branches[i], _bark_dead)
	mi.transform = Transform3D(bas, base - bas * a + Vector3(0, 0.12 / maxf(s, 0.2), 0))


## Sementes no chão: o fruto com a asa.
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
		var b := Basis(Vector3.UP, rot) * Basis(Vector3.FORWARD, 0.18)
		by_chunk[ck].append(Transform3D(b, Vector3(x, _jogo.height_at(x, z) + 0.015, z)))
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
	_bark = bark
	var dead: StandardMaterial3D = bark.duplicate()
	dead.albedo_color = Color(0.62, 0.6, 0.58)
	_bark_dead = dead

	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = sh
	lm.set_shader_parameter("leaf_tex", _leaf_texture(false))
	_leaves = lm

	var lsh := Shader.new()
	lsh.code = LITTER_SHADER
	var ltm := ShaderMaterial.new()
	ltm.shader = lsh
	ltm.set_shader_parameter("leaf_tex", _leaf_texture(true))
	_litter = ltm

	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _seed_texture()
	sm.roughness = 0.85
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sm.alpha_scissor_threshold = 0.5
	_seed_mat = sm


const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
// tint: rgb = cor para onde a folha vai (amarelo, marrom), a = quanto já mudou (0 = verde)
instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
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
	vec3 green = c.rgb * COLOR.rgb;
	float lum = dot(green, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(green, tint.rgb * (0.45 + lum * 1.1), tint.a);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = mix(vec3(0.18, 0.28, 0.08), tint.rgb * 0.25, tint.a);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""

## Folhas secas no chão: aparecem aos poucos conforme 'amount' (0 a 1).
const LITTER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
instance uniform float amount = 1.0;
void fragment() {
	vec4 c = texture(leaf_tex, UV);
	// cada folha tem um 'número' na transparência: com mais 'amount', mais folhas aparecem
	if (c.a < 0.2 || c.a < 1.0 - amount * 0.8) { discard; }
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
"""


## Textura de folhas desenhada aqui. Verde (copa) ou seca, espalhada (chão).
func _leaf_texture(dry: bool) -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 if not dry else 33
	for k in (140 if not dry else 110):
		var cx := rng.randf_range(20, S - 20)
		var cy := rng.randf_range(20, S - 20)
		if not dry:
			var to_c := Vector2(S * 0.5 - cx, S * 0.5 - cy)
			if to_c.length() > S * 0.46 and rng.randf() < 0.7:
				continue
		var ang := rng.randf() * TAU
		var L := rng.randf_range(16, 28) if not dry else rng.randf_range(10, 17)
		var Wd := L * rng.randf_range(0.36, 0.46)
		var base: Color
		if dry:
			base = [Color(0.55, 0.38, 0.16), Color(0.66, 0.5, 0.2), Color(0.45, 0.3, 0.15), Color(0.72, 0.58, 0.28)][rng.randi() % 4]
		else:
			base = Color(0.07, 0.17, 0.05).lerp(Color(0.16, 0.29, 0.08), rng.randf())
		var id_alpha := rng.randf_range(0.25, 1.0) if dry else 1.0
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
					col.a = id_alpha
					img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Textura do fruto: asa cor de palha com nervuras em leque e bordinha, e a sementinha
## escura e lisa na base. O que fica fora do contorno é transparente.
func _seed_texture() -> ImageTexture:
	var W := 128
	var H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for py in H:
		for px in W:
			var u := float(px) / (W - 1)            # 0 = semente, 1 = ponta da asa
			var v := (float(py) / (H - 1)) * 2.0 - 1.0
			if u < 0.2:
				# sementinha: oval escura, com brilho no meio
				var e := pow((u - 0.1) / 0.1, 2.0) + pow(v / 0.45, 2.0)
				if e <= 1.0:
					img.set_pixel(px, py, Color(0.3, 0.18, 0.1).lerp(Color(0.5, 0.33, 0.18), 1.0 - e))
				continue
			# asa: estreita junto da semente, larga e arredondada na ponta
			var half := 0.3 + 0.62 * sin(clampf((u - 0.2) / 0.7, 0.0, 1.0) * PI * 0.5)
			if u > 0.85:
				half *= sqrt(maxf(0.0, 1.0 - pow((u - 0.85) / 0.15, 2.0)))
			if absf(v) > half:
				continue
			var t := absf(v) / maxf(half, 0.01)
			var base := Color(0.82, 0.69, 0.47).lerp(Color(0.66, 0.5, 0.3), t * 0.8)
			var vein := absf(sin((v / maxf(half, 0.05)) * 5.0 + u * 2.0))
			if vein < 0.1:
				base = base.darkened(0.22)
			if t > 0.9:
				base = base.darkened(0.25)   # bordinha
			img.set_pixel(px, py, base)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ================== MODELOS ==================

## Peças de malha (vértices, normais, uv, cores, índices), para montar árvore inteira ou por partes.
class Piece:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nn: Vector3, t: Vector2, col := Color(1, 1, 1)) -> int:
		v.append(p)
		n.append(nn)
		uv.append(t)
		c.append(col)
		return v.size() - 1


static func _mesh(pieces: Array) -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	var I := PackedInt32Array()
	for pc in pieces:
		var off := V.size()
		V.append_array(pc.v)
		N.append_array(pc.n)
		U.append_array(pc.uv)
		C.append_array(pc.c)
		for i in pc.idx:
			I.append(i + off)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Cedrinho em peças: tronco (com sapopemas), galhos e o cacho de folhas de cada galho.
func _make_tree(seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var H := rng.randf_range(22.0, 28.0)          # altura do tronco até a copa
	var r0 := rng.randf_range(0.42, 0.52)         # raio do tronco no chão
	var lean := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
	var trunk_axis := func(h: float) -> Vector3:
		var t := h / H
		return Vector3(lean.x * t * t + sin(h * 0.21) * 0.08, h, lean.y * t * t + cos(h * 0.17) * 0.08)

	# tronco
	var core := Piece.new()
	var SEG := 14
	var RINGS := 22
	var fin_phase := rng.randf() * TAU
	for ri in RINGS + 1:
		var h := H * pow(float(ri) / RINGS, 1.35)
		var c: Vector3 = trunk_axis.call(h)
		var taper := lerpf(r0, r0 * 0.42, h / H)
		var flare := 1.0 + 0.55 * exp(-h * 1.4)
		for si in SEG + 1:
			var a := TAU * si / SEG
			var fin := pow(maxf(0.0, cos(a * 5 + fin_phase)), 8.0) * maxf(0.0, 1.0 - h / 1.8) * 1.1
			var r := taper * flare + fin
			core.vert(c + Vector3(cos(a) * r, 0, sin(a) * r), Vector3(cos(a), 0.15, sin(a)).normalized(), Vector2(float(si) / SEG * 2.0, h / 3.0))
	for ri in RINGS:
		for si in SEG:
			var a := ri * (SEG + 1) + si
			var b := a + SEG + 1
			core.idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))

	# galhos (cada galho grosso junto com o galhinho que sai dele)
	var branches: Array = []
	var axes: Array = []
	var tips_of: Array = []
	var nb := rng.randi_range(5, 7)
	for bi in nb:
		var pc := Piece.new()
		var h0 := H * rng.randf_range(0.66, 0.9)
		var start: Vector3 = trunk_axis.call(h0)
		var ang := TAU * bi / nb + rng.randf_range(-0.3, 0.3)
		var up := rng.randf_range(0.55, 0.9)
		var length := rng.randf_range(4.5, 7.0)
		var dirv := Vector3(cos(ang), up, sin(ang)).normalized()
		var tip := start + dirv * length
		_cyl(pc, start, tip, r0 * 0.38, r0 * 0.12)
		var mid := start.lerp(tip, 0.55)
		var side := Vector3(cos(ang + 0.9), up + 0.2, sin(ang + 0.9)).normalized()
		var tip2 := mid + side * length * 0.45
		_cyl(pc, mid, tip2, r0 * 0.16, r0 * 0.06)
		branches.append(pc)
		axes.append([start, tip])
		tips_of.append([tip, tip2])

	# copa: cachos de folhas, cada um preso a um galho (ou ao topo)
	var top: Vector3 = trunk_axis.call(H)
	var crown_c := top + Vector3(0, 2.0, 0)
	var crown_r := Vector3(rng.randf_range(7.0, 9.0), rng.randf_range(3.2, 4.2), rng.randf_range(7.0, 9.0))
	var clusters: Array = []
	for i in nb + 1:
		clusters.append(Piece.new())
	for k in 95:
		var p: Vector3
		if k < nb * 2 * 5:
			var tips: Array = tips_of[k % nb]
			var tip: Vector3 = tips[(k / nb) % 2]
			p = tip + Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(-0.6, 1.6), rng.randf_range(-2.2, 2.2))
		else:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-1, 1)).normalized()
			p = crown_c + d * crown_r * rng.randf_range(0.55, 1.0)
		# o cacho fica com o galho mais perto (ou com o topo)
		var owner := nb
		var bd := (p - top).length_squared()
		for bi in nb:
			for tp in tips_of[bi]:
				var dd := (p - (tp as Vector3)).length_squared()
				if dd < bd:
					bd = dd
					owner = bi
		var pc: Piece = clusters[owner]
		var outward := ((p - crown_c) / crown_r + Vector3(0, 0.6, 0)).normalized()
		var size := rng.randf_range(2.6, 3.8)
		var tint := Color(1, 1, 1).lerp(Color(0.8, 0.95, 0.75), rng.randf())
		for qd in 2:
			var bs := Basis(Vector3.UP, rng.randf() * TAU + qd * PI * 0.5) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
			var ax := bs.x * size * 0.5
			var ay := bs.y * size * 0.5
			var i0 := pc.vert(p - ax - ay, outward, Vector2(0, 1), tint)
			pc.vert(p + ax - ay, outward, Vector2(1, 1), tint)
			pc.vert(p + ax + ay, outward, Vector2(1, 0), tint)
			pc.vert(p - ax + ay, outward, Vector2(0, 0), tint)
			pc.idx.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3]))

	var model := {}
	model.core = _mesh([core])
	model.trunk = _mesh([core] + branches)
	model.crown = _mesh(clusters)
	model.branches = branches.map(func(pc): return _mesh([pc]))
	model.clusters = clusters.filter(func(pc): return pc.v.size() > 0).map(func(pc): return _mesh([pc]))
	model.axes = axes
	model.height = (model.crown as Mesh).get_aabb().end.y
	return model


## Cilindro afinando de 'a' até 'b' (um galho), com uma curvinha.
static func _cyl(pc: Piece, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var SEG := 7
	var RINGS := 4
	var base := pc.v.size()
	for ri in RINGS + 1:
		var t := float(ri) / RINGS
		var c := a.lerp(b, t) + up * sin(t * PI) * 0.25
		var r := lerpf(ra, rb, t)
		for si in SEG + 1:
			var ang := TAU * si / SEG
			var nn := (side * cos(ang) + up * sin(ang)).normalized()
			pc.vert(c + nn * r, nn, Vector2(float(si) / SEG, t * 2.0))
	for ri in RINGS:
		for si in SEG:
			var i0 := base + ri * (SEG + 1) + si
			var i1 := i0 + SEG + 1
			pc.idx.append_array(PackedInt32Array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1]))


## Muda (1 m de altura; a instância é esticada para a altura de verdade).
func _make_sapling() -> Array:
	var stem := Piece.new()
	var SEG := 5
	for ri in 2:
		var y := float(ri)
		var r := 0.018 if ri == 0 else 0.008
		for si in SEG + 1:
			var a := TAU * si / SEG
			stem.vert(Vector3(cos(a) * r, y, sin(a) * r), Vector3(cos(a), 0, sin(a)), Vector2(float(si) / SEG, y))
	for si in SEG:
		stem.idx.append_array(PackedInt32Array([si, si + SEG + 1, si + 1, si + 1, si + SEG + 1, si + SEG + 2]))
	var lv := Piece.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in 7:
		var p := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.45, 1.0), rng.randf_range(-0.12, 0.12))
		var size := rng.randf_range(0.28, 0.42)
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.9, -0.3))
		var ax := bs.x * size * 0.5
		var ay := bs.y * size * 0.5
		var nn := Vector3(p.x, 0.8, p.z).normalized()
		var i0 := lv.vert(p - ax - ay, nn, Vector2(0, 1))
		lv.vert(p + ax - ay, nn, Vector2(1, 1))
		lv.vert(p + ax + ay, nn, Vector2(1, 0))
		lv.vert(p - ax + ay, nn, Vector2(0, 0))
		lv.idx.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3]))
	return [_mesh([stem]), _mesh([lv])]


## Fruto do Cedrinho: uma lâmina fina (a asa, com a textura de nervuras e a sementinha
## na base), levemente torcida e curvada. Uns 9 cm (um pouco maior que o real, para
## dar para achar no chão).
func _make_seed() -> Mesh:
	var pc := Piece.new()
	var L := 0.09
	var Wd := 0.035
	var NU := 12
	for i in NU + 1:
		var u := float(i) / NU
		var twist := u * 0.6
		var lift := sin(u * PI) * 0.006 + u * u * 0.012
		for j in 2:
			var s := -1.0 if j == 0 else 1.0
			var off := Vector3(0, sin(twist) * s * Wd * 0.5, cos(twist) * s * Wd * 0.5)
			pc.vert(Vector3(u * L, lift + 0.004, 0) + off, Vector3(0, 1, 0), Vector2(u, 0.0 if j == 0 else 1.0))
	for i in NU:
		var a := i * 2
		pc.idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	# volume da sementinha: um gomo baixo por cima da base da asa
	var c := Vector3(0.009, 0.006, 0)
	var top := pc.vert(c + Vector3(0, 0.007, 0), Vector3.UP, Vector2(0.1, 0.5))
	var ring := []
	for k in 8:
		var a := TAU * k / 8.0
		ring.append(pc.vert(c + Vector3(cos(a) * 0.009, 0.0, sin(a) * 0.006), Vector3(cos(a), 0.6, sin(a)).normalized(), Vector2(0.1 + cos(a) * 0.08, 0.5 + sin(a) * 0.4)))
	for k in 8:
		pc.idx.append_array(PackedInt32Array([top, ring[(k + 1) % 8], ring[k]]))
	return _mesh([pc])


## Quadrado no chão (1 x 1 m) para as folhas secas.
func _make_litter_quad() -> Mesh:
	var pc := Piece.new()
	var i0 := pc.vert(Vector3(-0.5, 0, -0.5), Vector3.UP, Vector2(0, 0))
	pc.vert(Vector3(0.5, 0, -0.5), Vector3.UP, Vector2(1, 0))
	pc.vert(Vector3(0.5, 0, 0.5), Vector3.UP, Vector2(1, 1))
	pc.vert(Vector3(-0.5, 0, 0.5), Vector3.UP, Vector2(0, 1))
	pc.idx.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3]))
	return _mesh([pc])
