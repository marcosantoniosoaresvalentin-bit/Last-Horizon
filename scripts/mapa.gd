extends Control
## Mapa Vivo: gera um mapa com uma serra e simula a chuva.
## A água escorre morro abaixo, empoça nas baixadas formando lagoas,
## infiltra no solo e brota de novo como nascente no pé da serra.
##
## A simulação roda numa thread separada para não travar a tela.

const W := 100
const H := 75
const N := W * H
const SC := 200.0 / W           # escala para manter as proporções do gerador
const GW_CAP := 1.6             # quanta água o solo segura
const STEPS_DAY := 360
const STEPS_PER_SEC := 12.0
const STEP_MULT := 2.5           # cada passo vale 2,5 passos de tempo

# --- dados da simulação (só a thread mexe neles) ---
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
var _pixels := PackedByteArray()

# --- comunicação entre a tela e a thread ---
var _thread := Thread.new()
var _mx := Mutex.new()
var _quit := false
var _regen := true
var _generating := true
var raining := false
var user_rain := 0
var speed := 1
var layer := 0                  # 0 natural, 1 relevo, 2 solo
var sel := Vector2i(-1, -1)
var _out_pixels := PackedByteArray()
var _out_new := false
var _out_stats := {}
var _out_info := ""

# --- interface ---
var _img: Image
var _tex: ImageTexture
var _map: TextureRect
var _overlay: Control
var _weather: Label
var _stats: Label
var _info: Label
var _status: Label


func _ready() -> void:
	ter.resize(N); wat.resize(N); gw.resize(N); moist.resize(N)
	fl.resize(N); fr.resize(N); ft.resize(N); fb.resize(N)
	shade.resize(N); spring.resize(N)
	_pixels.resize(N * 3)
	_build_ui()
	_img = Image.create(W, H, false, Image.FORMAT_RGB8)
	_tex = ImageTexture.create_from_image(_img)
	_map.texture = _tex
	_thread.start(_sim_loop)


func _exit_tree() -> void:
	_quit = true
	if _thread.is_started():
		_thread.wait_to_finish()


# ================== INTERFACE ==================

func _label(text: String, size: int, color := Color(0.91, 0.86, 0.77)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.063, 0.086, 0.059)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16; row.offset_top = 16; row.offset_right = -16; row.offset_bottom = -16
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	var aspect := AspectRatioContainer.new()
	aspect.ratio = float(W) / float(H)
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(aspect)

	_map = TextureRect.new()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.gui_input.connect(_on_map_input)
	aspect.add_child(_map)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_map.add_child(_overlay)

	_status = _label("Gerando o mapa…", 26)
	_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_status.add_theme_constant_override("outline_size", 6)
	_map.add_child(_status)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 10)
	row.add_child(side)

	side.add_child(_label("Mapa Vivo", 30))
	_weather = _label("Tempo seco", 20, Color(0.42, 0.71, 0.84))
	side.add_child(_weather)
	_stats = _label("", 18, Color(0.66, 0.70, 0.60))
	side.add_child(_stats)
	_info = _label("Toque no mapa para ver a altitude, a água e o solo daquele ponto.", 17)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_info)

	side.add_child(_button("Fazer chover", func(): user_rain = 280))

	var sp := HBoxContainer.new()
	for s in [1, 2, 4]:
		var b := _button("%dx" % s, func(): speed = s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.add_child(b)
	side.add_child(sp)

	var ly := HBoxContainer.new()
	var names := ["Natural", "Relevo", "Solo"]
	for k in 3:
		var b := _button(names[k], func(): layer = k)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ly.add_child(b)
	side.add_child(ly)

	side.add_child(_button("Novo mapa", _on_new_map))
	side.add_child(_button("Voltar", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))


func _on_new_map() -> void:
	if _generating:
		return
	_generating = true
	_status.visible = true
	_regen = true


func _on_map_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var p: Vector2 = e.position / _map.size
		sel = Vector2i(clampi(int(p.x * W), 0, W - 1), clampi(int(p.y * H), 0, H - 1))


func _process(_delta: float) -> void:
	_mx.lock()
	if _out_new:
		_img.set_data(W, H, false, Image.FORMAT_RGB8, _out_pixels)
		_tex.update(_img)
		_out_new = false
		_status.visible = _generating
		var s := _out_stats
		if not s.is_empty():
			_weather.text = "Chovendo" if s.raining else "Tempo seco"
			_stats.text = "Dia %d\nÁrea com água: %s%%\nLagoas: %d\nNascentes: %d" % [
				s.day, str(snappedf(s.water, 0.1)).replace(".", ","), s.ponds, s.springs]
		if _out_info != "":
			_info.text = _out_info
	_mx.unlock()
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	var sz := _overlay.size
	if raining:
		for k in 70:
			var p := Vector2(randf() * sz.x, randf() * sz.y)
			_overlay.draw_line(p, p + Vector2(-4, 12), Color(0.8, 0.88, 0.94, 0.35), 1.5)
	if sel.x >= 0:
		var c := Vector2(sel) / Vector2(W, H) * sz
		var cell := sz.x / W
		_overlay.draw_rect(Rect2(c - Vector2.ONE * cell * 2, Vector2.ONE * cell * 5), Color(0.89, 0.66, 0.29), false, 2.0)


# ================== SIMULAÇÃO (thread) ==================

func _sim_loop() -> void:
	var t_last := Time.get_ticks_usec()
	var acc := 0.0
	var loops := 0
	while not _quit:
		if _regen:
			_regen = false
			_generate()
			_generating = false
			_publish(true)
			t_last = Time.get_ticks_usec()
			acc = 0.0
		var now := Time.get_ticks_usec()
		acc += (now - t_last) / 1000000.0 * STEPS_PER_SEC * speed
		t_last = now
		var n := mini(int(acc), 8)
		acc -= n
		if acc > 8.0:
			acc = 0.0
		for k in n:
			_weather_step()
			_step(raining, STEP_MULT)
		loops += 1
		if n > 0:
			_publish(loops % 20 == 0)
		OS.delay_msec(8)


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
	for k in 80:
		_step(true, 9.0)
	for k in 70:
		_step(false, 9.0)
	steps = 0
	raining = false
	dry_t = 250


func _weather_step() -> void:
	if user_rain > 0:
		user_rain -= 1
		raining = true
		return
	if raining:
		rain_t -= 1
		if rain_t <= 0:
			raining = false
			dry_t = 600 + randi() % 1000
	else:
		dry_t -= 1
		if dry_t <= 0:
			raining = true
			rain_t = 200 + randi() % 360


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


# ================== DESENHO E NÚMEROS (thread) ==================

func _build_pixels() -> void:
	var ly := layer
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


func _count(test: Callable, min_size: int, still_only: bool) -> int:
	var seen := PackedByteArray()
	seen.resize(N)
	var count := 0
	for i in N:
		if seen[i] == 1 or not test.call(i):
			continue
		var q := [i]
		seen[i] = 1
		var n := 0
		var flow := 0.0
		while not q.is_empty():
			var c: int = q.pop_back()
			n += 1
			flow += fl[c] + fr[c] + ft[c] + fb[c]
			var x := c % W
			for j in [c - 1 if x > 0 else -1, c + 1 if x < W - 1 else -1, c - W, c + W]:
				if j < 0 or j >= N or seen[j] == 1 or not test.call(j):
					continue
				seen[j] = 1
				q.append(j)
		if n >= min_size and (not still_only or flow / n < 0.05):
			count += 1
	return count


func _cell_info(i: int) -> String:
	var w := wat[i]
	var flow := fl[i] + fr[i] + ft[i] + fb[i]
	var kind := "terra seca"
	if spring[i] > 0.5 and w < 0.3: kind = "nascente"
	elif w > 0.25 and flow < 0.05: kind = "lagoa"
	elif w > 0.05: kind = "córrego correndo"
	elif w > 0.02: kind = "poça"
	elif gw[i] / GW_CAP > 0.85: kind = "solo encharcado"
	var agua := "%d cm" % int(w * 60) if w > 0.02 else "nenhuma"
	return "%d m de altitude\n%s\nÁgua: %s\nSolo %d%% úmido" % [int(ter[i] * 18 + 40), kind[0].to_upper() + kind.substr(1), agua, int(gw[i] / GW_CAP * 100)]


func _publish(with_stats: bool) -> void:
	_build_pixels()
	var stats := {}
	if with_stats:
		var wet := 0
		for i in N:
			if wat[i] > 0.05:
				wet += 1
		stats = {
			"day": steps / STEPS_DAY + 1,
			"water": wet * 100.0 / N,
			"ponds": _count(func(i): return wat[i] >= 0.25, 4, true),
			"springs": _count(func(i): return spring[i] > 0.5 and wat[i] < 0.3, 2, false),
			"raining": raining,
		}
	var info := _cell_info(sel.y * W + sel.x) if sel.x >= 0 else ""
	_mx.lock()
	_out_pixels = _pixels.duplicate()
	_out_new = true
	if with_stats:
		_out_stats = stats
	if info != "":
		_out_info = info
	_mx.unlock()
