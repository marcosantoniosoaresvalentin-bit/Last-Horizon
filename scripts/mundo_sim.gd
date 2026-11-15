extends Node
## Simulação do mundo: gera o terreno com uma serra e cuida do clima.
## A chuva vem sozinha com o tempo. A água escorre morro abaixo, empoça nas
## baixadas formando lagoas, infiltra no solo e brota como nascente no pé
## da serra. Roda numa thread separada para não travar o jogo.

signal world_ready

const W := 128
const H := 96
const N := W * H
const SC := 200.0 / W
const GW_CAP := 1.6
const STEPS_PER_SEC := 8.0
const STEP_MULT := 3.75
const STEPS_DAY := 3840          # um dia de jogo = 8 minutos
const START_HOUR := 7.0

var ter := PackedFloat32Array()
var wat := PackedFloat32Array()
var gw := PackedFloat32Array()
var moist := PackedFloat32Array()
var fl := PackedFloat32Array()
var fr := PackedFloat32Array()
var ft := PackedFloat32Array()
var fb := PackedFloat32Array()
var shade := PackedFloat32Array()
var spring := PackedFloat32Array()
var max_h := 1.0
var steps := 0
var rain_t := 0
var dry_t := 0
var raining := false
var spawn := Vector2i(W / 2, H / 2)
var is_ready := false

var _pixels := PackedByteArray()
var _thread := Thread.new()
var _mx := Mutex.new()
var _quit := false
var _out_pixels := PackedByteArray()
var _out_new := false
var _out_wat := PackedFloat32Array()
var _water_new := false
## Cópias estáveis feitas logo após gerar o mundo (seguras para ler na tela).
var ter0 := PackedFloat32Array()
var moist0 := PackedFloat32Array()
var gw0 := PackedFloat32Array()


func _ready() -> void:
	for a in ["ter", "wat", "gw", "moist", "fl", "fr", "ft", "fb", "shade", "spring"]:
		var arr := PackedFloat32Array()
		arr.resize(N)
		set(a, arr)
	_pixels.resize(N * 3)
	_thread.start(_sim_loop)


func _exit_tree() -> void:
	_quit = true
	if _thread.is_started():
		_thread.wait_to_finish()


## Hora do dia (0 a 24).
func hour() -> float:
	return fmod(START_HOUR + float(steps) / STEPS_DAY * 24.0, 24.0)


func day() -> int:
	return int((START_HOUR / 24.0 + float(steps) / STEPS_DAY)) + 1


## Profundidade da água numa célula (0 se seca).
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


## Devolve os pixels novos do mapa, ou um array vazio se nada mudou.
func take_pixels() -> PackedByteArray:
	var out := PackedByteArray()
	_mx.lock()
	if _out_new:
		out = _out_pixels
		_out_new = false
	_mx.unlock()
	return out


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
		loops += 1
		if n > 0 and loops % 8 == 0:
			_publish()
		OS.delay_msec(15)


func _find_spawn() -> void:
	var best := -1.0
	for k in 400:
		var x := randi_range(8, W - 9)
		var y := randi_range(8, H - 9)
		var i := y * W + x
		var h := ter[i] / max_h
		if wat[i] > 0.02 or h > 0.55:
			continue
		var score := moist[i] + gw[i] * 0.2 - absf(h - 0.3)
		if score > best:
			best = score
			spawn = Vector2i(x, y)


func _publish() -> void:
	var w := wat.duplicate()
	_mx.lock()
	_out_wat = w
	_water_new = true
	_mx.unlock()


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

	# serra: um segmento alongado em algum lugar do meio do mapa
	var ax := 200.0 * (0.25 + rng.randf() * 0.2)
	var ay := 150.0 * (0.25 + rng.randf() * 0.5)
	var ang := rng.randf() * PI
	var length := 200.0 * (0.22 + rng.randf() * 0.15)
	var vx := cos(ang) * length
	var vy := sin(ang) * length
	var tilt := rng.randf() * TAU

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
			ter[y * W + x] = h
			mn = minf(mn, h)
	max_h = 0.0
	for i in N:
		ter[i] -= mn
		max_h = maxf(max_h, ter[i])
	for y in H:
		for x in W:
			var hx := ter[y * W + mini(W - 1, x + 1)] - ter[y * W + maxi(0, x - 1)]
			var hy := ter[mini(H - 1, y + 1) * W + x] - ter[maxi(0, y - 1) * W + x]
			shade[y * W + x] = clampf((-hx - hy) * 0.06, -0.6, 0.6)

	wat.fill(0.0); moist.fill(0.0); spring.fill(0.0)
	fl.fill(0.0); fr.fill(0.0); ft.fill(0.0); fb.fill(0.0)
	gw.fill(GW_CAP * 0.25)
	steps = 0
	# aquece o mundo: chuva forte e depois tempo seco, para já começar com lagoas e córregos
	for k in 70:
		_step(true, 10.0)
	for k in 60:
		_step(false, 10.0)
	steps = 0
	raining = false
	dry_t = 900


func _weather_step() -> void:
	if raining:
		rain_t -= 1
		if rain_t <= 0:
			raining = false
			dry_t = 700 + randi() % 1500
	else:
		dry_t -= 1
		if dry_t <= 0:
			raining = true
			rain_t = 250 + randi() % 450


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
	var mh := max_h
	var evap := (0.00005 if rain_now else 0.0005) * mult
	var rain := 0.0008 * mult
	var inf_max := 0.00025 * mult
	for i in N:
		var w := Wt[i]
		if rain_now:
			w += rain * (0.55 + T[i] / mh * 0.9)
		var room := GW_CAP - G[i]
		if w > 0.0 and room > 0.0:
			var inf := minf(minf(w, inf_max), room)
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

	# água subterrânea: anda devagar morro abaixo e brota onde o solo enche
	if steps % 4 == 0:
		var gm := 0.012 * mult
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
		var loss := 0.00012 * mult
		for c in N:
			SP[c] *= 0.97
			var gc := G[c]
			if gc > GW_CAP * 0.97:
				var out := (gc - GW_CAP * 0.93) * 0.15
				G[c] = gc - out
				Wt[c] += out
				SP[c] = minf(1.0, SP[c] + out * 40.0)
			else:
				G[c] = maxf(0.0, gc - loss)

	wat = Wt; gw = G; fl = L; fr = R; ft = U; fb = D; spring = SP; moist = M
	steps += 1


func _build_pixels() -> void:
	var ly := 0
	for i in N:
		var h := ter[i] / max_h
		var w := wat[i]
		var r: float
		var g: float
		var b: float
		if ly == 1:
			r = lerpf(40, 235, h); g = lerpf(70, 220, h); b = lerpf(40, 190, h)
			if floori(ter[i] / 2.5) != floori((ter[i] + 0.4) / 2.5):
				r *= 0.6; g *= 0.6; b *= 0.6
		elif ly == 2:
			var t := gw[i] / GW_CAP
			r = lerpf(150, 30, t); g = lerpf(110, 90, t); b = lerpf(60, 150, t)
		else:
			var green := minf(1.0, moist[i] * 2.2 + gw[i] / GW_CAP * 0.55)
			if h > 0.78:
				var k := (h - 0.78) * 4.0
				r = lerpf(110, 150, k); g = lerpf(108, 140, k); b = lerpf(92, 125, k)
			else:
				r = lerpf(150, 38, green); g = lerpf(132, 96, green); b = lerpf(78, 40, green)
				if h > 0.6:
					var k := (h - 0.6) / 0.18 * 0.6
					r = lerpf(r, 104, k); g = lerpf(g, 100, k); b = lerpf(b, 84, k)
		var L := 1.0 + shade[i]
		r *= L; g *= L; b *= L
		if w > 0.02 and ly != 2:
			var a := minf(0.9, 0.35 + w * 0.9)
			var deep := minf(1.0, w / 2.2)
			r = lerpf(r, lerpf(110, 28, deep), a)
			g = lerpf(g, lerpf(175, 78, deep), a)
			b = lerpf(b, lerpf(200, 130, deep), a)
		if ly == 0 and spring[i] > 0.5 and w < 0.3:
			r = lerpf(r, 190, 0.6); g = lerpf(g, 235, 0.6); b = lerpf(b, 255, 0.6)
		var p := i * 3
		_pixels[p] = clampi(int(r), 0, 255)
		_pixels[p + 1] = clampi(int(g), 0, 255)
		_pixels[p + 2] = clampi(int(b), 0, 255)
