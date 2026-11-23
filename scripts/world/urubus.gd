extends Node3D
## Os urubus (urubu-de-cabeça-preta, Coragyps atratus).
##
## Onde tem bicho morto (a carcaça no chão, um pedaço de carne, a buchada, uma pata, a
## cabeça) eles acham depois de umas horas. Vão chegando um por um lá do alto, planando,
## e ficam rondando juntos na mesma térmica (todos girando para o mesmo lado, cada um
## numa altura). Quando não tem ninguém perto, descem em espiral e pousam uns metros
## longe, freando com as asas e as pernas para a frente. Ficam um pouco atentos, olhando
## em volta, e chegam andando (balançando a cabeça) ou aos pulos de asa meio aberta.
## Na carniça só cabem uns poucos comendo de cada vez: enfiam a cabeça e puxam aos
## trancos, engolem, levantam a cabeça para olhar. Os outros esperam do lado (em pé,
## encolhidos, ou tomando sol de asas abertas) e de vez em quando um briga pelo lugar:
## abre as asas, chia e dá um bote, e o que estava comendo sai pulando.
## Gente a uns 35 m: param de comer e ficam de cabeça erguida. Mais perto: correm uns
## pulos batendo as asas e levantam voo, voltam a rondar e descem de novo quando a
## pessoa vai embora. Acabou a carne, ou anoitecendo: vão embora.
##
## Não são salvos: aparecem e somem conforme a carniça. O que comem fica na carniça
## (caca.comer), e isso adianta a decomposição até sobrar só o osso.

const Sons := preload("res://scripts/sons.gd")

const MAX_URUBUS := 16
const KG_H := 6.0                  # quanto um urubu come por hora do jogo (kg)
const LONGE_POUSA := 30.0          # ninguém a menos disso para descer
const LONGE_ATENTO := 35.0         # gente a menos disso: param de comer e olham
const LONGE_FOGE := 16.0           # mais perto que isso: voam
const V_PLANA := 9.5               # m/s planando

var _jogo: Node = null
var _aves: Array = []              # {node: Urubu, est, site, ...}
var _sites := {}                   # chave -> {pos, kg, comidas, t, prox, sent, ...}
var _t_sites := 0.0
var _rng := RandomNumberGenerator.new()


func build(jogo: Node) -> void:
	_jogo = jogo
	_rng.randomize()


func _hora() -> float:
	return float(_jogo.sim.hour()) if _jogo and _jogo.sim else 12.0


func _de_dia() -> bool:
	var h := _hora()
	return h > 6.8 and h < 17.6


## Onde estão as pessoas (este jogador e os outros).
func _pessoas() -> Array:
	var out := []
	if _jogo._player:
		out.append((_jogo._player as Node3D).global_position)
	for pid in _jogo._remotos:
		var r = _jogo._remotos[pid]
		if is_instance_valid(r):
			out.append((r as Node3D).global_position)
	return out


func _mais_perto(p: Vector3) -> float:
	var d := 1e9
	for q in _pessoas():
		d = minf(d, Vector2(q.x - p.x, q.z - p.z).length())
	return d


## De onde vem o perigo (a pessoa mais perto).
func _perigo(p: Vector3) -> Vector3:
	var d := 1e9
	var best := p + Vector3.FORWARD
	for q in _pessoas():
		var dd := Vector2(q.x - p.x, q.z - p.z).length()
		if dd < d:
			d = dd
			best = q
	return best


func _chao(x: float, z: float) -> float:
	return float(_jogo.ground_at(x, z))


func update(delta: float) -> void:
	if _jogo == null or _jogo._caca == null:
		return
	_t_sites -= delta
	if _t_sites <= 0.0:
		_t_sites = 4.0
		_acha_sites()
	var dh := delta / maxf(float(_jogo.sim.real_s_por_hora()), 1.0)
	for s in _sites.values():
		# o centro da térmica anda devagar com o vento
		s.wa = float(s.get("wa", 0.0)) + delta * 0.05
	for a in _aves.duplicate():
		_ave(a, delta, dh)


## Junta a carniça em lugares (o que está a menos de 12 m vira um lugar só).
func _acha_sites() -> void:
	var com: Array = _jogo._caca.comidas()
	var novos := {}
	for f in com:
		var p: Vector3 = f.pos
		var achou := ""
		for k in novos:
			if (novos[k].pos as Vector3).distance_to(p) < 12.0:
				achou = k
				break
		if achou == "":
			achou = str(f.key)
			novos[achou] = {"pos": p, "kg": 0.0, "comidas": []}
		novos[achou].kg = float(novos[achou].kg) + float(f.kg)
		(novos[achou].comidas as Array).append(f)
	# os lugares que continuam guardam o que já tinham
	for k in novos:
		if _sites.has(k):
			for kk in ["t", "prox", "sent", "wa"]:
				novos[k][kk] = _sites[k].get(kk, 0.0)
		else:
			novos[k]["t"] = 0.0
			novos[k]["prox"] = 0.0
			novos[k]["sent"] = 1.0 if _rng.randf() < 0.55 else -1.0     # a térmica gira para um lado só
			novos[k]["wa"] = _rng.randf() * TAU
	_sites = novos
	# quantos urubus cada lugar chama (mais carne, mais urubu); vão chegando aos poucos
	var tot := _aves.size()
	for k in _sites:
		var s: Dictionary = _sites[k]
		s.t = float(s.t) + 4.0
		var quer := clampi(roundi(pow(maxf(float(s.kg), 0.5), 0.4) / 1.4), 1, 8)
		var tem := 0
		for a in _aves:
			if str(a.site) == k and str(a.est) != "indo":
				tem += 1
		if _de_dia() and tem < quer and tot < MAX_URUBUS and float(s.t) > float(s.prox):
			_novo(k)
			tot += 1
			s.prox = float(s.t) + _rng.randf_range(10.0, 35.0)
	for a in _aves:
		if not _sites.has(str(a.site)) and str(a.est) in ["chao", "atento", "come", "andando", "espera", "briga"]:
			_foge(a)


## O centro da térmica de um lugar (em cima da carniça, andando um pouco com o vento).
func _termica(s: Dictionary) -> Vector3:
	var c: Vector3 = s.pos
	var wa := float(s.get("wa", 0.0))
	return c + Vector3(cos(wa), 0, sin(wa * 0.7)) * 6.0


func _novo(site: String) -> void:
	var s: Dictionary = _sites[site]
	var c: Vector3 = s.pos
	var ang := _rng.randf() * TAU
	var n := Urubu.new()
	add_child(n)
	var de := c + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(170.0, 230.0)
	de.y = _chao(de.x, de.z) + _rng.randf_range(55.0, 85.0)
	n.global_position = de
	n.modo = "plana"
	_aves.append({"node": n, "est": "chegando", "site": site, "R": _rng.randf_range(10.0, 22.0), "alt": _rng.randf_range(18.0, 45.0),
		"ang": _rng.randf() * TAU, "t": 0.0, "ronda": 0.0, "bate": 0.0, "vel": Vector3.ZERO, "alvo": Vector3.ZERO,
		"comida": {}, "chia": _rng.randf_range(6.0, 20.0), "espera": _rng.randf_range(15.0, 30.0), "olha": 0.0, "corre": 0})


## Gente chegando (ou acabou): corre uns pulos batendo as asas e levanta voo.
func _foge(a: Dictionary) -> void:
	var n: Urubu = a.node
	a.est = "corrida"
	a.t = 0.0
	a.comida = {}
	var p := n.global_position
	var pg := _perigo(p)
	var fora := Vector3(p.x - pg.x, 0, p.z - pg.z)
	fora = fora.normalized() if fora.length() > 0.1 else Vector3.FORWARD
	a.fuga = fora.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	n.modo = "bate"
	if _rng.randf() < 0.8:
		Sons.play_at(self, "urubu_asas", p, 0.0, _rng.randf_range(0.9, 1.1), 60.0, 5.0)


## Quantos estão comendo nessa comida agora (só cabem uns poucos).
func _comendo_em(key: String) -> Array:
	var out := []
	for b in _aves:
		if str(b.est) in ["come", "andando"] and str((b.comida as Dictionary).get("key", "")) == key:
			out.append(b)
	return out


func _cabe(f: Dictionary) -> int:
	var r := float(f.get("r", 0.3))
	return clampi(roundi(r * 5.0), 1, 4)


func _ave(a: Dictionary, delta: float, dh: float) -> void:
	var n: Urubu = a.node
	if not is_instance_valid(n):
		_aves.erase(a)
		return
	a.t = float(a.t) + delta
	var tem_site := _sites.has(str(a.site))
	var site: Dictionary = _sites.get(str(a.site), {})
	var c: Vector3 = site.pos if tem_site else n.global_position
	var chao_c := _chao(c.x, c.z)
	var no_chao := str(a.est) in ["chao", "atento", "come", "andando", "espera", "briga"]
	# a noite chegando ou sem carniça faz tempo: vão embora
	if str(a.est) != "indo":
		if not _de_dia() or (not tem_site and float(a.t) > 40.0 and str(a.est) == "rondando"):
			if no_chao:
				_foge(a)
			elif str(a.est) != "corrida":
				a.est = "indo"
				var ang := _rng.randf() * TAU
				a.alvo = n.global_position + Vector3(cos(ang), 0, sin(ang)) * 450.0 + Vector3.UP * 60.0
	# no chão: gente perto?
	if no_chao:
		var p0 := n.global_position
		p0.y = _chao(p0.x, p0.z)
		n.global_position = p0
		var dp := _mais_perto(p0)
		if dp < LONGE_FOGE:
			_foge(a)
			return
		n.alerta = dp < LONGE_ATENTO
		if n.alerta:
			_vira(n, (_perigo(p0) - p0).normalized(), delta * 1.5)
	match str(a.est):
		"chegando":
			var cc := _termica(site) if tem_site else c
			var alvo := cc + Vector3(cos(float(a.ang)) * float(a.R), chao_c - cc.y + float(a.alt), sin(float(a.ang)) * float(a.R))
			_voa_para(a, alvo, delta, V_PLANA * 1.3)
			n.modo = "plana"
			if n.global_position.distance_to(alvo) < 10.0:
				a.est = "rondando"
				a.ronda = 0.0
		"rondando":
			a.ronda = float(a.ronda) + delta
			var cc2 := _termica(site) if tem_site else c
			var sent := float(site.get("sent", 1.0))
			a.ang = float(a.ang) + sent * V_PLANA / float(a.R) * delta
			# na térmica vai subindo devagar; lá em cima solta e desce planando de novo
			var alt := chao_c + float(a.alt) + sin(float(a.t) * 0.11 + float(a.R)) * 6.0
			var alvo2 := Vector3(cc2.x + cos(float(a.ang)) * float(a.R), alt, cc2.z + sin(float(a.ang)) * float(a.R))
			_voa_para(a, alvo2, delta, V_PLANA)
			# o urubu-de-cabeça-preta bate as asas de vez em quando (umas batidas rápidas)
			a.bate = maxf(0.0, float(a.bate) - delta)
			if float(a.bate) <= 0.0 and _rng.randf() < delta * 0.06:
				a.bate = _rng.randf_range(0.7, 1.4)
			n.modo = "bate" if float(a.bate) > 0.0 else "plana"
			# desce: rondou um tempo, ninguém perto
			if tem_site and float(a.ronda) > float(a.espera) and _mais_perto(c) > LONGE_POUSA and _de_dia():
				a.est = "descendo"
				var ang2 := _rng.randf() * TAU
				var pouso := c + Vector3(cos(ang2), 0, sin(ang2)) * _rng.randf_range(4.0, 9.0)
				pouso.y = _chao(pouso.x, pouso.z)
				a.alvo = pouso
				a.espera = _rng.randf_range(15.0, 40.0)
		"descendo":
			if tem_site and _mais_perto(c) < LONGE_POUSA * 0.8:
				a.est = "subindo"
				a.t = 0.0
				return
			var p := n.global_position
			var alvo3: Vector3 = a.alvo
			var falta := p.y - alvo3.y
			var hd := Vector2(alvo3.x - p.x, alvo3.z - p.z)
			if falta > 3.0:
				# espiral: gira em volta do ponto de pouso, fechando e descendo
				var raio := clampf(falta * 0.55, 3.0, 16.0)
				a.ang = float(a.ang) + float(site.get("sent", 1.0)) * 0.8 * delta
				var alvo4 := alvo3 + Vector3(cos(float(a.ang)) * raio, maxf(falta - 5.0 * delta * 3.0, 2.5), sin(float(a.ang)) * raio)
				_voa_para(a, alvo4, delta, 8.0)
				n.modo = "plana"
			else:
				# a reta final: freia com as asas, as pernas para a frente
				var v := clampf(hd.length() * 1.5 + 1.0, 1.2, 6.0)
				_voa_para(a, alvo3 + Vector3.UP * 0.05, delta, v)
				n.modo = "pousa"
				if falta < 0.25 and hd.length() < 0.8:
					n.global_position = Vector3(p.x, _chao(p.x, p.z), p.z)
					n.ereto()
					a.est = "atento"
					a.t = 0.0
					a.olha = _rng.randf_range(2.0, 6.0)
					n.modo = "chao"
		"atento":
			# acabou de pousar: fica parado olhando em volta antes de chegar perto
			n.modo = "chao"
			if float(a.t) > float(a.olha) and not n.alerta:
				_escolhe(a, site)
		"espera":
			# esperando a vez: encolhido, às vezes tomando sol de asas abertas; de vez em
			# quando tenta de novo (e briga com quem está comendo)
			n.modo = "sol" if float(a.get("sol", 0.0)) > 0.0 else "chao"
			a.sol = maxf(0.0, float(a.get("sol", 0.0)) - delta)
			if float(a.get("sol", 0.0)) <= 0.0 and _rng.randf() < delta * 0.03:
				a.sol = _rng.randf_range(8.0, 25.0)
			if float(a.t) > float(a.get("vez", 8.0)) and not n.alerta:
				a.sol = 0.0
				_escolhe(a, site, true)
		"andando":
			if n.alerta:
				n.modo = "chao"
				return
			var alvo5: Vector3 = a.alvo
			var d5 := Vector2(alvo5.x - n.global_position.x, alvo5.z - n.global_position.z)
			if d5.length() > 0.1:
				var longe := d5.length() > 2.5
				n.modo = "pula" if longe else "anda"
				var passo := minf(d5.length(), (1.6 if longe else 0.55) * delta)
				var dv := Vector3(d5.x, 0, d5.y).normalized()
				n.global_position += dv * passo
				_vira(n, dv, delta * 5.0)
			elif bool(a.get("vai_esperar", false)):
				a.est = "espera"
				a.t = 0.0
				a.vez = _rng.randf_range(6.0, 18.0)
			else:
				a.est = "come"
				a.t = 0.0
		"briga":
			# o bote: asas abertas, chiando, avança pulando em cima do que está comendo
			n.modo = "ameaca"
			var rival: Dictionary = a.get("rival", {})
			var rn: Urubu = rival.get("node", null) if not rival.is_empty() else null
			if rn == null or not is_instance_valid(rn) or float(a.t) > 2.5:
				a.est = "chao"
				_escolhe(a, site)
				return
			var dr := rn.global_position - n.global_position
			dr.y = 0.0
			_vira(n, dr.normalized(), delta * 6.0)
			if dr.length() > 0.5:
				n.global_position += dr.normalized() * minf(dr.length(), 2.2 * delta)
			elif str(rival.est) == "come":
				# o outro sai pulando de asa aberta e vai esperar; este fica com o lugar
				rival.est = "andando"
				rival.vai_esperar = true
				var fora := (rn.global_position - n.global_position)
				fora.y = 0.0
				fora = fora.normalized() if fora.length() > 0.05 else Vector3.RIGHT
				var pe: Vector3 = rn.global_position + fora * _rng.randf_range(1.5, 3.0)
				pe.y = _chao(pe.x, pe.z)
				rival.alvo = pe
				a.comida = rival.comida
				rival.comida = {}
				a.alvo = rn.global_position
				a.est = "andando"
				a.vai_esperar = false
		"come":
			if not _comida_ok(a):
				a.comida = {}
				_escolhe(a, site)
				return
			var cp: Vector3 = (a.comida as Dictionary).pos
			var dv2 := Vector3(cp.x - n.global_position.x, 0, cp.z - n.global_position.z)
			if dv2.length() > 0.01 and not n.alerta:
				_vira(n, dv2.normalized(), delta * 3.0)
			if n.alerta:
				n.modo = "chao"
				return
			a.chia = float(a.chia) - delta
			if float(a.chia) <= 0.0:
				a.chia = _rng.randf_range(10.0, 28.0)
				n.abre = 1.0
				Sons.play_at(self, "urubu_chiado", n.global_position + Vector3.UP * 0.3, -2.0, _rng.randf_range(0.9, 1.15), 40.0, 3.0)
			# às vezes para, levanta a cabeça e olha em volta (engolindo)
			a.olha = float(a.olha) - delta
			if float(a.olha) <= 0.0:
				a.olha = _rng.randf_range(5.0, 14.0)
				n.levanta = _rng.randf_range(1.2, 2.5)
			n.modo = "come"
			if n.levanta <= 0.0:
				_jogo._caca.comer(str((a.comida as Dictionary).key), KG_H * dh)
				(a.comida as Dictionary).kg = float((a.comida as Dictionary).kg) - KG_H * dh
		"corrida":
			# uns pulos correndo e batendo as asas antes de sair do chão
			var fg: Vector3 = a.get("fuga", Vector3.FORWARD)
			_vira(n, fg, delta * 8.0)
			var p3 := n.global_position
			var sobe := clampf((float(a.t) - 0.6) * 2.5, 0.0, 3.0)
			p3 += fg * (2.5 + float(a.t) * 2.0) * delta
			p3.y = _chao(p3.x, p3.z) + sobe + absf(sin(float(a.t) * 9.0)) * 0.15 * (1.0 - minf(sobe, 1.0))
			n.global_position = p3
			n.modo = "bate"
			a.vel = fg * 4.0 + Vector3.UP * 2.0
			if float(a.t) > 1.4:
				a.est = "subindo"
				a.t = 0.0
		"subindo":
			# sobe batendo forte e vai rondar de novo
			var p2 := n.global_position
			var ang4 := atan2(p2.z - c.z, p2.x - c.x)
			var alvo6 := Vector3(c.x + cos(ang4) * 20.0, chao_c + 18.0, c.z + sin(ang4) * 20.0)
			_voa_para(a, alvo6, delta, 7.0)
			n.modo = "bate"
			if p2.y - _chao(p2.x, p2.z) > 12.0 or float(a.t) > 7.0:
				a.est = "rondando"
				a.ronda = 0.0
				a.ang = ang4
				a.espera = _rng.randf_range(25.0, 60.0)
				a.comida = {}
		"indo":
			var alvo7: Vector3 = a.alvo
			_voa_para(a, alvo7, delta, V_PLANA * 1.4)
			n.modo = "plana"
			if n.global_position.distance_to(alvo7) < 20.0 or float(a.t) > 90.0:
				n.queue_free()
				_aves.erase(a)


## Escolhe o que comer: a comida mais perto que tem vaga; sem vaga, fica esperando do
## lado (ou, se for valente, briga com quem está comendo).
func _escolhe(a: Dictionary, site: Dictionary, valente := false) -> void:
	var n: Urubu = a.node
	var melhor := {}
	var md := 1e9
	var cheia := {}
	for f in site.get("comidas", []):
		if float(f.kg) <= 0.05:
			continue
		var d := (f.pos as Vector3).distance_to(n.global_position)
		if _comendo_em(str(f.key)).size() < _cabe(f):
			if d < md:
				md = d
				melhor = f
		elif cheia.is_empty():
			cheia = f
	if melhor.is_empty() and cheia.is_empty():
		_foge(a)
		return
	a.vai_esperar = false
	if melhor.is_empty():
		var rivais := _comendo_em(str(cheia.key))
		if valente and not rivais.is_empty() and _rng.randf() < 0.6:
			a.est = "briga"
			a.t = 0.0
			a.rival = rivais[_rng.randi() % rivais.size()]
			Sons.play_at(self, "urubu_chiado", n.global_position + Vector3.UP * 0.3, 0.0, _rng.randf_range(0.95, 1.2), 40.0, 3.0)
			return
		# vai esperar a uns metros da carniça
		var ang := _rng.randf() * TAU
		var pe: Vector3 = (cheia.pos as Vector3) + Vector3(cos(ang), 0, sin(ang)) * (float(cheia.r) + _rng.randf_range(1.5, 3.5))
		pe.y = _chao(pe.x, pe.z)
		a.alvo = pe
		a.vai_esperar = true
		a.est = "andando"
		return
	a.comida = melhor
	# chega em volta da carniça, de frente para ela (cada um num lado)
	var ang3 := _rng.randf() * TAU
	var r := float(melhor.r) + _rng.randf_range(0.12, 0.3)
	var ap: Vector3 = (melhor.pos as Vector3) + Vector3(cos(ang3), 0, sin(ang3)) * r
	ap.y = _chao(ap.x, ap.z)
	a.alvo = ap
	a.est = "andando"


func _comida_ok(a: Dictionary) -> bool:
	var f: Dictionary = a.comida
	if f.is_empty() or float(f.get("kg", 0.0)) <= 0.05:
		return false
	var site: Dictionary = _sites.get(str(a.site), {})
	for g in site.get("comidas", []):
		if str(g.key) == str(f.key):
			return true
	return false


## Voa para o ponto: vira aos poucos (inclinando nas curvas), a velocidade dada.
func _voa_para(a: Dictionary, alvo: Vector3, delta: float, v: float) -> void:
	var n: Urubu = a.node
	var p := n.global_position
	var d := alvo - p
	if d.length() < 0.01:
		return
	var vel: Vector3 = a.vel
	var quer := d.normalized() * minf(v, d.length() * 2.0 + 1.0)
	vel = vel.lerp(quer, 1.0 - exp(-delta * 1.1))
	if vel.length() < 0.4:
		vel = quer * 0.3
	var antes: Vector3 = a.vel
	a.vel = vel
	n.global_position = p + vel * delta
	# o corpo olha para onde vai e inclina na curva
	var fr := vel.normalized()
	var curva := 0.0
	if antes.length() > 0.5:
		var ah := Vector2(antes.x, antes.z).angle()
		var bh := Vector2(vel.x, vel.z).angle()
		curva = wrapf(bh - ah, -PI, PI) / maxf(delta, 1e-4)
	var roll := clampf(-curva * 0.45, -0.75, 0.75)
	n.inclina = lerpf(n.inclina, roll, 1.0 - exp(-delta * 2.0))
	var b := Basis.looking_at(Vector3(fr.x, clampf(fr.y, -0.5, 0.5) * 0.5, fr.z), Vector3.UP)
	n.global_transform.basis = b * Basis(Vector3.FORWARD, n.inclina)


func _vira(n: Node3D, dir: Vector3, k: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var b := Basis.looking_at(dir.normalized(), Vector3.UP)
	n.global_transform.basis = n.global_transform.basis.orthonormalized().slerp(b, clampf(k, 0.0, 1.0))


# ================== O URUBU (o desenho) ==================

class Urubu:
	extends Node3D
	## Uns 62 cm do bico ao rabo, 1,45 m de asa aberta. Penas pretas (com um brilho
	## frio, em fileiras), uma gola de penas onde começa o pescoço pelado; a cabeça e o
	## pescoço de pele cinza-escura enrugada; o bico comprido e curvo, escuro, com a ponta
	## clara; os olhos castanhos; as pernas cinza-claro, os dedos com unhas pretas. As
	## asas largas, com as secundárias serrilhadas atrás e as seis primárias separadas
	## como dedos na ponta, claras embaixo (a mancha das pontas). O rabo curto e quadrado.
	## A origem é nos pés (no chão) e no meio do corpo (voando). Frente = -Z.
	## Modos: "plana", "bate", "pousa", "chao", "anda", "pula", "come", "sol", "ameaca".

	var modo := "plana"
	var inclina := 0.0
	var abre := 0.0                   # abre as asas um instante (briga)
	var levanta := 0.0                # come: levanta a cabeça e olha (engolindo)
	var alerta := false               # gente perto: cabeça erguida, parado
	var _t := 0.0
	var _corpo: Node3D
	var _pesc: Node3D
	var _cab: Node3D
	var _rabo: Node3D
	var _asas := []
	var _dobradas := []
	var _pernas := []
	var _olhar := 0.0
	var _olhar_alvo := 0.0
	var _ac := {}                     # os ângulos agora (suaves)
	static var _m := {}

	func _ready() -> void:
		_t = randf() * 10.0
		if _m.is_empty():
			_faz_malhas()
		_corpo = Node3D.new()
		add_child(_corpo)
		_mi(_corpo, _m.corpo, _m.pena, Transform3D.IDENTITY)
		_detalhes.append(_mi(_corpo, _m.gola, _m.pena, Transform3D(Basis(), Vector3(0, 0.045, -0.15))))
		_rabo = Node3D.new()
		_rabo.position = Vector3(0, 0.01, 0.14)
		_corpo.add_child(_rabo)
		_mi(_rabo, _m.rabo, _m.asa_mat, Transform3D.IDENTITY)
		_pesc = Node3D.new()
		_pesc.position = Vector3(0, 0.05, -0.155)
		_corpo.add_child(_pesc)
		_mi(_pesc, _m.pescoco, _m.pele, Transform3D.IDENTITY)
		_cab = Node3D.new()
		_cab.position = Vector3(0, 0.0, -0.085)
		_pesc.add_child(_cab)
		_mi(_cab, _m.cabeca, _m.pele, Transform3D.IDENTITY)
		_detalhes.append(_mi(_cab, _m.bico, _m.bico_mat, Transform3D.IDENTITY))
		for sg in [-1.0, 1.0]:
			_detalhes.append(_mi(_cab, _m.olho, _m.olho_mat, Transform3D(Basis().scaled(Vector3.ONE * 0.0085), Vector3(sg * 0.0165, 0.012, -0.022))))
			# a asa: o braço (com as secundárias) e a mão (as primárias)
			var braco := Node3D.new()
			braco.position = Vector3(sg * 0.075, 0.055, -0.06)
			_corpo.add_child(braco)
			_mi(braco, _m["braco_" + ("d" if sg > 0 else "e")], _m.asa_mat, Transform3D.IDENTITY)
			var mao := Node3D.new()
			mao.position = Vector3(sg * 0.31, 0, -0.01)
			braco.add_child(mao)
			_mi(mao, _m["mao_" + ("d" if sg > 0 else "e")], _m.asa_mat, Transform3D.IDENTITY)
			_asas.append({"braco": braco, "mao": mao, "sg": sg})
			# a asa fechada (dobrada no lado do corpo, as pontas cruzando em cima do rabo)
			var dob := _mi(_corpo, _m["dobrada_" + ("d" if sg > 0 else "e")], _m.asa_mat, Transform3D.IDENTITY)
			_dobradas.append(dob)
			# a perna: a coxa escondida nas penas, a canela clara, os dedos
			var perna := Node3D.new()
			perna.position = Vector3(sg * 0.045, -0.055, 0.03)
			_corpo.add_child(perna)
			_mi(perna, _m.perna, _m.perna_mat, Transform3D.IDENTITY)
			_detalhes.append(_mi(perna, _m.dedos, _m.perna_mat, Transform3D(Basis(), Vector3(0, -0.145, 0))))
			_detalhes.append(_mi(perna, _m.unhas, _m.unha_mat, Transform3D(Basis(), Vector3(0, -0.145, 0))))
			_pernas.append(perna)
		ereto()

	func ereto() -> void:
		var b := global_transform.basis
		var fr := -b.z
		fr.y = 0.0
		if fr.length() < 0.01:
			fr = Vector3.FORWARD
		global_transform.basis = Basis.looking_at(fr.normalized(), Vector3.UP)
		inclina = 0.0

	func _mi(pai: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		m.transform = xf
		pai.add_child(m)
		return m

	# ---------- as malhas (feitas uma vez) ----------

	## Um tubo ao longo de uma linha de pontos, a seção elíptica (largura = r*sx).
	static func _tubo(st: SurfaceTool, pts: Array, rs: Array, sx: float, lados := 10, fecha := true) -> void:
		var n := pts.size()
		var aneis := []
		for i in n:
			var pa: Vector3 = pts[maxi(i - 1, 0)]
			var pb: Vector3 = pts[mini(i + 1, n - 1)]
			var tg := (pb - pa).normalized()
			var up := Vector3.UP if absf(tg.dot(Vector3.UP)) < 0.95 else Vector3.BACK
			var bx := tg.cross(up).normalized()
			var by := bx.cross(tg).normalized()
			var anel := []
			for k in lados:
				var a := TAU * k / lados
				anel.append([(pts[i] as Vector3) + bx * cos(a) * float(rs[i]) * sx + by * sin(a) * float(rs[i]), (bx * cos(a) * sx + by * sin(a)).normalized(), float(i) / (n - 1)])
			aneis.append(anel)
		for i in n - 1:
			for k in lados:
				var k2 := (k + 1) % lados
				var q := [aneis[i][k], aneis[i + 1][k], aneis[i + 1][k2], aneis[i][k2]]
				for t in [0, 2, 1, 0, 3, 2]:
					st.set_normal(q[t][1])
					st.set_uv(Vector2(float(q[t][2]), float(k) / lados))
					st.add_vertex(q[t][0])
		if fecha:
			for e in [[0, -1.0], [n - 1, 1.0]]:
				var i: int = e[0]
				var cen: Vector3 = pts[i]
				for k in lados:
					var k2 := (k + 1) % lados
					var tri := [cen, aneis[i][k][0], aneis[i][k2][0]] if e[1] > 0 else [cen, aneis[i][k2][0], aneis[i][k][0]]
					for v in tri:
						st.set_normal(((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized() * float(e[1]))
						st.set_uv(Vector2(float(i) / (n - 1), 0.0))
						st.add_vertex(v)

	## Uma pena (lâmina com a ponta arredondada) de a, na direção d, comprimento L, largura w.
	static func _pena(st: SurfaceTool, a: Vector3, d: Vector3, lat: Vector3, L: float, w: float, uvx: float, curva := 0.0) -> void:
		var pts := []
		var n := 4
		for i in n + 1:
			var t := float(i) / n
			var lw := w * (1.0 - pow(t, 6.0) * 0.6)
			var c := a + d * L * t + Vector3.UP * curva * t * t * L
			pts.append([c - lat * lw * 0.5, c + lat * lw * 0.5, t])
		for i in n:
			var q := [pts[i][0], pts[i + 1][0], pts[i + 1][1], pts[i][1]]
			var tt := [pts[i][2], pts[i + 1][2], pts[i + 1][2], pts[i][2]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(uvx, float(tt[k])))
				st.add_vertex(q[k])

	static func _faz_malhas() -> void:
		# o corpo: corcunda, a barriga funda, afinando no rabo
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var perf := [[-0.17, 0.035, 0.02], [-0.145, 0.065, 0.015], [-0.1, 0.09, 0.005], [-0.04, 0.1, 0.0], [0.03, 0.095, -0.005], [0.09, 0.075, 0.0], [0.14, 0.045, 0.01], [0.17, 0.02, 0.015]]
		var pts := []
		var rs := []
		for e in perf:
			pts.append(Vector3(0, float(e[2]), float(e[0])))
			rs.append(float(e[1]))
		_tubo(st, pts, rs, 0.92, 14)
		_m.corpo = st.commit()
		# a gola de penas onde o pescoço pelado começa
		var sg2 := SurfaceTool.new()
		sg2.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tubo(sg2, [Vector3(0, 0, 0.02), Vector3(0, 0.005, -0.012), Vector3(0, 0.01, -0.03)], [0.05, 0.046, 0.026], 1.0, 12, false)
		_m.gola = sg2.commit()
		# o pescoço pelado (ao longo do -Z do nó do pescoço)
		var sp := SurfaceTool.new()
		sp.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tubo(sp, [Vector3(0, 0, 0.01), Vector3(0, 0.003, -0.03), Vector3(0, 0.002, -0.06), Vector3(0, 0.0, -0.09)], [0.026, 0.02, 0.017, 0.016], 0.95, 9)
		_m.pescoco = sp.commit()
		# a cabeça: comprida e baixa, a testa achatada
		var sc := SurfaceTool.new()
		sc.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tubo(sc, [Vector3(0, 0.003, 0.012), Vector3(0, 0.008, -0.008), Vector3(0, 0.009, -0.03), Vector3(0, 0.004, -0.05), Vector3(0, 0.0, -0.058)], [0.017, 0.024, 0.022, 0.015, 0.011], 0.85, 10)
		_m.cabeca = sc.commit()
		# o bico: comprido, a ponta curvando para baixo (gancho)
		var sb := SurfaceTool.new()
		sb.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bp := []
		var br := []
		for i in 8:
			var t := float(i) / 7.0
			bp.append(Vector3(0, 0.003 - t * t * t * 0.02, -0.052 - t * 0.04 + t * t * t * 0.006))
			br.append(lerpf(0.0095, 0.0025, t))
		_tubo(sb, bp, br, 0.7, 7)
		# a mandíbula de baixo (mais curta)
		_tubo(sb, [Vector3(0, -0.006, -0.05), Vector3(0, -0.008, -0.07), Vector3(0, -0.009, -0.082)], [0.006, 0.004, 0.0015], 0.75, 6)
		_m.bico = sb.commit()
		var so := SphereMesh.new()
		so.radius = 0.5
		so.height = 1.0
		so.radial_segments = 8
		so.rings = 5
		_m.olho = so
		# o rabo: 12 penas lado a lado, curto e quadrado
		var sr := SurfaceTool.new()
		sr.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 12:
			var x := lerpf(-0.055, 0.055, float(i) / 11.0)
			var d := Vector3(x * 0.6, 0, 1).normalized()
			_pena(sr, Vector3(x, -0.003 * absf(x) / 0.055, 0), d, Vector3(1, 0, -x * 0.6).normalized(), 0.15 - absf(x) * 0.12, 0.024, 0.2)
		_m.rabo = sr.commit()
		# as asas abertas
		for sg in [1.0, -1.0]:
			var lado := "d" if sg > 0 else "e"
			# o braço: a cobertura (as penas pequenas) e as secundárias serrilhadas atrás
			var sa := SurfaceTool.new()
			sa.begin(Mesh.PRIMITIVE_TRIANGLES)
			var cob := [Vector3(0, 0, -0.04), Vector3(sg * 0.31, 0, -0.035), Vector3(sg * 0.31, 0, 0.07), Vector3(0, 0, 0.08)]
			for k in ([0, 1, 2, 0, 2, 3] if sg > 0 else [0, 2, 1, 0, 3, 2]):
				sa.set_normal(Vector3.UP)
				sa.set_uv(Vector2(0.1, 0.0))
				sa.add_vertex(cob[k] + Vector3.UP * 0.004)
			for i in 11:
				var x2: float = sg * lerpf(0.02, 0.3, float(i) / 10.0)
				_pena(sa, Vector3(x2, 0, 0.03), Vector3(sg * 0.12, 0, 1).normalized(), Vector3(1, 0, 0), 0.16, 0.034, 0.2)
			_m["braco_" + lado] = sa.commit()
			# a mão: a cobertura e as seis primárias separadas na ponta
			var sm := SurfaceTool.new()
			sm.begin(Mesh.PRIMITIVE_TRIANGLES)
			var cm := [Vector3(0, 0, -0.03), Vector3(sg * 0.14, 0, -0.03), Vector3(sg * 0.15, 0, 0.08), Vector3(0, 0, 0.07)]
			for k in ([0, 1, 2, 0, 2, 3] if sg > 0 else [0, 2, 1, 0, 3, 2]):
				sm.set_normal(Vector3.UP)
				sm.set_uv(Vector2(0.35, 0.0))
				sm.add_vertex(cm[k] + Vector3.UP * 0.003)
			for i in 7:
				var t2 := float(i) / 6.0
				var base: Vector3 = Vector3(sg * lerpf(0.13, 0.04, t2 * t2), 0, lerpf(-0.025, 0.07, t2))
				var ang := lerpf(-0.12, 0.75, t2)
				var dv: Vector3 = Vector3(sg * cos(ang), 0, sin(ang))
				var comp := lerpf(0.29, 0.17, absf(t2 - 0.25) * 1.3)
				_pena(sm, base, dv, Vector3(-dv.z, 0, dv.x) * sg, comp, 0.034, 0.75, 0.05)
			_m["mao_" + lado] = sm.commit()
			# a asa fechada: dobrada junto do corpo, as pontas passando do rabo
			var sd := SurfaceTool.new()
			sd.begin(Mesh.PRIMITIVE_TRIANGLES)
			var dp := [Vector3(sg * 0.08, 0.05, -0.1), Vector3(sg * 0.09, 0.045, -0.04), Vector3(sg * 0.087, 0.04, 0.04), Vector3(sg * 0.068, 0.04, 0.12), Vector3(sg * 0.04, 0.045, 0.2), Vector3(sg * 0.018, 0.048, 0.235)]
			_tubo(sd, dp, [0.028, 0.045, 0.048, 0.038, 0.022, 0.008], 0.22, 10)
			_m["dobrada_" + lado] = sd.commit()
		# a perna (canela) e os dedos (3 para a frente, 1 para trás) com as unhas
		var sl := SurfaceTool.new()
		sl.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tubo(sl, [Vector3(0, 0.02, 0), Vector3(0, -0.06, 0.005), Vector3(0, -0.145, 0.0)], [0.018, 0.011, 0.01], 1.0, 7)
		_m.perna = sl.commit()
		var sdd := SurfaceTool.new()
		sdd.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sun := SurfaceTool.new()
		sun.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in [[-0.45, 0.055], [0.0, 0.065], [0.45, 0.055], [PI, 0.035]]:
			var dd := Vector3(sin(float(e[0])), 0, -cos(float(e[0])))
			var L := float(e[1])
			_tubo(sdd, [Vector3(0, 0, 0), dd * L * 0.5 + Vector3.DOWN * 0.003, dd * L + Vector3.DOWN * 0.004], [0.006, 0.005, 0.004], 1.0, 5)
			_tubo(sun, [dd * L + Vector3.DOWN * 0.004, dd * (L + 0.012) + Vector3.DOWN * 0.007], [0.0035, 0.0008], 1.0, 4)
		_m.dedos = sdd.commit()
		_m.unhas = sun.commit()
		# os materiais
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
float hh(vec2 q) { return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	// pena: preta, a raque (o talo do meio) um pouco mais clara, a beirada gasta
	float meio = 1.0 - smoothstep(0.0, 0.08, abs(fract(UV.x * 31.0) - 0.5));
	vec3 preto = vec3(0.032, 0.031, 0.035) * (0.85 + 0.3 * hh(floor(UV * vec2(40.0, 6.0))));
	vec3 c = preto;
	if (UV.x > 0.6) {
		// as primárias: o talo claro em cima; embaixo a base clara (a mancha das pontas)
		c = mix(preto, vec3(0.3, 0.29, 0.28), meio * 0.25);
		if (!FRONT_FACING) {
			c = mix(c, vec3(0.7, 0.69, 0.66), (1.0 - smoothstep(0.25, 0.55, UV.y)) * 0.85);
		}
	}
	ALBEDO = c * 0.8;
	ROUGHNESS = 0.75;
	SPECULAR = 0.15;
	// o brilho frio das penas no sol
	RIM = 0.1;
	RIM_TINT = 0.6;
}
"""
		var am := ShaderMaterial.new()
		am.shader = sh
		_m.asa_mat = am
		var shp := Shader.new()
		shp.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
varying vec3 lp;
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lp = VERTEX; }
void fragment() {
	// as penas do corpo em fileiras (escamas sobrepostas), pretas com brilho frio
	vec2 g = vec2(lp.x * 70.0 + floor(lp.z * 45.0) * 0.5, lp.z * 45.0);
	float esc = fract(g.y) + 0.35 * abs(fract(g.x) - 0.5);
	float borda = smoothstep(0.75, 0.95, esc);
	vec3 c = vec3(0.035, 0.034, 0.038) * (0.8 + 0.4 * ruido(lp * 120.0)) * (1.0 - borda * 0.35);
	ALBEDO = c;
	ROUGHNESS = 0.78;
	SPECULAR = 0.18;
	RIM = 0.12;
	RIM_TINT = 0.6;
}
"""
		var pena := ShaderMaterial.new()
		pena.shader = shp
		_m.pena = pena
		var shk := Shader.new()
		shk.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec3 lp;
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lp = VERTEX; }
void fragment() {
	// a pele pelada: cinza-escura, cheia de rugas e verrugas
	float rug = ruido(lp * vec3(260.0, 520.0, 160.0));
	float ver = smoothstep(0.72, 0.85, ruido(lp * 330.0 + 5.0));
	vec3 c = mix(vec3(0.09, 0.088, 0.085), vec3(0.2, 0.19, 0.18), rug);
	c = mix(c, vec3(0.26, 0.25, 0.23), ver * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
"""
		var pele := ShaderMaterial.new()
		pele.shader = shk
		_m.pele = pele
		var shb := Shader.new()
		shb.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
void fragment() {
	// o bico: escuro na base, a ponta (o gancho) cor de marfim
	vec3 c = mix(vec3(0.12, 0.115, 0.11), vec3(0.78, 0.74, 0.64), smoothstep(0.45, 0.75, UV.x));
	ALBEDO = c;
	ROUGHNESS = 0.35;
	SPECULAR = 0.45;
}
"""
		var bm := ShaderMaterial.new()
		bm.shader = shb
		_m.bico_mat = bm
		var om := StandardMaterial3D.new()
		om.albedo_color = Color(0.2, 0.1, 0.04)
		om.roughness = 0.05
		om.metallic_specular = 0.9
		_m.olho_mat = om
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.46, 0.45, 0.43)
		pm.roughness = 0.85
		_m.perna_mat = pm
		var um := StandardMaterial3D.new()
		um.albedo_color = Color(0.06, 0.055, 0.05)
		um.roughness = 0.4
		_m.unha_mat = um

	# ---------- os movimentos ----------

	## Vai até o ângulo aos poucos (k por segundo).
	func _sv(nome: String, alvo: float, k: float, delta: float) -> float:
		var v := float(_ac.get(nome, alvo))
		v = lerpf(v, alvo, 1.0 - exp(-k * delta))
		_ac[nome] = v
		return v

	var _detalhes := []                # as partes pequenas (somem de longe)
	var _longe := false
	var _lod_t := 0.0
	var _pula := 0
	var _acum := 0.0

	func _process(delta0: float) -> void:
		# de longe: some o miúdo (olhos, pés, bico, gola) e anima menos vezes
		_lod_t -= delta0
		if _lod_t <= 0.0:
			_lod_t = 0.5
			var cam := get_viewport().get_camera_3d()
			var lg := cam != null and cam.global_position.distance_to(global_position) > 30.0
			if lg != _longe:
				_longe = lg
				for d in _detalhes:
					if is_instance_valid(d):
						(d as Node3D).visible = not lg
		_acum += delta0
		_pula += 1
		if _longe and _pula % 3 != 0:
			return
		var delta := _acum
		_acum = 0.0
		_t += delta
		abre = maxf(0.0, abre - delta)
		levanta = maxf(0.0, levanta - delta)
		var voando := modo in ["plana", "bate", "pousa"]
		var asas := voando or modo in ["sol", "ameaca", "pula"] or abre > 0.0
		for w in _asas:
			(w.braco as Node3D).visible = asas
		for d in _dobradas:
			(d as Node3D).visible = not asas
		# olhar em volta: a cabeça vira de vez em quando
		if randf() < delta * (0.8 if alerta else 0.35):
			_olhar_alvo = randf_range(-0.9, 0.9)
		_olhar = lerpf(_olhar, _olhar_alvo, 1.0 - exp(-delta * 6.0))
		# os alvos de cada parte (corpo, pescoço, cabeça, asas, pernas, rabo)
		var corpo_x := 0.0          # inclinação do corpo (+ a frente para cima)
		var corpo_y := 0.0
		var pesc_x := 0.3           # o pescoço (+ para cima)
		var pesc_y := 0.0
		var pesc_z := 0.0
		var braco_z := 0.0          # a asa subindo (+) e descendo
		var braco_y := 0.0          # para trás (-) / frente (+)
		var braco_x := 0.0          # torcida (borda da frente para cima)
		var mao_y := 0.0
		var mao_z := 0.0
		var perna_x := 0.0
		var rabo_x := 0.0
		var rabo_abre := 1.0
		match modo:
			"plana":
				braco_z = 0.06 + sin(_t * 0.8) * 0.02
				braco_y = 0.06
				mao_y = -0.12
				mao_z = 0.08
				perna_x = -1.4
				pesc_x = -0.05
				pesc_y = _olhar * 0.5
			"bate":
				# batida forte: desce com a asa aberta, sobe com o punho dobrando para trás
				var ph := _t * TAU * 4.2
				var s := sin(ph)
				var sobe := maxf(cos(ph), 0.0)
				braco_z = 0.15 + s * 0.75
				braco_y = 0.12 - sobe * 0.35
				braco_x = s * 0.25
				mao_y = -0.15 - sobe * 0.9
				mao_z = s * 0.35
				perna_x = -1.3
				pesc_x = 0.0
			"pousa":
				# freando: asas para cima e para a frente, o rabo aberto para baixo, as pernas na frente
				var ph2 := _t * TAU * 2.8
				braco_z = 0.55 + sin(ph2) * 0.3
				braco_y = 0.35
				braco_x = 0.55
				mao_y = -0.2
				mao_z = 0.25
				perna_x = 1.35
				corpo_x = 0.55
				rabo_x = -0.5
				rabo_abre = 1.5
				pesc_x = 0.1
			"chao":
				# em pé, encolhido (o pescoço recolhido na gola)
				corpo_x = 0.62
				pesc_x = 0.35 if not alerta else 0.85
				pesc_z = 0.03
				pesc_y = _olhar
				rabo_x = -0.35
			"anda":
				var ph3 := _t * 7.0
				corpo_x = 0.45
				corpo_y = absf(sin(ph3)) * 0.015
				pesc_x = 0.45
				pesc_z = sin(ph3) * 0.035          # a cabeça vai e vem
				rabo_x = -0.3
			"pula":
				# pulos compridos com as asas meio abertas
				var ph4 := _t * 5.0
				corpo_x = 0.2
				corpo_y = absf(sin(ph4)) * 0.18
				braco_z = 0.35 + sin(ph4 * 2.0) * 0.15
				braco_y = -0.55
				mao_y = -1.0
				pesc_x = 0.3
				perna_x = 0.3 * absf(sin(ph4))
			"come":
				if levanta > 0.0 or alerta:
					corpo_x = 0.25
					pesc_x = 0.9
					pesc_y = _olhar * 0.7
					# engolindo: o pescoço sobe e desce
					pesc_z = sin(_t * 9.0) * 0.012 if levanta > 0.0 else 0.0
				else:
					# a cabeça enfiada na carniça, puxando aos trancos
					var ciclo := fmod(_t, 1.6) / 1.6
					var tranco := smoothstep(0.55, 0.62, ciclo) * (1.0 - smoothstep(0.8, 0.95, ciclo))
					corpo_x = -0.05 + tranco * 0.15
					pesc_x = -1.05 + tranco * 0.45 + sin(_t * 23.0) * 0.04 * tranco
					pesc_y = sin(_t * 1.3) * 0.25
					pesc_z = -0.02
					corpo_y = -0.01
				rabo_x = -0.15
			"sol":
				# tomando sol: em pé, as asas abertas para os lados, paradas
				corpo_x = 0.55
				braco_z = 0.25
				braco_y = 0.2
				braco_x = 0.35
				mao_y = -0.1
				mao_z = -0.15
				pesc_x = 0.6
				pesc_y = _olhar * 0.6
				rabo_x = -0.45
				rabo_abre = 1.3
			"ameaca":
				# abre as asas para a frente, cabeça baixa esticada, chiando
				corpo_x = 0.1
				braco_z = 0.45 + sin(_t * 12.0) * 0.08
				braco_y = 0.55
				braco_x = 0.3
				mao_y = 0.2
				pesc_x = -0.25
				pesc_z = -0.03
				corpo_y = absf(sin(_t * 8.0)) * 0.05
		if abre > 0.0 and not voando and modo != "ameaca":
			braco_z = 0.5 + sin(_t * 10.0) * 0.1
			braco_y = 0.3
			mao_y = 0.0
		var k := 14.0 if modo == "bate" else 7.0
		for w in _asas:
			var sg: float = w.sg
			var bz := _sv("bz", braco_z, k, delta) if sg > 0 else float(_ac.get("bz", braco_z))
			var by := _sv("by", braco_y, k, delta) if sg > 0 else float(_ac.get("by", braco_y))
			var bx := _sv("bx", braco_x, k, delta) if sg > 0 else float(_ac.get("bx", braco_x))
			var my := _sv("my", mao_y, k, delta) if sg > 0 else float(_ac.get("my", mao_y))
			var mz := _sv("mz", mao_z, k, delta) if sg > 0 else float(_ac.get("mz", mao_z))
			(w.braco as Node3D).rotation = Vector3(bx, sg * by, sg * bz)
			(w.mao as Node3D).rotation = Vector3(0, sg * my, sg * mz)
		var px := _sv("px", perna_x, 6.0, delta)
		var cx := _sv("cx", corpo_x, 6.0, delta)
		_corpo.rotation.x = cx
		for p in _pernas:
			# em pé as pernas ficam retas para baixo (o corpo inclina, elas não)
			(p as Node3D).rotation.x = px - (cx if not voando else 0.0)
		var em_pe := not voando
		_corpo.position.y = _sv("cy", (0.205 + corpo_y) if em_pe else 0.0, 10.0, delta)
		_pesc.rotation = Vector3(_sv("nx", pesc_x, 8.0, delta), _sv("ny", pesc_y, 5.0, delta), 0.0)
		_pesc.position = Vector3(0, 0.05, -0.155 + _sv("nz", pesc_z, 12.0, delta))
		_cab.rotation.x = -float(_ac.get("nx", 0.0)) * 0.55 if em_pe else 0.1
		_rabo.rotation.x = _sv("rx", rabo_x, 5.0, delta)
		_rabo.scale = Vector3(_sv("ra", rabo_abre, 5.0, delta), 1.0, 1.0)
