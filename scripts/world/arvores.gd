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
const Sons := preload("res://scripts/sons.gd")
const GalhoGeo := preload("res://scripts/world/galho_geo.gd")

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
const CUT_H := 1.0              # altura (m) onde o machado bate no tronco
const STUMP_LIFE_MIN := 900     # dias até o toco apodrecer e sumir (2,5 a 4 anos)
const STUMP_LIFE_MAX := 1400
const GREEN_FALLEN_DAYS := 40   # dias até as folhas da árvore derrubada verde secarem e caírem
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
var _bark_log: Material
var _leaves: Material
var _litter: Material
var _seed_mat: Material
var _instances: Array = []
var _seed_nodes: Array = []
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var stumps: Array = []             # tocos: [x, z, dia do corte, raio em cima, raio embaixo, altura]
var _stump_top_mat: Material
var _bark_2s: StandardMaterial3D
var cuts := {}                     # Vector2(x, z) da árvore -> [machadadas, lado do corte]
var _cut_nodes := {}
var _cut_mat: Material
var _chips_mat: Material
var _falling: Array = []
var fell_hook := Callable()          # avisado quando uma árvore começa a tombar (cipós)
var fall_done_hook := Callable()
var _log_nodes := {}               # tora derrubada pelo jogador -> nó desenhado
var extra_barks := {}              # casca de outras plantas (ex.: "buriti") para as toras soltas
var free_logs: Array = []          # pedaços de tora soltos (levados pelo jogador): ver _free_log
var _free_nodes: Array = []
var _nat_segs: Array = []          # troncos que caíram sozinhos (colisão)
var _log_segs: Array = []          # [ponta A, ponta B, raio] de cada tora (para colidir e subir)          # árvores tombando agora (a animação desenha elas)
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
	# nada de árvore, muda, semente ou toco dentro do mar (mundo antigo que virou ilha)
	plants = plants.filter(func(p): return not _in_sea(float(p[0]), float(p[1])))
	seeds = seeds.filter(func(sd): return not _in_sea(float(sd[0]), float(sd[1])))
	stumps = stumps.filter(func(st): return not _in_sea(float(st[0]), float(st[1])))
	trees = plants
	_rebuild()
	# troncos que caíram sozinhos em jogos antigos: viram toco + tronco que dá para cortar
	var snapped_any := false
	for p in plants:
		if int(p[5]) == FALLEN and not (p.size() > 9 and p[9] is Array):
			_snap_natural(p, int(p[6]))
			snapped_any = true
	if snapped_any:
		_rebuild()
	# toras já cortadas de jogos antigos ainda presas na árvore caída: caem no chão agora
	for p in plants:
		if int(p[5]) == FALLEN and p.size() > 10 and p[10] is Array and (p[10] as Array).size() > 1 and p[9] is Array:
			_release_pieces(p)
	_rebuild_logs()


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
	# toco que já apodreceu de vez some
	var keep_st := []
	for st_ in stumps:
		if day - int(st_[2]) < _stump_life(st_):
			keep_st.append(st_)
	stumps = keep_st
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
	_snap_natural(p, day)


## Árvore seca que caiu sozinha: o tronco podre quebra a 1 m do chão. Fica o toco e o
## tronco deitado, que dá para cortar em toras como o das árvores derrubadas a machado.
func _snap_natural(p: Array, day: int) -> void:
	if p.size() > 9 and p[9] is Array:
		return
	var h := height_of(p, day)
	if h < SAPLING_MAX_H + 0.5:
		return
	var v := int(p[4]) % VARIANTS
	var s: float = h / float(_models[v].height)
	if p.size() < 10:
		p.resize(10)
	p[8] = 0
	var a := float(p[7])
	p[9] = [hits_to_fell(p), a + PI]
	# a árvore seca já tinha perdido os galhos
	if p.size() < 13:
		p.resize(13)
	var gone := []
	for bi in (_models[v].binfo as Array).size():
		gone.append(bi)
	p[12] = gone
	stumps.append([float(p[0]), float(p[1]), int(p[6]), v, s, _cut_from(p, p[9], s)])


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


## No mar ou na beira dele (água salgada e areia da praia: árvore não nasce).
func _in_sea(x: float, z: float) -> bool:
	return _jogo.height_at(x, z) < MundoSim.SEA * _jogo.HS + 0.6


func _ground_ok(x: float, z: float) -> bool:
	var sim = _jogo.sim
	var cell: float = _jogo.CELL
	if _in_sea(x, z):
		return false
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
		var cl := []
		for k in cuts:
			cl.append([k.x, k.y, cuts[k][0], cuts[k][1]])
		f.store_string(JSON.stringify({"versao": 3, "dia": last_day, "plantas": plants, "sementes": seeds, "cortes": cl, "tocos": stumps, "toras": free_logs}))
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
	stumps = d.get("tocos", [])
	free_logs = []
	for fl in d.get("toras", []):
		if fl is Dictionary and fl.has("pos"):
			if _jogo.sim.converted:
				fl.pos[1] = float(fl.pos[1]) + (MundoSim.SEA + 0.6) * _jogo.HS   # o mundo virou ilha: o chão subiu
			free_logs.append(fl)
	cuts = {}
	for c in d.get("cortes", []):
		cuts[Vector2(float(c[0]), float(c[1]))] = [int(c[2]), float(c[3])]
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true


# ================== DESENHO ==================

## Monta (ou remonta) tudo com o tamanho e a fase de hoje.
func _rebuild() -> void:
	# libera na hora (não no fim do quadro): cada folha amarelando usa um espaço do
	# "tint" no shader, e o celular só tem 4096; redesenhar duas vezes no mesmo quadro estourava
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	for k in _cut_nodes:
		if is_instance_valid(_cut_nodes[k]):
			_cut_nodes[k].free()
	_cut_nodes.clear()
	for k in _log_nodes:
		if is_instance_valid(_log_nodes[k]):
			_log_nodes[k].free()
	_log_nodes.clear()
	_log_segs.clear()
	_nat_segs.clear()
	for n in _free_nodes:
		if is_instance_valid(n):
			n.free()
	_free_nodes.clear()
	for fl in free_logs:
		_place_free_node(fl)
	_instances.clear()
	_grid.clear()
	var day := last_day
	var full := {}    # Vector3i(chunk x, chunk z, variante) -> [Transform3D]  árvores vivas
	var logs := {}    # troncos caídos
	var small := {}   # Vector2i(chunk) -> [Transform3D]  mudas
	for p in plants:
		if _falling.has(p):
			continue
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
		if st == FALLEN and p.size() > 9 and p[9] is Array:
			_build_log(p, v, s, day)        # derrubada pelo jogador: só a parte de cima do corte
			continue
		if st == FALLEN and p.size() > 8 and int(p[8]) == 1 and day - int(p[6]) < GREEN_FALLEN_DAYS:
			_build_fallen_green(p, v, s, day)
			continue
		if st == FALLEN:
			var rest := _rest_pose(p, h)
			if not logs.has(key):
				logs[key] = []
			var lxf := Transform3D(Basis(rest[1], rest[2]) * Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), rest[0])
			logs[key].append(lxf)
			var mm: Dictionary = _models[v]
			_nat_segs.append([lxf * _axis_of(mm, 1.0), lxf * _axis_of(mm, float(mm.H) * 0.6), float(mm.r0) * s])
			continue
		var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
		if not _grid.has(gk):
			_grid[gk] = []
		_grid[gk].append(Vector3(x, z, TRUNK_HIT * s + 0.3))
		var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, y - 0.05, z))
		if cuts.has(_cut_key(p)):
			_build_cut_tree(p, v, xf, s, day)    # com a boca do machado escavada
			continue
		if _alive_now(p, day):
			if not full.has(key):
				full[key] = []
			full[key].append(xf)
		else:
			_build_dying(p, v, xf, s, day)
	for st_ in stumps:
		_build_stump(st_, day)
	if not cuts.is_empty():
		var live := {}
		for p in plants:
			if int(p[5]) != FALLEN and cuts.has(_cut_key(p)):
				live[_cut_key(p)] = true
		for k in cuts.keys():
			if not live.has(k):
				cuts.erase(k)    # árvore caiu ou sumiu: o corte vai junto
	for key in full:
		_add_mm(_models[key.z].trunk, full[key], _bark, VIEW_DIST)
		_add_mm(_models[key.z].crown, full[key], _leaves, VIEW_DIST)
	for key in logs:
		_add_mm(_models[key.z].core, logs[key], _bark_log, VIEW_DIST)
	for key in small:
		_add_mm(_sapling[0], small[key], _bark, SMALL_VIEW)
		_add_mm(_sapling[1], small[key], _leaves, SMALL_VIEW)
	_rebuild_seeds()


## Árvore em pé que já levou machadadas: o tronco desenhado sozinho, com a boca escavada.
func _build_cut_tree(p: Array, v: int, xf: Transform3D, s: float, day: int) -> void:
	var m: Dictionary = _models[v]
	var cut := _cut_info(p)
	var mesh := _trunk_build(m, 0.0, float(m.H), [cut], s)
	var root: Node3D
	if _alive_now(p, day):
		root = Node3D.new()
		root.transform = xf
		add_child(root)
		_trunk_node(root, mesh, _bark)
		for b in m.branches:
			_piece(root, b, _bark)
		_piece(root, m.crown, _leaves)
	else:
		root = _build_dying(p, v, xf, s, day, mesh)
		_instances.erase(root)
	_cut_nodes[_cut_key(p)] = root


## Só uma árvore mudou (mais uma machadada): refaz só ela.
func _rebuild_cut(p: Array) -> void:
	var k := _cut_key(p)
	if _cut_nodes.has(k) and is_instance_valid(_cut_nodes[k]):
		_cut_nodes[k].free()
	_cut_nodes.erase(k)
	var day := last_day
	var h := height_of(p, day)
	var v := int(p[4]) % VARIANTS
	var s: float = h / float(_models[v].height)
	var x := float(p[0])
	var z := float(p[1])
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, _jogo.height_at(x, z) - 0.15, z))
	_build_cut_tree(p, v, xf, s, day)


func _stump_life(st_: Array) -> float:
	var hsh := absi(hash(Vector3(float(st_[0]), float(st_[1]), 7)))
	return lerpf(STUMP_LIFE_MIN, STUMP_LIFE_MAX, (hsh % 1009) / 1009.0)


## O toco: a parte de baixo do próprio tronco (com as raízes), do chão até o corte,
## com a ponta lascada. Com o tempo a madeira escurece, a casca seca, o topo
## esfarela e vai baixando até o toco sumir.
func _build_stump(st_: Array, day: int) -> void:
	if st_.size() < 6 or not st_[5] is Dictionary:
		return
	var x := float(st_[0])
	var z := float(st_[1])
	var v := int(st_[3]) % VARIANTS
	var s := float(st_[4])
	var cut: Dictionary = st_[5]
	var m: Dictionary = _models[v]
	var t := clampf(float(day - int(st_[2])) / _stump_life(st_), 0.0, 1.0)
	var top := float(cut.h) * lerpf(1.0, 0.4, smoothstep(0.45, 1.0, t))
	var tint := Color(1, 1, 1).lerp(Color(0.62, 0.58, 0.55), smoothstep(0.0, 0.3, t)).lerp(Color(0.32, 0.27, 0.22), smoothstep(0.3, 0.85, t))
	var mesh := _trunk_build(m, 0.0, top, [cut], s, cut, {}, tint)
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	var root := Node3D.new()
	root.transform = Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, _jogo.height_at(x, z) - 0.15, z))
	add_child(root)
	_instances.append(root)
	_trunk_node(root, mesh, _bark if t < 0.4 else _bark_dead)
	var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not _grid.has(gk):
		_grid[gk] = []
	_grid[gk].append(Vector3(x, z, _radius_of(m, top, 0.0) * s * 1.1 + 0.3))


## Onde a tora derrubada fica no chão (transformação do modelo para o mundo).
func _log_xf(p: Array, h: float, s: float, cut: Dictionary) -> Transform3D:
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var x := float(p[0])
	var z := float(p[1])
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	var rest := _rest_pose(p, h)
	var away := Vector3(sin(float(p[7])), 0, cos(float(p[7])))
	var b := Basis(rest[1], rest[2]) * Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
	# a ponta cortada fica logo depois do toco, encostada nele
	var hinge: Vector3 = rest[0] + away * (trunk_radius(p) * 1.35 + 0.12)
	return Transform3D(b, hinge - b * _axis_of(m, float(cut.h)))


## Tora derrubada pelo jogador: do corte para cima, com a ponta lascada, os galhos
## e (se caiu verde) a copa secando aos poucos.
func _build_log(p: Array, v: int, s: float, day: int) -> void:
	var k := _cut_key(p)
	if _log_nodes.has(k) and is_instance_valid(_log_nodes[k]):
		_log_nodes[k].free()
	var m: Dictionary = _models[v]
	var h := height_of(p, day)
	var c: Array = p[9]
	var cut := _cut_from(p, c, s)
	var xf := _log_xf(p, h, s, cut)
	var root := Node3D.new()
	add_child(root)
	_log_nodes[k] = root
	var green := p.size() > 8 and int(p[8]) == 1
	var age := float(day - int(p[6]))
	var bark_m: Material = _bark if age < 200 else _bark_dead
	var along := (xf * _axis_of(m, float(m.H)) - xf * _axis_of(m, float(cut.h))).normalized()
	var a_up := _log_up_angle(xf)
	var buck = p[11] if p.size() > 11 else null
	for pc in log_pieces(p):
		var h0 := float(pc[0])
		var h1 := float(pc[1])
		var node := Node3D.new()
		node.transform = Transform3D(xf.basis, xf.origin + along * float(pc[2]))
		root.add_child(node)
		# pontas: a de baixo da primeira é a quebra do tombo; as outras são cortes de machado
		var bottom: Dictionary = cut if absf(h0 - float(cut.h)) < 0.0001 else _buck_end(p, a_up, h0, 1.0)
		var top := {} if absf(h1 - float(m.H)) < 0.0001 else _buck_end(p, a_up, h1, -1.0)
		var notches := []
		if buck is Array and float(buck[0]) > h0 and float(buck[0]) < h1:
			notches.append(_buck_notch(p, a_up, float(buck[0]), int(buck[1]), s))
		_trunk_node(node, _trunk_build(m, h0, h1, notches, s, top, bottom), bark_m)
		# colisão: o jogador não atravessa a tora (pode pular por cima ou subir nela)
		var A: Vector3 = node.transform * _axis_of(m, h0)
		var B: Vector3 = node.transform * _axis_of(m, h1)
		_log_segs.append([A, B, _radius_of(m, (h0 + h1) * 0.5, 0.0) * s])
		if absf(h1 - float(m.H)) > 0.0001:
			continue
		# a copa fica com o último pedaço: galhos inteiros, cortados (com o entalhe) ou só o toco
		# cada galho no seu nó: o que ficaria enterrado é levantado (gira em volta da base)
		var holders := {}
		for bi in m.branches.size():
			var lift := branch_lift(p, bi, node.transform)
			var hold := Node3D.new()
			hold.transform = node.transform.affine_inverse() * lift * node.transform
			node.add_child(hold)
			holders[bi] = hold
			var st := branch_state(p, bi)
			if int(st[0]) == 0 and int(st[1]) == 0:
				_piece(hold, m.branches[bi], bark_material() if age < 200 else bark_m)
			else:
				var up_model := ((node.transform.basis * hold.transform.basis).inverse() * Vector3.UP).normalized()
				var bd := GalhoGeo.Builder.new()
				_branch_partial(bd, m, bi, st, up_model, h0)
				_trunk_node(hold, bd.commit(), bark_material() if age < 200 else bark_m)
		if green and age < GREEN_FALLEN_DAYS:
			var color := fallen_leaf_tint(p)
			for i in m.clusters.size():
				var owner := int(m.cluster_owner[i])
				if _cluster_gone(p, m, owner):
					continue
				if _cluster_shown(p, i):
					var mi := _piece(holders.get(owner, node), m.clusters[i], _leaves)
					mi.set_instance_shader_parameter("tint", color)


# ---------- galhos da árvore derrubada: 3 cortes em cada galho ----------
# 1) onde estão as folhas (a ponta com as folhas cai), 2) no meio (cai a parte de fora),
# 3) no toco, rente ao tronco (cai o resto). Se o lugar do corte está alto demais para
# alcançar, corta no próximo lugar que alcança (e cai tudo o que está depois dele).

const BR_CUTS := [0.8, 0.45, 0.07]     # onde fica cada corte, ao longo do galho (0 = tronco)
const BR_END := [1.0, 0.8, 0.45, 0.07]  # até onde o galho vai em cada estágio


## [estágio (0 inteiro, 1 sem folhas, 2 só a metade de dentro, 3 só o toco), machadadas, t do corte]
func branch_state(p: Array, i: int) -> Array:
	var gone: Array = p[12] if p.size() > 12 and p[12] is Array else []
	if gone.has(i):
		return [3, 0, 0.0]
	if p.size() > 13 and p[13] is Dictionary:
		var st = p[13].get(str(i))
		if st is Array and st.size() >= 3:
			return [int(st[0]), int(st[1]), float(st[2])]
	return [0, 0, 0.0]


func _set_branch_state(p: Array, i: int, st: Array) -> void:
	if p.size() < 14:
		p.resize(14)
	if not p[13] is Dictionary:
		p[13] = {}
	p[13][str(i)] = st
	if int(st[0]) >= 3:
		var gone: Array = p[12] if p[12] is Array else []
		if not gone.has(i):
			gone.append(i)
		p[12] = gone


## Os cachos de folhas de um galho (ou do topo, owner = nº de galhos) já caíram?
func _cluster_gone(p: Array, m: Dictionary, owner: int) -> bool:
	if owner < m.axes.size():
		return int(branch_state(p, owner)[0]) >= 1
	for bi in m.axes.size():
		if int(branch_state(p, bi)[0]) < 1:
			return false
	return true


## Algum galho ainda preso na árvore caída (com mais que o toquinho)?
func has_branches(p: Array) -> bool:
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	for bi in m.axes.size():
		if int(branch_state(p, bi)[0]) < 3:
			return true
	return false


func _crown_xf(p: Array) -> Variant:
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var h := height_of(p, last_day)
	var s: float = h / float(m.height)
	for pc in log_piece_xfs(p):
		if absf(float(pc[1]) - float(m.H) * s) < 0.01:
			return pc[2]
	return null


## Galho da árvore caída que ficaria enterrado no chão: gira em volta da base dele
## até ficar um pouco para cima (todos os galhos ficam à vista e dá para cortar).
## Devolve a transformação no mundo (identidade se o galho já está para fora).
func branch_lift(p: Array, i: int, xf: Transform3D) -> Transform3D:
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	if i >= m.binfo.size():
		return Transform3D.IDENTITY
	var bi: Dictionary = m.binfo[i]
	var a: Vector3 = xf * (bi.a as Vector3)
	var b: Vector3 = xf * (bi.b as Vector3)
	var mid: Vector3 = xf * _br_center(bi, 0.5)
	if b.y - _jogo.surface_at(b.x, b.z) > 0.5 and mid.y - _jogo.surface_at(mid.x, mid.z) > 0.3:
		return Transform3D.IDENTITY
	var v := b - a
	var h := Vector3(v.x, 0, v.z)
	if h.length() < 0.05:
		h = Vector3(1, 0, 0)
	var want := (h.normalized() * cos(0.45) + Vector3.UP * sin(0.45)).normalized()
	var r := Basis(Quaternion(v.normalized(), want))
	return Transform3D(r, a - r * a)


static func _br_center(bi: Dictionary, t: float) -> Vector3:
	return GalhoGeo.branch_center(bi.a, bi.b, t)


static func _br_radius(bi: Dictionary, t: float) -> float:
	return lerpf(float(bi.ra), float(bi.rb), t)


## Próximo corte de galho ao alcance do machado:
## {p, i, t (onde corta), to (estágio depois), point (no mundo)} ou {}.
func felled_branch_target(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for p in plants:
		if int(p[5]) != FALLEN or p.size() < 10 or not p[9] is Array or _falling.has(p):
			continue
		var cx = _crown_xf(p)
		if cx == null:
			continue
		var xf: Transform3D = cx
		var m: Dictionary = _models[int(p[4]) % VARIANTS]
		for i in m.binfo.size():
			var st := branch_state(p, i)
			var stage := int(st[0])
			if stage >= 3:
				continue
			var lift := branch_lift(p, i, xf)
			for k in range(stage, 3):
				var t: float = BR_CUTS[k]
				var c: Vector3 = lift * (xf * _br_center(m.binfo[i], t))
				var above: float = c.y - _jogo.surface_at(c.x, c.z)
				if above > 2.0 or above < -0.12:
					continue          # alto demais (ou enterrado no chão): tenta mais perto do tronco
				var d := Vector2(pos.x - c.x, pos.z - c.z).length()
				if d < bd:
					bd = d
					best = {"p": p, "i": i, "t": t, "to": k + 1, "point": c}
				break
	return best


## Machadadas para cortar o galho no ponto t (galho grosso pede mais).
func branch_hits_needed(p: Array, i: int, t: float) -> int:
	if bool(_jogo.teste):
		return 1
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var s: float = height_of(p, last_day) / float(m.height)
	var r := _br_radius(m.binfo[i], t) * s
	return clampi(int(round(1.0 + r * 16.0)), 2, 4)


## Uma machadada no galho. Quando termina, devolve o que caiu (no mundo):
## {wood: [[pontos], [raios]] (pedaços de madeira), leaves: [índices dos cachos], xf}.
## Senão devolve {}.
func branch_hit(p: Array, i: int, t: float, to: int) -> Dictionary:
	var st := branch_state(p, i)
	if absf(float(st[2]) - t) > 0.001:
		st = [int(st[0]), 0, t]
	st[1] = int(st[1]) + 1
	var cx = _crown_xf(p)
	if int(st[1]) < branch_hits_needed(p, i, t) or cx == null:
		_set_branch_state(p, i, st)
		_rebuild_logs()
		return {}
	var xf0: Transform3D = cx
	var xf: Transform3D = branch_lift(p, i, xf0) * xf0     # o galho (levantado, se ia ficar enterrado)
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var bi: Dictionary = m.binfo[i]
	var from := int(st[0])
	var leaves_before := []
	for ci in m.clusters.size():
		if not _cluster_gone(p, m, int(m.cluster_owner[ci])) and _cluster_shown(p, ci):
			leaves_before.append(ci)
	var out := {"wood": [], "leaves": [], "xf": xf, "lxf": {}}
	var s: float = height_of(p, last_day) / float(m.height)
	# o pedaço do galho de t até onde ele ia
	var t_end: float = BR_END[from]
	var pts := []
	var radii := []
	for k in 7:
		var tt := lerpf(t, t_end, k / 6.0)
		pts.append(xf * _br_center(bi, tt))
		radii.append(_br_radius(bi, tt) * s)
	out.wood.append([pts, radii])
	# o galhinho do meio vai junto quando corta antes dele
	if from < 2 and to >= 2:
		var sp := []
		var sr := []
		for k in 5:
			var tt := k / 4.0
			sp.append(xf * (bi.m as Vector3).lerp(bi.t2, tt))
			sr.append(lerpf(float(bi.ra2), float(bi.rb2), tt) * s)
		out.wood.append([sp, sr])
	_set_branch_state(p, i, [to, 0, 0.0])
	for ci in leaves_before:
		var owner := int(m.cluster_owner[ci])
		if _cluster_gone(p, m, owner):
			out.leaves.append(ci)
			out.lxf[ci] = branch_lift(p, owner, xf0) * xf0
	_rebuild_logs()
	return out


## O cacho de folhas ainda está na árvore caída (vai secando e caindo sozinho com o tempo)?
func _cluster_shown(p: Array, ci: int) -> bool:
	var green := p.size() > 8 and int(p[8]) == 1
	var age := float(last_day - int(p[6]))
	if not green or age >= GREEN_FALLEN_DAYS:
		return false
	return age / GREEN_FALLEN_DAYS < _hash_range(p, 0.45, 1.0, 140 + ci)


## Cor das folhas da árvore caída agora (amarelando).
func fallen_leaf_tint(p: Array) -> Color:
	var age := float(last_day - int(p[6]))
	var f := age / GREEN_FALLEN_DAYS
	var yellow := Color(0.62, 0.5, 0.12)
	var brown := Color(0.48, 0.3, 0.13)
	var color := yellow.lerp(brown, clampf((f - 0.35) / 0.4, 0.0, 1.0))
	color.a = clampf(f / 0.35, 0.0, 1.0)
	return color


func cluster_mesh(v: int, ci: int) -> Mesh:
	return _models[v % VARIANTS].clusters[ci]


## Desenha um galho que já levou machadadas ou foi cortado (no espaço do modelo).
func _branch_partial(bd, m: Dictionary, i: int, st: Array, up_model: Vector3, min_y: float) -> void:
	var bi: Dictionary = m.binfo[i]
	var stage := int(st[0])
	var t_end: float = BR_END[stage]
	if stage >= 3 and (bi.a as Vector3).y < min_y:
		return              # o toquinho ficou no pedaço de baixo, que já foi levado
	var ts := []
	for k in 9:
		ts.append(t_end * k / 8.0)
	var notch := {}
	if int(st[1]) > 0 and float(st[2]) < t_end:
		var tc := float(st[2])
		var best := 0
		for k in ts.size():
			if absf(float(ts[k]) - tc) < absf(float(ts[best]) - tc):
				best = k
		ts[best] = tc
		var prog := clampf(float(st[1]) / 4.0, 0.0, 1.0)
		notch = {"i": best, "dir": up_model, "depth": 0.3 + 0.55 * prog, "w": 0.7}
	var pts := []
	var radii := []
	for tt in ts:
		pts.append(_br_center(bi, float(tt)))
		radii.append(_br_radius(bi, float(tt)))
	bd.tube(pts, radii, [false, stage > 0], notch, 7)
	if stage < 2:
		var sp := []
		var sr := []
		for k in 5:
			sp.append((bi.m as Vector3).lerp(bi.t2, k / 4.0))
			sr.append(lerpf(float(bi.ra2), float(bi.rb2), k / 4.0))
		bd.tube(sp, sr, [false, false], {}, 6)


## Pedaços da tora: [[de, até (altura no modelo), deslocamento (m) ao longo da tora], ...]
func log_pieces(p: Array) -> Array:
	if p.size() > 10 and p[10] is Array:
		return p[10]          # (vazio = todas as toras já foram levadas)
	var s: float = height_of(p, last_day) / float(_models[int(p[4]) % VARIANTS].height)
	var cut := _cut_from(p, p[9], s)
	return [[float(cut.h), float(_models[int(p[4]) % VARIANTS].H), 0.0]]


## Ângulo (no anel do tronco) que aponta para cima com a tora deitada.
static func _log_up_angle(xf: Transform3D) -> float:
	return atan2(xf.basis.z.y, xf.basis.x.y)


func _buck_notch(p: Array, a_up: float, h_at: float, hits: int, s: float) -> Dictionary:
	var prog := clampf(float(hits) / buck_hits_needed(p, h_at), 0.0, 1.0)
	return {"h": h_at, "ac": a_up, "depth": 0.12 + 0.78 * prog, "up": (0.06 + 0.1 * prog) / s,
		"down": (0.06 + 0.1 * prog) / s, "open": 1.0 + 0.6 * prog,
		"seed": absi(hash(Vector3(float(p[0]), float(p[1]), h_at))) % 100000}


func _buck_end(p: Array, a_up: float, h_at: float, sign: float) -> Dictionary:
	return {"ac": a_up + PI, "seed": absi(hash(Vector3(float(p[0]), float(p[1]), h_at))) % 100000,
		"rough": 0.45, "sign": sign}


## Tamanho das toras (m): 2 metros, para ficarem altas fincadas nos buracos
## (com 80 cm enterrados sobra 1,2 m para fora: a base das construções).
func piece_len(_p: Array) -> float:
	return 2.0


## Machadadas para cortar a tora num ponto (tora grossa pede mais).
func buck_hits_needed(p: Array, h_at: float) -> int:
	if bool(_jogo.teste):
		return 1
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var s: float = height_of(p, last_day) / float(m.height)
	var r := _radius_of(m, h_at, 0.0) * s
	return clampi(int(round(2.0 + r * 14.0)), 3, 10)


## Lugar da tora mais perto do jogador onde dá para cortar: de meio em meio metro,
## deixando pedaços de pelo menos 1 m. Devolve {} se não tem tora perto.
func log_target(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for p in plants:
		if int(p[5]) != FALLEN or p.size() < 10 or not p[9] is Array or _falling.has(p):
			continue
		var v := int(p[4]) % VARIANTS
		var m: Dictionary = _models[v]
		var h := height_of(p, last_day)
		var s: float = h / float(m.height)
		var cut := _cut_from(p, p[9], s)
		var xf := _log_xf(p, h, s, cut)
		var along := (xf * _axis_of(m, float(m.H)) - xf * _axis_of(m, float(cut.h))).normalized()
		var buck = p[11] if p.size() > 11 else null
		for pc in log_pieces(p):
			var h0 := float(pc[0])
			var h1 := float(pc[1])
			# a árvore inteira vira tora: de 2 em 2 metros até o topo (o que sobrar curto fica)
			var L := piece_len(p)
			if (h1 - h0) * s < L + 0.25:
				continue          # já está do tamanho de uma tora (ou é a sobra)
			var off: Vector3 = along * float(pc[2])
			var A: Vector3 = xf * _axis_of(m, h0) + off
			var B: Vector3 = xf * _axis_of(m, h1) + off
			var ab := Vector2(B.x - A.x, B.z - A.z)
			var t := clampf(Vector2(pos.x - A.x, pos.z - A.z).dot(ab) / ab.length_squared(), 0.0, 1.0)
			# posição do corte: sempre num múltiplo do tamanho da tora, contado da base do tronco
			var start := (h0 - float(cut.h)) * s
			var end := (h1 - float(cut.h)) * s
			# corta uma tora por vez, do tamanho certo, a partir da ponta de baixo do pedaço
			var at_m := start + L
			if at_m > end + 0.001:
				continue
			var h_at := float(cut.h) + at_m / s
			if absf(h1 - float(m.H)) < 0.0001 and _branch_below(p, m, h_at + 0.3 / s):
				continue          # primeiro corta os galhos que estão nessa parte do tronco
			if buck is Array and absf(float(buck[0]) - h_at) * s < 0.6 and float(buck[0]) > h0 and float(buck[0]) < float(pc[1]):
				h_at = float(buck[0])          # continua o corte que já começou
			var P: Vector3 = xf * _axis_of(m, h_at) + off
			var d := Vector2(pos.x - P.x, pos.z - P.z).length()
			if d < bd:
				bd = d
				var r := _radius_of(m, h_at, 0.0) * s
				best = {"p": p, "h": h_at, "point": P + Vector3.UP * r, "axis": P, "along": along, "r": r}
	return best


## Pedaço de tronco caído mais perto para escolher onde cortar (qualquer pedaço com
## mais de 80 cm): {p, h0, h1, s, A (ponta de baixo), B (ponta de cima), along, cut_h}.
func log_piece_near(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for p in plants:
		if int(p[5]) != FALLEN or p.size() < 10 or not p[9] is Array or _falling.has(p):
			continue
		var m: Dictionary = _models[int(p[4]) % VARIANTS]
		var h := height_of(p, last_day)
		var s: float = h / float(m.height)
		var cut := _cut_from(p, p[9], s)
		var xf := _log_xf(p, h, s, cut)
		var along := (xf * _axis_of(m, float(m.H)) - xf * _axis_of(m, float(cut.h))).normalized()
		for pc in log_pieces(p):
			var h0 := float(pc[0])
			var h1 := float(pc[1])
			if (h1 - h0) * s < 0.8:
				continue
			var off: Vector3 = along * float(pc[2])
			var A: Vector3 = xf * _axis_of(m, h0) + off
			var B: Vector3 = xf * _axis_of(m, h1) + off
			var ab := Vector2(B.x - A.x, B.z - A.z)
			var t := clampf(Vector2(pos.x - A.x, pos.z - A.z).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var P := A.lerp(B, t)
			var d := Vector2(pos.x - P.x, pos.z - P.z).length()
			if d < bd:
				bd = d
				best = {"p": p, "h0": h0, "h1": h1, "s": s, "A": A, "B": B, "off": off, "along": along}
	return best


## O corte no ponto h (no modelo) do pedaço: {p, h, point, axis, along, r, galho}
func log_cut_at(info: Dictionary, h_at: float) -> Dictionary:
	var p: Array = info.p
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var s := float(info.s)
	var h := height_of(p, last_day)
	var cut := _cut_from(p, p[9], s)
	var xf := _log_xf(p, h, s, cut)
	var P: Vector3 = xf * _axis_of(m, h_at) + (info.off as Vector3)
	var r := _radius_of(m, h_at, 0.0) * s
	var galho := absf(float(info.h1) - float(m.H)) < 0.0001 and _branch_below(p, m, h_at + 0.3 / s)
	return {"p": p, "h": h_at, "point": P + Vector3.UP * r, "axis": P, "along": info.along, "r": r, "galho": galho}


## Ainda tem galho (mais que o toquinho) preso no tronco abaixo da altura h (no modelo)?
func _branch_below(p: Array, m: Dictionary, h: float) -> bool:
	for bi in m.binfo.size():
		if int(branch_state(p, bi)[0]) < 3 and (m.binfo[bi].a as Vector3).y < h:
			return true
	return false


## Uma machadada na tora. Quando termina, a tora se parte em dois pedaços.
func buck_hit(p: Array, h_at: float) -> bool:
	if p.size() < 12:
		p.resize(12)
	var buck = p[11]
	if not buck is Array or absf(float(buck[0]) - h_at) > 0.0001:
		buck = [h_at, 0]
	buck[1] = int(buck[1]) + 1
	p[11] = buck
	var done := int(buck[1]) >= buck_hits_needed(p, h_at)
	if done:
		var pieces: Array = log_pieces(p).duplicate(true)
		for i in pieces.size():
			var pc: Array = pieces[i]
			if h_at > float(pc[0]) and h_at < float(pc[1]):
				var upper := [h_at, float(pc[1]), float(pc[2]) + 0.14]
				pc[1] = h_at
				pieces.insert(i + 1, upper)
				# os pedaços de cima se afastam um pouquinho
				for j in range(i + 2, pieces.size()):
					pieces[j][2] = float(pieces[j][2]) + 0.14
				break
		p[10] = pieces
		p[11] = null
		_release_pieces(p)
	_rebuild_logs()
	return done


## Os pedaços de tora já cortados (todos menos o da copa) se soltam da árvore: caem no
## chão e, no morro, rolam até onde não tem mais inclinação.
func _release_pieces(p: Array) -> void:
	var v := int(p[4]) % VARIANTS
	var m: Dictionary = _models[v]
	var h := height_of(p, last_day)
	var s: float = h / float(m.height)
	var cut := _cut_from(p, p[9], s)
	var xf := _log_xf(p, h, s, cut)
	var along := (xf * _axis_of(m, float(m.H)) - xf * _axis_of(m, float(cut.h))).normalized()
	var a_up := _log_up_angle(xf)
	var keep := []
	for pc in log_pieces(p):
		if absf(float(pc[1]) - float(m.H)) < 0.0001:
			keep.append(pc)
			continue
		var off: Vector3 = along * float(pc[2])
		var A: Vector3 = xf * _axis_of(m, float(pc[0])) + off
		var B: Vector3 = xf * _axis_of(m, float(pc[1])) + off
		var bot: Dictionary = cut if absf(float(pc[0]) - float(cut.h)) < 0.0001 else _buck_end(p, a_up, float(pc[0]), 1.0)
		var fl := {"v": v, "s": s, "h0": float(pc[0]), "h1": float(pc[1]), "bot": bot,
			"top": _buck_end(p, a_up, float(pc[1]), -1.0), "pos": [0, 0, 0], "yaw": 0.0, "dia": int(p[6])}
		var d := B - A
		var c := (A + B) * 0.5
		fl.pos = [c.x, c.y, c.z]
		fl.yaw = atan2(-d.z, d.x)
		roll_log(fl, Transform3D(Basis(Quaternion(Vector3.RIGHT, d.normalized())), c))
	p[10] = keep


## Onde a tora para no chão: rola de lado (perpendicular ao comprimento) morro abaixo
## enquanto o chão for inclinado. Devolve [centro final, quanto rolou (m)].
func _settle(fl: Dictionary) -> Array:
	var c := Vector2(float(fl.pos[0]), float(fl.pos[2]))
	if fl.has("sec"):
		return [c, 0.0]          # pedaço rachado: deita na face reta e não rola
	var dir := Vector2(cos(float(fl.yaw)), -sin(float(fl.yaw)))
	var n := Vector2(-dir.y, dir.x)
	var L := free_log_length(fl)
	var dist := 0.0
	for _it in 220:
		var hp := 0.0
		var hm := 0.0
		for t in [-0.35, 0.0, 0.35]:
			var q: Vector2 = c + dir * L * t
			hp += _jogo.height_at(q.x + n.x * 0.4, q.y + n.y * 0.4)
			hm += _jogo.height_at(q.x - n.x * 0.4, q.y - n.y * 0.4)
		var slope := (hp - hm) / 3.0 / 0.8
		if absf(slope) < 0.14:
			break          # plano o bastante: para
		var step := n * (-signf(slope)) * 0.15
		var nc := c + step
		if nc.x < 2.0 or nc.y < 2.0 or nc.x > MundoSim.W * _jogo.CELL - 2.0 or nc.y > MundoSim.H * _jogo.CELL - 2.0:
			break
		c = nc
		dist += 0.15
	return [c, dist]


## Põe a tora solta no chão a partir de onde ela estava (start, no mundo): ela cai,
## rola morro abaixo se for o caso, e só então fica parada como tora solta.
func roll_log(fl: Dictionary, start: Transform3D) -> void:
	var res := _settle(fl)
	var c: Vector2 = res[0]
	var dist: float = res[1]
	var r := free_log_radius(fl)
	var L := free_log_length(fl)
	var dir := Vector3(cos(float(fl.yaw)), 0, -sin(float(fl.yaw)))
	var e1 := Vector3(c.x, 0, c.y) - dir * L * 0.5
	var e2 := Vector3(c.x, 0, c.y) + dir * L * 0.5
	e1.y = _jogo.height_at(e1.x, e1.z) + r * 0.9
	e2.y = _jogo.height_at(e2.x, e2.z) + r * 0.9
	var d := (e2 - e1).normalized()
	var mid := (e1 + e2) * 0.5
	fl.pos = [mid.x, mid.y, mid.z]
	var n := free_log_node(fl)
	add_child(n)
	n.transform = start
	# primeiro cai no chão onde está, depois rola
	var p0 := Vector3(float(start.origin.x), 0, float(start.origin.z))
	p0.y = _jogo.height_at(p0.x, p0.z) + r * 0.9
	var b0 := Basis(Quaternion(Vector3.RIGHT, d))
	var fall_t := clampf(sqrt(maxf(start.origin.y - p0.y, 0.05) / 4.9), 0.12, 0.6)
	var roll_t := dist / 2.2
	var ang := dist / maxf(r, 0.05)
	var rdir := signf(Vector3(mid.x - p0.x, 0, mid.z - p0.z).dot(Vector3(-d.z, 0, d.x)))
	var tw := n.create_tween()
	tw.tween_method(func(t: float) -> void:
		n.transform = start.interpolate_with(Transform3D(b0, p0), t * t), 0.0, 1.0, fall_t)
	tw.tween_callback(func(): Sons.play_at(self, "baque", p0, clampf(-10.0 + r * 20.0, -10.0, 0.0), 0.9))
	if roll_t > 0.05:
		tw.tween_method(func(t: float) -> void:
			var pos := p0.lerp(mid, t)
			pos.y = _jogo.height_at(pos.x, pos.z) + r * 0.9
			n.transform = Transform3D(Basis(d, -ang * t * rdir) * b0, pos), 0.0, 1.0, roll_t).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		n.queue_free()
		free_logs.append(fl)
		_rebuild_logs())


func _rebuild_logs() -> void:
	_log_segs.clear()
	for n in _free_nodes:
		if is_instance_valid(n):
			n.free()
	_free_nodes.clear()
	for fl in free_logs:
		_place_free_node(fl)
	for k in _log_nodes:
		if is_instance_valid(_log_nodes[k]):
			_log_nodes[k].free()
	_log_nodes.clear()
	for p in plants:
		if int(p[5]) == FALLEN and p.size() > 9 and p[9] is Array and not _falling.has(p):
			var v := int(p[4]) % VARIANTS
			var s: float = height_of(p, last_day) / float(_models[v].height)
			_build_log(p, v, s, last_day)
	if fall_done_hook.is_valid():
		fall_done_hook.call()     # o cipó agarrado nas toras acompanha


## Dados do corte guardados na árvore derrubada ([machadadas, lado]).
func _cut_from(p: Array, c: Array, s: float) -> Dictionary:
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var rot := fmod(float(p[0]) * 12.9898 + float(p[1]) * 78.233, TAU)
	var A := float(c[1])
	var local := Basis(Vector3.UP, rot).inverse() * Vector3(sin(A), 0, cos(A))
	return {"h": CUT_H / s, "ac": atan2(local.z, local.x), "depth": 0.74,
		"up": 0.26 / s, "down": 0.05 / s, "open": 1.4,
		"seed": absi(hash(Vector2(float(p[0]), float(p[1])))) % 100000, "s": s}


## Como o tronco caído fica deitado: em cima do chão (não afundado) e acompanhando
## o morro. Devolve [base, eixo do tombo, ângulo].
func _rest_pose(p: Array, h: float) -> Array:
	var x := float(p[0])
	var z := float(p[1])
	var ang := float(p[7])
	var away := Vector3(sin(ang), 0, cos(ang))
	var axis := Vector3.UP.cross(away).normalized()
	var hb: float = _jogo.height_at(x, z)
	var length := maxf(h * 0.45, 0.5)
	var ht: float = _jogo.height_at(x + away.x * length, z + away.z * length)
	var a := clampf(PI * 0.5 - atan2(ht - hb, length), PI * 0.5 - 0.6, PI * 0.5 + 0.35)
	var r := trunk_radius(p) * 1.15
	return [Vector3(x, hb + r * 0.85, z), axis, a]


## Árvore que o jogador derrubou ainda verde: fica deitada com a copa; as folhas
## amarelam, ficam marrons e vão caindo ao longo de umas semanas (depois vira só o tronco).
func _build_fallen_green(p: Array, v: int, s: float, day: int) -> void:
	var m: Dictionary = _models[v]
	var x := float(p[0])
	var z := float(p[1])
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	var rest := _rest_pose(p, height_of(p, day))
	var root := Node3D.new()
	root.position = rest[0]
	root.basis = Basis(rest[1], rest[2]) * Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
	add_child(root)
	_instances.append(root)
	var age := float(day - int(p[6])) / GREEN_FALLEN_DAYS
	_piece(root, m.core, _bark)
	for b in m.branches:
		_piece(root, b, _bark)
	var yellow := Color(0.62, 0.5, 0.12)
	var brown := Color(0.48, 0.3, 0.13)
	var color := yellow.lerp(brown, clampf((age - 0.35) / 0.4, 0.0, 1.0))
	color.a = clampf(age / 0.35, 0.0, 1.0)
	for i in m.clusters.size():
		if age < _hash_range(p, 0.45, 1.0, 140 + i):
			var mi := _piece(root, m.clusters[i], _leaves)
			mi.set_instance_shader_parameter("tint", color)


## Árvore morrendo ou seca: monta peça por peça conforme a fase.
func _build_dying(p: Array, v: int, xf: Transform3D, s: float, day: int, core_mesh: ArrayMesh = null) -> Node3D:
	var m: Dictionary = _models[v]
	var ph := phase_of(p, day)
	var leaf: float = ph.leaf
	var decay: float = ph.decay
	var root := Node3D.new()
	root.transform = xf
	add_child(root)
	_instances.append(root)
	var bark_m: Material = _bark if leaf < 0.6 else _bark_dead
	if core_mesh:
		_trunk_node(root, core_mesh, bark_m)
	else:
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
	return root


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


## Árvore em pé mais perto do jogador, ao alcance do machado (ou null).
func nearest_standing(pos: Vector3, reach: float) -> Variant:
	var best = null
	var bd := 1e9
	var day := last_day
	for p in plants:
		if int(p[5]) == FALLEN or int(p[5]) == -1:
			continue
		var h := height_of(p, day)
		if h < 0.6:
			continue
		var r := TRUNK_HIT * h / float(_models[int(p[4]) % VARIANTS].height) + 0.3
		var d := Vector2(float(p[0]) - pos.x, float(p[1]) - pos.z).length() - r
		if d < reach and d < bd:
			bd = d
			best = p
	return best


## Ponto (no mundo) na casca de uma árvore em pé, a y metros do chão e no ângulo ang
## (usado pelos cipós que sobem no tronco). "out" afasta da casca.
func trunk_point(p: Array, y: float, ang: float, out := 0.0) -> Vector3:
	var v := int(p[4]) % VARIANTS
	var m: Dictionary = _models[v]
	var h := height_of(p, last_day)
	var s: float = h / float(m.height)
	var x := float(p[0])
	var z := float(p[1])
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	var hm := y / maxf(s, 0.01)
	var r := _radius_of(m, hm, ang)
	var local := _axis_of(m, hm) + Vector3(cos(ang), 0, sin(ang)) * r
	var w := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, _jogo.height_at(x, z) - 0.15, z)) * local
	var c := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, _jogo.height_at(x, z) - 0.15, z)) * _axis_of(m, hm)
	var d := (w - c)
	d.y = 0.0
	return w + (d.normalized() * out if d.length() > 0.0001 else Vector3.ZERO)


## Transformação do modelo da árvore para o mundo, com ela em pé.
func stand_xf(p: Array) -> Transform3D:
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var s: float = height_of(p, last_day) / float(m.height)
	var x := float(p[0])
	var z := float(p[1])
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	return Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, _jogo.height_at(x, z) - 0.15, z))


## Pedaços da tora derrubada: [de (m do chão, em pé), até, transformação modelo->mundo].
func log_piece_xfs(p: Array) -> Array:
	var out := []
	if p.size() < 10 or not p[9] is Array:
		return out
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var h := height_of(p, last_day)
	var s: float = h / float(m.height)
	var cut := _cut_from(p, p[9], s)
	var xf := _log_xf(p, h, s, cut)
	var along := (xf * _axis_of(m, float(m.H)) - xf * _axis_of(m, float(cut.h))).normalized()
	for pc in log_pieces(p):
		out.append([float(pc[0]) * s, float(pc[1]) * s, Transform3D(xf.basis, xf.origin + along * float(pc[2]))])
	return out


## Árvore em pé (viva ou secando) por posição, para o cipó saber onde está apoiado.
func standing_at(x: float, z: float) -> Variant:
	for p in plants:
		if absf(float(p[0]) - x) < 0.01 and absf(float(p[1]) - z) < 0.01:
			return p if int(p[5]) != FALLEN else null
	return null


## Raio (m) do tronco na altura do corte (1 m do chão), do jeito que ele é desenhado.
func trunk_radius(p: Array) -> float:
	var h := height_of(p, last_day)
	if int(p[5]) == ALIVE and h < SAPLING_MAX_H:
		return 0.03 * h
	var m: Dictionary = _models[int(p[4]) % VARIANTS]
	var s: float = h / float(m.height)
	var hm := CUT_H / maxf(s, 0.01)          # 1 m do chão no tamanho do modelo
	var taper := lerpf(float(m.r0), float(m.r0) * 0.42, clampf(hm / float(m.H), 0.0, 1.0))
	return s * taper * (1.0 + 0.55 * exp(-hm * 1.4))


# ================== CORTE (MARCA DO MACHADO) ==================

func _cut_key(p: Array) -> Vector2:
	return Vector2(snappedf(float(p[0]), 0.01), snappedf(float(p[1]), 0.01))


func cut_hits(p: Array) -> int:
	return int(cuts.get(_cut_key(p), [0, 0.0])[0])


## Uma machadada: aprofunda o corte do lado de onde o jogador está batendo.
func add_cut(p: Array, from: Vector3) -> int:
	var k := _cut_key(p)
	var first := not cuts.has(k)
	var c: Array = cuts.get(k, [0, atan2(from.x, from.z)])
	c[0] = int(c[0]) + 1
	cuts[k] = c
	if first:
		_rebuild()          # sai do desenho em grupo e passa a ser desenhada sozinha
	else:
		_rebuild_cut(p)
	return int(c[0])


## Ponto (no mundo) onde a lâmina entra no tronco.
func cut_point(p: Array) -> Vector3:
	var c: Array = cuts.get(_cut_key(p), [0, 0.0])
	var a := float(c[1])
	var info := _cut_info(p)
	var r := trunk_radius(p) * (1.0 - float(info.get("depth", 0.0)) * 0.8)
	var x := float(p[0]) + sin(a) * r
	var z := float(p[1]) + cos(a) * r
	return Vector3(x, _jogo.height_at(float(p[0]), float(p[1])) + CUT_H, z)


## Quantas machadadas para derrubar: muda sai com 2, árvore grande pede umas 14.
func hits_to_fell(p: Array) -> int:
	if bool(_jogo.teste):
		return 1
	return clampi(int(round(2.0 + height_of(p, last_day) * 0.55)), 2, 16)


## A árvore cortada tomba para o lado contrário de quem cortou: começa devagar,
## vai acelerando, bate no chão e quica um pouco. Depois vira tronco caído.
## Não dá madeira na hora: o tronco fica no chão.
func fell_by_player(p: Array, away: Vector3) -> void:
	var day := last_day
	var h := height_of(p, day)
	var v := int(p[4]) % VARIANTS
	var m: Dictionary = _models[v]
	var s: float = h / float(m.height)
	var x := float(p[0])
	var z := float(p[1])
	var y: float = _jogo.height_at(x, z) - 0.15
	var rot := fmod(x * 12.9898 + z * 78.233, TAU)
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var alive := _alive_now(p, day)
	var small := alive and h < SAPLING_MAX_H
	var c: Array = cuts.get(_cut_key(p), [1, atan2(-away.x, -away.z)])
	if p.size() < 10:
		p.resize(10)
	p[8] = 1 if alive and not small else 0   # caiu verde: as folhas secam aos poucos no chão
	p[5] = FALLEN
	p[6] = day
	p[7] = atan2(away.x, away.z)
	var cut := {}
	if not small:
		p[9] = [int(c[0]), float(c[1])]
		cut = _cut_from(p, p[9], s)
		# fica o toco: a parte de baixo do tronco, do chão até o corte
		stumps.append([x, z, day, v, s, cut])
	cuts.erase(_cut_key(p))
	_falling.append(p)
	_rebuild()
	# a parte de cima tomba girando em volta do corte
	var pivot := Node3D.new()
	add_child(pivot)
	var tree := Node3D.new()
	pivot.add_child(tree)
	var hinge0: Vector3
	if small:
		tree.basis = Basis(Vector3.UP, rot).scaled(Vector3(h, h, h))
		_piece(tree, _sapling[0], _bark)
		_piece(tree, _sapling[1], _leaves)
		hinge0 = Vector3(x, y + 0.1, z)
	else:
		var bt := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
		var cut_pt := _axis_of(m, float(cut.h))
		tree.basis = bt
		tree.position = -(bt * cut_pt)
		hinge0 = Vector3(x, y, z) + bt * cut_pt
		_trunk_node(tree, _trunk_build(m, float(cut.h), float(m.H), [cut], s, {}, cut), _bark if alive else _bark_dead)
		for b in m.branches:
			_piece(tree, b, _bark if alive else _bark_dead)
		if alive:
			_piece(tree, m.crown, _leaves)
		# o cipó que subia nela cai junto, agarrado no tronco
		if fell_hook.is_valid():
			fell_hook.call(p, tree)
	pivot.position = hinge0
	var rest := _rest_pose(p, h)
	var axis: Vector3 = rest[1]
	var a_end: float = rest[2]
	var hinge1: Vector3 = hinge0
	if not small:
		var lx := _log_xf(p, h, s, cut)
		hinge1 = lx * _axis_of(m, float(cut.h))
	else:
		hinge1 = rest[0]
	var tw := pivot.create_tween()
	var fall := func(a: float) -> void:
		pivot.basis = Basis(axis, a)
		# no começo gira em cima do toco; perto do fim escorrega do toco para o chão
		pivot.position = hinge0.lerp(hinge1, smoothstep(0.55, 1.0, clampf(a / a_end, 0.0, 1.0)))
	var dur := clampf(1.2 + h * 0.09, 1.2, 3.2)
	# a madeira estala e range quando começa a tombar; no fim, o baque no chão
	Sons.play_at(self, "estalo", hinge0, 2.0)
	tw.tween_method(fall, 0.02, a_end, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		var mid := hinge1 + Vector3(sin(float(p[7])), 0, cos(float(p[7]))) * h * 0.4
		Sons.play_at(self, "queda", mid, clampf(-6.0 + h * 0.5, -6.0, 6.0), clampf(1.3 - h * 0.025, 0.8, 1.2)))
	tw.tween_method(fall, a_end, a_end - 0.08, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(fall, a_end - 0.08, a_end, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		_falling.erase(p)
		pivot.queue_free()
		_rebuild()
		if fall_done_hook.is_valid():
			fall_done_hook.call())


# ================== TRONCO SOB MEDIDA (corte, toco e tora) ==================

## Eixo do tronco do modelo (igual ao usado para gerar a árvore).
static func _axis_of(m: Dictionary, h: float) -> Vector3:
	var H := float(m.H)
	var lean: Vector2 = m.lean
	var t := h / H
	return Vector3(lean.x * t * t + sin(h * 0.21) * 0.08, h, lean.y * t * t + cos(h * 0.17) * 0.08)


static func _radius_of(m: Dictionary, h: float, a: float) -> float:
	var H := float(m.H)
	var r0 := float(m.r0)
	var taper := lerpf(r0, r0 * 0.42, clampf(h / H, 0.0, 1.0))
	var flare := 1.0 + 0.55 * exp(-h * 1.4)
	var fin := pow(maxf(0.0, cos(a * 5 + float(m.fin_phase))), 8.0) * maxf(0.0, 1.0 - h / 1.8) * 1.1
	return taper * flare + fin


## Quanto a madeira já foi tirada (0 a 1 do raio) num ponto do tronco, pela boca do corte.
static func _notch_at(cut: Dictionary, h: float, a: float) -> float:
	if cut.is_empty() or float(cut.depth) <= 0.0:
		return 0.0
	var da := absf(wrapf(a - float(cut.ac), -PI, PI))
	var side := 1.0 - smoothstep(float(cut.open) * 0.55, float(cut.open), da)
	if side <= 0.0:
		return 0.0
	var dh := h - float(cut.h)
	var prof := 0.0
	if dh >= 0.0:
		prof = 1.0 - dh / float(cut.up)           # face de cima: inclinada
	else:
		prof = 1.0 - (-dh) / float(cut.down)      # face de baixo: quase reta
	if prof <= 0.0:
		return 0.0
	# machado de pedra: o corte sai torto e lascado
	var hsh := absi(hash(Vector3i(int(cut.seed), int(a * 9.0), int(h * 40.0))))
	var rough := 1.0 + ((hsh % 1000) / 1000.0 - 0.5) * 0.35
	return clampf(float(cut.depth) * prof * side * rough, 0.0, 0.97)


## Altura (no modelo) da ponta quebrada do corte em cada ângulo: do lado da boca
## o corte é mais baixo e liso; do outro lado a madeira rachou e ficou com lascas.
static func _break_at(cut: Dictionary, a: float, s: float) -> float:
	var da := absf(wrapf(a - float(cut.ac), -PI, PI))
	var hinge := smoothstep(0.6, PI, da)          # 0 na boca, 1 do lado oposto
	var hsh := absi(hash(Vector2i(int(cut.seed), int(round(a * 40.0)))))
	var spike := (hsh % 1000) / 1000.0
	var amount := float(cut.get("rough", 1.0))
	return (hinge * 0.07 + spike * spike * 0.08 * (0.3 + hinge)) * amount * float(cut.get("sign", 1.0)) / s


## Monta um pedaço do tronco do modelo, de h0 até h1 (alturas do modelo), com a boca
## do corte escavada e, se pedir, a ponta de cima/de baixo quebrada no corte.
## Duas superfícies: 0 = casca (usa a textura), 1 = madeira (cor nos vértices).
func _trunk_build(m: Dictionary, h0: float, h1: float, notches: Array, s: float, top_break := {}, bottom_break := {}, wood_tint := Color(1, 1, 1)) -> ArrayMesh:
	var broken_top := not top_break.is_empty()
	var broken_bottom := not bottom_break.is_empty()
	var SEG := 26
	var hs: Array = []
	var RINGS := 22
	var H := float(m.H)
	for ri in RINGS + 1:
		var hh := H * pow(float(ri) / RINGS, 1.35)
		if hh > h0 + 0.001 and hh < h1 - 0.001:
			hs.append(hh)
	for cut in notches:
		var lo := float(cut.h) - float(cut.down) * 1.3
		var hi := float(cut.h) + float(cut.up) * 1.2
		for k in 13:
			var hh := lerpf(lo, hi, k / 12.0)
			if hh > h0 + 0.001 and hh < h1 - 0.001:
				hs.append(hh)
	hs.append(h0)
	hs.append(h1)
	hs.sort()
	var rings: Array = []
	for hh in hs:
		var ring := []
		for si in SEG + 1:
			var a := TAU * si / SEG
			var y: float = hh
			if broken_top and absf(hh - h1) < 0.0001:
				y = h1 + _break_at(top_break, a, s)
			elif broken_bottom and absf(hh - h0) < 0.0001:
				y = h0 + _break_at(bottom_break, a, s)
			var c := _axis_of(m, y)
			var cut_frac := 0.0
			for cut in notches:
				cut_frac = maxf(cut_frac, _notch_at(cut, y, a))
			var r := _radius_of(m, y, a) * (1.0 - cut_frac)
			ring.append([c + Vector3(cos(a) * r, 0, sin(a) * r), Vector2(float(si) / SEG * 2.0, y / 3.0), cut_frac, c])
		rings.append(ring)
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light := Color(0.55, 0.41, 0.25) * wood_tint
	var heart := Color(0.4, 0.27, 0.15) * wood_tint
	var any_wood := false
	for ri in rings.size() - 1:
		for si in SEG:
			var q := [rings[ri][si], rings[ri][si + 1], rings[ri + 1][si], rings[ri][si + 1], rings[ri + 1][si + 1], rings[ri + 1][si]]
			var deep := maxf(maxf(q[0][2], q[1][2]), maxf(q[2][2], q[5][2]))
			if deep > 0.06:
				any_wood = true
				for v in q:
					var col := light.lerp(heart, clampf(float(v[2]) * 1.3, 0.0, 1.0))
					col.a = 1.0
					wood.set_color(col)
					wood.add_vertex(v[0])
			else:
				for v in q:
					var out: Vector3 = (v[0] - v[3])
					out.y = 0.0
					bark.set_normal(out.normalized() if out.length() > 0.0001 else Vector3.RIGHT)
					bark.set_uv(v[1])
					bark.add_vertex(v[0])
	# pontas: madeira com os anéis (a de baixo do tronco inteiro fica enterrada)
	for end in [[h1, true, broken_top], [h0, false, broken_bottom]]:
		var hh: float = end[0]
		if not end[1] and h0 <= 0.001:
			continue
		var ring: Array = rings[rings.size() - 1] if end[1] else rings[0]
		var center: Vector3 = _axis_of(m, hh + (0.03 / s if end[2] else 0.0))
		any_wood = true
		for si in SEG:
			var a0: Vector3 = ring[si][0]
			var a1: Vector3 = ring[si + 1][0]
			for k in 3:
				var f0 := k / 3.0
				var f1 := (k + 1) / 3.0
				var col := light.lerp(heart, 0.5 - k * 0.15) if k < 2 else light
				if end[2]:
					col = col.darkened(0.08 * (si % 3))   # lascas
				col.a = 1.0
				wood.set_color(col)
				var p00 := center.lerp(a0, f0)
				var p01 := center.lerp(a0, f1)
				var p10 := center.lerp(a1, f0)
				var p11 := center.lerp(a1, f1)
				if end[1]:
					for v in [p00, p11, p01, p00, p10, p11]:
						wood.add_vertex(v)
				else:
					for v in [p00, p01, p11, p00, p11, p10]:
						wood.add_vertex(v)
	bark.index()
	var mesh := bark.commit()
	if any_wood:
		wood.generate_normals()
		mesh = wood.commit(mesh)
	return mesh


## Material de casca (usado também nas forquilhas e nos galhos do chão).
func bark_material() -> Material:
	if _bark_2s == null:
		_bark_2s = (_bark as StandardMaterial3D).duplicate()
		_bark_2s.cull_mode = BaseMaterial3D.CULL_DISABLED     # galho cortado: visível de todo lado
	return _bark_2s


func leaf_material() -> Material:
	return _leaves


func _trunk_node(parent: Node3D, mesh: ArrayMesh, bark_mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = VIEW_DIST
	mi.set_surface_override_material(0, bark_mat)
	if mesh.get_surface_count() > 1:
		mi.set_surface_override_material(1, _stump_top_mat)
	parent.add_child(mi)
	return mi


## Dados do corte de uma árvore no espaço do modelo (para escavar o tronco).
func _cut_info(p: Array) -> Dictionary:
	var c: Array = cuts.get(_cut_key(p), [])
	if c.is_empty():
		var st_ = p[9] if p.size() > 9 else null
		if st_ is Array:
			c = st_
		else:
			return {}
	var v := int(p[4]) % VARIANTS
	var m: Dictionary = _models[v]
	var h := height_of(p, last_day)
	var s: float = h / float(m.height)
	var rot := fmod(float(p[0]) * 12.9898 + float(p[1]) * 78.233, TAU)
	var A := float(c[1])
	var local := Basis(Vector3.UP, rot).inverse() * Vector3(sin(A), 0, cos(A))
	var prog := clampf(float(c[0]) / hits_to_fell(p), 0.0, 1.0)
	return {"h": CUT_H / s, "ac": atan2(local.z, local.x), "depth": 0.12 + 0.62 * prog,
		"up": (0.1 + 0.16 * prog) / s, "down": 0.05 / s, "open": 0.85 + 0.55 * prog,
		"seed": absi(hash(Vector2(float(p[0]), float(p[1])))) % 100000, "s": s}


# ================== TORAS SOLTAS (pegar, carregar e largar) ==================

const WOOD_DENSITY := 520.0     # kg por m³ (madeira de Cedrinho ainda verde, mais leve)
const CARRY_MAX_KG := 60.0      # o máximo que uma pessoa carrega no ombro

## Tora solta: {v, s, h0, h1, bot, top (pontas), pos [x, y, z] (centro), yaw, dia}.
## O desenho usa o tronco do modelo de h0 a h1 (no tamanho s), deitado ao longo de +X.
func free_log_node(fl: Dictionary) -> Node3D:
	if fl.has("cil"):
		return _piece_node(fl)
	var v := int(fl.v) % VARIANTS
	var m: Dictionary = _models[v]
	var s := float(fl.s)
	var h0 := float(fl.h0)
	var h1 := float(fl.h1)
	var a := _axis_of(m, h0)
	var b := _axis_of(m, h1)
	var mid := (a + b) * 0.5
	var bas := Basis(Quaternion((b - a).normalized(), Vector3.RIGHT)).scaled(Vector3(s, s, s))
	var root := Node3D.new()
	var holder := Node3D.new()
	holder.transform = Transform3D(bas, -(bas * mid))
	root.add_child(holder)
	var age := float(last_day - int(fl.get("dia", last_day)))
	var bot: Dictionary = fl.get("bot", {})
	var top: Dictionary = fl.get("top", {})
	# entalhe da rodela sendo cortada na ponta (o machado bate de cima)
	var notches := []
	var en: Dictionary = fl.get("entalhe", {})
	if not en.is_empty():
		var e := int(en.e)
		var prog := clampf(float(en.hits) / maxf(float(en.need), 1.0), 0.0, 1.0)
		var hc := h1 - SLICE_M / s if e > 0 else h0 + SLICE_M / s
		var upm: Vector3 = Basis(Quaternion((b - a).normalized(), Vector3.RIGHT)).inverse() * Vector3.UP
		if bool(en.get("serra", false)):
			# serra: um rasgo fino descendo de cima (os dentes de pedra deixam ele irregular)
			var k := 0.006 / s
			notches.append({"h": hc, "ac": atan2(upm.z, upm.x), "depth": 0.08 + 0.85 * prog,
				"up": k, "down": k, "open": 1.4 + 0.8 * prog, "seed": int(en.hits) * 31 + 7, "s": s})
		else:
			var flat := 0.012 / s                       # lado da rodela: face reta
			var bevel := (0.03 + 0.05 * prog) / s       # lado da tora: inclinado
			notches.append({"h": hc, "ac": atan2(upm.z, upm.x), "depth": 0.18 + 0.7 * prog,
				"up": flat if e > 0 else bevel, "down": bevel if e > 0 else flat,
				"open": 0.9 + 0.9 * prog, "seed": int(en.hits) * 31 + 7, "s": s})
	_trunk_node(holder, _trunk_build(m, h0, h1, notches, s, top, bot), _bark if age < 200 else _bark_dead)
	return root


const SLICE_M := 0.05   # grossura da rodela (igual a Apoios.SLICE)


## Raio da tora solta no ponto u (0 = ponta h0, 1 = ponta h1), contando o
## alargamento do pé da árvore e as sapopemas.
func free_log_radius_at(fl: Dictionary, u: float) -> float:
	if fl.has("cil"):
		return _cil_r(fl, u) * _sec_ext(fl).x
	var m: Dictionary = _models[int(fl.v) % VARIANTS]
	var h := lerpf(float(fl.h0), float(fl.h1), clampf(u, 0.0, 1.0))
	var r := 0.0
	for k in 8:
		r = maxf(r, _radius_of(m, h, TAU * k / 8.0))
	return r * float(fl.s)


## Raio maior da tora (para a colisão).
func free_log_max_radius(fl: Dictionary) -> float:
	if fl.has("cil"):
		var e := _sec_ext(fl)
		return maxf(float(fl.cil.ra), float(fl.cil.rb)) * maxf(e.x, e.y)
	var r := 0.0
	for k in 9:
		r = maxf(r, free_log_radius_at(fl, k / 8.0))
	return r


## Formato da ponta da tora (raio em 24 ângulos, em cm redondos): a rodela sai assim.
func free_log_end_profile(fl: Dictionary, e: int) -> Array:
	if fl.has("cil"):
		var out2 := []
		for k in 24:
			out2.append(snappedf(_cil_r(fl, 1.0 if e > 0 else 0.0), 0.01))
		return out2
	var m: Dictionary = _models[int(fl.v) % VARIANTS]
	var h := float(fl.h1) if e > 0 else float(fl.h0)
	var out := []
	for k in 24:
		out.append(snappedf(_radius_of(m, h, TAU * k / 24.0) * float(fl.s), 0.01))
	return out


## Raio da tora solta numa das pontas (e = 1: ponta h1; -1: ponta h0).
func free_log_end_radius(fl: Dictionary, e: int) -> float:
	if fl.has("cil"):
		return _cil_r(fl, 1.0 if e > 0 else 0.0) * _sec_ext(fl).x
	var m: Dictionary = _models[int(fl.v) % VARIANTS]
	var h := float(fl.h1) if e > 0 else float(fl.h0)
	return _radius_of(m, h, 0.0) * float(fl.s)


## Tira um pedaço da ponta da tora (a rodela): fica mais curta, com a ponta
## nova cortada a machado.
func shorten_free_log(fl: Dictionary, e: int, length: float, rough := 0.25) -> void:
	if fl.has("cil"):
		# pedaço rachado: fica mais curto (o raio de cada ponta acompanha a tora de origem)
		var L := float(fl.cil.L)
		var f := clampf(length / L, 0.0, 0.95)
		if e > 0:
			fl.cil.rb = lerpf(float(fl.cil.ra), float(fl.cil.rb), 1.0 - f)
		else:
			fl.cil.ra = lerpf(float(fl.cil.ra), float(fl.cil.rb), f)
		fl.cil.L = L - length
		return
	var dh := length / float(fl.s)
	var cap := {"ac": PI, "seed": absi(hash(Vector3(float(fl.h0), float(fl.h1), float(e)))) % 100000,
		"rough": rough, "sign": -1.0 if e > 0 else 1.0}
	if e > 0:
		fl.h1 = float(fl.h1) - dh
		fl.top = cap
	else:
		fl.h0 = float(fl.h0) + dh
		fl.bot = cap


func free_log_length(fl: Dictionary) -> float:
	if fl.has("cil"):
		return float(fl.cil.L)
	var m: Dictionary = _models[int(fl.v) % VARIANTS]
	return (_axis_of(m, float(fl.h1)) - _axis_of(m, float(fl.h0))).length() * float(fl.s)


func free_log_radius(fl: Dictionary) -> float:
	if fl.has("cil"):
		return _cil_r(fl, 0.5) * _sec_ext(fl).x
	var m: Dictionary = _models[int(fl.v) % VARIANTS]
	return _radius_of(m, (float(fl.h0) + float(fl.h1)) * 0.5, 0.0) * float(fl.s)


func free_log_kg(fl: Dictionary) -> float:
	if fl.has("cil"):
		var rm := _cil_r(fl, 0.5)
		return _poly_area(fl.sec) * rm * rm * free_log_length(fl) * WOOD_DENSITY
	var r := free_log_radius(fl)
	return PI * r * r * free_log_length(fl) * WOOD_DENSITY


## Põe a tora deitada no chão: centro em pos, virada para yaw, acompanhando o morro.
## As pontas da tora solta como ela fica deitada (acompanhando o chão): [A, B] no eixo.
func free_axis(fl: Dictionary) -> Array:
	var x := float(fl.pos[0])
	var z := float(fl.pos[2])
	var L := free_log_length(fl)
	var r := free_log_radius(fl)
	var dir := Vector3(cos(float(fl.yaw)), 0, -sin(float(fl.yaw)))
	var e1 := Vector3(x, 0, z) - dir * L * 0.5
	var e2 := Vector3(x, 0, z) + dir * L * 0.5
	e1.y = _jogo.height_at(e1.x, e1.z) + r * 0.9
	e2.y = _jogo.height_at(e2.x, e2.z) + r * 0.9
	return [e1, e2]


func _place_free_node(fl: Dictionary) -> void:
	var n := free_log_node(fl)
	add_child(n)
	_free_nodes.append(n)
	var x := float(fl.pos[0])
	var z := float(fl.pos[2])
	var L := free_log_length(fl)
	var r := free_log_radius(fl)
	var dir := Vector3(cos(float(fl.yaw)), 0, -sin(float(fl.yaw)))
	var e1 := Vector3(x, 0, z) - dir * L * 0.5
	var e2 := Vector3(x, 0, z) + dir * L * 0.5
	e1.y = _jogo.height_at(e1.x, e1.z) + r * 0.9
	e2.y = _jogo.height_at(e2.x, e2.z) + r * 0.9
	var d := (e2 - e1).normalized()
	n.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, d)), (e1 + e2) * 0.5)
	_log_segs.append([e1, e2, r])


## Pedaço de tora mais perto que dá para pegar (não pega a parte da copa).
## Devolve {kind: "arvore" ou "solta", ...} ou {}.
func pick_target(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for i in free_logs.size():
		var fl: Dictionary = free_logs[i]
		var d := _seg_dist(pos, _free_ends(fl))
		if d < bd:
			bd = d
			best = {"kind": "solta", "i": i, "log": fl}
	for p in plants:
		if int(p[5]) != FALLEN or p.size() < 10 or not p[9] is Array or _falling.has(p):
			continue
		var v := int(p[4]) % VARIANTS
		var m: Dictionary = _models[v]
		var h := height_of(p, last_day)
		var s: float = h / float(m.height)
		var cut := _cut_from(p, p[9], s)
		var xf := _log_xf(p, h, s, cut)
		var along := (xf * _axis_of(m, float(m.H)) - xf * _axis_of(m, float(cut.h))).normalized()
		var a_up := _log_up_angle(xf)
		var pieces := log_pieces(p)
		for idx in pieces.size():
			var pc: Array = pieces[idx]
			if absf(float(pc[1]) - float(m.H)) < 0.0001 and has_branches(p):
				continue      # o pedaço com os galhos fica (corte os galhos antes)
			if (float(pc[1]) - float(pc[0])) * s < piece_len(p) * 0.75:
				continue      # sobra curta do topo: não serve de tora
			var off: Vector3 = along * float(pc[2])
			var A: Vector3 = xf * _axis_of(m, float(pc[0])) + off
			var B: Vector3 = xf * _axis_of(m, float(pc[1])) + off
			var d := _seg_dist(pos, [A, B])
			if d < bd:
				bd = d
				var bot: Dictionary = cut if absf(float(pc[0]) - float(cut.h)) < 0.0001 else _buck_end(p, a_up, float(pc[0]), 1.0)
				var fl := {"v": v, "s": s, "h0": float(pc[0]), "h1": float(pc[1]), "bot": bot,
					"top": _buck_end(p, a_up, float(pc[1]), -1.0), "pos": [0, 0, 0], "yaw": 0.0, "dia": int(p[6])}
				best = {"kind": "arvore", "p": p, "idx": idx, "log": fl, "center": (A + B) * 0.5}
	if not best.is_empty() and best.kind == "solta":
		var fl: Dictionary = best.log
		best["center"] = Vector3(float(fl.pos[0]), float(fl.pos[1]), float(fl.pos[2]))
	return best


func _free_ends(fl: Dictionary) -> Array:
	var dir := Vector3(cos(float(fl.yaw)), 0, -sin(float(fl.yaw)))
	var c := Vector3(float(fl.pos[0]), float(fl.pos[1]), float(fl.pos[2]))
	var L := free_log_length(fl)
	return [c - dir * L * 0.5, c + dir * L * 0.5]


## Tora solta no chão mais perto (para cortar de novo com o machado), ou -1.
func free_log_near(pos: Vector3, reach: float, min_len := 0.55) -> int:
	var best := -1
	var bd := reach
	for i in free_logs.size():
		var fl: Dictionary = free_logs[i]
		if free_log_length(fl) < min_len:
			continue
		var d := _seg_dist(pos, _free_ends(fl))
		if d < bd:
			bd = d
			best = i
	return best


## Parte a tora solta em duas no ponto u (0 = ponta de -x, 1 = ponta de +x): as duas
## ficam no mesmo lugar, a ponta nova de cada uma cortada a machado.
func split_free_log(fl: Dictionary, u: float) -> Array:
	var i := free_logs.find(fl)
	if i < 0:
		return []
	var L := free_log_length(fl)
	var ends := _free_ends(fl)
	var A: Vector3 = ends[0]
	var B: Vector3 = ends[1]
	var a: Dictionary = fl.duplicate(true)
	var b: Dictionary = fl.duplicate(true)
	for k in ["entalhe", "racha", "cupim", "veneno", "oleo", "em_pe", "corte_m"]:
		a.erase(k)
		b.erase(k)
	if fl.has("cil"):
		var rm := lerpf(float(fl.cil.ra), float(fl.cil.rb), u)
		a.cil = {"L": L * u, "ra": float(fl.cil.ra), "rb": rm}
		b.cil = {"L": L * (1.0 - u), "ra": rm, "rb": float(fl.cil.rb)}
	else:
		var hm := lerpf(float(fl.h0), float(fl.h1), u)
		var seed_ := absi(hash(Vector3(float(fl.h0), float(fl.h1), hm))) % 100000
		a.h1 = hm
		a.top = {"ac": PI, "seed": seed_, "rough": 0.45, "sign": -1.0}
		b.h0 = hm
		b.bot = {"ac": PI, "seed": seed_ + 1, "rough": 0.45, "sign": 1.0}
	var cut := A.lerp(B, u)
	var ca := (A + cut) * 0.5
	var cb := (cut + B) * 0.5
	a.pos = [ca.x, float(fl.pos[1]), ca.z]
	b.pos = [cb.x, float(fl.pos[1]), cb.z]
	free_logs.remove_at(i)
	free_logs.append(a)
	free_logs.append(b)
	_rebuild_logs()
	return [a, b]


static func _seg_dist(pos: Vector3, seg: Array) -> float:
	var A: Vector3 = seg[0]
	var B: Vector3 = seg[1]
	var ab := Vector2(B.x - A.x, B.z - A.z)
	var L2 := maxf(ab.length_squared(), 0.0001)
	var t := clampf(Vector2(pos.x - A.x, pos.z - A.z).dot(ab) / L2, 0.0, 1.0)
	var c := A.lerp(B, t)
	return Vector2(pos.x - c.x, pos.z - c.z).length()


## Tira o pedaço do mundo (o jogador pegou). Devolve a tora para ser carregada.
func take_log(target: Dictionary) -> Dictionary:
	var fl: Dictionary = target.log
	if target.kind == "solta":
		free_logs.remove_at(int(target.i))
	else:
		var p: Array = target.p
		var pieces: Array = log_pieces(p).duplicate(true)
		pieces.remove_at(int(target.idx))
		if p.size() < 11:
			p.resize(11)
		p[10] = pieces
	_rebuild_logs()
	return fl


## Larga a tora no chão.
func drop_log(fl: Dictionary, center: Vector3, yaw: float) -> void:
	fl.pos = [center.x, center.y, center.z]
	fl.yaw = yaw
	var d := Vector3(cos(yaw), 0, -sin(yaw))
	var c := center
	c.y = _jogo.height_at(c.x, c.z) + free_log_radius(fl) * 0.9
	roll_log(fl, Transform3D(Basis(Quaternion(Vector3.RIGHT, d)), c))


## Altura do topo de uma tora embaixo do jogador (para ficar em pé em cima dela), ou -1e9.
func support_y(x: float, z: float) -> float:
	var best := -1e9
	for sg in _log_segs + _nat_segs:
		var A: Vector3 = sg[0]
		var B: Vector3 = sg[1]
		var r: float = sg[2]
		var ab := Vector2(B.x - A.x, B.z - A.z)
		var L2 := ab.length_squared()
		if L2 < 0.0001:
			continue
		var t := clampf(Vector2(x - A.x, z - A.z).dot(ab) / L2, 0.0, 1.0)
		var c := A.lerp(B, t)
		var l := Vector2(x - c.x, z - c.z).length()
		if l < r * 0.95:
			best = maxf(best, c.y + sqrt(maxf(0.0, r * r - l * l)))
	return best


## O jogador não atravessa os troncos: empurra a posição para fora.
func push_out(p: Vector3, feet_y := -1e9) -> Vector3:
	# toras deitadas: só passa por cima pulando (ou andando em cima delas)
	for sg in _log_segs + _nat_segs:
		var A: Vector3 = sg[0]
		var B: Vector3 = sg[1]
		var r: float = sg[2]
		var ab := Vector2(B.x - A.x, B.z - A.z)
		var L2 := ab.length_squared()
		if L2 < 0.0001:
			continue
		var t := clampf(Vector2(p.x - A.x, p.z - A.z).dot(ab) / L2, 0.0, 1.0)
		var c := A.lerp(B, t)
		var d := Vector2(p.x - c.x, p.z - c.z)
		var l := d.length()
		var lim := r + 0.28
		if l < lim and feet_y < c.y + r - 0.2:
			var n := d / l if l > 0.001 else Vector2(-ab.y, ab.x).normalized()
			p.x = c.x + n.x * lim
			p.z = c.z + n.y * lim
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
	var cs := Shader.new()
	cs.code = CUT_SHADER
	var cm := ShaderMaterial.new()
	cm.shader = cs
	_cut_mat = cm
	var chm := StandardMaterial3D.new()
	chm.albedo_texture = _chips_texture()
	chm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	chm.alpha_scissor_threshold = 0.5
	chm.roughness = 0.95
	_chips_mat = chm
	var stm := StandardMaterial3D.new()
	stm.vertex_color_use_as_albedo = true
	stm.vertex_color_is_srgb = true
	stm.roughness = 0.9
	stm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stump_top_mat = stm
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
	# tronco caído inteiro (que caiu sozinho): sem esconder o lado de dentro nas pontas
	var lg: StandardMaterial3D = dead.duplicate()
	lg.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bark_log = lg

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


## Boca do corte do machado: a casca do tronco está por cima dela, então o desenho é
## puxado um pouco para a frente (na direção da câmera) e só aparece do lado do corte.
const CUT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying vec3 center;
varying vec3 dir;
varying float rad;
void vertex(){
	center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	dir = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	rad = UV.y;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz += normalize(-vp.xyz) * UV.x;
	POSITION = PROJECTION_MATRIX * vp;
}
void fragment(){
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - center;
	to_cam.y = 0.0;
	if (dot(normalize(to_cam), dir) < 0.15) discard;
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
// tint: rgb = cor para onde a folha vai (amarelo, marrom), a = quanto já mudou (0 = verde)
instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
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
## Lascas e serragem clara espalhadas no chão.
func _chips_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in 70:
		var c := Vector2(r.randf_range(4, 60), r.randf_range(4, 60))
		var dc := (c - Vector2(32, 32)).length() / 32.0
		if r.randf() < dc * 0.9:
			continue
		var col := Color(0.86, 0.72, 0.5).darkened(r.randf_range(0.0, 0.3))
		var w := r.randi_range(1, 4)
		var hh := r.randi_range(1, 2)
		for x in w:
			for y in hh:
				var px := int(c.x) + x
				var py := int(c.y) + y
				if px < 64 and py < 64:
					img.set_pixel(px, py, col)
	return ImageTexture.create_from_image(img)


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
			core.idx.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))

	# galhos (cada galho grosso junto com o galhinho que sai dele)
	var branches: Array = []
	var axes: Array = []
	var binfo: Array = []
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
		binfo.append({"a": start, "b": tip, "ra": r0 * 0.38, "rb": r0 * 0.12, "m": mid, "t2": tip2,
			"ra2": r0 * 0.16, "rb2": r0 * 0.06})
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
	model.clusters = []
	model.cluster_owner = []          # de qual galho é cada cacho de folhas (nb = topo)
	for ci in clusters.size():
		if (clusters[ci] as Piece).v.size() > 0:
			model.clusters.append(_mesh([clusters[ci]]))
			model.cluster_owner.append(ci)
	model.axes = axes
	model.binfo = binfo
	model.height = (model.crown as Mesh).get_aabb().end.y
	model.r0 = r0
	model.H = H
	model.lean = lean
	model.fin_phase = fin_phase
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
	# a face da frente tem que ficar para fora (senão a câmera vê o lado de dentro do galho)
	var j0 := base
	var j1 := base + SEG + 1
	var tri_n := (pc.v[j1] - pc.v[j0]).cross(pc.v[j0 + 1] - pc.v[j0])
	var outward := tri_n.dot(pc.n[j0]) > 0.0
	for ri in RINGS:
		for si in SEG:
			var i0 := base + ri * (SEG + 1) + si
			var i1 := i0 + SEG + 1
			if outward:
				pc.idx.append_array(PackedInt32Array([i0, i0 + 1, i1, i0 + 1, i1 + 1, i1]))
			else:
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



# ================== PEDAÇOS RACHADOS (cunha e marreta) ==================
# Tora rachada no comprido: um "cilindro" simples {L, ra, rb} (comprimento e raio nas
# pontas da tora de origem) com uma seção de corte "sec": polígono em unidades do raio
# (Vector2(z, y): de lado, para cima), cada ponto com o tipo da aresta que sai dele
# (0 = casca, 1 = madeira rachada). "ax" é onde ficava o eixo (o miolo) na seção.
# Deitado no chão a face mais larga fica embaixo; nas forquilhas fica "em pé"
# (em_pe: girado 90°), e a cunha racha de cima para baixo: corta a seção em y = 0.

static func circle_sec() -> Dictionary:
	var pts := []
	for k in 24:
		var a := TAU * k / 24.0
		pts.append([cos(a), sin(a), 0])
	return {"pts": pts, "ax": [0.0, 0.0]}


func _cil_r(fl: Dictionary, u: float) -> float:
	return lerpf(float(fl.cil.ra), float(fl.cil.rb), clampf(u, 0.0, 1.0))


## Meia altura e meia largura da seção (em unidades do raio), como está agora.
func _sec_ext(fl: Dictionary) -> Vector2:
	var hy := 0.0
	var hz := 0.0
	for p in fl.sec.pts:
		hz = maxf(hz, absf(float(p[0])))
		hy = maxf(hy, absf(float(p[1])))
	return Vector2(hz, hy) if bool(fl.get("em_pe", false)) else Vector2(hy, hz)


static func _poly_area(sec: Dictionary) -> float:
	var a := 0.0
	var pts: Array = sec.pts
	for k in pts.size():
		var p: Array = pts[k]
		var q: Array = pts[(k + 1) % pts.size()]
		a += float(p[0]) * float(q[1]) - float(q[0]) * float(p[1])
	return absf(a) * 0.5


## Racha a seção ao meio (linha y = 0 da posição em pé = no plano vertical da cunha).
## Devolve as duas seções, cada uma já deitada (face mais larga embaixo) e centrada.
static func split_sec(sec: Dictionary, em_pe: bool) -> Array:
	var pts := []
	for p in sec.pts:
		pts.append([float(p[0]), float(p[1]), int(p[2])])
	var out := []
	for keep in [1.0, -1.0]:
		var res := []        # [z, y, tipo da aresta que CHEGA no ponto]
		var n := pts.size()
		for k in n:
			var P: Array = pts[k]
			var Q: Array = pts[(k + 1) % n]
			var t := int(P[2])
			# em pé nas forquilhas o plano da cunha (vertical) é o y = 0 da seção
			# guardada (paralelo à face larga: sai tábua); a tora inteira racha em z = 0
			var vp: float = float(P[1]) if em_pe else float(P[0])
			var vq: float = float(Q[1]) if em_pe else float(Q[0])
			var inP: bool = vp * keep >= 0.0
			var inQ: bool = vq * keep >= 0.0
			if inP and inQ:
				res.append([Q[0], Q[1], t])
			elif inP != inQ:
				var f := vp / (vp - vq)
				var I := [lerpf(float(P[0]), float(Q[0]), f), lerpf(float(P[1]), float(Q[1]), f)]
				if inP:
					res.append([I[0], I[1], t])
				else:
					res.append([I[0], I[1], 1])
					res.append([Q[0], Q[1], t])
		if res.size() < 3:
			continue
		# tipo da aresta que SAI de cada ponto = o que chega no próximo
		var poly := []
		for k in res.size():
			poly.append([float(res[k][0]), float(res[k][1]), int(res[(k + 1) % res.size()][2])])
		out.append(_lay_flat(poly, sec.ax))
	return out


## Deita a seção na aresta mais comprida (embaixo, reta) e centra no meio da caixa.
static func _lay_flat(poly: Array, ax: Array) -> Dictionary:
	var best := 0
	var bl := -1.0
	for k in poly.size():
		var p: Array = poly[k]
		var q: Array = poly[(k + 1) % poly.size()]
		var l := Vector2(float(q[0]) - float(p[0]), float(q[1]) - float(p[1])).length()
		if l > bl:
			bl = l
			best = k
	var A: Array = poly[best]
	var B: Array = poly[(best + 1) % poly.size()]
	var ang := -atan2(float(B[1]) - float(A[1]), float(B[0]) - float(A[0]))
	var rot := func(v: Vector2) -> Vector2:
		return v.rotated(ang)
	var cen := Vector2.ZERO
	for p in poly:
		cen += Vector2(float(p[0]), float(p[1]))
	cen /= poly.size()
	var ya: float = (rot.call(Vector2(float(A[0]), float(A[1]))) as Vector2).y
	if (rot.call(cen) as Vector2).y < ya:
		ang += PI
	var r2 := []
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in poly:
		var v := Vector2(float(p[0]), float(p[1])).rotated(ang)
		r2.append([v.x, v.y, int(p[2])])
		mn = mn.min(v)
		mx = mx.max(v)
	var c := (mn + mx) * 0.5
	for p in r2:
		p[0] = snappedf(float(p[0]) - c.x, 0.0001)
		p[1] = snappedf(float(p[1]) - c.y, 0.0001)
	var a2 := Vector2(float(ax[0]), float(ax[1])).rotated(ang) - c
	return {"pts": r2, "ax": [a2.x, a2.y]}


## Malha do pedaço rachado: casca nas arestas de casca; madeira rachada nas outras
## (ondulada nas fibras, com degraus, rachaduras, o miolo escuro e farpas); pontas com anéis.
func _piece_node(fl: Dictionary) -> Node3D:
	var L := float(fl.cil.L)
	var pts: Array = fl.sec.pts
	var ax := Vector2(float(fl.sec.ax[0]), float(fl.sec.ax[1]))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(str(pts.size()) + str(L) + str(pts[0])))
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 1.0
	var mesh := ArrayMesh.new()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations := 16
	var P := func(v: Vector2, u: float) -> Vector3:
		var r := _cil_r(fl, u)
		return Vector3((u - 0.5) * L, v.y * r, v.x * r)
	var n := pts.size()
	var pcen := Vector2.ZERO
	for p0 in pts:
		pcen += Vector2(float(p0[0]), float(p0[1]))
	pcen /= n
	var arc := 0.0
	for k in n:
		var a := Vector2(float(pts[k][0]), float(pts[k][1]))
		var b := Vector2(float(pts[(k + 1) % n][0]), float(pts[(k + 1) % n][1]))
		var typ := int(pts[k][2])
		var en := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		var mid := (a + b) * 0.5
		if en.dot(mid - pcen) < 0.0:
			en = -en          # sempre para fora do pedaço
		if typ == 0:
			var seg := a.distance_to(b)
			for i in stations:
				var u0 := float(i) / stations
				var u1 := float(i + 1) / stations
				var q := [P.call(a, u0), P.call(b, u0), P.call(b, u1), P.call(a, u1)]
				var uv := [Vector2(arc, u0 * L), Vector2(arc + seg * 0.3, u0 * L), Vector2(arc + seg * 0.3, u1 * L), Vector2(arc, u1 * L)]
				var nn := Vector3(0, en.y, en.x)
				var out3 := nn
				for tri in [[0, 1, 2], [0, 2, 3]]:
					_tri_out(bark, q[tri[0]], q[tri[1]], q[tri[2]], out3, Color.WHITE, Color.WHITE, Color.WHITE, uv[tri[0]], uv[tri[1]], uv[tri[2]], true, false)
			arc += a.distance_to(b) * 0.3
		else:
			# face rachada: subdivide e desloca para fora/dentro (não fica plana)
			var across := 30
			var nn3 := Vector3(0, en.y, en.x)
			for i in stations * 3:
				for j in across:
					var q := []
					var cs := []
					for e in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
						var u := float(e[0]) / (stations * 3)
						var w := float(e[1]) / across
						var v := a.lerp(b, w)
						var x := (u - 0.5) * L
						var edge := 1.0 - smoothstep(0.82, 1.0, absf(w * 2.0 - 1.0))
						var h := nz.get_noise_2d(x * 1.2 + k * 31.0, w * 4.0) * 0.02 + nz.get_noise_2d(x * 5.0, w * 16.0) * 0.006
						h += 0.008 if nz.get_noise_2d(x * 0.8 + 100.0 + k, w * 2.0) > 0.25 else 0.0
						# rachaduras: riscos finos e compridos no sentido das fibras
						var crack := false
						for cc in 3:
							var cw := 0.5 + 0.38 * nz.get_noise_1d(x * 0.35 + cc * 57.0 + k * 13.0)
							var on := nz.get_noise_1d(x * 0.5 + cc * 91.0 + k * 7.0) > 0.05
							if on and absf(w - cw) < 0.026:
								crack = true
						if crack:
							h -= 0.01
						var r := _cil_r(fl, u)
						var pw: Vector3 = P.call(v, u) + nn3 * h * edge
						q.append(pw)
						var core := 1.0 - smoothstep(0.0, 0.12, v.distance_to(ax))
						var grain := 0.07 * nz.get_noise_2d(x * 2.0, w * 30.0 + k)
						var col := Color(0.36, 0.27, 0.18).darkened(core * 0.35 + grain)
						if crack:
							col = Color(0.1, 0.07, 0.04)
						cs.append(col)
						var _r := r
					for tri in [[0, 1, 2], [0, 2, 3]]:
						_tri_out(wood, q[tri[0]], q[tri[1]], q[tri[2]], nn3, cs[tri[0]], cs[tri[1]], cs[tri[2]])
			# farpas levantadas da face, no sentido das fibras
			var fl_len := a.distance_to(b) * _cil_r(fl, 0.5)
			for f in int(clampf(fl_len * 60.0, 3.0, 24.0)):
				var u := rng.randf_range(0.03, 0.97)
				var v := a.lerp(b, rng.randf_range(0.05, 0.95))
				var base: Vector3 = P.call(v, u)
				var dx := 1.0 if rng.randf() < 0.5 else -1.0
				var ln := rng.randf_range(0.04, 0.13)
				var tip := base + Vector3(dx * ln, 0, 0) + nn3 * rng.randf_range(0.01, 0.035)
				var side := Vector3(0, -en.x, en.y) * rng.randf_range(0.004, 0.009)
				var col := Color(0.58, 0.43, 0.28).darkened(rng.randf() * 0.15)
				for vtx in [base - side, base + side, tip]:
					wood.set_color(col)
					wood.add_vertex(vtx)
	# pontas: a seção com os anéis em volta do miolo
	var cen := Vector2.ZERO
	for p in pts:
		cen += Vector2(float(p[0]), float(p[1]))
	cen /= n
	for end in [0.0, 1.0]:
		for k in n:
			var a := Vector2(float(pts[k][0]), float(pts[k][1]))
			var b := Vector2(float(pts[(k + 1) % n][0]), float(pts[(k + 1) % n][1]))
			var cols := []
			for v in [cen, a, b]:
				var dd: float = (v as Vector2).distance_to(ax)
				cols.append(Color(0.56, 0.42, 0.28).darkened(0.1 * absf(sin(dd * 14.0))))
			_tri_out(wood, P.call(cen, end), P.call(a, end), P.call(b, end), Vector3(1 if end > 0.5 else -1, 0, 0), cols[0], cols[1], cols[2])
	wood.generate_normals()
	bark.generate_normals()
	bark.commit(mesh)
	if mesh.get_surface_count() > 0:
		var age := float(last_day - int(fl.get("dia", last_day)))
		mesh.surface_set_material(0, extra_barks[str(fl.casca)] if extra_barks.has(str(fl.get("casca", ""))) else (_bark if age < 200 else _bark_dead))
	wood.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _piece_wood_mat())
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = VIEW_DIST
	if bool(fl.get("em_pe", false)):
		mi.rotation.x = -PI * 0.5        # nas forquilhas: a face larga fica em pé
	root.add_child(mi)
	return root


## Põe o triângulo com a frente para "out" (a Godot desenha só a frente).
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, ca := Color.WHITE, cb := Color.WHITE, cc := Color.WHITE, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, use_uv := false, use_col := true) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		var tu := uvb
		uvb = uvc
		uvc = tu
	for e in [[a, ca, uva], [b, cb, uvb], [c, cc, uvc]]:
		if use_col:
			st.set_color(e[1])
		if use_uv:
			st.set_uv(e[2])
		st.add_vertex(e[0])


var _pwm: StandardMaterial3D

func _piece_wood_mat() -> StandardMaterial3D:
	if _pwm == null:
		_pwm = StandardMaterial3D.new()
		_pwm.vertex_color_use_as_albedo = true
		_pwm.vertex_color_is_srgb = true
		_pwm.roughness = 1.0
		_pwm.metallic_specular = 0.1
		_pwm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _pwm
