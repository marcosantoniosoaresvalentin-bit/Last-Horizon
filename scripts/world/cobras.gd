extends Node3D
## Jararaca (Bothrops atrox): a cobra do chão da mata.
##
## Vida (um dia de cada vez, mesmo longe do jogador):
## - Sem lugar fixo: fica de tocaia nas moitas (capim alto, pé de árvore, folhas) e de
##   vez em quando muda de moita (anda pouco: umas dezenas de metros por dia).
## - Come os bichinhos do chão (ratos, lagartos, sapos): tem comida para um tanto de
##   cobras no mapa; passou disso, a fome segura (morrem as mais fracas, nascem menos).
## - Pare os filhotes vivos no começo das chuvas (6 a 15 de uma vez); a maioria morre
##   pequena (gavião, outros bichos). Vive uns 10 a 15 anos.
## - Pica os outros bichos que passam do lado: tamanduá, macaco que desce no chão e arara
##   comendo no chão. A picada mata o bicho.
##
## Perto do jogador:
## - Enrolada, parada, camuflada nas folhas; põe a língua para fora de vez em quando.
## - Alguém chegando (a uns 4 m): levanta o pescoço em S, chia e treme o rabo nas folhas.
## - Bem perto (a 1,2 m): dá o bote. Nem sempre acerta (uns 55%). Depois volta a se
##   enrolar e, se o jogador continua perto, dá outro bote.

const Sons := preload("res://scripts/sons.gd")
const START := 26
const VIDA_MIN := 3650
const VIDA_MAX := 5475
const ADULTA := 900               # dias
const SHOW := 40.0                # perto assim do jogador aparece
const ALERTA := 4.0
const BOTE := 1.2
const ACERTO := 0.55
const PASSEIO := 40.0             # m que muda de moita num dia (no máximo)

## Cobra: {id, nasc, vida, x, z, yaw, s (tamanho), mae (prenha: dia do parto ou -1)}
var cobras: Array = []
var last_day := 0
var _next_id := 1
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _agents := {}                 # id -> {node, modo, t, bote, alvo, cd, lingua, ...}
var _mat: StandardMaterial3D


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 3301
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.55
	_mat.metallic_specular = 0.35
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if save_path == "" or not _load(save_path):
		_generate()
	last_day = int(_jogo.sim.elapsed_days())


func _generate() -> void:
	var day := int(_jogo.sim.elapsed_days())
	var tries := 0
	while cobras.size() < START and tries < START * 20:
		tries += 1
		var p := _moita_qualquer()
		if p == Vector2.INF:
			continue
		var ag := _rng.randi_range(200, 3000)
		cobras.append(_nova(day - ag, p.x, p.y))


func _nova(nasc: int, x: float, z: float) -> Dictionary:
	var c := {"id": _next_id, "nasc": nasc, "vida": _rng.randi_range(VIDA_MIN, VIDA_MAX), "x": x, "z": z,
		"yaw": _rng.randf() * TAU, "mae": -1}
	_next_id += 1
	return c


## Um lugar bom para a cobra no mapa: seco, fora da praia, perto de capim ou de árvore.
func _moita_qualquer() -> Vector2:
	var cap = _jogo._capins
	if cap and not cap.items.is_empty() and _rng.randf() < 0.6:
		var it: Dictionary = cap.items[_rng.randi() % cap.items.size()]
		return Vector2(float(it.x) + _rng.randf_range(-1.5, 1.5), float(it.z) + _rng.randf_range(-1.5, 1.5))
	var arv = _jogo._arvores
	if arv and not arv.plants.is_empty():
		var p: Array = arv.plants[_rng.randi() % arv.plants.size()]
		var a := _rng.randf() * TAU
		var x := float(p[0]) + cos(a) * _rng.randf_range(1.0, 4.0)
		var z := float(p[1]) + sin(a) * _rng.randf_range(1.0, 4.0)
		if _seco(x, z):
			return Vector2(x, z)
	return Vector2.INF


func _seco(x: float, z: float) -> bool:
	var sim = _jogo.sim
	var c := Vector2i(int(x / _jogo.CELL), int(z / _jogo.CELL))
	if c.x < 0 or c.y < 0 or c.x >= sim.W or c.y >= sim.H:
		return false
	var i: int = c.y * sim.W + c.x
	return float(sim.wat[i]) < 0.05 and float(sim.ter[i]) > sim.SEA + 0.3


## Moita perto (para onde muda): capim alto ou pé de árvore até r metros.
func _moita_perto(x: float, z: float, r: float) -> Vector2:
	for k in 8:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(r * 0.3, r)
		var px := x + cos(a) * d
		var pz := z + sin(a) * d
		if _seco(px, pz):
			return Vector2(px, pz)
	return Vector2(x, z)


# ================== A VIDA (POR DIA) ==================

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


static func _month(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


## Quantas cobras os bichinhos do chão do mapa sustentam.
func _comida() -> float:
	var n := 40.0
	if _jogo._capins:
		n += _jogo._capins.items.size() * 0.04
	if _jogo._arvores:
		n += _jogo._arvores.plants.size() * 0.05
	return n


func _day(day: int) -> void:
	var month := _month(day)
	var aperto := clampf((cobras.size() - _comida()) / _comida(), 0.0, 2.0)
	var keep := []
	var born := []
	for c in cobras:
		var ag := day - int(c.nasc)
		if ag > int(c.vida):
			continue                                  # morreu de velha
		if ag < 365 and _rng.randf() < 0.006:
			continue                                  # filhote: gavião, outros bichos
		if aperto > 0.0 and _rng.randf() < 0.003 * aperto:
			continue                                  # pouca comida para tantas
		# muda de moita de vez em quando (as que não estão na tela)
		if not _agents.has(int(c.id)) and _rng.randf() < 0.35:
			var p := _moita_perto(float(c.x), float(c.z), PASSEIO)
			c.x = p.x
			c.z = p.y
			c.yaw = _rng.randf() * TAU
		# fêmea adulta: prenha no fim das secas, pare no começo das chuvas
		if ag >= ADULTA and int(c.id) % 2 == 0:
			if int(c.mae) >= 0:
				if day >= int(c.mae):
					c.mae = -1
					var nf := _rng.randi_range(6, 15)
					for k in nf:
						var f := _nova(day, float(c.x) + _rng.randf_range(-2, 2), float(c.z) + _rng.randf_range(-2, 2))
						born.append(f)
			elif month >= 7 and month <= 9 and _rng.randf() < 0.01 * (1.0 - minf(aperto, 1.0)):
				c.mae = day + _rng.randi_range(100, 140)
		keep.append(c)
	keep.append_array(born)
	cobras = keep
	# picam os outros bichos que passam (longe do jogador também)
	_picadas_do_dia()


func _picadas_do_dia() -> void:
	var n := float(cobras.size())
	var tam = _jogo._tamanduas
	if tam:
		for b in tam.bichos.duplicate():
			if _rng.randf() < 0.00004 * n:
				tam.matar(int(b.id))
	var mac = _jogo._macacos
	if mac:
		for t in mac.troops:
			var mem: Array = t.membros
			if not mem.is_empty() and _rng.randf() < 0.00002 * n * mem.size():
				mem.remove_at(_rng.randi() % mem.size())
	var ara = _jogo._araras
	if ara and not ara.birds.is_empty() and _rng.randf() < 0.00003 * n * ara.birds.size():
		ara.matar(int(ara.birds[_rng.randi() % ara.birds.size()].id))


# ================== NA TELA ==================

func _idade_s(c: Dictionary) -> float:
	var ag := float(last_day - int(c.nasc))
	return clampf(0.35 + ag / 900.0 * 0.65, 0.35, 1.0)


func update(delta: float) -> void:
	var pp: Vector3 = _jogo._player.global_position
	var seen := {}
	for c in cobras:
		var cp := Vector2(float(c.x), float(c.z))
		if cp.distance_to(Vector2(pp.x, pp.z)) > SHOW:
			continue
		var id := int(c.id)
		seen[id] = true
		var a = _agents.get(id)
		if a == null:
			var mi := MeshInstance3D.new()
			mi.mesh = ImmediateMesh.new()
			mi.material_override = _mat
			add_child(mi)
			a = {"node": mi, "modo": "enrolada", "t": _rng.randf() * 10.0, "bote": -1.0, "cd": 0.0,
				"lingua": _rng.randf_range(1.0, 4.0), "som": _rng.randf_range(0.0, 2.0), "andar": _rng.randf_range(20.0, 60.0), "alvo": Vector2.INF}
			_agents[id] = a
		_agent(c, a, pp, delta)
	for id in _agents.keys():
		if not seen.has(id):
			(_agents[id].node as Node).queue_free()
			_agents.erase(id)


func _agent(c: Dictionary, a: Dictionary, pp: Vector3, delta: float) -> void:
	a.t = float(a.t) + delta
	a.cd = maxf(0.0, float(a.cd) - delta)
	var pos := Vector3(float(c.x), _jogo.height_at(float(c.x), float(c.z)), float(c.z))
	# quem está perto: o jogador ou um tamanduá passando
	var alvo := Vector3.INF
	var alvo_tam := -1
	var dj := Vector2(pp.x - pos.x, pp.z - pos.z).length()
	if bool(_jogo.vivo()):
		alvo = pp
	var tam = _jogo._tamanduas
	if tam:
		for tid in tam._agents:
			var b: Dictionary = tam._find(int(tid))
			if b.is_empty():
				continue
			var dt := Vector2(float(b.x) - pos.x, float(b.z) - pos.z).length()
			if dt < dj and dt < ALERTA:
				dj = dt
				alvo = Vector3(float(b.x), pos.y, float(b.z))
				alvo_tam = int(tid)
	var s := _idade_s(c)
	var modo := str(a.modo)
	if float(a.bote) >= 0.0:
		# o bote: o pescoço estica até o alvo e volta
		a.bote = float(a.bote) + delta
		if float(a.bote) >= 0.12 and not bool(a.get("mordeu", false)):
			a.mordeu = true
			var acertou: bool = _rng.randf() < ACERTO and float(a.get("dist_bote", 9.0)) < BOTE + 0.2
			if acertou:
				if int(a.get("alvo_tam", -1)) >= 0:
					if tam:
						tam.matar(int(a.alvo_tam))
				else:
					_jogo.picada_de_cobra()
		if float(a.bote) > 0.45:
			a.bote = -1.0
			a.mordeu = false
			a.cd = _rng.randf_range(1.6, 3.0)
	elif alvo != Vector3.INF and dj < BOTE and float(a.cd) <= 0.0:
		a.bote = 0.0
		a.dist_bote = dj
		a.alvo_tam = alvo_tam
		a.alvo3 = alvo
		c.yaw = atan2(-(alvo.z - pos.z), alvo.x - pos.x)
		Sons.play_at(self, "cobra_bote", pos + Vector3.UP * 0.2, 0.0, _rng.randf_range(0.92, 1.1), 40.0, 4.0)
	elif alvo != Vector3.INF and dj < ALERTA * s + 1.0:
		if modo != "alerta":
			a.modo = "alerta"
			a.som = 0.0
		c.yaw = lerp_angle(float(c.yaw), atan2(-(alvo.z - pos.z), alvo.x - pos.x), minf(1.0, delta * 3.0))
		a.som = float(a.som) - delta
		if float(a.som) <= 0.0:
			Sons.play_at(self, "cobra_chiado" if _rng.randf() < 0.65 else "cobra_rabo", pos + Vector3.UP * 0.2, 0.0, _rng.randf_range(0.9, 1.1), 35.0, 3.0)
			a.som = _rng.randf_range(1.6, 3.2)
	else:
		if modo == "alerta":
			a.modo = "enrolada"
		# de vez em quando muda de moita (anda devagar, se arrastando)
		a.andar = float(a.andar) - delta
		if str(a.modo) == "enrolada" and float(a.andar) <= 0.0:
			var to := _moita_perto(float(c.x), float(c.z), 8.0)
			a.alvo = to
			a.modo = "andando"
		if str(a.modo) == "andando":
			var to2: Vector2 = a.alvo
			var v := to2 - Vector2(float(c.x), float(c.z))
			if v.length() < 0.2:
				a.modo = "enrolada"
				a.andar = _rng.randf_range(30.0, 90.0)
			else:
				var stp := minf(v.length(), 0.25 * delta)
				var np := Vector2(float(c.x), float(c.z)) + v.normalized() * stp
				if _seco(np.x, np.y):
					c.x = np.x
					c.z = np.y
					c.yaw = lerp_angle(float(c.yaw), atan2(-v.y, v.x), minf(1.0, delta * 2.0))
				else:
					a.modo = "enrolada"
		# a língua de vez em quando (e um chiadinho bem baixo, de perto)
		a.lingua = float(a.lingua) - delta
		if float(a.lingua) < -0.5:
			a.lingua = _rng.randf_range(2.0, 6.0)
	_desenha(c, a, pos, s)


## O corpo: um tubo ao longo da espinha (grosso no meio, fino no pescoço e no rabo), cor
## de folha seca com as manchas escuras em "V" da jararaca dos lados e a barriga clara;
## a cabeça larga e triangular; a língua bifurcada vermelha de vez em quando.
func _desenha(c: Dictionary, a: Dictionary, pos: Vector3, s: float) -> void:
	var L := 1.25 * s
	var spine := _espinha(c, a, L)
	var im: ImmediateMesh = (a.node as MeshInstance3D).mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.5, 0.39, 0.26)
	var escuro := Color(0.16, 0.11, 0.07)
	var barriga := Color(0.78, 0.72, 0.52)
	var segs := 8
	var n := spine.size()
	var rings := []
	for i in n:
		var u := float(i) / (n - 1)          # 0 = cabeça, 1 = ponta do rabo
		var r := 0.032 * s * (0.55 + 0.75 * sin(clampf(u * 1.15 + 0.08, 0.0, 1.0) * PI))
		if u > 0.75:
			r *= lerpf(1.0, 0.18, (u - 0.75) / 0.25)
		var p: Vector3 = spine[i]
		var fwd: Vector3 = (spine[maxi(i - 1, 0)] - spine[mini(i + 1, n - 1)]).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(fwd).normalized()
		var ring := []
		for k in segs:
			var ang := TAU * k / segs
			var off := side * cos(ang) * r + up * sin(ang) * r * 0.85
			var col := base
			var lado := absf(cos(ang))
			if sin(ang) < -0.35:
				col = barriga
			else:
				# as manchas em "V"/trapézio escuro dos lados, alternando
				var faixa := fmod(u * 22.0 + (0.5 if cos(ang) > 0.0 else 0.0), 1.0)
				if faixa < 0.38 and lado > 0.25:
					col = escuro
				elif faixa < 0.5 and lado > 0.25:
					col = base.lerp(Color(0.85, 0.72, 0.5), 0.5)     # a borda clara da mancha
			ring.append([p + off, col])
		rings.append(ring)
	for i in n - 1:
		for k in segs:
			var k2 := (k + 1) % segs
			var q := [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]]
			for idx in [0, 1, 2, 0, 2, 3]:
				im.surface_set_color(q[idx][1])
				im.surface_add_vertex(q[idx][0])
	# a cabeça: triangular e achatada, os olhos escuros
	var h0: Vector3 = spine[0]
	var hd: Vector3 = (spine[0] - spine[2]).normalized()
	var hs := hd.cross(Vector3.UP).normalized()
	var hu := hs.cross(hd).normalized()
	var w := 0.05 * s
	var ponta := h0 + hd * 0.06 * s
	var tri := [h0 - hs * w + hu * 0.012 * s, h0 + hs * w + hu * 0.012 * s, ponta + hu * 0.008 * s,
		h0 - hs * w - hu * 0.01 * s, h0 + hs * w - hu * 0.01 * s, ponta - hu * 0.006 * s]
	for f in [[0, 1, 2], [3, 5, 4], [0, 2, 5, 0, 5, 3], [1, 4, 5, 1, 5, 2], [0, 3, 4, 0, 4, 1]]:
		for idx in f:
			im.surface_set_color(base.darkened(0.15) if idx < 3 else barriga)
			im.surface_add_vertex(tri[idx])
	for sg in [-1.0, 1.0]:
		var e: Vector3 = h0 + hs * float(sg) * w * 0.62 + hd * 0.012 * s + hu * 0.014 * s
		for v in [e, e + hd * 0.008 * s, e + hu * 0.006 * s]:
			im.surface_set_color(Color(0.05, 0.04, 0.03))
			im.surface_add_vertex(v)
	# a língua bifurcada (de vez em quando, e sempre no alerta)
	if float(a.lingua) < 0.0 or str(a.modo) == "alerta":
		var lp := ponta + hu * 0.0
		var lt := lp + hd * 0.045 * s
		var tw := 0.0035 * s
		for seg in [[lp, lt], [lt, lt + (hd + hs * 0.6).normalized() * 0.015 * s], [lt, lt + (hd - hs * 0.6).normalized() * 0.015 * s]]:
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			for v in [p0 - hs * tw, p1 - hs * tw, p1 + hs * tw, p0 - hs * tw, p1 + hs * tw, p0 + hs * tw]:
				im.surface_set_color(Color(0.75, 0.08, 0.12))
				im.surface_add_vertex(v)
	im.surface_end()


## A linha do corpo agora (da cabeça para o rabo), no mundo.
func _espinha(c: Dictionary, a: Dictionary, L: float) -> Array:
	var pos := Vector3(float(c.x), 0, float(c.z))
	var yaw := float(c.yaw)
	var fwd := Vector3(cos(yaw), 0, -sin(yaw))
	var side := Vector3(sin(yaw), 0, cos(yaw))
	var t := float(a.t)
	var n := 26
	var pts := []
	var modo := str(a.modo)
	var bote := float(a.bote)
	for i in n:
		var u := float(i) / (n - 1)
		var p: Vector3
		if modo == "andando" and bote < 0.0:
			# se arrastando em S, a onda correndo do pescoço para o rabo
			var sdist := u * L
			p = pos - fwd * sdist + side * sin(sdist * 9.0 - t * 6.0) * 0.07 * (0.3 + u)
		else:
			# enrolada: o corpo em espiral no chão; o pescoço sai do meio
			var neck := 0.3
			if u > neck:
				var k := (u - neck) / (1.0 - neck)
				var ang := yaw + PI + k * TAU * 1.6
				var rr := lerpf(0.06, 0.17, k) * L / 1.25
				p = pos + Vector3(cos(ang) * rr, 0, -sin(ang) * rr)
			else:
				var k2 := u / neck                      # 0 = cabeça, 1 = onde entra no rolo
				var start := pos + Vector3(cos(yaw + PI) * 0.06, 0, -sin(yaw + PI) * 0.06) * L / 1.25
				var lift := 0.0
				var ahead := 0.0
				if modo == "alerta" or bote >= 0.0:
					lift = sin((1.0 - k2) * PI * 0.5) * 0.16 * L / 1.25     # pescoço em S levantado
					ahead = (1.0 - k2) * 0.12 * L / 1.25
				if bote >= 0.0:
					var e := sin(clampf(bote / 0.45, 0.0, 1.0) * PI)      # estica e volta
					ahead += (1.0 - k2) * e * float(a.get("dist_bote", 1.0)) * 0.85
					lift *= 1.0 - e * 0.7
				var sway := sin(t * 1.3) * 0.015 * (1.0 - k2)
				p = start + fwd * (ahead + (1.0 - k2) * 0.08) + side * (sin(k2 * PI * 1.4) * 0.05 * L / 1.25 + sway) + Vector3.UP * lift
		var y: float = _jogo.height_at(p.x, p.z)
		pts.append(Vector3(p.x, maxf(p.y, 0.0) + y + 0.025, p.z))
	return pts


## Morre (picada não; outro bicho, ou o jogador matou).
func matar(id: int) -> void:
	for i in cobras.size():
		if int(cobras[i].id) == id:
			cobras.remove_at(i)
			break


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "prox": _next_id, "cobras": cobras}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	cobras = d.get("cobras", [])
	_next_id = int(d.get("prox", 1))
	last_day = int(d.get("dia", 0))
	return true


func _rebuild() -> void:
	pass                              # (chegou de outro jogador: as que estão na tela se refazem sozinhas)


func count() -> int:
	return cobras.size()
