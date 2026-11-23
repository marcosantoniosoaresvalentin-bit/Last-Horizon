extends Node3D
## Os urubus (urubu-de-cabeça-preta, Coragyps atratus).
##
## Onde tem bicho morto (a carcaça no chão, um pedaço de carne, a buchada, uma pata, a
## cabeça) eles acham depois de umas horas: vão chegando um por um lá do alto e ficam
## rondando por cima, planando em círculos (quase sem bater as asas). Quando não tem
## ninguém perto, descem em espiral, pousam um pouco longe, chegam andando aos pulinhos
## e comem (bicando, brigando de vez em quando com chiado). Gente chegando perto: todos
## levantam voo (batendo as asas pesado) e voltam a rondar. Acabou a carne, ou a noite
## chegando: vão embora.
##
## Não são salvos: aparecem e somem conforme a carniça. O que comem fica na carniça
## (caca.comer), e isso adianta a decomposição até sobrar só o osso.

const Sons := preload("res://scripts/sons.gd")

const MAX_URUBUS := 16
const KG_H := 6.0                  # quanto um urubu come por hora do jogo (kg)
const LONGE_POUSA := 28.0          # ninguém a menos disso para descer
const LONGE_FOGE := 15.0           # alguém chega a menos disso: voam
const V_PLANA := 9.0               # m/s planando

var _jogo: Node = null
var _aves: Array = []              # {node: Urubu, est, site, ...}
var _sites := {}                   # chave -> {pos, kg, comidas: [...], chegou: tempo, ...}
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


func update(delta: float) -> void:
	if _jogo == null or _jogo._caca == null:
		return
	_t_sites -= delta
	if _t_sites <= 0.0:
		_t_sites = 2.0
		_acha_sites()
	var dh := delta / maxf(float(_jogo.sim.real_s_por_hora()), 1.0)
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
	# os lugares que continuam guardam o que já tinham (quando chegaram)
	for k in novos:
		if _sites.has(k):
			novos[k]["t"] = _sites[k].get("t", 0.0)
			novos[k]["n"] = _sites[k].get("n", 0)
			novos[k]["prox"] = _sites[k].get("prox", 0.0)
		else:
			novos[k]["t"] = 0.0
			novos[k]["n"] = 0
	_sites = novos
	# quantos urubus cada lugar chama (mais carne, mais urubu); vão chegando aos poucos
	var tot := _aves.size()
	for k in _sites:
		var s: Dictionary = _sites[k]
		s.t = float(s.t) + 2.0
		var quer := clampi(roundi(pow(maxf(float(s.kg), 0.5), 0.4) / 1.4), 1, 8)
		var tem := 0
		for a in _aves:
			if str(a.site) == k and str(a.est) != "indo":
				tem += 1
		if _de_dia() and tem < quer and tot < MAX_URUBUS and float(s.t) > float(s.get("prox", 0.0)):
			_novo(k)
			tot += 1
			s["prox"] = float(s.t) + _rng.randf_range(8.0, 30.0)
	# lugar que acabou: quem estava nele vai embora (depois de rondar mais um pouco)
	for a in _aves:
		if not _sites.has(str(a.site)) and str(a.est) != "indo":
			if str(a.est) in ["chao", "come", "andando"]:
				_levanta(a)
			a["sem_site"] = float(a.get("sem_site", 0.0))


func _novo(site: String) -> void:
	var s: Dictionary = _sites[site]
	var c: Vector3 = s.pos
	var ang := _rng.randf() * TAU
	var n := Urubu.new()
	add_child(n)
	var de := c + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(160.0, 220.0)
	de.y = float(_jogo.ground_at(de.x, de.z)) + _rng.randf_range(60.0, 90.0)
	n.global_position = de
	n.modo = "plana"
	_aves.append({"node": n, "est": "chegando", "site": site, "R": _rng.randf_range(12.0, 26.0), "alt": _rng.randf_range(20.0, 42.0),
		"ang": _rng.randf() * TAU, "sent": 1.0 if _rng.randf() < 0.6 else -1.0, "t": 0.0, "ronda": 0.0, "bate": 0.0,
		"vel": Vector3.ZERO, "alvo": Vector3.ZERO, "comida": {}, "pulo": 0.0, "bica": 0.0, "chia": _rng.randf_range(6.0, 20.0)})


func _levanta(a: Dictionary) -> void:
	a.est = "subindo"
	a.t = 0.0
	(a.node as Urubu).modo = "bate"
	a.bate = 2.2
	if _rng.randf() < 0.7:
		Sons.play_at(self, "urubu_asas", (a.node as Node3D).global_position, 0.0, _rng.randf_range(0.9, 1.1), 60.0, 5.0)


func _ave(a: Dictionary, delta: float, dh: float) -> void:
	var n: Urubu = a.node
	if not is_instance_valid(n):
		_aves.erase(a)
		return
	a.t = float(a.t) + delta
	var tem_site := _sites.has(str(a.site))
	var site: Dictionary = _sites.get(str(a.site), {})
	var c: Vector3 = site.pos if tem_site else n.global_position
	var chao_c := float(_jogo.ground_at(c.x, c.z))
	# a noite chegando ou sem carniça faz tempo: vão embora
	if str(a.est) != "indo":
		if not _de_dia() or (not tem_site and float(a.t) > 40.0 and str(a.est) == "rondando"):
			if str(a.est) in ["chao", "come", "andando"]:
				_levanta(a)
			else:
				a.est = "indo"
				var ang := _rng.randf() * TAU
				a.alvo = n.global_position + Vector3(cos(ang), 0, sin(ang)) * 400.0 + Vector3.UP * 60.0
	match str(a.est):
		"chegando":
			var alvo := c + Vector3(cos(float(a.ang)) * float(a.R), chao_c - c.y + float(a.alt), sin(float(a.ang)) * float(a.R))
			_voa_para(a, alvo, delta, V_PLANA * 1.3)
			if n.global_position.distance_to(alvo) < 8.0:
				a.est = "rondando"
				a.ronda = 0.0
		"rondando":
			a.ronda = float(a.ronda) + delta
			a.ang = float(a.ang) + float(a.sent) * V_PLANA / float(a.R) * delta
			var alt := chao_c + float(a.alt) + sin(float(a.t) * 0.3) * 2.0
			var alvo2 := Vector3(c.x + cos(float(a.ang)) * float(a.R), alt, c.z + sin(float(a.ang)) * float(a.R))
			_voa_para(a, alvo2, delta, V_PLANA)
			# de vez em quando umas batidas de asa
			a.bate = maxf(0.0, float(a.bate) - delta)
			if float(a.bate) <= 0.0 and _rng.randf() < delta * 0.04:
				a.bate = _rng.randf_range(0.8, 1.6)
			n.modo = "bate" if float(a.bate) > 0.0 else "plana"
			# desce: rondou um tempo, ninguém perto
			if tem_site and float(a.ronda) > float(a.get("espera", 18.0)) and _mais_perto(c) > LONGE_POUSA and _de_dia():
				a.est = "descendo"
				var ang2 := _rng.randf() * TAU
				var pouso := c + Vector3(cos(ang2), 0, sin(ang2)) * _rng.randf_range(3.0, 7.0)
				pouso.y = float(_jogo.ground_at(pouso.x, pouso.z))
				a.alvo = pouso
				a.espera = _rng.randf_range(10.0, 35.0)
		"descendo":
			if tem_site and _mais_perto(c) < LONGE_POUSA * 0.8:
				_levanta(a)
				return
			var p := n.global_position
			var alvo3: Vector3 = a.alvo
			var hd := Vector2(alvo3.x - p.x, alvo3.z - p.z)
			var falta := p.y - alvo3.y
			# espiral: gira em volta do ponto de pouso, fechando e descendo
			var raio := clampf(falta * 0.5, 0.0, 14.0)
			a.ang = float(a.ang) + float(a.sent) * 0.9 * delta
			var alvo4 := alvo3 + Vector3(cos(float(a.ang)) * raio, minf(falta, falta - 3.5 * delta * 2.0), sin(float(a.ang)) * raio)
			alvo4.y = maxf(alvo3.y, p.y - 4.0 * delta)
			_voa_para(a, alvo4, delta, clampf(V_PLANA * 0.7, 3.0, 8.0))
			n.modo = "plana" if falta > 4.0 else "pousa"
			if falta < 0.35 and hd.length() < 1.5:
				n.global_position = Vector3(p.x, alvo3.y, p.z)
				a.est = "chao"
				a.t = 0.0
				n.modo = "chao"
		"chao", "andando":
			n.global_position.y = float(_jogo.ground_at(n.global_position.x, n.global_position.z))
			if _mais_perto(n.global_position) < LONGE_FOGE:
				_levanta(a)
				return
			# escolhe o que comer (o mais perto que ainda tem carne) e vai aos pulinhos
			if (a.comida as Dictionary).is_empty() or not _comida_ok(a):
				var melhor := {}
				var md := 1e9
				for f in site.get("comidas", []):
					var d := (f.pos as Vector3).distance_to(n.global_position)
					if d < md and float(f.kg) > 0.05:
						md = d
						melhor = f
				if melhor.is_empty():
					_levanta(a)
					return
				a.comida = melhor
				var ang3 := _rng.randf() * TAU
				var r := float(melhor.r) + _rng.randf_range(0.15, 0.35)
				var ap: Vector3 = (melhor.pos as Vector3) + Vector3(cos(ang3), 0, sin(ang3)) * r
				ap.y = float(_jogo.ground_at(ap.x, ap.z))
				a.alvo = ap
			var alvo5: Vector3 = a.alvo
			var d5 := Vector2(alvo5.x - n.global_position.x, alvo5.z - n.global_position.z)
			if d5.length() > 0.12:
				a.est = "andando"
				n.modo = "anda"
				var passo := minf(d5.length(), 0.9 * delta)
				var dv := Vector3(d5.x, 0, d5.y).normalized()
				n.global_position += dv * passo
				_vira(n, dv, delta * 6.0)
			else:
				a.est = "come"
				a.t = 0.0
		"come":
			n.global_position.y = float(_jogo.ground_at(n.global_position.x, n.global_position.z))
			if _mais_perto(n.global_position) < LONGE_FOGE:
				_levanta(a)
				return
			if not _comida_ok(a):
				a.comida = {}
				a.est = "chao"
				return
			var cp: Vector3 = (a.comida as Dictionary).pos
			var dv2 := Vector3(cp.x - n.global_position.x, 0, cp.z - n.global_position.z)
			if dv2.length() > 0.01:
				_vira(n, dv2.normalized(), delta * 4.0)
			# bicando (e de vez em quando abre as asas, briga, chia)
			a.chia = float(a.chia) - delta
			if float(a.chia) <= 0.0:
				a.chia = _rng.randf_range(8.0, 25.0)
				n.abre = 1.2
				Sons.play_at(self, "urubu_chiado", n.global_position + Vector3.UP * 0.3, -2.0, _rng.randf_range(0.9, 1.15), 40.0, 3.0)
			n.modo = "come"
			_jogo._caca.comer(str((a.comida as Dictionary).key), KG_H * dh)
			(a.comida as Dictionary).kg = float((a.comida as Dictionary).kg) - KG_H * dh
		"subindo":
			# levanta batendo forte e sobe para rondar de novo
			var p2 := n.global_position
			var ang4 := atan2(p2.z - c.z, p2.x - c.x)
			var alvo6 := Vector3(c.x + cos(ang4) * 18.0, chao_c + 16.0, c.z + sin(ang4) * 18.0)
			_voa_para(a, alvo6, delta, 6.5)
			n.modo = "bate"
			if p2.y - float(_jogo.ground_at(p2.x, p2.z)) > 10.0 or float(a.t) > 6.0:
				a.est = "rondando"
				a.ronda = 0.0
				a.ang = ang4
				a.espera = _rng.randf_range(20.0, 50.0)
				a.comida = {}
		"indo":
			var alvo7: Vector3 = a.alvo
			_voa_para(a, alvo7, delta, V_PLANA * 1.4)
			n.modo = "plana"
			if n.global_position.distance_to(alvo7) < 20.0 or float(a.t) > 90.0:
				n.queue_free()
				_aves.erase(a)


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
	var quer := d.normalized() * v
	vel = vel.lerp(quer, 1.0 - exp(-delta * 1.2))
	if vel.length() < 0.5:
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
	var roll := clampf(-curva * 0.35, -0.7, 0.7)
	n.inclina = lerpf(n.inclina, roll, 1.0 - exp(-delta * 2.0))
	var b := Basis.looking_at(Vector3(fr.x, fr.y * 0.4, fr.z), Vector3.UP)
	n.global_transform.basis = b * Basis(Vector3.FORWARD, n.inclina)


func _vira(n: Node3D, dir: Vector3, k: float) -> void:
	var b := Basis.looking_at(dir, Vector3.UP)
	n.global_transform.basis = n.global_transform.basis.orthonormalized().slerp(b, clampf(k, 0.0, 1.0))


# ================== O URUBU (o desenho) ==================

class Urubu:
	extends Node3D
	## Uns 62 cm do bico ao rabo, 1,45 m de asa aberta. Todo preto, a cabeça e o pescoço
	## de pele pelada cinza-escura enrugada, o bico fino e curvo (escuro, a ponta clara),
	## as pernas cinza-claro; embaixo da ponta das asas uma mancha clara (as penas
	## primárias). Frente = -Z. Modos: "plana" (asas abertas paradas, um V raso),
	## "bate" (batendo), "pousa" (asas abertas freando, pernas para baixo), "chao" (em pé,
	## asas fechadas), "anda" (aos pulinhos), "come" (bicando).

	var modo := "plana"
	var inclina := 0.0
	var abre := 0.0
	var _t := 0.0
	var _corpo: Node3D
	var _cab: Node3D
	var _asas := []
	var _dobradas := []
	var _pernas := []
	static var _m := {}

	func _ready() -> void:
		_t = randf() * 10.0
		if _m.is_empty():
			_faz_malhas()
		_corpo = Node3D.new()
		add_child(_corpo)
		_mi(_corpo, _m.corpo, _m.pena, Transform3D(Basis().scaled(Vector3(0.15, 0.14, 0.34)), Vector3(0, 0.0, 0.0)))
		_mi(_corpo, _m.rabo, _m.pena, Transform3D(Basis(), Vector3(0, 0.01, 0.2)))
		var pesc := _mi(_corpo, _m.pescoco, _m.pele, Transform3D(Basis(Vector3.RIGHT, -0.9).scaled(Vector3(0.045, 0.1, 0.045)), Vector3(0, 0.07, -0.16)))
		pesc.name = "pescoco"
		_cab = Node3D.new()
		_cab.position = Vector3(0, 0.11, -0.21)
		_corpo.add_child(_cab)
		_mi(_cab, _m.cabeca, _m.pele, Transform3D(Basis().scaled(Vector3(0.05, 0.05, 0.075)), Vector3.ZERO))
		_mi(_cab, _m.bico, _m.bico_mat, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.25), Vector3(0, -0.006, -0.055)))
		for sg in [-1.0, 1.0]:
			# o olho
			_mi(_cab, _m.olho, _m.olho_mat, Transform3D(Basis().scaled(Vector3.ONE * 0.008), Vector3(sg * 0.022, 0.008, -0.018)))
			# a asa: o braço e a mão (pontas abertas como dedos)
			var braco := Node3D.new()
			braco.position = Vector3(sg * 0.07, 0.05, -0.04)
			_corpo.add_child(braco)
			_mi(braco, _m.braco_d if sg > 0 else _m.braco_e, _m.asa_mat, Transform3D.IDENTITY)
			var mao := Node3D.new()
			mao.position = Vector3(sg * 0.33, 0, 0.0)
			braco.add_child(mao)
			_mi(mao, _m.mao_d if sg > 0 else _m.mao_e, _m.asa_mat, Transform3D.IDENTITY)
			_asas.append({"braco": braco, "mao": mao, "sg": sg})
			# a asa fechada (dobrada no lado do corpo, a ponta passando do rabo)
			var dob := _mi(_corpo, _m.corpo, _m.pena, Transform3D(Basis(Vector3.UP, sg * 0.08).scaled(Vector3(0.035, 0.07, 0.3)), Vector3(sg * 0.12, 0.035, 0.07)))
			_dobradas.append(dob)
			# a perna
			var perna := Node3D.new()
			perna.position = Vector3(sg * 0.05, -0.1, 0.03)
			_corpo.add_child(perna)
			_mi(perna, _m.perna, _m.perna_mat, Transform3D(Basis().scaled(Vector3(0.014, 0.1, 0.014)), Vector3(0, -0.06, 0)))
			_mi(perna, _m.perna, _m.perna_mat, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.01, 0.07, 0.008)), Vector3(0, -0.105, -0.03)))
			_pernas.append(perna)

	func _mi(pai: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		m.transform = xf
		pai.add_child(m)
		return m

	static func _faz_malhas() -> void:
		var sph := SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		sph.radial_segments = 12
		sph.rings = 7
		_m.corpo = sph
		_m.cabeca = sph
		_m.olho = sph
		var cil := CylinderMesh.new()
		cil.top_radius = 0.5
		cil.bottom_radius = 0.6
		cil.height = 1.0
		cil.radial_segments = 8
		_m.pescoco = cil
		var pe := CylinderMesh.new()
		pe.top_radius = 0.5
		pe.bottom_radius = 0.4
		pe.height = 1.0
		pe.radial_segments = 6
		_m.perna = pe
		var bc := CylinderMesh.new()
		bc.top_radius = 0.0
		bc.bottom_radius = 0.011
		bc.height = 0.055
		bc.radial_segments = 6
		_m.bico = bc
		# o rabo: curto e quadrado
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for q in [[Vector3(-0.06, 0, 0), Vector3(0.06, 0, 0), Vector3(0.065, -0.01, 0.15)], [Vector3(-0.06, 0, 0), Vector3(0.065, -0.01, 0.15), Vector3(-0.065, -0.01, 0.15)]]:
			for v in q:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)
		_m.rabo = st.commit()
		for sg in [1.0, -1.0]:
			# o braço da asa: largo (cobre o corpo até o cotovelo)
			var sb := SurfaceTool.new()
			sb.begin(Mesh.PRIMITIVE_TRIANGLES)
			var b := [Vector3(0, 0, -0.07), Vector3(sg * 0.33, 0, -0.06), Vector3(sg * 0.33, 0, 0.17), Vector3(0, 0, 0.16)]
			_quad(sb, b, [0.0, 0.0, 0.0, 0.0], sg)
			_m["braco_" + ("d" if sg > 0 else "e")] = sb.commit()
			# a mão: afinando, com as 6 penas primárias separadas na ponta (os "dedos")
			var sm := SurfaceTool.new()
			sm.begin(Mesh.PRIMITIVE_TRIANGLES)
			var mm := [Vector3(0, 0, -0.06), Vector3(sg * 0.2, 0, -0.055), Vector3(sg * 0.22, 0, 0.12), Vector3(0, 0, 0.17)]
			_quad(sm, mm, [0.0, 0.6, 0.6, 0.0], sg)
			for i in 6:
				var z0 := lerpf(-0.05, 0.1, float(i) / 5.0)
				var comp := 0.17 - absf(float(i) - 1.5) * 0.018
				var ang := lerpf(-0.18, 0.32, float(i) / 5.0)
				var dirv := Vector3(sg * cos(ang), 0, sin(ang))
				var lat := Vector3(-dirv.z * sg, 0, dirv.x * sg).normalized() * 0.014
				var a0 := Vector3(sg * 0.19, 0, z0)
				var pena := [a0 - lat, a0 + dirv * comp - lat * 0.6, a0 + dirv * comp + lat * 0.6, a0 + lat]
				_quad(sm, pena, [0.9, 0.5, 0.5, 0.9], sg)
			_m["mao_" + ("d" if sg > 0 else "e")] = sm.commit()
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
void fragment() {
	// em cima tudo preto; embaixo, a base das primárias clara (a mancha das pontas)
	vec3 preto = vec3(0.035, 0.035, 0.04);
	vec3 c = preto;
	if (!FRONT_FACING) {
		c = mix(preto, vec3(0.62, 0.62, 0.6), smoothstep(0.45, 0.7, UV.x));
	}
	ALBEDO = c;
	ROUGHNESS = 0.65;
	SPECULAR = 0.35;
}
"""
		var am := ShaderMaterial.new()
		am.shader = sh
		_m.asa_mat = am
		var pena := StandardMaterial3D.new()
		pena.albedo_color = Color(0.04, 0.04, 0.045)
		pena.roughness = 0.6
		pena.metallic_specular = 0.2
		pena.cull_mode = BaseMaterial3D.CULL_DISABLED
		_m.pena = pena
		var pele := StandardMaterial3D.new()
		pele.albedo_color = Color(0.17, 0.16, 0.16)
		pele.roughness = 0.9
		_m.pele = pele
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.45, 0.42, 0.38)
		bm.roughness = 0.5
		_m.bico_mat = bm
		var om := StandardMaterial3D.new()
		om.albedo_color = Color(0.25, 0.12, 0.05)
		om.roughness = 0.1
		_m.olho_mat = om
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.56, 0.54, 0.5)
		pm.roughness = 0.8
		_m.perna_mat = pm

	static func _quad(st: SurfaceTool, q: Array, uvx: Array, sg: float) -> void:
		var tri := [0, 1, 2, 0, 2, 3] if sg > 0 else [0, 2, 1, 0, 3, 2]
		for t in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(uvx[t]), 0.0))
			st.add_vertex(q[t])

	func _process(delta: float) -> void:
		_t += delta
		abre = maxf(0.0, abre - delta)
		var voando := modo in ["plana", "bate", "pousa"]
		var asas_abertas := voando or abre > 0.0
		for w in _asas:
			(w.braco as Node3D).visible = asas_abertas
		for d in _dobradas:
			(d as Node3D).visible = not asas_abertas
		for p in _pernas:
			(p as Node3D).rotation.x = -1.2 if voando and modo != "pousa" else 0.0
		var cab_x := 0.0
		var corpo_y := 0.0
		var corpo_x := 0.0
		match modo:
			"plana":
				for w in _asas:
					var sg: float = w.sg
					(w.braco as Node3D).rotation = Vector3(0, 0, sg * 0.14 + sin(_t * 0.7) * 0.02)
					(w.mao as Node3D).rotation = Vector3(0, -sg * 0.08, sg * 0.06)
			"bate":
				var f := sin(_t * 11.0)
				for w in _asas:
					var sg2: float = w.sg
					(w.braco as Node3D).rotation = Vector3(0, 0, sg2 * (0.15 + f * 0.65))
					(w.mao as Node3D).rotation = Vector3(0, -sg2 * 0.2 * f, sg2 * f * 0.35)
			"pousa":
				for w in _asas:
					var sg3: float = w.sg
					(w.braco as Node3D).rotation = Vector3(-0.5, 0, sg3 * (0.35 + sin(_t * 8.0) * 0.25))
					(w.mao as Node3D).rotation = Vector3(0, sg3 * 0.3, 0)
				corpo_x = 0.5
			"anda":
				corpo_y = absf(sin(_t * 9.0)) * 0.05
				corpo_x = 0.3
			"come":
				corpo_x = 0.05
				var bic := sin(_t * 5.0)
				cab_x = -0.7 - maxf(bic, 0.0) * 0.6
				corpo_y = -0.03
			_:
				corpo_x = 0.4
		if abre > 0.0 and not voando:
			for w in _asas:
				var sg4: float = w.sg
				(w.braco as Node3D).rotation = Vector3(0, -sg4 * 0.3, sg4 * (0.5 + sin(_t * 6.0) * 0.15))
				(w.mao as Node3D).rotation = Vector3(0, -sg4 * 0.3, 0)
		_corpo.rotation.x = corpo_x if not voando else 0.0
		_corpo.position.y = (0.225 + corpo_y) if not voando else 0.0
		_cab.rotation.x = cab_x
		_cab.position = Vector3(0, 0.11 + cab_x * 0.06, -0.21 + cab_x * 0.03)
