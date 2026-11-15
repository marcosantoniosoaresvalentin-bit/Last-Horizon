extends Node
## Simulação da Terra: relevo, estações do ano, água e solo.
##
## - O ano tem estação chuvosa (cheia) e estação seca. Na cheia chove muito
##   e as baixadas viram lagos; na seca o sol evapora a água e eles somem.
## - A água escorre morro abaixo, empoça nos lugares fundos, infiltra no solo
##   e brota como nascente no pé da serra.
## - A argila nasce da rocha: feldspato e mica se decompõem com água e calor,
##   ao longo do tempo geológico. Viram três tipos de argila:
##   caulinita (solo bem drenado e lavado pela chuva, o latossolo amazônico),
##   ilita (vem da mica, solo mais jovem) e esmectita (onde a água fica parada;
##   incha molhada e racha fundo quando seca).
## - A enxurrada arranca argila dos morros e deposita no fundo dos lagos.
##   Fundo de argila segura a água por mais tempo.
## - A grama cresce onde o solo tem água, amarela na seca e morre afogada.
##
## Roda numa thread separada para não travar o jogo.

signal world_ready

const W := 128
const H := 96
const N := W * H
const SC := 200.0 / W
const GW_CAP := 1.6
const STEPS_PER_SEC := 6.0
const STEP_MULT := 5.0
const STEPS_DAY := 2880           # um dia de jogo = 8 minutos
const START_HOUR := 7.0
const SEASON_DAYS := 4.0          # cada estação dura 4 dias de jogo
const YEAR_DAYS := SEASON_DAYS * 2.0

# terreno e água
var ter := PackedFloat32Array()
var wat := PackedFloat32Array()
var gw := PackedFloat32Array()
var moist := PackedFloat32Array()
var fl := PackedFloat32Array()
var fr := PackedFloat32Array()
var ft := PackedFloat32Array()
var fb := PackedFloat32Array()
var spring := PackedFloat32Array()
# solo
var clay := PackedFloat32Array()       # argila (0 a 1)
var sand := PackedFloat32Array()       # areia (0 a 1)
var sus := PackedFloat32Array()        # argila sendo carregada pela água
var cover := PackedFloat32Array()      # quanto de grama tem ali (0 a 1)
var wetmem := PackedFloat32Array()     # lembrança de que ali alagou
# geologia e tipos de argila
var feld := PackedFloat32Array()       # feldspato na rocha de origem
var mica := PackedFloat32Array()       # mica na rocha de origem
var kao := PackedFloat32Array()        # parte da argila que é caulinita
var ili := PackedFloat32Array()        # parte da argila que é ilita
var sme := PackedFloat32Array()        # parte da argila que é esmectita
var rock_name := PackedByteArray()     # 0 sedimento antigo, 1 granito, 2 gnaisse, 3 xisto

var max_h := 1.0
var steps := 0
var rain_t := 0
var dry_t := 0
var raining := false
var spawn := Vector2i(W / 2, H / 2)
var is_ready := false

var _thread := Thread.new()
var _mx := Mutex.new()
var _quit := false
var _out_wat := PackedFloat32Array()
var _water_new := false
var _out_soil := PackedByteArray()
var _out_types := PackedByteArray()
var _soil_new := false
var _info := PackedFloat32Array()
var _dig_queue := []
## Cópias estáveis feitas logo após gerar o mundo (seguras para ler na tela).
var ter0 := PackedFloat32Array()
var moist0 := PackedFloat32Array()
var gw0 := PackedFloat32Array()


func _ready() -> void:
	rock_name.resize(N)
	for a in ["ter", "wat", "gw", "moist", "fl", "fr", "ft", "fb", "spring", "clay", "sand", "sus", "cover", "wetmem", "feld", "mica", "kao", "ili", "sme"]:
		var arr := PackedFloat32Array()
		arr.resize(N)
		set(a, arr)
	_thread.start(_sim_loop)


func _exit_tree() -> void:
	_quit = true
	if _thread.is_started():
		_thread.wait_to_finish()


# ================== TEMPO E ESTAÇÕES ==================

## Hora do dia (0 a 24).
func hour() -> float:
	return fmod(START_HOUR + float(steps) / STEPS_DAY * 24.0, 24.0)


func day() -> int:
	return int((START_HOUR / 24.0 + float(steps) / STEPS_DAY)) + 1


## Fase do ano: 0 = começo da cheia, 0.5 = começo da seca.
func year_phase() -> float:
	return fmod((START_HOUR / 24.0 + float(steps) / STEPS_DAY) / YEAR_DAYS, 1.0)


## Quanto o ano está "molhado" agora: 1 no auge da cheia, 0 no auge da seca.
func wetness() -> float:
	return 0.5 + 0.5 * sin(year_phase() * TAU)


func season_name() -> String:
	var p := year_phase()
	if p < 0.5:
		return "Cheia" if p > 0.08 else "Começo da cheia"
	return "Seca" if p > 0.58 else "Começo da seca"


# ================== LEITURA PELA TELA ==================

func water_at(cell: Vector2i) -> float:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return 0.0
	_mx.lock()
	var v := _out_wat[cell.y * W + cell.x] if _out_wat.size() == N else 0.0
	_mx.unlock()
	return v


## Devolve a água atual se mudou desde a última vez, ou um array vazio.
func take_water() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	_mx.lock()
	if _water_new:
		out = _out_wat
		_water_new = false
	_mx.unlock()
	return out


## Mapas do solo, se mudaram: [RGBA argila/areia/umidade/grama, RGBA caulinita/ilita/esmectita/rocha].
func take_soil() -> Array:
	var out := []
	_mx.lock()
	if _soil_new:
		out = [_out_soil, _out_types]
		_soil_new = false
	_mx.unlock()
	return out


const ROCKS := ["sedimento antigo", "granito", "gnaisse", "xisto"]
const CLAY_NAMES := ["caulinita", "ilita", "esmectita"]


## Dados do solo numa célula (vazio se ainda não há dados).
func soil_data(cell: Vector2i) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return {}
	var i := cell.y * W + cell.x
	_mx.lock()
	if _info.size() != N * 7:
		_mx.unlock()
		return {}
	var d := {"clay": _info[i * 7], "sand": _info[i * 7 + 1], "moist": _info[i * 7 + 2],
		"types": [_info[i * 7 + 3], _info[i * 7 + 4], _info[i * 7 + 5]], "water": _info[i * 7 + 6]}
	_mx.unlock()
	var t: Array = d.types
	var top := 0
	for k in 3:
		if t[k] > t[top]:
			top = k
	d["kind"] = top
	return d


## Tira argila de uma célula (o jogador cavou ali). Aplicado pela simulação.
func dig(cell: Vector2i, amount: float) -> void:
	_mx.lock()
	_dig_queue.append([cell.y * W + cell.x, amount])
	var q := (cell.y * W + cell.x) * 7
	if _info.size() == N * 7:
		_info[q] = maxf(0.0, _info[q] - amount)
	_mx.unlock()

## Descrição do solo numa célula, para mostrar ao jogador.
func soil_info(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return ""
	var i := cell.y * W + cell.x
	_mx.lock()
	if _info.size() != N * 7:
		_mx.unlock()
		return ""
	var c := _info[i * 7]; var sa := _info[i * 7 + 1]; var g := _info[i * 7 + 2]
	var k := _info[i * 7 + 3]; var il := _info[i * 7 + 4]; var sm := _info[i * 7 + 5]; var w := _info[i * 7 + 6]
	_mx.unlock()
	var rock: String = ROCKS[rock_name[i]]
	var kind := "solo arenoso"
	if c > 0.35:
		var names := {"caulinita": k, "ilita": il, "esmectita": sm}
		var top := "caulinita"
		for n in names:
			if names[n] > names[top]:
				top = n
		kind = "argila (%s)" % top
		if top == "esmectita" and g < 0.35 and w < 0.03:
			kind = "barro rachado de esmectita"
	elif sa < 0.35:
		kind = "terra misturada"
	var state := "seco"
	if w > 0.1: state = "alagado"
	elif g > 0.85: state = "encharcado"
	elif g > 0.45: state = "úmido"
	return "Solo: %s · argila %d%% · areia %d%% · %s · rocha: %s" % [kind, int(c * 100), int(sa * 100), state, rock]


# ================== LAÇO PRINCIPAL ==================

func _sim_loop() -> void:
	_generate()
	_find_spawn()
	ter0 = ter.duplicate()
	moist0 = moist.duplicate()
	gw0 = gw.duplicate()
	_publish()
	is_ready = true
	call_deferred("emit_signal", "world_ready")
	var t_last := Time.get_ticks_usec()
	var acc := 0.0
	var loops := 0
	while not _quit:
		var now := Time.get_ticks_usec()
		acc += (now - t_last) / 1000000.0 * STEPS_PER_SEC
		t_last = now
		var n := mini(int(acc), 4)
		acc = minf(acc - n, 4.0)
		for k in n:
			_weather_step()
			_step(raining, STEP_MULT)
		_mx.lock()
		var digs := _dig_queue
		_dig_queue = []
		_mx.unlock()
		for d in digs:
			clay[d[0]] = maxf(0.0, clay[d[0]] - d[1])
		loops += 1
		if n > 0 and loops % 8 == 0:
			_publish()
		OS.delay_msec(15)


func _find_spawn() -> void:
	var best := -1e9
	for k in 600:
		var x := randi_range(10, W - 11)
		var y := randi_range(10, H - 11)
		var i := y * W + x
		var h := ter[i] / max_h
		if wat[i] > 0.02 or h > 0.5:
			continue
		# perto de um lugar que alaga, mas no seco
		var near := 0.0
		for o in [-3, 3, -3 * W, 3 * W]:
			near = maxf(near, wetmem[i + o])
		var score := near + cover[i] * 0.5 - absf(h - 0.25)
		if score > best:
			best = score
			spawn = Vector2i(x, y)


func _publish() -> void:
	var w := wat.duplicate()
	var soil := PackedByteArray()
	soil.resize(N * 4)
	for i in N:
		var p := i * 4
		soil[p] = int(clampf(clay[i], 0.0, 1.0) * 255.0)
		soil[p + 1] = int(clampf(sand[i], 0.0, 1.0) * 255.0)
		soil[p + 2] = int(clampf(maxf(wetmem[i] * 0.9, gw[i] / GW_CAP), 0.0, 1.0) * 255.0)
		soil[p + 3] = int(clampf(cover[i], 0.0, 1.0) * 255.0)
	var types := PackedByteArray()
	types.resize(N * 4)
	var info := PackedFloat32Array()
	info.resize(N * 7)
	for i in N:
		var p := i * 4
		types[p] = int(clampf(kao[i], 0.0, 1.0) * 255.0)
		types[p + 1] = int(clampf(ili[i], 0.0, 1.0) * 255.0)
		types[p + 2] = int(clampf(sme[i], 0.0, 1.0) * 255.0)
		types[p + 3] = rock_name[i] * 80
		var q := i * 7
		info[q] = clay[i]; info[q + 1] = sand[i]; info[q + 2] = gw[i] / GW_CAP
		info[q + 3] = kao[i]; info[q + 4] = ili[i]; info[q + 5] = sme[i]; info[q + 6] = wat[i]
	_mx.lock()
	_out_wat = w
	_water_new = true
	_out_soil = soil
	_out_types = types
	_info = info
	_soil_new = true
	_mx.unlock()


# ================== GERAÇÃO DO MUNDO ==================

func _n01(n: FastNoiseLite, x: float, y: float) -> float:
	return (n.get_noise_2d(x, y) + 1.0) * 0.5


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := rng.randi()
	var base := FastNoiseLite.new()
	base.seed = s; base.noise_type = FastNoiseLite.TYPE_PERLIN
	base.fractal_octaves = 4; base.frequency = 0.018
	var fine := FastNoiseLite.new()
	fine.seed = s + 1; fine.noise_type = FastNoiseLite.TYPE_PERLIN
	fine.fractal_octaves = 3; fine.frequency = 0.07
	var wid := FastNoiseLite.new()
	wid.seed = s + 2; wid.noise_type = FastNoiseLite.TYPE_PERLIN
	wid.fractal_octaves = 3; wid.frequency = 0.03
	var rid := FastNoiseLite.new()
	rid.seed = s + 3; rid.noise_type = FastNoiseLite.TYPE_PERLIN
	rid.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	rid.fractal_octaves = 5; rid.frequency = 0.035
	var soiln := FastNoiseLite.new()
	soiln.seed = s + 4; soiln.noise_type = FastNoiseLite.TYPE_PERLIN
	soiln.fractal_octaves = 3; soiln.frequency = 0.05

	# serra: um segmento alongado em algum lugar do meio do mapa
	var ax := 200.0 * (0.25 + rng.randf() * 0.2)
	var ay := 150.0 * (0.25 + rng.randf() * 0.5)
	var ang := rng.randf() * PI
	var length := 200.0 * (0.22 + rng.randf() * 0.15)
	var vx := cos(ang) * length
	var vy := sin(ang) * length
	var tilt := rng.randf() * TAU

	# baixadas: lugares fundos longe da serra, onde a água vai se juntar
	var dips := []
	var tries := 0
	while dips.size() < 6 and tries < 200:
		tries += 1
		var dx := rng.randf_range(15.0, 185.0)
		var dy := rng.randf_range(15.0, 135.0)
		var t0 := clampf(((dx - ax) * vx + (dy - ay) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
		if Vector2(dx - (ax + vx * t0), dy - (ay + vy * t0)).length() < 35.0:
			continue
		dips.append([dx, dy, rng.randf_range(9.0, 18.0), rng.randf_range(4.0, 7.5)])

	var mn := 1e9
	for y in H:
		for x in W:
			var ux := x * SC
			var uy := y * SC
			var t := clampf(((ux - ax) * vx + (uy - ay) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
			var dist := Vector2(ux - (ax + vx * t), uy - (ay + vy * t)).length()
			var w := 24.0 + _n01(wid, ux, uy) * 16.0
			var serra := exp(-pow(dist / w, 2.0)) * (0.75 + 0.25 * sin(t * PI))
			var h := serra * (34.0 + _n01(rid, ux, uy) * 18.0)
			h += _n01(base, ux + 50.0, uy) * 10.0
			h += (_n01(fine, ux, uy) - 0.5) * 3.0
			h += ((float(x) / W - 0.5) * cos(tilt) + (float(y) / H - 0.5) * sin(tilt)) * 7.0
			for d in dips:
				var dd := Vector2(ux - d[0], uy - d[1]).length() / float(d[2])
				h -= float(d[3]) * exp(-dd * dd * 1.6) * (0.8 + 0.4 * _n01(fine, ux * 2.0, uy * 2.0))
			ter[y * W + x] = h
			mn = minf(mn, h)
	max_h = 0.0
	for i in N:
		ter[i] -= mn
		max_h = maxf(max_h, ter[i])

	_initial_soil(soiln)

	wat.fill(0.0); moist.fill(0.0); spring.fill(0.0); sus.fill(0.0)
	fl.fill(0.0); fr.fill(0.0); ft.fill(0.0); fb.fill(0.0)
	gw.fill(GW_CAP * 0.35)
	steps = 0
	# aquece o mundo: uma cheia forte para encher as baixadas
	for k in 90:
		_step(true, 10.0)
	for k in 50:
		_step(false, 10.0)
	steps = 0
	raining = false
	dry_t = 500


## Geologia e solo inicial, como se milhões de anos tivessem passado.
## A rocha de cada lugar se decompõe conforme a água que passa por ali,
## e a argila formada desce pelos vales e se junta nas baixadas.
func _initial_soil(soiln: FastNoiseLite) -> void:
	var geo := FastNoiseLite.new()
	geo.seed = soiln.seed + 9; geo.noise_type = FastNoiseLite.TYPE_CELLULAR
	geo.frequency = 0.035; geo.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	# área que drena para cada célula (quanto mais água passa, mais fundo de vale)
	var order := []
	order.resize(N)
	for i in N:
		order[i] = i
	order.sort_custom(func(a, b): return ter[a] > ter[b])
	var accum := PackedFloat32Array(); accum.resize(N); accum.fill(1.0)
	var recv := PackedInt32Array(); recv.resize(N); recv.fill(-1)
	for i in order:
		var x: int = i % W; var y: int = i / W
		var best := -1; var drop := 0.0
		for o in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nx: int = x + o[0]; var ny: int = y + o[1]
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var d := ter[i] - ter[ny * W + nx]
			if d > drop:
				drop = d; best = ny * W + nx
		if best >= 0:
			accum[best] += accum[i]
			recv[i] = best
	var made := PackedFloat32Array(); made.resize(N)
	for y in H:
		for x in W:
			var i := y * W + x
			var hx := ter[y * W + mini(W - 1, x + 1)] - ter[y * W + maxi(0, x - 1)]
			var hy := ter[mini(H - 1, y + 1) * W + x] - ter[maxi(0, y - 1) * W + x]
			var slope := clampf(Vector2(hx, hy).length() / 6.0, 0.0, 1.0)
			var hn := ter[i] / max_h
			var valley := clampf(log(accum[i]) / 6.0, 0.0, 1.0)
			var around := 0.0
			for o in [-4, 4, -4 * W, 4 * W]:
				around += ter[clampi(i + o, 0, N - 1)]
			var pit := clampf((around / 4.0 - ter[i]) / 2.0, 0.0, 1.0)
			var n := _n01(soiln, x, y)
			# 1. rocha de origem: serra de granito/gnaisse, faixas de xisto, planície de sedimento
			var g := _n01(geo, x, y)
			var r := 0
			if hn > 0.35 or g > 0.82:
				r = 3 if g > 0.82 else (1 if g < 0.5 else 2)
			rock_name[i] = r
			match r:
				1: feld[i] = 0.7; mica[i] = 0.15   # granito: muito feldspato
				2: feld[i] = 0.5; mica[i] = 0.3    # gnaisse
				3: feld[i] = 0.15; mica[i] = 0.7   # xisto: muita mica
				_: feld[i] = 0.25; mica[i] = 0.1   # sedimento antigo: já muito lavado
			# 2 a 4. água + calor úmido + tempo: quanto de rocha virou argila ali
			var water_idx := clampf(0.4 + valley * 0.4 + (1.0 - slope) * 0.3, 0.0, 1.0)
			var weather := clampf((feld[i] + mica[i]) * water_idx * (1.0 - slope * 0.7) * 1.8, 0.0, 1.0)
			made[i] = weather
			sand[i] = clampf(0.15 + feld[i] * 0.25 + slope * 0.35 + (0.5 - n) * 0.3, 0.0, 1.0)
			# tipo da argila formada no lugar
			var drained := clampf(slope * 1.5 + sand[i] * 0.5 - pit, 0.0, 1.0)
			var k := feld[i] * (0.4 + drained)       # caulinita: feldspato bem lavado pela chuva
			var il := mica[i] * (1.2 - water_idx * 0.5)  # ilita: da mica, menos lavada
			var sm := pit * 1.2 + (1.0 - drained) * 0.2   # esmectita: água parada
			var tot := k + il + sm + 0.0001
			kao[i] = k / tot; ili[i] = il / tot; sme[i] = sm / tot
			cover[i] = clampf(1.0 - smoothstep(0.72, 0.86, hn) - slope * 0.6, 0.0, 1.0)
			wetmem[i] = pit
	# 5. deposição: parte da argila desce pelos caminhos da água e se junta onde ela para
	for i in N:
		clay[i] = made[i] * 0.6
	for i in order:
		var go := made[i] * 0.4
		var j: int = recv[i]
		var steps_down := 0
		while j >= 0 and steps_down < 60:
			var stop := 0.08 + wetmem[j] * 0.6
			var drop := go * stop
			clay[j] += drop
			go -= drop
			j = recv[j]
			steps_down += 1
	for i in N:
		clay[i] = clampf(clay[i], 0.0, 1.0)
		sand[i] *= 1.0 - clay[i] * 0.6
		# argila acumulada em baixada encharcada vira esmectita
		var pit_mix := wetmem[i] * clay[i]
		sme[i] = lerpf(sme[i], 1.0, pit_mix * 0.7)
		var tot := kao[i] + ili[i] + sme[i]
		kao[i] /= tot; ili[i] /= tot; sme[i] /= tot


# ================== CLIMA ==================

func _weather_step() -> void:
	var wet := wetness()
	if raining:
		rain_t -= 1
		if rain_t <= 0:
			raining = false
			# na cheia o tempo seco dura pouco; na seca dura muito
			dry_t = int(lerpf(2600.0, 250.0, wet) * randf_range(0.6, 1.4))
	else:
		dry_t -= 1
		if dry_t <= 0:
			raining = true
			rain_t = int(lerpf(120.0, 900.0, wet) * randf_range(0.6, 1.4))


# ================== PASSO DA SIMULAÇÃO ==================

func _step(rain_now: bool, mult: float) -> void:
	const C := 0.22
	const DAMP := 0.985
	# Cópias locais: em GDScript, mexer em variáveis locais é bem mais rápido.
	var T := ter
	var Wt := wat
	var G := gw
	var L := fl
	var R := fr
	var U := ft
	var D := fb
	var SP := spring
	var M := moist
	var CL := clay
	var SA := sand
	var mh := max_h
	var season_wet := wetness()
	# o sol da seca evapora bem mais
	var evap := (0.00002 if rain_now else lerpf(0.0002, 0.00006, season_wet)) * mult
	var rain := 0.0008 * mult
	var inf_max := 0.00025 * mult
	for i in N:
		var w := Wt[i]
		if rain_now:
			w += rain * (0.55 + T[i] / mh * 0.9)
		var room := GW_CAP - G[i]
		if w > 0.0 and room > 0.0:
			# argila quase não deixa a água entrar; areia deixa muito
			var inf := minf(minf(w, inf_max * (1.1 - CL[i] * 0.95) * (0.7 + SA[i] * 0.8)), room)
			w -= inf
			G[i] += inf
		Wt[i] = maxf(0.0, w - evap)

	# fluxo de superfície (modelo de canos virtuais)
	var i := 0
	for y in H:
		for x in W:
			var wi := Wt[i]
			var h := T[i] + wi
			var l := 0.0
			var r := 0.0
			var t := 0.0
			var b := 0.0
			if x > 0:
				l = maxf(0.0, L[i] * DAMP + C * (h - T[i - 1] - Wt[i - 1]))
			if x < W - 1:
				r = maxf(0.0, R[i] * DAMP + C * (h - T[i + 1] - Wt[i + 1]))
			if y > 0:
				t = maxf(0.0, U[i] * DAMP + C * (h - T[i - W] - Wt[i - W]))
			if y < H - 1:
				b = maxf(0.0, D[i] * DAMP + C * (h - T[i + W] - Wt[i + W]))
			var s := l + r + t + b
			if s > wi and s > 0.0:
				var k := wi / s
				l *= k; r *= k; t *= k; b *= k
			L[i] = l; R[i] = r; U[i] = t; D[i] = b
			i += 1
	i = 0
	for y in H:
		for x in W:
			var inn := 0.0
			if x > 0: inn += R[i - 1]
			if x < W - 1: inn += L[i + 1]
			if y > 0: inn += D[i - W]
			if y < H - 1: inn += U[i + W]
			var w := maxf(0.0, Wt[i] + inn - L[i] - R[i] - U[i] - D[i])
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				w *= 0.8  # a água sai pelas bordas do mapa
			Wt[i] = w
			M[i] = M[i] * 0.9993 + (0.0007 if w > 0.03 else 0.0)
			i += 1

	wat = Wt; gw = G; fl = L; fr = R; ft = U; fb = D; moist = M
	if steps % 4 == 0:
		_slow_step(mult * 4.0, season_wet)
	steps += 1


## Processos lentos (a cada 4 passos): água subterrânea, nascentes,
## erosão e depósito de argila, e a grama crescendo ou secando.
func _slow_step(mult: float, season_wet: float) -> void:
	var T := ter
	var Wt := wat
	var G := gw
	var SP := spring
	var L := fl
	var R := fr
	var U := ft
	var D := fb
	var CL := clay
	var SA := sand
	var S := sus
	var CV := cover
	var WM := wetmem
	var FE := feld
	var MI := mica
	var KA := kao
	var IL := ili
	var SM := sme
	var mh := max_h

	# água subterrânea anda devagar morro abaixo
	var gm := 0.003 * mult
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var c := y * W + x
			var gc := G[c]
			if gc <= 0.01:
				continue
			var lvl := T[c] + gc
			var best := -1
			var bd := 0.0
			var d := lvl - T[c - 1] - G[c - 1]
			if d > bd: bd = d; best = c - 1
			d = lvl - T[c + 1] - G[c + 1]
			if d > bd: bd = d; best = c + 1
			d = lvl - T[c - W] - G[c - W]
			if d > bd: bd = d; best = c - W
			d = lvl - T[c + W] - G[c + W]
			if d > bd: bd = d; best = c + W
			if best >= 0:
				var m := minf(minf(gc * 0.5, bd * gm), GW_CAP - G[best])
				if m > 0.0:
					G[c] = gc - m
					G[best] += m

	# a argila carregada pela água vai junto com a correnteza
	var moved := PackedFloat32Array(); moved.resize(N)
	var i := 0
	for y in H:
		for x in W:
			var w := Wt[i]
			var keep := S[i]
			if w > 0.02 and keep > 0.0:
				var out := L[i] + R[i] + U[i] + D[i]
				var frac := clampf(out * 4.0 / w, 0.0, 0.9)
				var go := keep * frac
				keep -= go
				if out > 0.0:
					var k := go / out
					if x > 0: moved[i - 1] += L[i] * k
					if x < W - 1: moved[i + 1] += R[i] * k
					if y > 0: moved[i - W] += U[i] * k
					if y < H - 1: moved[i + W] += D[i] * k
			moved[i] += keep
			i += 1

	var loss := 0.00003 * mult * lerpf(1.8, 0.7, season_wet)
	var grow := 0.00035 * mult
	for c in N:
		var w := Wt[c]
		var sc := moved[c]
		var hn := T[c] / mh
		var flow := L[c] + R[c] + U[c] + D[c]
		var speed := flow / maxf(w, 0.05)
		# erosão: água correndo forte arranca argila (e deixa a areia)
		if w > 0.08 and speed > 0.35 and hn < 0.85:
			var e := minf(CL[c] * 0.2, (speed - 0.35) * 0.00003 * mult)
			CL[c] -= e
			sc += e
			SA[c] = minf(1.0, SA[c] + e * 0.4)
		# depósito: água parada (ou secando) solta a argila no fundo
		var settle := 0.25 if speed < 0.15 else 0.02
		if w < 0.02:
			settle = 1.0
		var dep := sc * settle
		CL[c] = minf(1.0, CL[c] + dep)
		SA[c] = maxf(0.0, SA[c] - dep * 0.3)
		sc -= dep
		S[c] = sc

		# nascentes: solo encharcado devolve água para a superfície
		SP[c] *= 0.97
		var gc := G[c]
		if gc > GW_CAP * 0.97:
			var out := (gc - GW_CAP * 0.93) * 0.15
			G[c] = gc - out
			Wt[c] += out
			SP[c] = minf(1.0, SP[c] + out * 40.0)
		else:
			G[c] = maxf(0.0, gc - loss)

		# lembrança de alagamento
		WM[c] = maxf(WM[c] * (1.0 - 0.0004 * mult), 1.0 if w > 0.1 else 0.0)

		# intemperismo: feldspato e mica viram argila com água e calor (bem devagar)
		var water_now := clampf(G[c] / GW_CAP + WM[c] * 0.5, 0.0, 1.0)
		var heat := lerpf(0.8, 1.0, season_wet)          # calor úmido da Amazônia
		var wx := (FE[c] + MI[c]) * water_now * heat * 0.0000025 * mult
		if wx > 0.0 and CL[c] < 1.0:
			FE[c] = maxf(0.0, FE[c] - wx * 0.1)
			MI[c] = maxf(0.0, MI[c] - wx * 0.05)
			CL[c] = minf(1.0, CL[c] + wx)
		# o tipo de argila muda aos poucos conforme o lugar
		if CL[c] > 0.05:
			var drained := clampf(SA[c] - WM[c], 0.0, 1.0)
			var tk := FE[c] * 0.5 + drained * season_wet
			var ti := MI[c] * 0.8 + 0.05
			var ts := WM[c] * 1.2 + (0.3 if w > 0.1 else 0.0)
			var tt := tk + ti + ts + 0.0001
			var rr := 0.00004 * mult
			KA[c] = lerpf(KA[c], tk / tt, rr)
			IL[c] = lerpf(IL[c], ti / tt, rr)
			SM[c] = lerpf(SM[c], ts / tt, rr)

		# grama: precisa de água no solo, morre afogada, não nasce na pedra
		var target := clampf(G[c] / GW_CAP * 1.4 + 0.4, 0.0, 1.0)
		target *= 1.0 - smoothstep(0.72, 0.86, hn)
		target *= 1.0 - CL[c] * WM[c] * 0.7     # barro de fundo de lago demora a pegar grama
		if w > 0.15:
			target = 0.0
		var rate := grow if target > CV[c] else grow * (3.0 if w > 0.15 else 0.6)
		CV[c] = move_toward(CV[c], target, rate)

	gw = G; spring = SP; clay = CL; sand = SA; sus = S; cover = CV; wetmem = WM; wat = Wt
	feld = FE; mica = MI; kao = KA; ili = IL; sme = SM
