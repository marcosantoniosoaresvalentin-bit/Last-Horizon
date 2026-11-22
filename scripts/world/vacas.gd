extends Node3D
## Vacas selvagens (gado zebu asselvajado) e o pasto que elas comem.
##
## O PASTO
## - A grama do chão é comida em pedacinhos de 2 m x 2 m: a parte de cima (as folhas
##   verdes) vai embora e fica só a grama curtinha, que rebrota em uns 20 dias.
## - As touceiras de capim alto (as que dão o capim seco do barro) são comidas do mesmo
##   jeito: fica só o toco rente ao chão, rebrotando (igual quando a gente colhe).
## - Onde as vacas comem de novo antes de rebrotar (muitas vacas no mesmo lugar), o pasto
##   vai judiando: depois de várias vezes a grama seca e morre ali (chão pelado). Sem
##   ninguém comer, volta a crescer em uns 2 meses.
##
## AS VACAS (um dia de cada vez, mesmo longe do jogador)
## - Vivem em rebanhos (um touro, as vacas e os bezerros), num pedaço do mapa. Cada uma
##   come uns 120 m² de pasto por dia em volta de onde o rebanho está. Acabou o pasto
##   bom ali, o rebanho muda para outro lugar com mais grama.
## - Sem comida passa fome; muitos dias de fome, morre. Não tem limite de quantas: o
##   pasto é que controla.
## - Cria: vaca adulta (2 anos e meio), bem alimentada, com touro no rebanho, emprenha;
##   o bezerro nasce uns 283 dias depois e segue a mãe até uns 8 meses. Vive uns 18 anos.
##
## PERTO DO JOGADOR
## - Pastam andando devagar, de cabeça baixa (arrancando a grama de verdade); no calor do
##   meio do dia e de noite deitam e ruminam. São bravas (selvagens): gente chegando
##   perto, o rebanho todo foge trotando.

const Modelo := preload("res://scripts/world/vaca_modelo.gd")
const MundoSim := preload("res://scripts/mundo_sim.gd")

# ---- pasto ----
const PRES := 2.0                # m de cada pedacinho de pasto
const PW := 320                  # 640 m / 2
const PH := 240                  # 480 m / 2
const REBROTA := 20              # dias para a grama comida crescer de novo
const JUDIA := 4                 # comida de novo (ainda baixa) tantas vezes seguidas: seca
const RECUPERA := 60             # dias para o pasto seco voltar

# ---- vacas ----
const ADULTA := 900              # dias (2,5 anos)
const GEST := 283
const SEGUE := 240               # o bezerro segue a mãe até aqui
const VIDA := 6500               # uns 18 anos
const FOME_MORRE := 25           # dias de fome seguidos
const COME_DIA := 30             # pedacinhos de pasto (2x2 m) por dia, adulta
const AREA := 28.0               # raio do pedaço onde o rebanho está pastando (m)
const SHOW := 110.0
const WALK := 0.7                # m/s
const TROTE := 3.2
const MEDO := 7.0                # gente mais perto que isso: o rebanho foge

var vacas: Array = []            # {id, sexo, nasc, reb, x, z, mae, prenhe, fome, vida, cor}
var rebanhos: Array = []         # {id, x, z}
var comido := {}                 # Vector2i -> [dia, vezes]
var seco := {}                   # Vector2i -> dia em que secou
var last_day := 0
var _next_id := 1
var _jogo: Node
var _rng := RandomNumberGenerator.new()
var _agents := {}
var _img: Image
var tex: ImageTexture
var _tex_sujo := false
var _gerar := false


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 4242
	last_day = int(jogo.sim.elapsed_days())
	_img = Image.create(PW, PH, false, Image.FORMAT_RG8)
	_img.fill(Color(0, 0, 0))
	tex = ImageTexture.create_from_image(_img)
	if save_path == "" or not _load(save_path):
		_gerar = true                    # nascem quando o mapa da grama estiver pronto
	_pinta_tudo()


func count() -> int:
	return vacas.size()


# ================== O PASTO ==================

## Quanto de grama tem no chão ali (0 nada: mata, areia, água; 1 pasto cheio).
func grama(x: float, z: float) -> float:
	return float(_jogo.grama_em(x, z))


static func px_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(x / PRES), 0, PW - 1), clampi(int(z / PRES), 0, PH - 1))


## Altura da grama no pedacinho agora (0 rapada, 1 crescida).
func altura(k: Vector2i, day := -1) -> float:
	if day < 0:
		day = last_day
	if seco.has(k):
		return 0.0
	if not comido.has(k):
		return 1.0
	return clampf(float(day - int(comido[k][0])) / REBROTA, 0.08, 1.0)


## Uma vaca arranca a grama do pedacinho. Devolve quanto comeu (0 a 1).
func comer_px(k: Vector2i, day := -1) -> float:
	if day < 0:
		day = last_day
	var g := grama(k.x * PRES + 1.0, k.y * PRES + 1.0)
	if g < 0.2 or seco.has(k):
		return 0.0
	var h := altura(k, day)
	if h < 0.3:
		return 0.0
	var vezes := 0
	if comido.has(k):
		vezes = int(comido[k][1])
	vezes = vezes + 1 if h < 0.6 else 0          # comida de novo ainda baixa: judia
	if vezes >= JUDIA:
		comido.erase(k)
		seco[k] = day                             # morreu: chão pelado
	else:
		comido[k] = [day, vezes]
	_pinta(k)
	return h * g


func _pinta(k: Vector2i) -> void:
	var h := altura(k)
	var s := 0.0
	if seco.has(k):
		s = 1.0 - clampf(float(last_day - int(seco[k]) - RECUPERA * 0.7) / (RECUPERA * 0.3), 0.0, 1.0)
	_img.set_pixel(k.x, k.y, Color(1.0 - h, s, 0))
	_tex_sujo = true


func _pinta_tudo() -> void:
	_img.fill(Color(0, 0, 0))
	for k in comido:
		_pinta(k)
	for k in seco:
		_pinta(k)
	tex.update(_img)
	_tex_sujo = false


## Um dia: a grama rebrota, o pasto seco volta devagar.
func _pasto_dia(day: int) -> void:
	for k in comido.keys():
		if day - int(comido[k][0]) >= REBROTA:
			comido.erase(k)
			_img.set_pixel(k.x, k.y, Color(0, 0, 0))
	for k in seco.keys():
		if day - int(seco[k]) >= RECUPERA:
			seco.erase(k)
			_img.set_pixel(k.x, k.y, Color(0, 0, 0))
	_tex_sujo = true


# ================== O REBANHO ==================

func _generate() -> void:
	for r in 2:
		var c := _lugar_bom(Vector2(_rng.randf_range(80, 560), _rng.randf_range(80, 400)), 400.0)
		if c == Vector2.INF:
			continue
		var rb := {"id": _next_id, "x": c.x, "z": c.y}
		_next_id += 1
		rebanhos.append(rb)
		var n_vacas := 4 if r == 0 else 3
		var cores := ["branca", "branca", "branca", "cinza", "vermelha", "parda", "malhada"]
		_nova("m", last_day - _rng.randi_range(1500, 3500), rb, -1, "branca" if _rng.randf() < 0.7 else "cinza")
		for k in n_vacas:
			var mae := _nova("f", last_day - _rng.randi_range(ADULTA + 100, 4000), rb, -1, cores[_rng.randi() % cores.size()])
			if k < 2:
				_nova("f" if _rng.randf() < 0.5 else "m", last_day - _rng.randi_range(20, 200), rb, int(mae.id), str(mae.cor))


func _nova(sexo: String, nasc: int, rb: Dictionary, mae: int, cor: String) -> Dictionary:
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(2.0, 14.0)
	var v := {"id": _next_id, "sexo": sexo, "nasc": nasc, "reb": int(rb.id), "x": float(rb.x) + cos(a) * d, "z": float(rb.z) + sin(a) * d,
		"mae": mae, "prenhe": -1, "fome": 0, "vida": VIDA + _rng.randi_range(-1200, 900), "cor": cor, "seed": _rng.randi() % 1000}
	_next_id += 1
	vacas.append(v)
	return v


## Um lugar com bastante grama (e sem água) perto de c, procurando até raio r.
func _lugar_bom(c: Vector2, r: float) -> Vector2:
	var best := Vector2.INF
	var bs := 0.0
	for k in 40:
		var a := _rng.randf() * TAU
		var q := c + Vector2(cos(a), sin(a)) * _rng.randf_range(0.0, r)
		q.x = clampf(q.x, 20.0, MundoSim.W * 5.0 - 20.0)
		q.y = clampf(q.y, 20.0, MundoSim.H * 5.0 - 20.0)
		var sc := _pasto_bom(q)
		if sc > bs:
			bs = sc
			best = q
	return best if bs > 0.25 else Vector2.INF


## Quanto pasto bom tem em volta do ponto (0 a 1): grama alta e não comida.
func _pasto_bom(q: Vector2) -> float:
	var cl := Vector2i(int(q.x / 5.0), int(q.y / 5.0))
	if _jogo.sim.water_at(cl) > 0.02 or _jogo.height_at(q.x, q.y) < MundoSim.SEA * _jogo.HS + 0.8:
		return 0.0
	var soma := 0.0
	for k in 9:
		var a := TAU * k / 9.0
		var p := q + Vector2(cos(a), sin(a)) * AREA * 0.6 * float(k % 3) / 2.0
		soma += grama(p.x, p.y) * altura(px_of(p.x, p.y))
	return soma / 9.0


func _rebanho(id: int) -> Dictionary:
	for rb in rebanhos:
		if int(rb.id) == id:
			return rb
	return {}


func _find(id: int) -> Dictionary:
	for v in vacas:
		if int(v.id) == id:
			return v
	return {}


func age(v: Dictionary) -> int:
	return last_day - int(v.nasc)


func matar(id: int) -> void:
	for i in vacas.size():
		if int(vacas[i].id) == id:
			vacas.remove_at(i)
			break
	if _agents.has(id):
		(_agents[id].node as Node).queue_free()
		_agents.erase(id)


# ================== UM DIA ==================

func tick() -> void:
	if _gerar:
		if _jogo.grama_em(320.0, 240.0) <= 0.0 and (_jogo._soil_bytes as PackedByteArray).is_empty():
			return
		_gerar = false
		_generate()
	var day := int(_jogo.sim.elapsed_days())
	if day > last_day:
		var n := 0
		while last_day < day and n < 60:
			last_day += 1
			_day(last_day)
			n += 1
		last_day = day
	if _tex_sujo:
		tex.update(_img)
		_tex_sujo = false


func _day(day: int) -> void:
	_pasto_dia(day)
	var capins = _jogo._capins
	# cada rebanho: come em volta; pouca comida, muda de lugar
	var fome_reb := {}
	for rb in rebanhos:
		var c := Vector2(float(rb.x), float(rb.z))
		var membros := []
		for v in vacas:
			if int(v.reb) == int(rb.id):
				membros.append(v)
		if membros.is_empty():
			continue
		var comeu_tot := 0.0
		var precisa := 0.0
		for v in membros:
			var ad := age(v) >= ADULTA
			var bezerro_mamando := int(v.mae) >= 0 and age(v) < 120
			if bezerro_mamando:
				v.fome = 0
				continue
			var need := COME_DIA if ad else COME_DIA / 2
			precisa += need
			var got := 0.0
			# perto de onde ela está: pedacinhos com grama alta
			for t in need * 3:
				if got >= float(need):
					break
				var a := _rng.randf() * TAU
				var r := sqrt(_rng.randf()) * AREA
				var q := c + Vector2(cos(a), sin(a)) * r
				got += comer_px(px_of(q.x, q.y), day)
			# as touceiras de capim verde em volta (gostam muito)
			if capins and got < float(need):
				for i in capins.items.size():
					var it: Dictionary = capins.items[i]
					if Vector2(float(it.x) - c.x, float(it.z) - c.y).length() < AREA and capins.comivel(i) and _rng.randf() < 0.2:
						capins.comer(i, false)
						got += 2.0
						if got >= float(need):
							break
			comeu_tot += got
			if got >= float(need) * 0.6:
				v.fome = 0
			else:
				v.fome = int(v.fome) + 1
		fome_reb[int(rb.id)] = comeu_tot < precisa * 0.75
		# pouca comida aqui (ou vontade de andar): o rebanho muda de pasto
		if bool(fome_reb[int(rb.id)]) or _rng.randf() < 0.08:
			var nv := _lugar_bom(c, 350.0)
			if nv != Vector2.INF:
				var dv := nv - c
				var np := c + dv.normalized() * minf(dv.length(), 600.0)
				rb.x = np.x
				rb.z = np.y
				for v in membros:
					if not _agents.has(int(v.id)):
						var a2 := _rng.randf() * TAU
						var d2 := _rng.randf_range(2.0, 16.0)
						v.x = np.x + cos(a2) * d2
						v.z = np.y + sin(a2) * d2
	# vida, morte e cria
	var keep := []
	var nascidos := []
	for v in vacas:
		var ag := day - int(v.nasc)
		if ag > int(v.vida) or int(v.fome) > FOME_MORRE:
			continue
		var mae := _find(int(v.mae)) if int(v.mae) >= 0 else {}
		if int(v.mae) >= 0 and ag < 120 and mae.is_empty():
			continue                        # bezerro novo sem a mãe não vive
		if str(v.sexo) == "f" and ag >= ADULTA:
			if int(v.prenhe) >= 0:
				if day - int(v.prenhe) >= GEST:
					v.prenhe = -1
					var rb2 := _rebanho(int(v.reb))
					if not rb2.is_empty():
						nascidos.append([v, rb2])
			elif int(v.fome) == 0 and not _tem_bezerro(v, day) and _touro_no(int(v.reb), day) and _rng.randf() < 0.012:
				v.prenhe = day
		keep.append(v)
	vacas = keep
	for nb in nascidos:
		var mae2: Dictionary = nb[0]
		var b := _nova("f" if _rng.randf() < 0.5 else "m", day, nb[1], int(mae2.id), str(mae2.cor) if _rng.randf() < 0.7 else ["branca", "cinza", "vermelha", "parda"][_rng.randi() % 4])
		b.x = float(mae2.x) - 0.8
		b.z = float(mae2.z) + 0.5
	# o bezerro que cresceu fica no rebanho (sem seguir a mãe); rebanho sem ninguém some
	for v in vacas:
		if int(v.mae) >= 0 and day - int(v.nasc) >= SEGUE:
			v.mae = -1
	var vivos := {}
	for v in vacas:
		vivos[int(v.reb)] = true
	rebanhos = rebanhos.filter(func(rb): return vivos.has(int(rb.id)))
	# rebanho grande demais racha: os mais novos saem com um touro novo
	for rb in rebanhos.duplicate():
		var m := vacas.filter(func(v): return int(v.reb) == int(rb.id) and int(v.mae) < 0)
		if m.size() > 14:
			var nr := {"id": _next_id, "x": float(rb.x) + _rng.randf_range(-80, 80), "z": float(rb.z) + _rng.randf_range(-80, 80)}
			_next_id += 1
			rebanhos.append(nr)
			m.sort_custom(func(a, b): return int(a.nasc) > int(b.nasc))
			for i in m.size() / 2:
				(m[i] as Dictionary).reb = int(nr.id)
				for f in vacas:
					if int(f.mae) == int(m[i].id):
						f.reb = int(nr.id)


func _tem_bezerro(v: Dictionary, day: int) -> bool:
	for o in vacas:
		if int(o.mae) == int(v.id) and day - int(o.nasc) < SEGUE:
			return true
	return false


func _touro_no(reb: int, day: int) -> bool:
	for o in vacas:
		if int(o.reb) == reb and str(o.sexo) == "m" and day - int(o.nasc) >= ADULTA:
			return true
	return false


# ================== NA TELA ==================

func _acordada(h: float) -> bool:
	return (h >= 5.5 and h < 11.0) or (h >= 14.5 and h < 19.5)


func update(delta: float) -> void:
	if _jogo == null or _jogo._player == null:
		return
	var pp: Vector3 = _jogo._player.position
	var h: float = _jogo.sim.hour()
	for v in vacas:
		var id := int(v.id)
		var near := Vector2(float(v.x) - pp.x, float(v.z) - pp.z).length() < SHOW
		if near and not _agents.has(id):
			_spawn(v)
		elif not near and _agents.has(id):
			(_agents[id].node as Node3D).queue_free()
			_agents.erase(id)
	for id in _agents.keys():
		var v := _find(id)
		if v.is_empty():
			(_agents[id].node as Node3D).queue_free()
			_agents.erase(id)
			continue
		_step(v, _agents[id], pp, h, delta)
	if _tex_sujo and Engine.get_process_frames() % 20 == 0:
		tex.update(_img)
		_tex_sujo = false


func _spawn(v: Dictionary) -> void:
	var ag := age(v)
	var s := clampf(lerpf(0.45, 1.0, float(ag) / ADULTA), 0.45, 1.0)
	if str(v.sexo) == "m" and ag >= ADULTA:
		s *= 1.08
	var node := Modelo.build(s, str(v.get("cor", "branca")), str(v.sexo) == "m" and ag >= ADULTA, int(v.get("seed", 1)))
	add_child(node)
	var a := {"node": node, "modo": "parado", "alvo": Vector3.ZERO, "t": _rng.randf() * 10.0, "fase": 0.0,
		"yaw": _rng.randf() * TAU, "timer": _rng.randf_range(0.5, 4.0), "s": s, "mordida": _rng.randf_range(1.0, 3.0)}
	_agents[int(v.id)] = a
	node.position = Vector3(float(v.x), _jogo.ground_at(float(v.x), float(v.z)), float(v.z))
	node.rotation.y = a.yaw


func _step(v: Dictionary, a: Dictionary, pp: Vector3, h: float, delta: float) -> void:
	var node: Node3D = a.node
	a.t = float(a.t) + delta
	if _jogo._mp_client():
		# convidado: quem decide é o dono do mundo; aqui ela só vai até onde ele diz
		var alvo := Vector3(float(v.x), _jogo.ground_at(float(v.x), float(v.z)), float(v.z))
		var dd := Vector3(alvo.x - node.position.x, 0, alvo.z - node.position.z)
		var mv := dd.length()
		if mv > 25.0:
			node.position = alvo
		elif mv > 0.05:
			var stp2 := minf(mv, (TROTE if mv > 4.0 else WALK) * delta)
			node.position += dd / mv * stp2
			node.position.y = _jogo.ground_at(node.position.x, node.position.z)
			a.yaw = atan2(-dd.z, dd.x)
			a.fase = float(a.fase) + stp2 / 0.55 * PI
		node.rotation.y = lerp_angle(node.rotation.y, float(a.yaw), minf(1.0, delta * 3.0))
		var an := "correr" if mv > 4.0 else ("andar" if mv > 0.3 else ("deitar" if not _acordada(h) else "pastar"))
		Modelo.pose(node, an, float(a.fase), float(a.t))
		return
	var pos := Vector3(float(v.x), 0, float(v.z))
	var dist_p := Vector2(pos.x - pp.x, pos.z - pp.z).length()
	var modo := str(a.modo)
	var rb := _rebanho(int(v.reb))
	var mae := _find(int(v.mae)) if int(v.mae) >= 0 else {}
	# brava: gente perto, foge (e o rebanho junto)
	if modo != "fugir" and dist_p < (MEDO if modo != "deitar" else MEDO * 0.7):
		_assusta(int(v.reb), pp)
		modo = str(a.modo)
	match modo:
		"fugir":
			if _walk(v, a, TROTE, delta):
				a.modo = "parado"
				a.timer = _rng.randf_range(2.0, 5.0)
		"deitar":
			if _acordada(h) and float(a.timer) <= 0.0:
				a.modo = "parado"
				a.timer = 1.5
			a.timer = float(a.timer) - delta
		"pastar":
			# anda bem devagar de cabeça baixa e arranca a grama de verdade
			a.timer = float(a.timer) - delta
			a.mordida = float(a.mordida) - delta
			var fwd := Vector3(cos(float(a.yaw)), 0, -sin(float(a.yaw)))
			var stp := 0.12 * float(a.s) * delta
			var np := pos + fwd * stp
			if _pode_andar(np):
				v.x = np.x
				v.z = np.z
				a.fase = float(a.fase) + stp / 0.5 * PI
			if float(a.mordida) <= 0.0:
				a.mordida = _rng.randf_range(1.5, 3.5)
				_morder(v, a)
			if float(a.timer) <= 0.0:
				a.modo = "parado"
				a.timer = _rng.randf_range(1.0, 3.0)
		"andar":
			if _walk(v, a, WALK, delta):
				a.modo = "pastar"
				a.timer = _rng.randf_range(10.0, 30.0)
				a.yaw = float(a.yaw) + _rng.randf_range(-1.0, 1.0)
		_:
			a.timer = float(a.timer) - delta
			if float(a.timer) <= 0.0:
				if not _acordada(h):
					a.modo = "deitar"
					a.timer = _rng.randf_range(20.0, 60.0)
				elif not mae.is_empty():
					a.alvo = Vector3(float(mae.x) - 1.0, 0, float(mae.z) + 0.6)
					a.modo = "andar"
				elif not rb.is_empty() and Vector2(pos.x - float(rb.x), pos.z - float(rb.z)).length() > AREA:
					var a2 := _rng.randf() * TAU
					a.alvo = Vector3(float(rb.x) + cos(a2) * AREA * 0.5, 0, float(rb.z) + sin(a2) * AREA * 0.5)
					a.modo = "andar"
				elif _rng.randf() < 0.7:
					a.modo = "pastar"
					a.timer = _rng.randf_range(8.0, 25.0)
					a.yaw = float(a.yaw) + _rng.randf_range(-0.9, 0.9)
				else:
					var a3 := _rng.randf() * TAU
					a.alvo = pos + Vector3(cos(a3), 0, sin(a3)) * _rng.randf_range(3.0, 8.0)
					a.modo = "andar"
	# bezerro segue a mãe
	if not mae.is_empty() and str(a.modo) in ["andar", "pastar", "parado"] and Vector2(pos.x - float(mae.x), pos.z - float(mae.z)).length() > 3.0:
		a.alvo = Vector3(float(mae.x) - 1.0, 0, float(mae.z) + 0.6)
		a.modo = "andar"
	var y: float = _jogo.ground_at(float(v.x), float(v.z))
	node.position = Vector3(float(v.x), y, float(v.z))
	node.rotation.y = lerp_angle(node.rotation.y, float(a.yaw), minf(1.0, delta * 3.0))
	var anim := str(a.modo)
	if anim == "fugir":
		anim = "correr"
	Modelo.pose(node, anim, float(a.fase), float(a.t))


## Arranca a grama na frente do focinho (e a touceira de capim, se tiver).
func _morder(v: Dictionary, a: Dictionary) -> void:
	if _jogo._mp_client():
		return                               # quem manda no pasto é o dono do mundo
	var s := float(a.s)
	var fwd := Vector3(cos(float(a.yaw)), 0, -sin(float(a.yaw)))
	var boca := Vector3(float(v.x), 0, float(v.z)) + fwd * 1.15 * s
	comer_px(px_of(boca.x, boca.z))
	var capins = _jogo._capins
	if capins:
		var ci: int = capins.nearest(boca, 0.8)
		if ci >= 0 and capins.comivel(ci):
			capins.comer(ci, true)


func _assusta(reb: int, pp: Vector3) -> void:
	for v in vacas:
		if int(v.reb) != reb or not _agents.has(int(v.id)):
			continue
		var a: Dictionary = _agents[int(v.id)]
		var pos := Vector3(float(v.x), 0, float(v.z))
		var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
		if away.length() > 35.0:
			continue
		away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
		var lado := Vector3(-away.z, 0, away.x) * _rng.randf_range(-0.4, 0.4)
		a.alvo = pos + (away + lado).normalized() * _rng.randf_range(20.0, 30.0)
		a.modo = "fugir"


func _pode_andar(p: Vector3) -> bool:
	var c := Vector2i(int(p.x / 5.0), int(p.z / 5.0))
	if c.x < 1 or c.y < 1 or c.x >= MundoSim.W - 1 or c.y >= MundoSim.H - 1:
		return false
	var sim = _jogo.sim
	var i: int = c.y * MundoSim.W + c.x
	return float(sim.wat[i]) < 0.05 and float(sim.ter[i]) > MundoSim.SEA + 0.3


## Anda até o alvo; true quando chegou (ou quando a água não deixa).
func _walk(v: Dictionary, a: Dictionary, speed: float, delta: float) -> bool:
	var pos := Vector3(float(v.x), 0, float(v.z))
	var to: Vector3 = a.alvo
	var d := Vector3(to.x - pos.x, 0, to.z - pos.z)
	var L := d.length()
	if L < 0.3:
		return true
	var dir := d / L
	var stp := minf(L, speed * float(a.s) * delta)
	var np := pos + dir * stp
	if not _pode_andar(np):
		return true
	v.x = np.x
	v.z = np.z
	a.yaw = atan2(-dir.z, dir.x)
	a.fase = float(a.fase) + stp / (0.55 * float(a.s)) * PI
	return false


# ================== SALVAR ==================

func save(path: String) -> void:
	var cm := []
	for k in comido:
		cm.append([k.x, k.y, int(comido[k][0]), int(comido[k][1])])
	var sc := []
	for k in seco:
		sc.append([k.x, k.y, int(seco[k])])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "prox": _next_id, "vacas": vacas, "rebanhos": rebanhos, "comido": cm, "seco": sc}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	vacas = d.get("vacas", [])
	rebanhos = d.get("rebanhos", [])
	_next_id = int(d.get("prox", 1))
	last_day = mini(int(d.get("dia", last_day)), last_day)
	for v in vacas:
		for k in ["id", "nasc", "reb", "mae", "prenhe", "fome", "vida", "seed"]:
			v[k] = int(v.get(k, 0))
	for rb in rebanhos:
		rb.id = int(rb.id)
	comido = {}
	for e in d.get("comido", []):
		comido[Vector2i(int(e[0]), int(e[1]))] = [int(e[2]), int(e[3])]
	seco = {}
	for e in d.get("seco", []):
		seco[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	return true


## Chegou do dono do mundo (multiplayer): repinta o pasto.
func _rebuild() -> void:
	if _img:
		_pinta_tudo()
