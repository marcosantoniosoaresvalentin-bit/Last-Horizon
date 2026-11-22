extends RefCounted
## Sons do jogo: gravações reais (domínio público, CC0) na pasta sons/:
##  - machadada: "Ax on log" (Joseph Sardin, BigSoundBank.com, CC0)
##  - árvore caindo e baque: "Tree chop fall thud" (OpenGameArt, CC0)
##  - madeira rachando: Independent nu ljudbank, wood crack (OpenGameArt, CC0)
##  - cavadeira: "Shovel sound" (OpenGameArt, CC0)
##  - passos: Fantozzi's footsteps, terra/areia (OpenGameArt, CC0)
##  - água: qubodup, 6 short water splashes (OpenGameArt, CC0)
##  - pedra batendo, lascando e rachando: rubberduck, "75 CC0 breaking / falling / hit sfx" (OpenGameArt, CC0)
##  - serra: "Saw wood" (Joseph Sardin, BigSoundBank.com, CC0), cada passada separada
## Se algum arquivo faltar, usa um som gerado em código no lugar.

const RATE := 22050
const FILES := {
	"machado": ["machado1", "machado2", "machado3", "machado4"],
	"corrida": ["corrida1", "corrida2", "corrida3", "corrida4", "corrida5", "corrida6"],
	"estalo": ["estalo1", "estalo2"],
	"queda": ["queda1"],
	"cavar": ["cavar1"],
	"passo": ["passo1", "passo2", "passo3", "passo4", "passo5", "passo6"],
	"agua": ["agua1", "agua2", "agua4", "agua5"],
	"baque": ["baque1"],
	"serra": ["serra1", "serra2", "serra3", "serra4", "serra5", "serra6"],
	"pedra_bate": ["pedra_bate1", "pedra_bate2", "pedra_bate3", "pedra_bate4"],
	"pedra_lasca": ["pedra_lasca1", "pedra_lasca2"],
	"pedra_racha": ["pedra_racha1"],
	# araras: gritos reais de papagaios grandes (BigSoundBank, CC0); macacos: sintetizados (tools/sintetizar_bichos.py)
	"arara_voo": ["arara_voo1", "arara_voo2", "arara_voo3", "arara_voo4"],
	"arara_alarme": ["arara_alarme1", "arara_alarme2"],
	"arara_resmungo": ["arara_resmungo1", "arara_resmungo2", "arara_resmungo3"],
	"macaco_assobio": ["macaco_assobio1", "macaco_assobio2", "macaco_assobio3", "macaco_assobio4", "macaco_assobio5"],
	"macaco_trinado": ["macaco_trinado1", "macaco_trinado2", "macaco_trinado3"],
	"macaco_alarme": ["macaco_alarme1", "macaco_alarme2", "macaco_alarme3"],
	"macaco_guincho": ["macaco_guincho1", "macaco_guincho2"],
	# folha de buriti caindo e o talo sendo cortado (sintetizados: tools/sintetizar_folha.py)
	"folha_cai": ["folha_cai1", "folha_cai2", "folha_cai3"],
	"talo_corte": ["talo_corte1", "talo_corte2", "talo_corte3"],
	"fibra_puxa": ["fibra_puxa1", "fibra_puxa2", "fibra_puxa3", "fibra_puxa4"],
	"fibra_bate": ["fibra_bate1", "fibra_bate2", "fibra_bate3"],
	"serra_corte": ["serra_corte1", "serra_corte2", "serra_corte3", "serra_corte4"],
	"pedal_range": ["pedal_range1", "pedal_range2", "pedal_range3"],
	# a cobra (sintetizados: tools/sintetizar_cobra.py)
	"cobra_chiado": ["cobra_chiado1", "cobra_chiado2", "cobra_chiado3"],
	"cobra_rabo": ["cobra_rabo1", "cobra_rabo2"],
	"cobra_bote": ["cobra_bote1", "cobra_bote2"],
	# a doença da água suja (sintetizados: tools/sintetizar_doenca.py)
	"barriga_ronco": ["barriga_ronco1", "barriga_ronco2", "barriga_ronco3"],
	"gases": ["gases1", "gases2", "gases3"],
}
## Volume de cada som (dB): passos baixos e a água bem baixinha.
const VOLUME := {"machado": 0.0, "corrida": -12.0, "estalo": 0.0, "queda": 2.0, "cavar": -2.0, "passo": -10.0, "agua": -18.0, "baque": -3.0, "serra": -9.0, "pedra_bate": -4.0, "pedra_lasca": -3.0, "pedra_racha": 0.0,
	"arara_voo": 2.0, "arara_alarme": 3.0, "arara_resmungo": -8.0, "macaco_assobio": -6.0, "macaco_trinado": -7.0,
	"macaco_alarme": -1.0, "macaco_guincho": -2.0, "folha_cai": 2.0, "talo_corte": -2.0, "fibra_puxa": -1.0, "fibra_bate": -2.0, "serra_corte": -1.0, "pedal_range": -6.0,
	"cobra_chiado": -4.0, "cobra_rabo": -6.0, "cobra_bote": -2.0, "barriga_ronco": -6.0, "gases": -8.0}

static var _cache := {}


## Um som pelo nome (variação sorteada): "machado", "estalo", "queda", "cavar", "passo", "agua", "baque".
static func pick(name: String) -> AudioStream:
	if not _cache.has(name):
		var arr := []
		for f in FILES.get(name, []):
			var bytes := FileAccess.get_file_as_bytes("res://sons/%s.somog" % f)
			if not bytes.is_empty():
				var st := AudioStreamOggVorbis.load_from_buffer(bytes)
				if st:
					arr.append(st)
		if arr.is_empty():
			arr = _make_set(name)
		_cache[name] = arr
	var arr: Array = _cache[name]
	return arr[randi() % arr.size()]


## Toca um som num ponto do mundo (o volume cai com a distância).
static func play_at(parent: Node, name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 90.0, unit := 6.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = pick(name)
	p.volume_db = volume_db + float(VOLUME.get(name, 0.0))
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.unit_size = unit
	p.max_distance = max_dist
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


static func _make_set(name: String) -> Array:
	var out := []
	var n := 4 if name in ["machado", "passo", "agua", "cavar"] else 2
	for v in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name) + v * 977
		var s: PackedFloat32Array
		match name:
			"machado": s = _chop(rng)
			"estalo": s = _crack(rng)
			"queda": s = _fall(rng)
			"cavar": s = _dig(rng)
			"passo", "corrida": s = _step(rng)
			"agua": s = _splash(rng)
			_: s = _thud(rng)
		out.append(_wav(s))
	return out


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


# ---------- sons ----------

## Machadada: pancada grave + estalo da madeira + ressonância do tronco.
static func _chop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.45)
	var lp := 0.0
	var f0 := rng.randf_range(95.0, 125.0)
	var res := rng.randf_range(330.0, 460.0)
	var ph := 0.0
	var ph2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := f0 * (1.0 - 0.35 * minf(t / 0.08, 1.0))
		ph += TAU * f / RATE
		ph2 += TAU * res / RATE
		var thump := sin(ph) * exp(-t / 0.07)
		var n := rng.randf_range(-1.0, 1.0)
		lp += 0.35 * (n - lp)
		var click := (n - lp) * exp(-t / 0.012) * 0.9
		var ring := sin(ph2) * exp(-t / 0.09) * 0.35
		var chips := lp * exp(-t / 0.05) * 0.5
		s[i] = (thump * 0.9 + click + ring + chips) * 0.8
	return s


## Madeira quebrando: estalos cada vez mais perto uns dos outros e um rangido grave.
static func _crack(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(1.6)
	var ph := 0.0
	var next := 0.0
	var env := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := t / 1.6
		if t >= next:
			env = rng.randf_range(0.4, 1.0)
			next = t + lerpf(0.18, 0.025, u) * rng.randf_range(0.5, 1.5)
		env *= 0.993
		var crackle := rng.randf_range(-1.0, 1.0) * env * env
		var f := lerpf(85.0, 55.0, u) + sin(t * 31.0) * 6.0
		ph += TAU * f / RATE
		var saw := (fmod(ph / TAU, 1.0) * 2.0 - 1.0) * 0.35 * sin(u * PI) * (0.6 + 0.4 * sin(t * 13.0))
		s[i] = (crackle * 0.7 + saw) * 0.8
	return s


## Árvore batendo no chão: baque fundo + galhos e folhas chiando.
static func _fall(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(2.2)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(55.0, 32.0, minf(t / 0.6, 1.0)) / RATE
		var boom := sin(ph) * exp(-t / 0.45)
		var n := rng.randf_range(-1.0, 1.0)
		lp += 0.08 * (n - lp)
		var rumble := lp * 3.0 * exp(-t / 0.35)
		lp2 += 0.5 * (n - lp2)
		var leaves := (n - lp2) * 0.35 * exp(-t / 0.9) * (0.7 + 0.3 * sin(t * 40.0))
		var snaps := 0.0
		if rng.randf() < 0.0015 * exp(-t / 0.8):
			snaps = rng.randf_range(-1.0, 1.0)
		s[i] = (boom + rumble + leaves + snaps * 0.6) * 0.75
	return s


## Cavadeira na terra: a pedra entrando (baque) + terra arranhando e caindo.
static func _dig(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.6)
	var lp := 0.0
	var ph := 0.0
	var grit := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * 75.0 / RATE
		var thud := sin(ph) * exp(-t / 0.05) * 0.7
		var n := rng.randf_range(-1.0, 1.0)
		lp += 0.18 * (n - lp)
		if rng.randf() < 0.02:
			grit = rng.randf_range(0.5, 1.0)
		grit *= 0.996
		var crunch := lp * 2.2 * (0.4 + grit) * exp(-t / 0.18)
		var fall := 0.0
		if t > 0.25:
			fall = lp * 1.2 * exp(-(t - 0.25) / 0.12) * grit
		s[i] = (thud + crunch + fall) * 0.8
	return s


## Passo no chão de terra e capim: batida abafada curtinha + capim.
static func _step(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.16)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var f := rng.randf_range(55.0, 75.0)
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * f / RATE
		var thump := sin(ph) * exp(-t / 0.025)
		var n := rng.randf_range(-1.0, 1.0)
		lp += 0.12 * (n - lp)
		lp2 += 0.6 * (n - lp2)
		var grass := (n - lp2) * 0.18 * exp(-t / 0.05)
		s[i] = (thump * 0.6 + lp * 1.6 * exp(-t / 0.03) + grass) * 0.7
	return s


## Passo na água: respingo + bolhinhas.
static func _splash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.45)
	var lp := 0.0
	var ph := 0.0
	var bub_f := 0.0
	var bub_t := 1.0
	for i in s.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		lp += 0.4 * (n - lp)
		var splash := (n - lp * 0.7) * exp(-t / 0.08) * (0.6 + 0.4 * sin(t * 90.0))
		bub_t += 1.0 / RATE
		if bub_t > rng.randf_range(0.03, 0.09):
			bub_t = 0.0
			bub_f = rng.randf_range(500.0, 1300.0)
		ph += TAU * bub_f * (1.0 + bub_t * 8.0) / RATE
		var bubble := sin(ph) * exp(-bub_t / 0.015) * 0.25 * exp(-t / 0.25)
		s[i] = (splash * 0.55 + bubble) * 1.4
	return s


## Baque de madeira no chão (largar tora).
static func _thud(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.4)
	var ph := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(90.0, 60.0, minf(t / 0.1, 1.0)) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		lp += 0.15 * (n - lp)
		s[i] = (sin(ph) * exp(-t / 0.09) + lp * exp(-t / 0.05)) * 0.8
	return s
