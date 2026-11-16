extends Node
## Simulação da Terra: relevo, estações do ano, água e solo.
##
## - Calendário de verdade (meses de 28 a 31 dias), começando em 1º/1/2000.
##   1 dia = 8 minutos de jogo. O tempo só passa com o jogo aberto.
##   Chove de acordo com o mês: muito de dezembro a abril, as chuvas param em
##   maio e junho, seca forte de julho a setembro (quase sem chuva, falta água)
##   e as chuvas voltam aos poucos em outubro e novembro.
## - A água escorre morro abaixo, empoça nos lugares fundos, infiltra no solo
##   e brota como nascente no pé da serra.
## - A argila nasce da rocha: feldspato e mica se decompõem com água e calor,
##   ao longo do tempo geológico. Viram três tipos de argila:
##   caulinita (solo bem drenado e lavado pela chuva, o latossolo amazônico),
##   ilita (vem da mica, solo mais jovem) e esmectita (onde a água fica parada;
##   incha molhada e racha fundo quando seca).
## - A enxurrada arranca argila dos morros e deposita no fundo dos lagos.
##   Fundo de argila segura a água por mais tempo.
## - O sol evapora a água (forte ao meio-dia, quase nada à noite). Quando uma
##   lagoa seca, o fundo vira lama; com o sol a lama seca e racha. Na chuva a
##   água escorre de novo para essas baixadas e a lagoa volta.
## - Argila para pegar só existe em poucas jazidas de terra avermelhada na beira
##   das lagoas. Ela se esgota quando o jogador cava e se forma de novo bem devagar.
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
# Calendário de verdade: meses de 28 a 31 dias, anos bissextos e dias da semana certos.
# Todo mundo novo começa em 1º de janeiro de 2000 (um sábado); depois 2001, 2002...
# O tempo só passa com o jogo aberto (fica pausado quando a pessoa sai).
const START_YEAR := 2000
const START_MONTH := 0            # o mundo começa em 1º de janeiro (0 = janeiro)
const MONTH_DAYS := 30.4375       # duração média de um mês (para o ritmo do clima)
## O clima foi ajustado para meses de 5 dias; com meses de verdade, os processos que
## duram a estação inteira (secar lagoas, intervalo entre chuvas na seca, água do solo)
## ficam K vezes mais lentos por dia, para cada mês continuar igual.
const K := MONTH_DAYS / 5.0
const WEEKDAYS := ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
const MONTHS := ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
	"Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]
## Quanto chove em cada mês (0 = nada, 1 = o máximo).
const RAIN_BY_MONTH := [0.9, 1.0, 1.0, 0.8, 0.5, 0.2, 0.05, 0.02, 0.05, 0.2, 0.45, 0.7]
## Água em medidas de verdade: 1 unidade de altura = 1,2 m, então 1 mm de chuva = 1/1200.
const MM := 1.0 / 1200.0
const STEP_HOURS := 24.0 / STEPS_DAY   # cada passo da simulação = 30 segundos do jogo

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
# lagoas e margens
var bed := PackedFloat32Array()        # leito de lagoa: onde a água fica parada (dura uma estação)
var shore := PackedFloat32Array()      # beira da lagoa (0 a 1), recalculada de tempos em tempos
var bank := PackedFloat32Array()       # argila que dá para pegar na beira (0 a 1)
var murk := PackedFloat32Array()       # água barrenta (0 limpa a 1 marrom de barro)
var tsoil := PackedFloat32Array()      # água na terra de cima (uns palmos); quando enche, a chuva escorre
var top := PackedFloat32Array()        # umidade da superfície: molha na chuva, seca no sol
var drain := PackedFloat32Array()      # quanta área escorre para cada célula (log); fixo depois de gerar
var deposit := PackedFloat32Array()    # jazidas de argila: poucos pontos de terra avermelhada perto das lagoas
const DEPOSITS := 5                    # quantas jazidas o mapa tem
var drain_min := 1e9                   # só os 4% de células com mais drenagem viram filete de enxurrada
var _shore_timer := 0

var max_h := 1.0
var steps := 0
var rain_t := 0
var dry_t := 0
var raining := false
var rain_mmh := 8.0       # força da chuva agora (milímetros por hora)
var long_rain := false    # chuva comprida de vários dias (só na época das chuvas)
var _warm := false        # aquecimento do mundo novo (enchente forte para formar rios e lagoas)
var spawn := Vector2i(W / 2, H / 2)
var is_ready := false
## No modo leve a simulação roda menos vezes por segundo (com passos maiores).
var steps_per_sec := STEPS_PER_SEC
var step_mult := STEP_MULT

## Pasta do mundo salvo ("" = não salva) e semente para gerar um mundo novo.
## Precisam ser definidas antes de adicionar a simulação na cena.
var save_dir := ""
var world_seed := 0
var loaded_from_save := false
var _save_req := false
const SAVE_VERSION := 1
const SAVE_ARRAYS := ["ter", "wat", "gw", "moist", "spring", "clay", "sand", "sus", "cover", "wetmem",
	"feld", "mica", "kao", "ili", "sme", "bed", "shore", "bank", "top", "drain", "deposit"]

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
	for a in ["ter", "wat", "gw", "moist", "fl", "fr", "ft", "fb", "spring", "clay", "sand", "sus", "cover", "wetmem", "feld", "mica", "kao", "ili", "sme", "bed", "shore", "bank", "top", "drain", "deposit", "murk", "tsoil"]:
		var arr := PackedFloat32Array()
		arr.resize(N)
		set(a, arr)
	_thread.start(_sim_loop)


func _exit_tree() -> void:
	_quit = true
	if _thread.is_started():
		_thread.wait_to_finish()
	# a simulação já parou: dá para salvar com segurança
	if save_dir != "" and is_ready:
		_save_state()


## Pede para a simulação salvar o mundo (feito entre dois passos, na thread dela).
func request_save() -> void:
	_mx.lock()
	_save_req = true
	_mx.unlock()


func _save_state() -> void:
	var data := {"versao": SAVE_VERSION, "max_h": max_h, "steps": steps, "rain_t": rain_t, "dry_t": dry_t,
		"raining": raining, "spawn": spawn, "drain_min": drain_min, "rock_name": rock_name,
		"rain_mmh": rain_mmh, "long_rain": long_rain, "murk": murk, "tsoil": tsoil}
	for a in SAVE_ARRAYS:
		data[a] = get(a)
	DirAccess.make_dir_recursive_absolute(save_dir)
	var tmp := save_dir + "/mundo.dat.tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var(data)
	f.close()
	# troca o arquivo só depois de gravar tudo, para nunca ficar um save pela metade
	DirAccess.rename_absolute(tmp, save_dir + "/mundo.dat")


func _load_state() -> bool:
	var path := save_dir + "/mundo.dat"
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var data = f.get_var()
	f.close()
	if not data is Dictionary or int(data.get("versao", 0)) != SAVE_VERSION:
		return false
	for a in SAVE_ARRAYS:
		var arr = data.get(a)
		if not arr is PackedFloat32Array or arr.size() != N:
			return false
	for a in SAVE_ARRAYS:
		set(a, data[a])
	var rn = data.get("rock_name")
	if rn is PackedByteArray and rn.size() == N:
		rock_name = rn
	max_h = float(data.max_h)
	steps = int(data.steps)
	rain_t = int(data.rain_t)
	dry_t = int(data.dry_t)
	raining = bool(data.raining)
	rain_mmh = float(data.get("rain_mmh", 8.0))
	long_rain = bool(data.get("long_rain", false))
	var mk = data.get("murk")
	if mk is PackedFloat32Array and mk.size() == N:
		murk = mk
	else:
		murk.resize(N)
		murk.fill(0.0)
	var ts = data.get("tsoil")
	if ts is PackedFloat32Array and ts.size() == N:
		tsoil = ts
	else:
		tsoil.resize(N)
		tsoil.fill(0.0)
	if not data.has("rain_mmh"):
		_calm_old_flood()
	spawn = data.spawn
	drain_min = float(data.drain_min)
	return true


# ================== TEMPO E ESTAÇÕES ==================

## Hora do dia (0 a 24).
func hour() -> float:
	return fmod(START_HOUR + float(steps) / STEPS_DAY * 24.0, 24.0)


## Força do sol agora (0 à noite, 1 ao meio-dia).
func sun() -> float:
	return clampf(sin((hour() - 6.0) / 12.0 * PI), 0.0, 1.0)


## Dias inteiros passados desde o começo do mundo.
func elapsed_days() -> int:
	return int((START_HOUR / 24.0 + float(steps) / STEPS_DAY))


static func start_unix() -> int:
	return Time.get_unix_time_from_datetime_dict({"year": START_YEAR, "month": START_MONTH + 1, "day": 1, "hour": 12})


## Data de hoje no jogo: {year, month (1-12), day, weekday (0 = domingo)}.
func date() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(start_unix() + elapsed_days() * 86400)


static func days_in_month(y: int, m: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0 else 28
	return 30 if m in [4, 6, 9, 11] else 31


## Dia da semana (0 = domingo) do dia 1 de um mês.
static func first_weekday(y: int, m: int) -> int:
	var u := Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": 1, "hour": 12})
	return int(Time.get_datetime_dict_from_unix_time(u).weekday)


## Dia do mês (1 a 31).
func day() -> int:
	return int(date().day)


## Mês atual (0 = janeiro).
func month() -> int:
	return int(date().month) - 1


func month_name() -> String:
	return MONTHS[month()]


## Ano do calendário: 2000, 2001, 2002...
func year() -> int:
	return int(date().year)


## Quanto está chovendo nesta época (0 a 1), passando suave de um mês para o outro.
func wetness() -> float:
	var d := date()
	var frac := (float(d.day) - 1.0 + hour() / 24.0) / days_in_month(d.year, d.month)
	var m := float(d.month - 1) + frac - 0.5
	var i := floori(m)
	var t := smoothstep(0.0, 1.0, m - i)
	return lerpf(RAIN_BY_MONTH[posmod(i, 12)], RAIN_BY_MONTH[posmod(i + 1, 12)], t)


func season_name() -> String:
	match month():
		11, 0, 1, 2, 3: return "Época das chuvas"
		4, 5: return "Fim das chuvas"
		6, 7, 8: return "Seca"
		_: return "Volta das chuvas"


# ================== LEITURA PELA TELA ==================

func water_at(cell: Vector2i) -> float:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return 0.0
	_mx.lock()
	var v := _out_wat[cell.y * W + cell.x] if _out_wat.size() >= N else 0.0
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


## Mapas do solo, se mudaram:
## [RGBA jazida de argila/areia/umidade do solo/grama, RGBA leito de lagoa/umidade da superfície/filete de enxurrada/rocha].
func take_soil() -> Array:
	var out := []
	_mx.lock()
	if _soil_new:
		out = [_out_soil, _out_types]
		_soil_new = false
	_mx.unlock()
	return out


const ROCKS := ["sedimento antigo", "granito", "gnaisse", "xisto"]
const INFO := 5   # valores por célula em _info: argila da beira, areia, umidade da superfície, leito, água


## Dados do solo numa célula (vazio se ainda não há dados).
func soil_data(cell: Vector2i) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return {}
	var i := cell.y * W + cell.x
	_mx.lock()
	if _info.size() != N * INFO:
		_mx.unlock()
		return {}
	var q := i * INFO
	var d := {"clay": _info[q], "sand": _info[q + 1], "moist": _info[q + 2], "bed": _info[q + 3], "water": _info[q + 4]}
	_mx.unlock()
	return d


## Tira argila da beira numa célula (o jogador cavou ali). Aplicado pela simulação.
func dig(cell: Vector2i, amount: float) -> void:
	_mx.lock()
	_dig_queue.append([cell.y * W + cell.x, amount])
	var q := (cell.y * W + cell.x) * INFO
	if _info.size() == N * INFO:
		_info[q] = maxf(0.0, _info[q] - amount)
	_mx.unlock()

## Descrição do solo numa célula, para mostrar ao jogador.
func soil_info(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return ""
	var i := cell.y * W + cell.x
	_mx.lock()
	if _info.size() != N * INFO:
		_mx.unlock()
		return ""
	var q := i * INFO
	var c := _info[q]; var sa := _info[q + 1]; var g := _info[q + 2]; var b := _info[q + 3]; var w := _info[q + 4]
	_mx.unlock()
	var rock: String = ROCKS[rock_name[i]]
	var kind := "solo arenoso" if sa > 0.5 else "terra"
	if b > 0.5:
		if w > 0.1:
			kind = "fundo de lagoa"
		elif g > 0.45:
			kind = "lama do fundo da lagoa"
		else:
			kind = "lama seca e rachada do fundo da lagoa"
	elif deposit[i] > 0.2:
		kind = "terra avermelhada, com argila" if c >= 0.35 else "terra avermelhada (argila esgotada, volta com o tempo)"
	elif shore[i] > 0.0:
		kind = "beira da lagoa"
	var state := "seco"
	if w > 0.1: state = "alagado"
	elif g > 0.85: state = "encharcado"
	elif g > 0.45: state = "úmido"
	var txt := "Solo: %s · %s" % [kind, state]
	if deposit[i] > 0.2 and b <= 0.5:
		txt += " · argila %d%%" % int(c * 100)
	return txt + " · rocha: %s" % rock


# ================== LAÇO PRINCIPAL ==================

func _sim_loop() -> void:
	loaded_from_save = save_dir != "" and _load_state()
	if not loaded_from_save:
		_generate()
		_find_spawn()
	ter0 = ter.duplicate()
	moist0 = moist.duplicate()
	gw0 = gw.duplicate()
	_publish()
	is_ready = true
	if save_dir != "" and not loaded_from_save:
		_save_state()
	call_deferred("emit_signal", "world_ready")
	var t_last := Time.get_ticks_usec()
	var acc := 0.0
	var loops := 0
	while not _quit:
		var now := Time.get_ticks_usec()
		acc += (now - t_last) / 1000000.0 * steps_per_sec
		t_last = now
		var n := mini(int(acc), 4)
		acc = minf(acc - n, 4.0)
		for k in n:
			_weather_step()
			_step(raining, step_mult)
		_mx.lock()
		var digs := _dig_queue
		_dig_queue = []
		_mx.unlock()
		for d in digs:
			bank[d[0]] = maxf(0.0, bank[d[0]] - d[1])
		_mx.lock()
		var want_save := _save_req
		_save_req = false
		_mx.unlock()
		if want_save and save_dir != "":
			_save_state()
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
	# Para a tela: [água que aparece como lâmina d'água (N), quanto ela está barrenta (N)].
	# Enxurrada rasa correndo não vira lâmina: aparece só como filete no chão.
	var w := PackedFloat32Array()
	w.resize(N * 2)
	for i in N:
		var a := wat[i]
		if a < 0.15:
			var speed := (fl[i] + fr[i] + ft[i] + fb[i]) / maxf(a, 0.02)
			if speed > 0.25 and bed[i] < 0.5:
				a = 0.0
		w[i] = a
		w[N + i] = murk[i]
	var soil := PackedByteArray()
	soil.resize(N * 4)
	for i in N:
		var p := i * 4
		soil[p] = int(clampf(deposit[i], 0.0, 1.0) * 255.0)
		soil[p + 1] = int(clampf(sand[i], 0.0, 1.0) * 255.0)
		soil[p + 2] = int(clampf(gw[i] / GW_CAP, 0.0, 1.0) * 255.0)
		soil[p + 3] = int(clampf(cover[i], 0.0, 1.0) * 255.0)
	var types := PackedByteArray()
	types.resize(N * 4)
	var info := PackedFloat32Array()
	info.resize(N * INFO)
	for i in N:
		var p := i * 4
		types[p] = int(clampf(bed[i], 0.0, 1.0) * 255.0)
		types[p + 1] = int(clampf(top[i], 0.0, 1.0) * 255.0)
		# filete de enxurrada: água rasa correndo nos caminhos naturais (desenhado no chão)
		types[p + 2] = int(clampf((wat[i] - 0.003) / 0.025, 0.0, 1.0) * 255.0) if drain[i] >= drain_min else 0
		types[p + 3] = rock_name[i] * 80
		var q := i * INFO
		info[q] = bank[i]; info[q + 1] = sand[i]; info[q + 2] = top[i]
		info[q + 3] = bed[i]; info[q + 4] = wat[i]
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
	if world_seed != 0:
		rng.seed = world_seed
	else:
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
	_warm = true
	for k in 170:
		_step(true, 10.0)
	for k in 50:
		_step(false, 10.0)
	_warm = false
	steps = 0
	raining = false
	dry_t = 500
	# só conta como lagoa o que ficou cheio depois da enchente inicial
	for i in N:
		bed[i] = 1.0 if wat[i] > 0.1 else 0.0
	# a enchente do aquecimento acabou: tira a enxurrada que ainda estava descendo os morros
	_calm_old_flood(0.0)
	# começa no meio das chuvas: lagoas e rios pela metade, ainda com espaço para subir
	for i in N:
		wat[i] = maxf(0.0, wat[i] - 0.3)
	_update_shore()
	_place_deposits(rng)
	bank = deposit.duplicate()
	for i in N:
		cover[i] *= 1.0 - deposit[i] * 0.8
		if drain[i] >= drain_min:
			cover[i] *= 0.35
	for i in N:
		top[i] = 1.0 if wat[i] > 0.02 else clampf(gw[i] / GW_CAP, 0.0, 0.6)


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
	for i in N:
		drain[i] = log(accum[i])
	var dr := drain.duplicate()
	dr.sort()
	drain_min = dr[int(N * 0.96)]
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
	var yr := year_rain()
	if raining:
		rain_t -= 1
		if rain_t <= 0:
			raining = false
			long_rain = false
			# nas chuvas o tempo firme dura pouco; na seca passa quase um mês sem chover
			dry_t = int(lerpf(STEPS_DAY * 4.5, 1000.0, pow(wet, 0.6)) * K * randf_range(0.6, 1.4) / yr)
	else:
		dry_t -= 1
		if dry_t <= 0:
			raining = true
			if randf() < 0.13 * wet * wet * yr:
				# chuva comprida: chove fraco/médio sem parar de meio dia a quase três dias
				long_rain = true
				rain_t = int(STEPS_DAY * randf_range(0.5, 2.8))
				rain_mmh = randf_range(1.5, 4.5) * yr
			else:
				# pancada: algumas horas de chuva e depois para; às vezes um temporal curto
				long_rain = false
				rain_t = int(lerpf(100.0, 450.0, wet) * randf_range(0.6, 1.4))
				rain_mmh = randf_range(3.0, 14.0) * yr
				if randf() < 0.12:
					rain_t = int(rain_t * 0.5)
					rain_mmh = randf_range(25.0, 45.0)


## Quanto chove neste ano comparado com um ano normal. Cada ano sorteia o seu
## (sempre igual para o mesmo mundo): uns mais secos, a maioria normal e, de vez
## em quando, um ano de cheia com bem mais chuva. O primeiro ano é sempre normal.
func year_rain(y := -1) -> float:
	if y < 0:
		y = year()
	if y <= START_YEAR:
		return 1.0
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(world_seed) + ":chuva:" + str(y))
	var roll := r.randf()
	if roll < 0.12:
		return r.randf_range(1.35, 1.7)     # ano de cheia
	if roll < 0.24:
		return r.randf_range(0.6, 0.8)      # ano seco
	return r.randf_range(0.85, 1.15)


## Saves antigos vieram de quando a chuva enchia demais: tira a enxurrada que ficou
## espalhada fora das lagoas (o que sobrar acima da borda das lagoas escoa sozinho).
func _calm_old_flood(keep := 0.03) -> void:
	for i in N:
		if bed[i] < 0.5 and wat[i] > keep:
			wat[i] = keep
		fl[i] = 0.0; fr[i] = 0.0; ft[i] = 0.0; fb[i] = 0.0


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
	# Tudo em medidas de verdade (milímetros por hora); "hrs" é quanto tempo do jogo este passo representa.
	var hrs := STEP_HOURS * mult / STEP_MULT
	# o sol da seca evapora bem mais (uns 8 mm por dia); ao meio-dia muito, à noite quase nada
	var evap := (0.02 if rain_now else lerpf(0.6, 0.25, season_wet) * (0.3 + 1.4 * sun())) * MM * hrs
	var rain := rain_mmh * MM * hrs
	# a terra seca chupa a chuva: areia uns 25 mm por hora, argila quase nada
	var inf_k := MM * hrs
	if _warm:
		evap = 0.00001 * mult / K
		rain = 0.00038 * mult
		inf_k = 0.0005 * mult / 25.0
	var TS := tsoil
	for i in N:
		var w := Wt[i]
		if rain_now:
			w += rain * (0.55 + T[i] / mh * 0.9)
		var room := GW_CAP - G[i]
		var cl := CL[i]
		if _warm:
			if w > 0.0 and room > 0.0:
				var inf0 := minf(minf(w, inf_k * lerpf(25.0, 1.5, cl) * (0.6 + SA[i] * 0.8)), room)
				w -= inf0
				G[i] += inf0
			Wt[i] = maxf(0.0, w - evap)
			continue
		# A chuva entra primeiro na terra de cima (4 a 6 cm de água cabem nela). Dali desce
		# devagar para o fundo. Chuva curta some na terra; chovendo horas e horas a terra
		# de cima enche e a água passa a escorrer para as baixadas e os rios.
		var ts := TS[i]
		var cap := lerpf(60.0, 25.0, cl) * MM
		if w > 0.0 and ts < cap:
			var inf := minf(minf(w, inf_k * lerpf(12.0, 1.0, cl) * (0.6 + SA[i] * 0.8)), cap - ts)
			w -= inf
			ts += inf
		if ts > 0.0 and room > 0.0:
			var perc := inf_k * lerpf(1.6, 0.25, cl) * clampf(room / (GW_CAP * 0.35), 0.0, 1.0)
			if w > 0.03:
				perc *= 0.1   # fundo de lagoa é vedado de lodo: vaza só uns milímetros por dia
			perc = minf(minf(perc, ts), room)
			ts -= perc
			G[i] += perc
		TS[i] = ts
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

	wat = Wt; gw = G; fl = L; fr = R; ft = U; fb = D; moist = M; tsoil = TS
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
	var BD := bed
	var SH := shore
	var BK := bank
	var DP := deposit
	var DR := drain
	var dmin := drain_min
	var TP := top
	var sun_now := sun()
	var raining_now := raining

	# água subterrânea anda devagar morro abaixo
	var gm := 0.0000015 * mult
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

	# a argila carregada pela água vai junto com a correnteza (e o barro que suja a água também)
	var moved := PackedFloat32Array(); moved.resize(N)
	var MK := murk
	var mud := PackedFloat32Array(); mud.resize(N)
	var i := 0
	for y in H:
		for x in W:
			var w := Wt[i]
			var keep := S[i]
			var out := L[i] + R[i] + U[i] + D[i]
			var frac := clampf(out * 4.0 / maxf(w, 0.0001), 0.0, 0.9)
			if w > 0.02 and keep > 0.0:
				var go := keep * frac
				keep -= go
				if out > 0.0:
					var k := go / out
					if x > 0: moved[i - 1] += L[i] * k
					if x < W - 1: moved[i + 1] += R[i] * k
					if y > 0: moved[i - W] += U[i] * k
					if y < H - 1: moved[i + W] += D[i] * k
			moved[i] += keep
			# barro: quantidade = quanto barro x quanta água
			var mm := MK[i] * w
			if mm > 0.0 and out > 0.0:
				var go2 := mm * frac
				mm -= go2
				var k2 := go2 / out
				if x > 0: mud[i - 1] += L[i] * k2
				if x < W - 1: mud[i + 1] += R[i] * k2
				if y > 0: mud[i - W] += U[i] * k2
				if y < H - 1: mud[i + W] += D[i] * k2
			mud[i] += mm
			i += 1
	# o barro assenta na água parada (em meio dia a água fica bem mais limpa)
	var slow_k := mult / (STEP_MULT * 4.0)
	var settle_mud := 1.0 - 0.0019 * slow_k

	# a terra perde água para as plantas e para o fundo: uns 5 mm por dia na seca, 2,5 nas chuvas
	var loss := lerpf(5.0, 2.5, season_wet) / 24.0 * MM * STEP_HOURS * mult / STEP_MULT
	if _warm:
		loss = 0.0000075 * mult * lerpf(1.8, 0.7, season_wet) / K
	var grow := 0.00035 * mult
	for c in N:
		var w := Wt[c]
		var sc := moved[c]
		var hn := T[c] / mh
		var flow := L[c] + R[c] + U[c] + D[c]
		var speed := flow / maxf(w, 0.05)
		# água barrenta: a enxurrada correndo pela terra fica marrom; chuva em cima da água suja um pouco
		var mk := mud[c] / maxf(w, 0.0001) if w > 0.001 else 0.0
		if w > 0.001:
			if raining_now and w < 0.06 and flow > 0.00002:
				mk = maxf(mk, 0.9)                 # filete de enxurrada: puro barro
			elif raining_now:
				mk += 0.0007 * slow_k              # pingos e beira lavando terra para dentro
			mk *= settle_mud if speed < 0.15 else 1.0 - (1.0 - settle_mud) * 0.2
		MK[c] = clampf(mk, 0.0, 1.0)
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
			# as plantas bebem primeiro da terra de cima; o resto sai do fundo
			var from_top := minf(tsoil[c], loss * 1.6)
			tsoil[c] -= from_top
			G[c] = maxf(0.0, gc - maxf(0.0, loss - from_top))

		# lembrança de alagamento
		WM[c] = maxf(WM[c] * (1.0 - 0.0004 * mult), 1.0 if w > 0.1 else 0.0)
		# leito de lagoa: só água parada conta (rio correndo não); some bem devagar (dura a seca inteira)
		BD[c] = maxf(BD[c] * (1.0 - 0.0000012 * mult / K), 1.0 if w > 0.1 and speed < 0.2 else 0.0)
		# superfície: molha com chuva ou água, seca com o sol (mais na seca)
		if w > 0.02 or raining_now:
			TP[c] = 1.0
		else:
			var dry := 0.00025 * mult * (0.15 + sun_now) * (1.3 - season_wet)
			if G[c] > GW_CAP * 0.95:
				dry *= 0.5   # solo encharcado por baixo demora mais a secar
			TP[c] = maxf(0.0, TP[c] - dry)
		# argila da jazida: depois de cavada, se forma de novo bem devagar
		if BK[c] < DP[c]:
			BK[c] = minf(DP[c], BK[c] + 0.00005 * mult)

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
		target *= 1.0 - BD[c] * 0.9             # fundo de lagoa seco fica só lama, sem grama
		target *= 1.0 - DP[c] * 0.8             # jazida de argila: terra vermelha quase sem grama
		if DR[c] >= dmin:
			target *= 0.35                      # sulco da enxurrada: a água corrente não deixa a grama fechar
		if w > 0.15:
			target = 0.0
		var rate := grow if target > CV[c] else grow * (3.0 if w > 0.15 else 0.6)
		CV[c] = move_toward(CV[c], target, rate)

	gw = G; spring = SP; clay = CL; sand = SA; sus = S; cover = CV; wetmem = WM; wat = Wt
	feld = FE; mica = MI; kao = KA; ili = IL; sme = SM
	bed = BD; bank = BK; top = TP; murk = MK
	_shore_timer += 1
	if _shore_timer >= 30:
		_shore_timer = 0
		_update_shore()


## Jazidas de argila: poucos pontos na beira das lagoas, longe uns dos outros.
## Cada jazida é uma mancha de uns 15 a 20 m de terra avermelhada.
func _place_deposits(rng: RandomNumberGenerator) -> void:
	deposit.fill(0.0)
	var cands := []
	for i in N:
		if shore[i] > 0.0 and ter[i] / max_h < 0.5:
			cands.append(i)
	if cands.is_empty():
		for i in N:
			if wetmem[i] > 0.3 and wat[i] < 0.05:
				cands.append(i)
	for k in cands.size():
		var j := rng.randi_range(k, cands.size() - 1)
		var t = cands[k]; cands[k] = cands[j]; cands[j] = t
	var picked := []
	for c in cands:
		if picked.size() >= DEPOSITS:
			break
		var cx: int = c % W; var cy: int = c / W
		var far := true
		for p in picked:
			if Vector2(cx - p % W, cy - p / W).length() < 28.0:
				far = false
				break
		if far:
			picked.append(c)
	for c in picked:
		var cx: int = c % W; var cy: int = c / W
		var r := rng.randf_range(1.6, 2.3)
		for y in range(maxi(0, cy - 3), mini(H, cy + 4)):
			for x in range(maxi(0, cx - 3), mini(W, cx + 4)):
				var d := Vector2(x - cx, y - cy).length() / r
				var v := clampf(1.15 - d, 0.0, 1.0)
				if bed[y * W + x] > 0.5:
					v = 0.0   # dentro da lagoa não; só na terra da margem
				deposit[y * W + x] = maxf(deposit[y * W + x], v)


## Beira da lagoa: célula seca, fora do leito, a até 2 células (10 m) de um leito.
## Calculada com um máximo em duas passadas (linhas e depois colunas).
func _update_shore() -> void:
	var B := bed
	var Wt := wat
	var T := ter
	var mh := max_h
	var rows := PackedFloat32Array()
	rows.resize(N)
	for y in H:
		for x in W:
			var m := 0.0
			for dx in range(maxi(0, x - 2), mini(W, x + 3)):
				m = maxf(m, B[y * W + dx])
			rows[y * W + x] = m
	var S := PackedFloat32Array()
	S.resize(N)
	for y in H:
		for x in W:
			var i := y * W + x
			if B[i] >= 0.45 or Wt[i] >= 0.05 or T[i] / mh > 0.7:
				continue
			var m := 0.0
			for dy in range(maxi(0, y - 2), mini(H, y + 3)):
				m = maxf(m, rows[dy * W + x])
			if m > 0.5:
				S[i] = 1.0
	shore = S
