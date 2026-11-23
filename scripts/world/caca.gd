extends Node3D
## Caça com arco e flecha.
##
## A flecha voa de verdade (sai na velocidade do arco puxado, cai com a gravidade) e
## acerta a parte do corpo que estiver no caminho. Cada bicho tem as suas partes, cada
## uma com o seu dano: a cabeça mata quase sempre, o peito (coração e pulmão) mata em um
## ou dois tiros, a barriga e a anca machucam, a perna e o rabo quase nada. O bicho
## ferido sangra, foge e vai pingando sangue no chão; o dano fica somado.
## Morto, ele cai (a vaca tem a animação de morrer; os outros tombam de lado), fica
## deitado no chão com a mancha de sangue onde a flecha entrou (e a flecha cravada) e
## uma poça de sangue vai se espalhando no chão. A carcaça fica uns 20 dias.
## Flecha que erra crava no chão (dá para pegar de novo; às vezes quebra).

const MundoSim := preload("res://scripts/mundo_sim.gd")
const VacaModelo := preload("res://scripts/world/vaca_modelo.gd")
const TamModelo := preload("res://scripts/world/tamandua_modelo.gd")
const MacacoModelo := preload("res://scripts/world/macaco_modelo.gd")
const AraraModelo := preload("res://scripts/world/arara_modelo.gd")
const Sons := preload("res://scripts/sons.gd")
const Podre := preload("res://scripts/world/podre.gd")

const G := 9.8
const FLECHA_L := 0.78
const APODRECE := 90              # dias que a carcaça fica (os ossos ficam muito tempo)

## Vida de cada bicho (o dano das partes soma até passar disso).
const VIDA := {"vaca": 120.0, "boi": 150.0, "bezerro": 60.0, "tamandua": 70.0, "macaco": 35.0, "arara": 25.0, "cobra": 25.0}

var carcacas: Array = []          # dados salvos: {uid, esp, id, xf: [12], p: {...}, feridas: [[x,y,z, dx,dy,dz]], dia, pts}
var feridas := {}                 # "esp:id" -> dano somado (bichos vivos)
var _jogo: Node
var _voando: Array = []           # flechas no ar: {pos, vel, node, t, forca}
var _nodes := {}                  # uid -> {node, t (caindo), anim}
var _poças: Array = []            # {node, r, alvo} poças crescendo
var _fontes: Array = []           # ferimentos sangrando: {pai, local, dn_local, ate, t, ritmo}
var _gotas: Array = []            # gotas caindo: {node, vel}
var _fios: Array = []             # filetes escorrendo pelo couro: {node, L, alvo, vel}
var _rng := RandomNumberGenerator.new()
static var _mats := {}
static var _flecha_mesh: ArrayMesh


func build(jogo: Node, save_path := "") -> void:
	_jogo = jogo
	_rng.randomize()
	if save_path != "":
		_load(save_path)
	_rebuild()


# ================== ATIRAR ==================

## Solta uma flecha de "de" na direção "dir"; forca de 0 (mal puxado) a 1 (puxado até o fim).
func atirar(de: Vector3, dir: Vector3, forca: float) -> void:
	var v := lerpf(14.0, 52.0, clampf(forca, 0.0, 1.0))
	# mal puxado sai torto
	var tremor := (1.0 - forca) * 0.04
	dir = (dir + Vector3(_rng.randf_range(-tremor, tremor), _rng.randf_range(-tremor, tremor), _rng.randf_range(-tremor, tremor))).normalized()
	var n := MeshInstance3D.new()
	n.mesh = flecha_mesh()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	_voando.append({"pos": de, "vel": dir * v, "node": n, "t": 0.0, "forca": forca})
	_aponta(n, de, dir)


static func _aponta(n: Node3D, pos: Vector3, dir: Vector3) -> void:
	var z := -dir.normalized()                     # a flecha olha para -Z (a ponta)
	var up := Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	n.global_transform = Transform3D(Basis(x, z.cross(x), z), pos)


func update(delta: float) -> void:
	if _jogo == null:
		return
	# as flechas no ar
	for f in _voando.duplicate():
		f.t = float(f.t) + delta
		var a: Vector3 = f.pos
		var vel: Vector3 = f.vel
		vel.y -= G * delta
		var b: Vector3 = a + vel * delta
		f.vel = vel
		var hit := _acerta_bicho(a, b)
		if not hit.is_empty():
			_voando.erase(f)
			_ferir(hit, vel, f)
			continue
		var gy: float = _jogo.ground_at(b.x, b.z)
		if b.y <= gy or float(f.t) > 5.0:
			_voando.erase(f)
			_no_chao(f, a, b, gy)
			continue
		f.pos = b
		_aponta(f.node, b, vel)
	# o bicho com o tiro fatal correndo até cair, e as carcaças caindo
	for uid in _nodes:
		var nd: Dictionary = _nodes[uid]
		if nd.has("corre"):
			_correr(nd, delta)
		elif nd.has("cai"):
			_cair(nd, delta)
	_sangue_tick(delta)
	_caindo_tick(delta)
	_pecas_tick()
	_couro_chao_tick(delta)
	_podre_t -= delta
	if _podre_t <= 0.0:
		_podre_t = 1.0
		_podre_tick()
	# poças de sangue crescendo
	for p in _poças.duplicate():
		p.r = move_toward(float(p.r), float(p.alvo), delta * 0.03)
		(p.node as Node3D).scale = Vector3(float(p.r), 1.0, float(p.r))
		if float(p.r) >= float(p.alvo):
			_poças.erase(p)


## Uma vez por dia: as carcaças velhas apodrecem e somem.
func dia(day: int) -> void:
	var keep := []
	for c in carcacas:
		if day - int(c.get("dia", day)) < APODRECE:
			keep.append(c)
	if keep.size() != carcacas.size():
		carcacas = keep
		_rebuild()


# ================== OS BICHOS E AS PARTES ==================

## Todas as partes que dá para acertar agora: [{esp, id, node, nome, c (mundo), r, dano, vida}]
func _alvos() -> Array:
	var out := []
	var j = _jogo
	# vacas: cabeça e pescoço pelos ossos (baixa para pastar), o resto pelo corpo
	if j._vacas:
		for id in j._vacas._agents:
			var a: Dictionary = j._vacas._agents[id]
			var v: Dictionary = j._vacas._find(int(id))
			if v.is_empty():
				continue
			var n: Node3D = a.node
			var xf := n.global_transform
			var s := float(a.get("s", 1.0))
			var esp := "vaca"
			if str(v.sexo) == "m" and j._vacas.age(v) >= j._vacas.ADULTA:
				esp = "boi"
			elif j._vacas.age(v) < 300:
				esp = "bezerro"
			var cab := xf * Vector3(0.85, 1.25, 0)
			var pes := xf * Vector3(0.62, 1.15, 0)
			if n.has_meta("sk"):
				var sk: Skeleton3D = n.get_meta("sk")
				var hb := sk.find_bone("Head")
				var nb := sk.find_bone("Neck")
				if hb >= 0 and nb >= 0:
					var hp: Transform3D = sk.get_bone_global_pose(hb)
					cab = sk.global_transform * (hp.origin + hp.basis.y * 0.011)
					pes = sk.global_transform * sk.get_bone_global_pose(nb).origin
			var vida: float = VIDA[esp]
			out.append({"esp": "vaca", "tipo": esp, "id": int(id), "node": n, "nome": "cabeça", "c": cab, "r": 0.19 * s, "dano": 230.0, "vida": vida})
			out.append({"esp": "vaca", "tipo": esp, "id": int(id), "node": n, "nome": "pescoço", "c": pes, "r": 0.2 * s, "dano": 70.0, "vida": vida})
			for pt in [[Vector3(0.4, 0.95, 0), 0.3, 95.0, "peito"], [Vector3(-0.02, 0.95, 0), 0.34, 35.0, "barriga"], [Vector3(-0.48, 1.0, 0), 0.3, 30.0, "anca"],
					[Vector3(0.42, 0.4, 0.15), 0.1, 15.0, "perna"], [Vector3(0.42, 0.4, -0.15), 0.1, 15.0, "perna"],
					[Vector3(-0.55, 0.4, 0.15), 0.11, 15.0, "perna"], [Vector3(-0.55, 0.4, -0.15), 0.11, 15.0, "perna"]]:
				out.append({"esp": "vaca", "tipo": esp, "id": int(id), "node": n, "nome": pt[3], "c": xf * (pt[0] as Vector3), "r": float(pt[1]) * s, "dano": pt[2], "vida": vida})
	# tamanduás (olham para +X)
	if j._tamanduas:
		for id in j._tamanduas._agents:
			var a2: Dictionary = j._tamanduas._agents[id]
			var n2: Node3D = a2.node
			var xf2 := n2.global_transform
			var deitado := str(a2.get("modo", "")) == "dormir"
			var dy := -0.25 if deitado else 0.0
			for pt in [[Vector3(0.62, 0.45 + dy, 0), 0.1, 140.0, "cabeça"], [Vector3(0.28, 0.52 + dy, 0), 0.2, 75.0, "peito"],
					[Vector3(-0.1, 0.5 + dy, 0), 0.22, 35.0, "barriga"], [Vector3(-0.42, 0.5 + dy, 0), 0.18, 30.0, "anca"],
					[Vector3(-0.85, 0.45 + dy, 0), 0.16, 5.0, "rabo"],
					[Vector3(0.3, 0.2, 0.12), 0.07, 15.0, "perna"], [Vector3(0.3, 0.2, -0.12), 0.07, 15.0, "perna"],
					[Vector3(-0.34, 0.2, 0.12), 0.07, 15.0, "perna"], [Vector3(-0.34, 0.2, -0.12), 0.07, 15.0, "perna"]]:
				out.append({"esp": "tamandua", "tipo": "tamandua", "id": int(id), "node": n2, "nome": pt[3], "c": xf2 * (pt[0] as Vector3), "r": pt[1], "dano": pt[2], "vida": VIDA.tamandua})
	# macacos: a cabeça de verdade (do modelo) e o corpo
	if j._macacos:
		for ti in j._macacos._agents:
			for a3 in j._macacos._agents[ti]:
				var n3: Node3D = a3.node
				var sc := n3.scale.x
				var hd: Vector3 = n3._head.global_position if n3.get("_head") != null else n3.global_position + Vector3.UP * 0.35 * sc
				var corpo := n3.global_position + Vector3.UP * 0.22 * sc
				out.append({"esp": "macaco", "tipo": "macaco", "id": int(a3.id), "tropa": int(ti), "node": n3, "nome": "cabeça", "c": hd, "r": 0.09 * sc, "dano": 140.0, "vida": VIDA.macaco})
				out.append({"esp": "macaco", "tipo": "macaco", "id": int(a3.id), "tropa": int(ti), "node": n3, "nome": "corpo", "c": corpo, "r": 0.16 * sc, "dano": 45.0, "vida": VIDA.macaco})
	# araras (frente -Z)
	if j._araras:
		for id in j._araras._agents:
			if int(id) < 0:
				continue
			var n4: Node3D = j._araras._agents[id].node
			var xf4 := n4.global_transform
			out.append({"esp": "arara", "tipo": "arara", "id": int(id), "node": n4, "nome": "cabeça", "c": xf4 * Vector3(0, 0.36, -0.05), "r": 0.07, "dano": 140.0, "vida": VIDA.arara})
			out.append({"esp": "arara", "tipo": "arara", "id": int(id), "node": n4, "nome": "corpo", "c": xf4 * Vector3(0, 0.2, 0.02), "r": 0.12, "dano": 40.0, "vida": VIDA.arara})
	# cobras: a espinha desenhada (a cabeça é o primeiro ponto)
	if j._cobras:
		for id in j._cobras._agents:
			var a5: Dictionary = j._cobras._agents[id]
			var sp: Array = a5.get("spine", [])
			if sp.is_empty():
				continue
			out.append({"esp": "cobra", "tipo": "cobra", "id": int(id), "node": a5.node, "nome": "cabeça", "c": sp[0], "r": 0.05, "dano": 140.0, "vida": VIDA.cobra})
			for i in range(4, sp.size(), 6):
				out.append({"esp": "cobra", "tipo": "cobra", "id": int(id), "node": a5.node, "nome": "corpo", "c": sp[i], "r": 0.05, "dano": 30.0, "vida": VIDA.cobra})
	return out


## A primeira parte que o segmento a→b atravessa (a mais perto de a), ou {}.
func _acerta_bicho(a: Vector3, b: Vector3) -> Dictionary:
	var d := b - a
	var L := d.length()
	if L < 0.0001:
		return {}
	var u := d / L
	var best := {}
	var bt := 1e9
	for p in _alvos():
		var c: Vector3 = p.c
		var r := float(p.r)
		var oc := a - c
		var bb := oc.dot(u)
		var cc := oc.dot(oc) - r * r
		var disc := bb * bb - cc
		if disc < 0.0:
			continue
		var t := -bb - sqrt(disc)
		if t < 0.0:
			t = 0.0 if cc < 0.0 else 1e9
		if t <= L and t < bt:
			bt = t
			best = p
			best["ponto"] = a + u * t
	return best


# ================== FERIR E MATAR ==================

## Em quem prender a flecha e a mancha: na vaca, no osso mais perto do ferimento (assim
## acompanha o corpo caindo na animação); nos outros, no próprio bicho.
static func _prender(n: Node3D, ponto: Vector3, osso := "") -> Node3D:
	if not n.has_meta("sk"):
		return n
	var sk: Skeleton3D = n.get_meta("sk")
	if osso == "":
		var bd := 1e9
		for nm in ["Body", "Hips", "Torso", "Shoulders", "Neck", "Head", "FrontUpLeg_R", "FrontUpLeg_L", "BackUpLeg_R", "BackUpLeg_L",
				"FrontLowLeg_R", "FrontLowLeg_L", "BackLowLeg_R", "BackLowLeg_L", "Tail1"]:
			var bi := sk.find_bone(nm)
			if bi < 0:
				continue
			var bp: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
			var d := bp.distance_to(ponto)
			if d < bd:
				bd = d
				osso = nm
	for c in sk.get_children():
		if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == osso and c.has_meta("caca"):
			return c
	var ba := BoneAttachment3D.new()
	ba.bone_name = osso
	ba.set_meta("caca", true)
	ba.set_meta("osso", osso)
	sk.add_child(ba)
	return ba


func _ferir(hit: Dictionary, vel: Vector3, f: Dictionary) -> void:
	var n: Node3D = hit.node
	var ponto: Vector3 = hit.ponto
	var dir := vel.normalized()
	var forca := float(f.forca)
	var dano := float(hit.dano) * lerpf(0.5, 1.0, forca) * _rng.randf_range(0.85, 1.15)
	var chave := "%s:%d" % [hit.esp, int(hit.id)]
	var total := float(feridas.get(chave, 0.0)) + dano
	feridas[chave] = total
	# a flecha fica cravada no bicho, entrando um pouco
	var fn: MeshInstance3D = f.node
	var entra := ponto + dir * 0.12
	var pai := _prender(n, ponto)
	fn.reparent(pai, false)
	_aponta(fn, entra, dir)
	Sons.play_at(_jogo, "baque", ponto, -6.0, 1.6)
	# o sangue: a mancha onde entrou, escorrendo e pingando
	_mancha_bicho(pai, ponto, dir, true)
	hit["pai"] = pai
	var fatal := total >= float(hit.vida)
	_fonte(pai, ponto, dir, 40.0 if fatal else clampf(dano * 0.6, 15.0, 45.0), 0.12 if fatal else 0.3)
	if fatal:
		_morrer(hit, ponto, dir)
	else:
		_assusta(hit)


func _assusta(hit: Dictionary) -> void:
	var j = _jogo
	var pp: Vector3 = j._player.global_position
	match str(hit.esp):
		"vaca":
			var v: Dictionary = j._vacas._find(int(hit.id))
			if not v.is_empty():
				j._vacas._assusta(int(v.reb), pp)
				var ag: Dictionary = j._vacas._agents.get(int(hit.id), {})
				if not ag.is_empty():
					var vp := Vector3(float(v.x), 0, float(v.z))
					var fora := Vector3(vp.x - pp.x, 0, vp.z - pp.z).normalized()
					ag.alvo = vp + fora.rotated(Vector3.UP, _rng.randf_range(-0.4, 0.4)) * _rng.randf_range(55.0, 80.0)
					ag.modo = "fugir"
		"tamandua":
			var a: Dictionary = j._tamanduas._agents.get(int(hit.id), {})
			if not a.is_empty():
				var b: Dictionary = j._tamanduas._find(int(hit.id))
				var pos := Vector3(float(b.x), 0, float(b.z))
				a.alvo = pos + Vector3(pos.x - pp.x, 0, pos.z - pp.z).normalized() * 50.0
				a.modo = "fugir"
		"macaco":
			j._macacos._alarm((hit.node as Node3D).global_position)


func _morrer(hit: Dictionary, ponto: Vector3, dir: Vector3) -> void:
	var j = _jogo
	var n: Node3D = hit.node
	var esp := str(hit.esp)
	var id := int(hit.id)
	var params := {}
	# tira o bicho da vida dele, mas fica com o corpo (o nó desenhado)
	match esp:
		"vaca":
			var v: Dictionary = j._vacas._find(id)
			params = {"s": float(j._vacas._agents[id].get("s", 1.0)), "cor": str(v.get("cor", "branca")), "touro": str(hit.tipo) == "boi", "seed": int(v.get("seed", 1))}
			j._vacas._agents.erase(id)
			j._vacas.matar(id)
		"tamandua":
			params = {"s": float(j._tamanduas._agents[id].get("s", 1.0))}
			j._tamanduas._agents.erase(id)
			j._tamanduas.matar(id)
		"macaco":
			var ti := int(hit.tropa)
			params = {"s": n.scale.x}
			var lst: Array = j._macacos._agents.get(ti, [])
			for a in lst.duplicate():
				if int(a.id) == id:
					lst.erase(a)
			if ti < j._macacos.troops.size():
				var mem: Array = j._macacos.troops[ti].membros
				for m in mem.duplicate():
					if int(m.get("id", -1)) == id:
						mem.erase(m)
			n.set_process(false)
		"arara":
			params = {"s": n.scale.x}
			j._araras._agents.erase(id)
			j._araras.matar(id)
			n.set_process(false)
		"cobra":
			var a5: Dictionary = j._cobras._agents[id]
			params = {"pts": _pts_json(a5.get("spine", []))}
			j._cobras._agents.erase(id)
			j._cobras.matar(id)
	feridas.erase("%s:%d" % [esp, id])
	n.reparent(self, true)
	var uid := "%d_%d" % [Time.get_ticks_msec(), _rng.randi() % 100000]
	var pai: Node3D = hit.get("pai", n)
	var local := pai.global_transform.affine_inverse() * ponto
	var ldir := pai.global_transform.basis.inverse() * dir
	var c := {"uid": uid, "esp": esp, "id": id, "p": params, "dia": int(j.sim.elapsed_days()), "t0": agora_h(),
		"feridas": [[local.x, local.y, local.z, ldir.x, ldir.y, ldir.z, str(pai.get_meta("osso", ""))]], "xf": []}
	carcacas.append(c)
	var nd := {"node": n, "c": c, "cai": 0.0, "de": n.global_transform}
	if n.has_meta("ap"):
		nd["ap"] = n.get_meta("ap")
	# ainda corre: na cabeça quase nada; no peito uns segundos; o resto (o sangue
	# acabando) um pouco mais, cada vez mais devagar até cair
	var dur := 0.0
	match str(hit.nome):
		"cabeça": dur = _rng.randf_range(0.0, 0.6)
		"pescoço", "peito": dur = _rng.randf_range(3.0, 6.0)
		_: dur = _rng.randf_range(5.0, 9.0)
	var v0: float = {"vaca": 5.5, "tamandua": 2.4, "macaco": 3.2}.get(esp, 0.0)
	if v0 <= 0.0 or dur < 0.3:
		_comeca_queda(nd)
	else:
		var pp: Vector3 = j._player.global_position
		var fora := Vector3(n.global_position.x - pp.x, 0, n.global_position.z - pp.z).normalized()
		if fora.length() < 0.1:
			fora = Vector3.RIGHT
		nd["corre"] = {"t": 0.0, "dur": dur, "v0": v0 * n.scale.x, "dir": fora.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)), "fase": 0.0}
		if esp == "macaco":
			n.set_process(true)
			n.mode = "walk"
		if nd.has("ap"):
			(nd.ap as AnimationPlayer).play(VacaModelo.ANIMS.correr, 0.2)
	_nodes[uid] = nd
	Sons.play_at(j, "baque", n.global_position, -2.0, 0.7)


func _comeca_queda(nd: Dictionary) -> void:
	var n: Node3D = nd.node
	nd.erase("corre")
	nd.cai = 0.0
	nd.de = n.global_transform
	if n is MacacoModelo:
		n.set_process(false)
	if nd.has("ap"):
		(nd.ap as AnimationPlayer).play(VacaModelo.ANIMS.morrer, 0.25)


## Correndo com o tiro fatal: vai perdendo a força (cada vez mais devagar, cambaleando)
## e o sangue vai pingando no caminho; no fim cai.
func _correr(nd: Dictionary, delta: float) -> void:
	var n: Node3D = nd.node
	if not is_instance_valid(n):
		nd.erase("corre")
		return
	var cr: Dictionary = nd.corre
	cr.t = float(cr.t) + delta
	var k := clampf(float(cr.t) / float(cr.dur), 0.0, 1.0)
	var v := float(cr.v0) * pow(1.0 - k, 1.3) + 0.25 * (1.0 - k)
	var dir: Vector3 = cr.dir
	dir = dir.rotated(Vector3.UP, sin(float(cr.t) * 2.3) * 0.6 * k * delta)     # cambaleia
	cr.dir = dir
	var np := n.global_position + dir * v * delta
	var c := Vector2i(int(np.x / 5.0), int(np.z / 5.0))
	var sim = _jogo.sim
	var agua: bool = c.x < 1 or c.y < 1 or c.x >= MundoSim.W - 1 or c.y >= MundoSim.H - 1 or float(sim.wat[c.y * MundoSim.W + c.x]) > 0.05
	if agua or k >= 1.0:
		_comeca_queda(nd)
		return
	np.y = _jogo.ground_at(np.x, np.z)
	n.global_position = np
	var esp := str(nd.c.esp)
	if esp == "macaco":
		n.rotation.y = atan2(-dir.x, -dir.z)
	else:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-dir.z, dir.x), minf(1.0, delta * 5.0))
	cr.fase = float(cr.fase) + v * delta / 0.5 * PI
	if nd.has("ap"):
		var ap: AnimationPlayer = nd.ap
		var quer: String = VacaModelo.ANIMS.correr if v > 2.2 * n.scale.x else VacaModelo.ANIMS.andar
		if ap.current_animation != quer:
			ap.play(quer, 0.4)
		ap.speed_scale = clampf(v / (4.0 * n.scale.x), 0.35, 1.2)
		ap.advance(delta)
	elif esp == "tamandua":
		TamModelo.pose(n, "correr" if v > 1.0 else "andar", float(cr.fase), float(cr.t))


## A queda: a vaca pela animação; os outros tombam de lado (e a ave cai do alto).
func _cair(nd: Dictionary, delta: float) -> void:
	var n: Node3D = nd.node
	if not is_instance_valid(n):
		nd.erase("cai")
		return
	nd.cai = float(nd.cai) + delta
	var c: Dictionary = nd.c
	var esp := str(c.esp)
	var k := 1.0
	if nd.has("ap"):
		var ap: AnimationPlayer = nd.ap
		ap.speed_scale = 1.0
		ap.advance(delta)
		k = clampf(float(nd.cai) / maxf(ap.current_animation_length, 0.1), 0.0, 1.0) if ap.current_animation != "" else 1.0
		# (a vaca fica de pé no lugar dela, a animação a deita)
		var xf: Transform3D = nd.de
		var gy: float = _jogo.ground_at(xf.origin.x, xf.origin.z)
		n.global_transform = Transform3D(xf.basis, Vector3(xf.origin.x, gy, xf.origin.z))
	else:
		var de: Transform3D = nd.de
		var gy2: float = _jogo.ground_at(de.origin.x, de.origin.z)
		var alto := de.origin.y - gy2
		var tempo := 0.7 + sqrt(maxf(alto, 0.0) * 2.0 / G)
		k = clampf(float(nd.cai) / tempo, 0.0, 1.0)
		var fwd: Vector3 = de.basis.x if esp == "tamandua" else -de.basis.z
		var deitado := Basis(fwd.normalized(), PI * 0.5) * de.basis
		var e := k * k
		var lado := _lado(esp) * de.basis.get_scale().x
		var pos := de.origin.lerp(Vector3(de.origin.x, gy2 + lado, de.origin.z), e)
		if esp == "cobra":
			deitado = de.basis
			pos = de.origin
		n.global_transform = Transform3D(de.basis.slerp(deitado, smoothstep(0.0, 1.0, k)), pos)
	if k >= 1.0:
		nd.erase("cai")
		c.xf = _xf_json(n.global_transform)
		for fo in _fontes:
			if is_instance_valid(fo.pai) and (fo.pai == n or n.is_ancestor_of(fo.pai)):
				fo.ate = minf(float(fo.ate), 12.0)        # parado, ainda pinga um pouco
		# a poça embaixo do ferimento
		var w: Array = (c.feridas as Array)[0]
		var pai2 := _prender(n, Vector3.ZERO, str(w[6])) if w.size() > 6 and str(w[6]) != "" else n
		var p: Vector3 = pai2.global_transform * Vector3(w[0], w[1], w[2])
		_mancha_chao(Vector3(p.x, 0, p.z), _rng.randf_range(0.35, 0.6), true)


## Quanto o corpo deitado fica acima do chão (meia largura).
static func _lado(esp: String) -> float:
	match esp:
		"tamandua": return 0.17
		"macaco": return 0.09
		"arara": return 0.07
	return 0.0


# ================== SANGUE ==================
# Sangue líquido: vermelho-escuro e brilhante como água (reflete a luz), com um pouco de
# transparência na borda. No couro: uma mancha de sangue que sujou (borda irregular,
# respingos, sem volume) e uns filetes de sangue escorrendo para baixo do ferimento; do
# fim deles as gotas pingam no chão. No chão: respingos onde as gotas caem e a poça
# brilhante embaixo do bicho morto, crescendo.

static var _texs := {}

## Textura de mancha (alfa na borda): "mancha" (sujou: irregular com respingos),
## "poca" (líquido: borda mais lisa), "escorrido" (comprida para baixo).
static func _tex(tipo: String, v: int) -> Texture2D:
	var key := "%s%d" % [tipo, v]
	if _texs.has(key):
		return _texs[key]
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.seed = 31 + v * 17 + tipo.length()
	nz.frequency = 0.045 if tipo != "poca" else 0.03
	nz.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + v * 101 + tipo.length() * 3
	var gotas := []
	if tipo != "poca":
		for k in rng.randi_range(6, 14):
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.42, 0.85)
			gotas.append([Vector2(0.5 + cos(a) * d * 0.5, 0.5 + sin(a) * d * 0.5), rng.randf_range(0.01, 0.035)])
	for y in N:
		for x in N:
			var u := Vector2(float(x) / N, float(y) / N)
			var p := (u - Vector2(0.5, 0.5)) * 2.0
			if tipo == "escorrido":
				p.x *= 2.6                           # estreita e comprida para baixo
				p.y = p.y * 0.9 + 0.1
			var r := p.length() + nz.get_noise_2d(x, y) * (0.45 if tipo != "poca" else 0.22)
			var a2 := 1.0 - smoothstep(0.62, 0.78, r)
			for g in gotas:
				var dd: float = u.distance_to(g[0])
				a2 = maxf(a2, 1.0 - smoothstep(float(g[1]) * 0.7, float(g[1]), dd))
			if a2 <= 0.001:
				img.set_pixel(x, y, Color(0.3, 0.0, 0.0, 0.0))
				continue
			# mais escuro no meio (mais grosso), vermelho vivo na borda fina
			var esp := clampf(1.0 - r / 0.75, 0.0, 1.0)
			var col := Color(0.3, 0.006, 0.008).lerp(Color(0.12, 0.0, 0.004), esp * 0.85)
			col = col.darkened(nz.get_noise_2d(x * 3.0, y * 3.0) * 0.15)
			col.a = a2 * (0.88 + 0.12 * esp) if tipo != "poca" else a2 * 0.97
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_texs[key] = t
	return t


static func _mat_tex(tipo: String, v: int) -> StandardMaterial3D:
	var key := "m_%s%d" % [tipo, v]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tipo, v)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.22 if tipo == "poca" else 0.5         # molhado: brilha um pouco
	m.metallic_specular = 0.3 if tipo == "poca" else 0.15
	_mats[key] = m
	return m


static func _mat(k: String) -> StandardMaterial3D:
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	match k:
		"liquido":
			# o sangue escorrendo e as gotas: brilha como água, vermelho-escuro
			m.albedo_color = Color(0.2, 0.0, 0.003)
			m.roughness = 0.25
			m.metallic_specular = 0.3
		"madeira":
			m.albedo_color = Color(0.62, 0.47, 0.29)
			m.roughness = 0.8
		"pedra":
			m.albedo_color = Color(0.38, 0.38, 0.37)
			m.roughness = 0.5
		"cipo":
			m.albedo_color = Color(0.25, 0.18, 0.08)
	_mats[k] = m
	return m


## A base de um plano encostado no couro (z para fora), e o "para baixo" nele.
static func _plano(dir: Vector3) -> Array:
	var z := -dir.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	var dn := Vector3.DOWN - z * z.dot(Vector3.DOWN)
	if dn.length() < 0.1:
		dn = -y
	return [Basis(x, y, z), dn.normalized()]


## A mancha no couro onde a flecha entrou, o escorrido manchando para baixo e os
## filetes de sangue líquido (fresco: crescem escorrendo).
func _mancha_bicho(pai: Node3D, ponto: Vector3, dir: Vector3, fresco := false) -> void:
	var pl := _plano(dir)
	var b: Basis = pl[0]
	var dn: Vector3 = pl[1]
	var fora := -dir.normalized()
	var v := _rng.randi() % 4
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.24, 0.24)
	q.mesh = qm
	q.material_override = _mat_tex("mancha", v)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(q)
	q.global_transform = Transform3D(b.rotated(fora, _rng.randf() * TAU), ponto + fora * 0.012)
	# o escorrido (sujou para baixo)
	var e := MeshInstance3D.new()
	var em := QuadMesh.new()
	em.size = Vector2(0.12, 0.34)
	e.mesh = em
	e.material_override = _mat_tex("escorrido", v)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(e)
	var ey := -dn
	var ex := ey.cross(fora).normalized()
	e.global_transform = Transform3D(Basis(ex, ey, fora), ponto + fora * 0.014 + dn * 0.15)
	# os filetes de líquido
	for k in _rng.randi_range(2, 3):
		var fio := Node3D.new()
		pai.add_child(fio)
		var desvio := ex * _rng.randf_range(-0.03, 0.03)
		var ddn := (dn + ex * _rng.randf_range(-0.15, 0.15)).normalized()
		var fy := -ddn
		var fx := fy.cross(fora).normalized()
		fio.global_transform = Transform3D(Basis(fx, fy, fora), ponto + fora * 0.018 + desvio)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0075
		cm.bottom_radius = 0.005
		cm.height = 1.0
		cm.radial_segments = 6
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = _mat("liquido")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, -0.5, 0)
		fio.add_child(mi)
		# a gota pendurada na ponta do filete
		var gp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.009
		sm.height = 0.024
		sm.radial_segments = 8
		sm.rings = 4
		gp.mesh = sm
		gp.material_override = _mat("liquido")
		gp.name = "gota"
		fio.add_child(gp)
		var alvo := _rng.randf_range(0.1, 0.3)
		var es: float = fio.global_transform.basis.get_scale().y
		if fresco:
			_fios.append({"node": fio, "L": 0.0, "alvo": alvo, "vel": _rng.randf_range(0.05, 0.12), "es": es})
			_fio_comp(fio, 0.001, es)
		else:
			_fio_comp(fio, alvo, es)


## O comprimento do filete (no mundo, mesmo com o pai escalado).
static func _fio_comp(fio: Node3D, L: float, _es := 1.0) -> void:
	var mi: MeshInstance3D = fio.get_child(0)
	var gp: Node3D = fio.get_node("gota")
	var s: float = fio.global_transform.basis.get_scale().x
	var Ll := L / maxf(s, 0.0001)
	mi.position = Vector3(0, -Ll * 0.5, 0)
	mi.scale = Vector3(1.0 / maxf(s, 0.0001), Ll, 1.0 / maxf(s, 0.0001))
	gp.position = Vector3(0, -Ll, 0)
	gp.scale = Vector3.ONE / maxf(s, 0.0001)


## Um ferimento sangrando: pinga gotas (do fim dos filetes) por "segundos".
func _fonte(pai: Node3D, ponto: Vector3, dir: Vector3, segundos: float, ritmo: float) -> void:
	var dn: Vector3 = _plano(dir)[1]
	var inv := pai.global_transform.affine_inverse()
	_fontes.append({"pai": pai, "local": inv * (ponto - dir.normalized() * 0.02 + dn * 0.2), "ate": segundos, "t": 0.1, "ritmo": ritmo})


func _sangue_tick(delta: float) -> void:
	# os filetes escorrendo (crescem até o tamanho deles)
	for f in _fios.duplicate():
		if not is_instance_valid(f.node):
			_fios.erase(f)
			continue
		f.L = minf(float(f.alvo), float(f.L) + float(f.vel) * delta)
		_fio_comp(f.node, float(f.L))
		if float(f.L) >= float(f.alvo):
			_fios.erase(f)
	# os ferimentos pingando (correndo, o rastro fica no caminho)
	for fo in _fontes.duplicate():
		if not is_instance_valid(fo.pai):
			_fontes.erase(fo)
			continue
		fo.ate = float(fo.ate) - delta
		fo.t = float(fo.t) - delta
		if float(fo.t) <= 0.0:
			var fim := clampf(float(fo.ate) / 10.0, 0.25, 1.0)
			fo.t = float(fo.ritmo) * _rng.randf_range(0.6, 1.6) / fim
			var w: Vector3 = (fo.pai as Node3D).global_transform * (fo.local as Vector3)
			_pinga(w)
		if float(fo.ate) <= 0.0:
			_fontes.erase(fo)
	# as gotas caindo; no chão viram respingo
	for g in _gotas.duplicate():
		var n: Node3D = g.node
		var vel: Vector3 = g.vel
		vel.y -= G * delta
		g.vel = vel
		var np := n.global_position + vel * delta
		var gy: float = _jogo.ground_at(np.x, np.z)
		if np.y <= gy:
			_gotas.erase(g)
			n.queue_free()
			_respingo(Vector3(np.x, gy, np.z), _rng.randf_range(0.04, 0.09))
			continue
		n.global_position = np
		n.scale = Vector3(1.0, clampf(1.0 + vel.length() * 0.25, 1.0, 2.5), 1.0)
	# as poças crescendo
	for p in _poças.duplicate():
		if not is_instance_valid(p.node):
			_poças.erase(p)
			continue
		p.r = move_toward(float(p.r), float(p.alvo), delta * 0.025)
		(p.node as Node3D).scale = Vector3(float(p.r), 1.0, float(p.r))
		if float(p.r) >= float(p.alvo):
			_poças.erase(p)


func _pinga(w: Vector3) -> void:
	if _gotas.size() > 60:
		return
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = _rng.randf_range(0.006, 0.011)
	sm.height = sm.radius * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	n.mesh = sm
	n.material_override = _mat("liquido")
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	n.global_position = w
	_gotas.append({"node": n, "vel": Vector3(_rng.randf_range(-0.1, 0.1), -0.3, _rng.randf_range(-0.1, 0.1))})


## Uma mancha deitada no chão (respingo de gota, ou a poça que cresce).
func _respingo(p: Vector3, r: float, tipo := "mancha", cresce := false) -> void:
	var n := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	n.mesh = qm
	n.material_override = _mat_tex(tipo, _rng.randi() % 4)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	n.global_position = Vector3(p.x, _jogo.ground_at(p.x, p.z) + 0.012 + _rng.randf() * 0.004, p.z)
	n.rotation.y = _rng.randf() * TAU
	if cresce:
		n.scale = Vector3(0.05, 1, 0.05)
		_poças.append({"node": n, "r": 0.05, "alvo": r})
	else:
		n.scale = Vector3(r, 1, r)
	_manchas.append(n)
	while _manchas.size() > 250:
		var velha: Node3D = _manchas.pop_front()
		if is_instance_valid(velha):
			velha.queue_free()


## A poça embaixo do bicho caído (ou só manchado, montando de novo).
func _mancha_chao(p: Vector3, r: float, cresce: bool) -> void:
	_respingo(p, r, "poca", cresce)
	for k in 3:
		var a := _rng.randf() * TAU
		_respingo(p + Vector3(cos(a), 0, sin(a)) * r * _rng.randf_range(0.7, 1.2), r * _rng.randf_range(0.15, 0.3))

var _manchas: Array = []


# ================== A FLECHA ==================

## A flecha: vareta reta, a ponta de pedra lascada e o cipó amarrando. A ponta em -Z.
static func flecha_mesh() -> ArrayMesh:
	if _flecha_mesh != null:
		return _flecha_mesh
	var m := ArrayMesh.new()
	var haste := CylinderMesh.new()
	haste.top_radius = 0.0055
	haste.bottom_radius = 0.0055
	haste.height = FLECHA_L
	haste.radial_segments = 6
	haste.rings = 1
	_junta(m, haste, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, FLECHA_L * 0.5)), _mat("madeira"))
	var ponta := CylinderMesh.new()
	ponta.top_radius = 0.0
	ponta.bottom_radius = 0.016
	ponta.height = 0.06
	ponta.radial_segments = 4
	ponta.rings = 1
	_junta(m, ponta, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(1.0, 1.0, 0.45)), Vector3(0, 0, -0.03)), _mat("pedra"))
	var amarra := CylinderMesh.new()
	amarra.top_radius = 0.0085
	amarra.bottom_radius = 0.0085
	amarra.height = 0.035
	amarra.radial_segments = 6
	amarra.rings = 1
	_junta(m, amarra, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.012)), _mat("cipo"))
	_flecha_mesh = m
	return m


static func _junta(m: ArrayMesh, prim: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
	var arr := prim.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in vs.size():
		vs[i] = xf * vs[i]
		ns[i] = (xf.basis * ns[i]).normalized()
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TANGENT] = null
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(m.get_surface_count() - 1, mat)


## Errou: crava no chão inclinada (vira a flecha do chão, para pegar de novo); às vezes
## a ponta bate numa pedra e quebra.
func _no_chao(f: Dictionary, a: Vector3, b: Vector3, gy: float) -> void:
	var n: Node3D = f.node
	n.queue_free()
	if _rng.randf() < 0.2:
		Sons.play_at(_jogo, "estalo", b, -12.0, 2.0)
		return
	var d := b - a
	var k := 1.0
	if absf(d.y) > 0.0001:
		k = clampf((a.y - gy) / (a.y - b.y), 0.0, 1.0)
	var p := a.lerp(b, k)
	var dir := (f.vel as Vector3).normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := asin(clampf(-dir.y, -1.0, 1.0))
	_jogo._add_ground("flecha", 1, p.x, p.z, 0.0, [snappedf(yaw, 0.01), snappedf(pitch, 0.01)])
	Sons.play_at(_jogo, "cavar", p, -16.0, 2.2)


# ================== SALVAR, CARREGAR E MULTIPLAYER ==================

static func _xf_json(t: Transform3D) -> Array:
	var b := t.basis
	return [snappedf(b.x.x, 0.0001), snappedf(b.x.y, 0.0001), snappedf(b.x.z, 0.0001), snappedf(b.y.x, 0.0001), snappedf(b.y.y, 0.0001), snappedf(b.y.z, 0.0001),
		snappedf(b.z.x, 0.0001), snappedf(b.z.y, 0.0001), snappedf(b.z.z, 0.0001), snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001)]


static func _xf_de(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D()
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))


static func _pts_json(pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	return out


# ---------- pendurada no tripé ----------
# A vaca morta amarrada pelas duas patas da frente (a corda pega as canelas juntas): as
# da frente esticadas para cima, as de trás soltas. Enquanto a traseira ainda está no chão
# o corpo gira em volta dela (a frente sobe e vem para baixo da roldana); levantada a
# altura do corpo, fica pendurada com o pescoço em cima.

const PEND_ROLL := PI * 0.5        # deitada de lado no chão


## A carcaça de vaca (caída e parada) com os pés de trás mais perto de pos (até raio), ou "".
func vaca_perto(pos: Vector3, raio: float) -> String:
	var best := ""
	var bd := raio
	for uid in _nodes:
		var nd: Dictionary = _nodes[uid]
		var c: Dictionary = nd.c
		if str(c.esp) != "vaca" or nd.has("corre") or nd.has("cai") or not is_instance_valid(nd.node):
			continue
		if (c.get("xf", []) as Array).size() < 12:
			continue
		var pe := pes_tras(str(uid))
		var d := Vector2(pe.x - pos.x, pe.z - pos.z).length()
		if d < bd:
			bd = d
			best = str(uid)
	return best


## Onde estão os pés de trás (o meio dos dois) agora.
func pes_tras(uid: String) -> Vector3:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return Vector3.ZERO
	var n: Node3D = nd.node
	if not n.has_meta("sk"):
		return n.global_position
	var sk: Skeleton3D = n.get_meta("sk")
	var soma := Vector3.ZERO
	for sd in ["_R", "_L"]:
		var a: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("FrontLowLeg" + sd)).origin
		var b: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("FrontFoot" + sd)).origin
		soma += a.lerp(b, 0.75)
	return soma * 0.5


## Como a vaca estava deitada antes de amarrar (para pendurar e para soltar depois).
func base_pendura(uid: String) -> Dictionary:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return {}
	var n: Node3D = nd.node
	var bx: Vector3 = n.global_transform.basis.x
	var c0 := n.global_position
	if n.has_meta("sk"):
		var sk: Skeleton3D = n.get_meta("sk")
		c0 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Body")).origin
	return {"yaw": atan2(-bx.z, bx.x), "c0": [c0.x, c0.z], "xf0": _xf_json(n.global_transform)}


## A pose de pendurada: as pernas de trás esticadas, as da frente soltas, a cabeça caída.
static func _pose_pendurada(sk: Skeleton3D) -> void:
	sk.reset_bone_poses()
	for sd in ["_R", "_L"]:
		VacaModelo._dobra(sk, "FrontUpLeg" + sd, -1.5)          # as da frente esticadas para cima (amarradas)
		VacaModelo._dobra(sk, "FrontLowLeg" + sd, -0.2)
		VacaModelo._dobra(sk, "BackUpLeg" + sd, 0.55)           # as de trás soltas, caídas
		VacaModelo._dobra(sk, "BackLowLeg" + sd, 0.25)
	VacaModelo._dobra(sk, "Neck", 1.1)                           # o pescoço cai entre as patas
	VacaModelo._dobra(sk, "Head", 0.45)
	VacaModelo._dobra(sk, "Tail1", 1.0)


## A pose de pendurada nos ossos (uma vez): devolve os pontos dela no corpo.
func _rig(n: Node3D) -> Dictionary:
	if n.has_meta("rig"):
		return n.get_meta("rig")
	var sk: Skeleton3D = n.get_meta("sk")
	_pose_pendurada(sk)
	for uid0 in _nodes:
		if _nodes[uid0].node == n:
			_cortes_escala(sk, _nodes[uid0].c)
	VacaModelo._cascos(sk)
	var inv := n.global_transform.affine_inverse()
	var pk := Vector3.ZERO
	var pt := Vector3.ZERO
	for sd in ["_R", "_L"]:
		var a: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("FrontLowLeg" + sd)).origin
		var b: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("FrontFoot" + sd)).origin
		pk += inv * a.lerp(b, 0.75) * 0.5
		pt += inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("BackFoot" + sd)).origin) * 0.5
	var ph := pt
	var cr: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Body")).origin)
	var rig := {"pk": pk, "l": pk.distance_to(ph) + 0.15, "cr": cr}
	n.set_meta("rig", rig)
	for uid in _nodes:
		if _nodes[uid].node == n and (_nodes[uid].c as Dictionary).has("couro"):
			couro_visual.call_deferred(str(uid))
	return rig


## Onde fica tudo com os pés de trás na altura alt (m acima do chão), puxados para baixo da
## roldana: {h (os pés), alt0 (a altura deitada), l (do pé ao focinho), xf}.
func pendura_calc(uid: String, roldana: Vector3, alt: float, base: Dictionary) -> Dictionary:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node) or not (nd.node as Node3D).has_meta("sk"):
		return {}
	var n: Node3D = nd.node
	var rig := _rig(n)
	var s := float((nd.c.get("p", {}) as Dictionary).get("s", 1.0))
	var yaw := float(base.yaw)
	var c0 := Vector3(float(base.c0[0]), 0, float(base.c0[1]))
	var pk: Vector3 = rig.pk * s
	var cr: Vector3 = rig.cr * s
	var L := float(rig.l) * s
	var b0 := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PEND_ROLL)
	var o0 := Vector3(c0.x, _jogo.ground_at(c0.x, c0.z) + 0.3 * s, c0.z) - b0 * cr
	var h0 := o0 + b0 * pk
	var alt0 := h0.y - float(_jogo.ground_at(h0.x, h0.z))
	if alt <= alt0:
		return {"h": h0, "alt0": alt0, "l": L, "xf": Transform3D(b0.scaled(Vector3.ONE * s), o0)}
	var f := clampf((alt - alt0) / L, 0.0, 1.0)
	var a := asin(f)
	var hx := Vector2(h0.x, h0.z).lerp(Vector2(roldana.x, roldana.z), f)
	var h := Vector3(hx.x, _jogo.ground_at(hx.x, hx.y) + alt, hx.y)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, a) * Basis(Vector3.RIGHT, PEND_ROLL)
	return {"h": h, "alt0": alt0, "l": L, "xf": Transform3D(b.scaled(Vector3.ONE * s), h - b * pk)}


## Põe a vaca na pose de pendurada; devolve onde estão os pés de trás (onde a corda amarra).
func pendurar(uid: String, roldana: Vector3, alt: float, base: Dictionary) -> Dictionary:
	var r := pendura_calc(uid, roldana, alt, base)
	if r.is_empty():
		return r
	var n0: Node3D = _nodes[uid].node
	n0.global_transform = r.xf
	if _nodes[uid].has("n2"):
		n0.set_meta("xf_inteira", r.xf)
		_partir_afasta(uid)
	return r


## Desamarrou: a vaca volta a ficar deitada como estava.
func despendurar(uid: String, base: Dictionary) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return
	var n: Node3D = nd.node
	if n.has_meta("rig"):
		n.remove_meta("rig")
		if n.has_meta("ap"):
			var ap: AnimationPlayer = n.get_meta("ap")
			ap.play(VacaModelo.ANIMS.morrer)
			ap.advance(ap.current_animation_length)
			_cortes_escala(n.get_meta("sk"), nd.c)
			VacaModelo._cascos(n.get_meta("sk"))
	if (base.get("xf0", []) as Array).size() >= 12:
		n.global_transform = _xf_de(base.xf0)
	if (nd.c as Dictionary).has("couro"):
		couro_visual(uid)


# ---------- as peças de carne ----------
# Cada pedaço cortado é uma peça: o trecho [u0, u1) de uma banda (do mesmo desenho da vaca,
# mostrando só ele), do jeito que foi cortado. Fica em algum lugar: no chão (onde caiu), no
# carrinho de mão (vai junto quando empurra), na mesa de carne, nas costas do jogador, ou
# caindo. Caiu na terra: suja (imprópria); no forro de folhas ou no carrinho: limpa.
# c.pecas = [{id, lado, u0, u1, onde ("chao"/"carrinho"/"mesa"/"costas"/"caindo"), xf (no
# chão), maq (o carrinho ou a mesa: índice) e rel (o lugar nele), sujo}]

var _peca_nodes := {}           # "uid:id" -> Node3D


static func _pk(uid: String, id: int) -> String:
	return "%s:%d" % [uid, id]


func pecas_de(uid: String) -> Array:
	var c := couro_de(uid)
	if c.is_empty():
		return []
	if not c.has("pecas"):
		c["pecas"] = []
	return c.pecas


func peca_de(uid: String, id: int) -> Dictionary:
	for pc in pecas_de(uid):
		if int(pc.id) == id:
			return pc
	return {}


## Uma peça nova (e o desenho dela).
func peca_nova(uid: String, d: Dictionary) -> Dictionary:
	var lst := pecas_de(uid)
	var mx := 0
	for pc in lst:
		mx = maxi(mx, int(pc.id))
	d["id"] = mx + 1
	lst.append(d)
	_peca_monta(uid, d)
	return d


## Quanto pesa (kg): pela parte do corpo que tem (meia vaca ~110 kg numa vaca adulta).
func peca_kg(uid: String, pc: Dictionary) -> float:
	var c := couro_de(uid)
	var s := float((c.get("p", {}) as Dictionary).get("s", 1.0))
	var a := maxf(float(pc.u0), -0.35)
	var b := minf(float(pc.u1), 1.2)
	return maxf(0.05, (b - a) / 1.55 * 110.0 * s * s * s * float(pc.get("frac", 1.0)))


## O desenho da peça: a vaca na pose de pendurada mostrando só o trecho dela.
func _peca_monta(uid: String, pc: Dictionary) -> Node3D:
	var k := _pk(uid, int(pc.id))
	if _peca_nodes.has(k) and is_instance_valid(_peca_nodes[k]):
		(_peca_nodes[k] as Node).queue_free()
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty():
		return null
	var c: Dictionary = nd.c
	var p: Dictionary = c.get("p", {})
	var no: Node3D = VacaModelo.build(float(p.get("s", 1.0)), str(p.get("cor", "branca")), bool(p.get("touro", false)), int(p.get("seed", 1)))
	add_child(no)
	var mi := _malha(no)
	if mi:
		mi.mesh = VacaModelo.malha_sem_ubere(mi.mesh)
		malha_cab(mi, no.get_meta("sk"))
	var sk: Skeleton3D = no.get_meta("sk")
	_pose_pendurada(sk)
	_cortes_escala(sk, c)
	_cortes_escala(sk, {"cortes": pc.get("cortes", [])})
	VacaModelo._cascos(sk)
	var lado := str(pc.lado)
	var bd0: Dictionary = c.get("banda", {})
	var cab_e0 := str(bd0.get("cab", "e")) == "e"
	var tem_cab: bool = (cab_e0 if lado == "e" else not cab_e0) and float(pc.u1) > 5.0 and not ("cabeca" in pc.get("cortes", []))
	for ba in no.find_children("*", "BoneAttachment3D", true, false):
		# os chifres (e o cupim) vão com a peça que tem a cabeça
		(ba as Node3D).visible = tem_cab
	for nm in ["saco", "prepucio"]:
		for ch in no.find_children(nm, "MeshInstance3D", true, false):
			ch.queue_free()
	var bd: Dictionary = c.get("banda", {})
	var cab_e := str(bd.get("cab", "e")) == "e"
	var com_cab: bool = cab_e if lado == "e" else not cab_e
	var sm := _banda_mat(no, c, 1.0 if lado == "e" else -1.0, com_cab and float(pc.u1) > 5.0)
	sm.set_shader_parameter("com_rabo", 0.0 if com_cab else 1.0)
	sm.set_shader_parameter("u_lo", float(pc.u0))
	sm.set_shader_parameter("u_hi", float(pc.u1))
	sm.set_shader_parameter("sujo", 1.0 if bool(pc.get("sujo", false)) else 0.0)
	var pls: Array = pc.get("pl", [])
	var plv := PackedVector4Array()
	for e in pls:
		plv.append(Vector4(float(e[0]), float(e[1]), float(e[2]), float(e[3])))
	while plv.size() < PL_MAX:
		plv.append(Vector4(0, 0, 0, -1))
	sm.set_shader_parameter("pl", plv)
	sm.set_shader_parameter("n_pl", mini(pls.size(), PL_MAX))
	mi.material_override = sm
	# os pontos da peça (no nó): o meio, as pontas do eixo e os de baixo (para encostar)
	var rf := _couro_ref(no)
	var to_no := no.global_transform.affine_inverse() * mi.global_transform
	var amostras := []
	var eixo := []
	var u_a := maxf(float(pc.u0), -0.25)
	var u_b := minf(float(pc.u1), 1.0)
	for i in 5:
		var u := lerpf(u_a, u_b, float(i) / 4.0)
		var y := lerpf(float(rf.y_rabo), float(rf.y_pescoco), u)
		var zb := _barriga_z(mi, y)
		var zt := _costas_z(mi, y)
		var wx := _meia_largura(mi, y) * (1.0 if lado == "e" else -1.0)
		eixo.append(to_no * Vector3(wx * 0.4, y, (zb + zt) * 0.5))
		for q in [Vector3(0, y, zb), Vector3(0, y, zt), Vector3(wx, y, (zb + zt) * 0.5)]:
			amostras.append(to_no * q)
	var inv := no.global_transform.affine_inverse()
	var sd: String = "_L" if lado == "e" else "_R"
	if float(pc.u0) < 0.15:
		for nm2 in ["BackFoot" + sd, "BackLowLeg" + sd, "Tail4"]:
			amostras.append(inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm2)).origin))
	if float(pc.u1) > 5.0:
		for nm3 in ["FrontFoot" + sd, "FrontLowLeg" + sd, "Head", "Neck"]:
			amostras.append(inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm3)).origin))
	var centro := Vector3.ZERO
	for q in eixo:
		centro += q
	centro /= eixo.size()
	if not pls.is_empty():
		# cortada na mesa: o meio, o eixo e os pontos de baixo pelo pedaço que sobrou
		var dentro := _dentro_pc(uid, pc, no)
		if dentro.size() >= 2:
			centro = Vector3.ZERO
			for q in dentro:
				centro += to_no * (q as Vector3)
			centro /= dentro.size()
			var a0: Vector3 = to_no * (dentro[0] as Vector3)
			var b0 := a0
			var dm := -1.0
			for q in dentro:
				var w: Vector3 = to_no * (q as Vector3)
				if w.distance_squared_to(centro) > dm:
					dm = w.distance_squared_to(centro)
					a0 = w
			dm = -1.0
			for q in dentro:
				var w: Vector3 = to_no * (q as Vector3)
				if w.distance_squared_to(a0) > dm:
					dm = w.distance_squared_to(a0)
					b0 = w
			eixo = [a0, b0]
			var am2 := []
			for q in amostras:
				if _no_pl(inv_mi(no, mi) * (q as Vector3), pls):
					am2.append(q)
			for i in mini(dentro.size(), 40):
				am2.append(to_no * (dentro[(i * 7919) % dentro.size()] as Vector3))
			amostras = am2
	no.set_meta("low", amostras)
	no.set_meta("eixo", [eixo[0], eixo[eixo.size() - 1]])
	no.set_meta("centro", centro)
	no.set_meta("fora", (to_no.basis * Vector3(1.0 if lado == "e" else -1.0, 0, 0)).normalized())
	no.set_meta("uid", uid)
	no.set_meta("peca", int(pc.id))
	# os tocos onde a pata ou a cabeça foram tiradas
	var m_por_u: float = mi.global_transform.basis.get_scale().x
	for t in pc.get("cortes", []):
		var pm := parte_malha(c, str(t))
		if pm.is_empty():
			continue
		var tc := _toco(float(PARTES[str(t)].r) / m_por_u)
		mi.add_child(tc)
		tc.transform = Transform3D(_base_para(pm.dir), pm.corte)
	_peca_nodes[k] = no
	if (pc.get("xf", []) as Array).size() >= 12:
		no.global_transform = _xf_de(pc.xf)
	_peca_lugar(uid, pc)
	return no


func peca_no(uid: String, id: int) -> Node3D:
	return _peca_nodes.get(_pk(uid, id), null)


## O meio da peça no mundo.
func peca_centro(uid: String, id: int) -> Vector3:
	var no := peca_no(uid, id)
	if no == null or not is_instance_valid(no):
		return Vector3.INF
	return no.global_transform * (no.get_meta("centro") as Vector3)


## O jeito de deitar a peça: o eixo do corpo na direção "ao_longo", o lado de fora para
## cima (a carne partida para baixo), com o meio em "onde".
func peca_deitada(uid: String, id: int, onde: Transform3D) -> Transform3D:
	var no := peca_no(uid, id)
	if no == null:
		return onde
	var ex: Array = no.get_meta("eixo")
	var a_l: Vector3 = ((ex[1] as Vector3) - (ex[0] as Vector3)).normalized()
	var f_l: Vector3 = no.get_meta("fora")
	f_l = (f_l - a_l * a_l.dot(f_l)).normalized()
	var de := Basis(a_l, f_l, a_l.cross(f_l))                 # no nó: eixo, fora, o outro
	var para := Basis(onde.basis.x.normalized(), onde.basis.y.normalized(), onde.basis.x.normalized().cross(onde.basis.y.normalized()))
	var b := para * de.inverse()
	var s := no.global_transform.basis.get_scale().x
	var cen: Vector3 = no.get_meta("centro")
	return Transform3D(b.scaled(Vector3.ONE * s), onde.origin - b * (cen * s))


## Põe a peça no lugar dela (no carrinho, na mesa: pelo lugar guardado; no chão: o xf).
func _peca_lugar(uid: String, pc: Dictionary) -> void:
	var no := peca_no(uid, int(pc.id))
	if no == null or not is_instance_valid(no):
		return
	match str(pc.onde):
		"carrinho", "mesa":
			var host: Transform3D = _jogo._peca_host_xf(int(pc.get("maq", -1)))
			if host != Transform3D.IDENTITY and (pc.get("rel", []) as Array).size() >= 12:
				no.global_transform = host * _xf_de(pc.rel)
		"costas":
			no.global_transform = _jogo._peca_costas_xf(uid, int(pc.id))
		"chao":
			if (pc.get("xf", []) as Array).size() >= 12:
				no.global_transform = _xf_de(pc.xf)


## Todo quadro: as peças no carrinho (anda), na mesa e nas costas acompanham.
func _pecas_tick() -> void:
	for uid in _nodes:
		var c: Dictionary = _nodes[uid].c
		for pc in c.get("pecas", []):
			if str(pc.onde) in ["carrinho", "mesa", "costas"]:
				_peca_lugar(str(uid), pc)


## Monta as peças salvas (ao montar a carcaça).
func _pecas_monta(uid: String) -> void:
	_couro_chao_monta(uid)
	for k in _peca_nodes.keys():
		if str(k).begins_with(uid + ":"):
			if is_instance_valid(_peca_nodes[k]):
				(_peca_nodes[k] as Node).queue_free()
			_peca_nodes.erase(k)
	var c := couro_de(uid)
	# (as peças antigas, de antes, que eram "quarto_" nas partes)
	var partes: Array = c.get("partes", [])
	for e in partes.duplicate():
		if str(e.tipo).begins_with("quarto_"):
			partes.erase(e)
			pecas_de(uid).append({"id": pecas_de(uid).size() + 1, "lado": str(e.tipo).substr(7), "u0": -9.0, "u1": QUARTO_U,
				"onde": "chao", "xf": e.xf, "sujo": bool(e.get("sujo", true))})
	for pc in pecas_de(uid):
		if str(pc.onde) == "caindo":
			pc.onde = "chao"
		_peca_monta(uid, pc)


## A peça mais perto (no chão), [uid, id] ou [].
func peca_perto(pos: Vector3, reach: float, onde := "chao") -> Array:
	var best := []
	var bd := reach
	for uid in _nodes:
		for pc in (_nodes[uid].c as Dictionary).get("pecas", []):
			if str(pc.onde) != onde:
				continue
			var cp := peca_centro(str(uid), int(pc.id))
			var d := Vector2(cp.x - pos.x, cp.z - pos.z).length()
			if d < bd:
				bd = d
				best = [str(uid), int(pc.id)]
	return best


## As peças num carrinho ou numa mesa (índice): [[uid, id]...].
func pecas_em(onde: String, mi: int) -> Array:
	var out := []
	for uid in _nodes:
		for pc in (_nodes[uid].c as Dictionary).get("pecas", []):
			if str(pc.onde) == onde and int(pc.get("maq", -1)) == mi:
				out.append([str(uid), int(pc.id)])
	return out


## Muda a peça de lugar (pega, põe no carrinho/mesa, solta no chão).
func peca_por(uid: String, id: int, onde: String, maq := -1, rel := Transform3D.IDENTITY) -> void:
	var pc := peca_de(uid, id)
	if pc.is_empty():
		return
	pc.onde = onde
	pc.erase("xf")
	pc.erase("rel")
	pc.erase("maq")
	if onde in ["carrinho", "mesa"]:
		pc["maq"] = maq
		pc["rel"] = _xf_json(rel)
	_peca_lugar(uid, pc)


## Solta a peça (das costas, ou o carrinho despejou): cai no chão.
func peca_cai(uid: String, id: int) -> void:
	var pc := peca_de(uid, id)
	var no := peca_no(uid, id)
	if pc.is_empty() or no == null:
		return
	pc.onde = "caindo"
	_caindo.append({"node": no, "vel": Vector3.DOWN * 0.2, "ang": Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 0.4,
		"uid": uid, "tipo": "peca", "peca": id, "chao": 0.0, "r": 0.3, "low": no.get_meta("low")})


## A peça é cortada em duas no ponto t (0..1 do comprimento dela): devolve a nova.
func peca_partir(uid: String, id: int, t: float) -> Dictionary:
	var pc := peca_de(uid, id)
	if pc.is_empty():
		return {}
	var a := maxf(float(pc.u0), -0.25)
	var b := minf(float(pc.u1), 1.0)
	var uc := lerpf(a, b, clampf(t, 0.08, 0.92))
	var nova := pc.duplicate(true)
	nova.erase("id")
	nova.u0 = uc
	pc.u1 = uc
	var d := peca_nova(uid, nova)
	_peca_monta(uid, pc)
	return d


## Cortes da mesa: cada peça guarda os planos (na malha) do lado que ficou com ela.
const PL_MAX := 12
static var _dentro_cache := {}


static func inv_mi(no: Node3D, mi: MeshInstance3D) -> Transform3D:
	return mi.global_transform.affine_inverse() * no.global_transform


static func _no_pl(q: Vector3, pls: Array) -> bool:
	for e in pls:
		if Vector3(float(e[0]), float(e[1]), float(e[2])).dot(q) < float(e[3]):
			return false
	return true


## Pontos de dentro da meia vaca (na malha), para pesar e achar o meio dos pedaços.
func _dentro_meia(uid: String, lado: String, no: Node3D) -> Array:
	var key := uid + ":" + lado
	if _dentro_cache.has(key):
		return _dentro_cache[key]
	var rf := _couro_ref(no)
	var mi: MeshInstance3D = rf.mi
	var sg := 1.0 if lado == "e" else -1.0
	var out := []
	for iu in 32:
		var u := lerpf(-0.25, 1.0, (float(iu) + 0.5) / 32.0)
		var y := lerpf(float(rf.y_rabo), float(rf.y_pescoco), u)
		var zb := _barriga_z(mi, y)
		var zt := _costas_z(mi, y)
		var wx := _meia_largura(mi, y)
		var zc := (zb + zt) * 0.5
		var hz := maxf((zt - zb) * 0.5, 1e-4)
		for ix in 6:
			var fx := (float(ix) + 0.5) / 6.0
			for iz in 8:
				var fz := (float(iz) + 0.5) / 8.0 * 2.0 - 1.0
				if fx * fx + fz * fz > 1.0:
					continue
				out.append([u, Vector3(sg * fx * wx, y, zc + fz * hz)])
	_dentro_cache[key] = out
	return out


## Os pontos de dentro desta peça (na malha).
func _dentro_pc(uid: String, pc: Dictionary, no: Node3D) -> Array:
	var out := []
	var pls: Array = pc.get("pl", [])
	for e in _dentro_meia(uid, str(pc.lado), no):
		var u := float(e[0])
		if u < float(pc.u0) or u >= float(pc.u1):
			continue
		if _no_pl(e[1], pls):
			out.append(e[1])
	return out


## Corta a peça num plano (n, w na malha): a peça fica com n·p >= w, a nova com o resto.
## Não corta (devolve {}) se a faca passa fora da carne ou já tem cortes demais.
func peca_partir_plano(uid: String, id: int, n: Vector3, w: float) -> Dictionary:
	var pc := peca_de(uid, id)
	var no := peca_no(uid, id)
	if pc.is_empty() or no == null:
		return {}
	var pls: Array = pc.get("pl", [])
	if pls.size() >= PL_MAX:
		return {}
	var tot := _dentro_pc(uid, pc, no)
	if tot.size() < 2:
		return {}
	var na := 0
	for q in tot:
		if n.dot(q) >= w:
			na += 1
	var nb := tot.size() - na
	if na < 1 or nb < 1:
		return {}
	var f0 := float(pc.get("frac", 1.0))
	var nova := pc.duplicate(true)
	nova.erase("id")
	var pa: Array = pls.duplicate(true)
	pa.append([n.x, n.y, n.z, w])
	var pb: Array = pls.duplicate(true)
	pb.append([-n.x, -n.y, -n.z, -w])
	pc["pl"] = pa
	nova["pl"] = pb
	pc["frac"] = f0 * float(na) / float(tot.size())
	nova["frac"] = f0 * float(nb) / float(tot.size())
	var d := peca_nova(uid, nova)
	_peca_monta(uid, pc)
	return d


## As partes que ainda estão na peça e têm que sair antes de cortar a carne: as patas
## (a canela de trás, se a peça tem a perna de trás; a da frente, se é a de cima) e a cabeça.
func peca_partes_falta(uid: String, pc: Dictionary) -> Array:
	var out := []
	var c := couro_de(uid)
	var lado := str(pc.lado)
	var feitas: Array = pc.get("cortes", [])
	if float(pc.u0) < 0.1:
		out.append("pe_te" if lado == "e" else "pe_td")
	if float(pc.u1) > 5.0:
		out.append("pe_fe" if lado == "e" else "pe_fd")
		var bd: Dictionary = c.get("banda", {})
		var cab_e := str(bd.get("cab", "e")) == "e"
		if cab_e == (lado == "e"):
			out.append("cabeca")
	return out.filter(func(t): return not (t in feitas))


## Onde a parte vai ser cortada na peça (no mundo).
func peca_parte_ponto(uid: String, id: int, tipo: String) -> Vector3:
	var no := peca_no(uid, id)
	var pm := parte_malha(couro_de(uid), tipo)
	if no == null or pm.is_empty():
		return Vector3.INF
	return (_malha(no) as MeshInstance3D).global_transform * (pm.corte as Vector3)


## Uma machadada na pata ou na cabeça da peça; no último golpe ela solta e cai.
func peca_golpe_parte(uid: String, id: int, tipo: String, golpe: int) -> bool:
	var pc := peca_de(uid, id)
	var no := peca_no(uid, id)
	if pc.is_empty() or no == null or not PARTES.has(tipo):
		return false
	var w := peca_parte_ponto(uid, id, tipo)
	_pinga(w)
	if golpe < int(PARTES[tipo].golpes):
		Sons.play_at(_jogo, "machado_osso", w, 0.0, _rng.randf_range(0.92, 1.08))
		return false
	Sons.play_at(_jogo, "osso_quebra", w, 2.0, _rng.randf_range(0.95, 1.05))
	var mi := _malha(no)
	var par := _parte_no(uid, tipo, [], mi)
	if not pc.has("cortes"):
		pc["cortes"] = []
	(pc.cortes as Array).append(tipo)
	_peca_monta(uid, pc)
	if par:
		var fora := par.global_position - w
		fora.y = 0.0
		fora = fora.normalized() if fora.length() > 0.01 else Vector3.RIGHT
		_caindo.append({"node": par, "vel": fora * 0.6 + Vector3.UP * 0.3, "ang": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * 3.0,
			"uid": uid, "tipo": tipo, "chao": 0.0, "r": float(PARTES[tipo].r)})
	return true


## A banda pendurada (a parte de cima, depois de partida) é solta da corda: cai inteira
## no chão como uma peça (com a pata da frente e, se for a dela, a cabeça).
func banda_soltar(uid: String, lado: String) -> void:
	var q := quarto_de(uid, lado)
	if bool(q.get("solta", false)):
		return
	var bn := banda_no(uid, lado)
	q["solta"] = true
	var pc := peca_nova(uid, {"lado": lado, "u0": QUARTO_U if bool(q.get("caiu", false)) else -9.0, "u1": 99.0, "onde": "caindo", "sujo": false,
		"xf": _xf_json(bn.global_transform) if bn else []})
	quarto_visual(uid, lado)
	var no := peca_no(uid, int(pc.id))
	if no:
		_caindo.append({"node": no, "vel": Vector3.DOWN * 0.2, "ang": Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 0.5,
			"uid": uid, "tipo": "peca", "peca": int(pc.id), "chao": 0.0, "r": 0.3, "low": no.get_meta("low")})
	Sons.play_at(_jogo, "baque", bn.global_position if bn else Vector3.ZERO, 2.0, 0.7)


## A peça sai do mundo (foi para a mochila).
func peca_tirar(uid: String, id: int) -> void:
	var lst := pecas_de(uid)
	for pc in lst.duplicate():
		if int(pc.id) == id:
			lst.erase(pc)
	var k := _pk(uid, id)
	if _peca_nodes.has(k):
		if is_instance_valid(_peca_nodes[k]):
			(_peca_nodes[k] as Node).queue_free()
		_peca_nodes.erase(k)


# ---------- partir a banda (faca e machado) ----------
# Cada banda pendurada é partida no meio: com a faca, entre os fios de costela (onde a
# carne é mole), corta a carne em volta da banda até a espinha; com o machado, a espinha.
# O pedaço de baixo cai: num carrinho de mão posto embaixo fica limpo (vai para ele); na
# terra, suja e fica impróprio para comer. c.quartos = {"e"/"d": {faca, golpes, caiu, onde}}.

const QUARTO_U := 0.3           # onde parte (perto do quadril: o pedaço da anca cabe no carrinho)
const QUARTO_GOLPES := 4
static var _largura := {}


## A banda ("e" a esquerda = a carcaça; "d" a direita = o segundo desenho).
func banda_no(uid: String, lado: String) -> Node3D:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty():
		return null
	if lado == "d":
		return nd.get("n2", null)
	return nd.node


func quarto_de(uid: String, lado: String) -> Dictionary:
	var c: Dictionary = couro_de(uid)
	if c.is_empty():
		return {}
	if not c.has("quartos"):
		c["quartos"] = {}
	if not (c.quartos as Dictionary).has(lado):
		c.quartos[lado] = {"faca": 0.0, "golpes": 0, "caiu": false}
	return c.quartos[lado]


## A metade da largura do corpo na altura y (na malha).
static func _meia_largura(mi: MeshInstance3D, y: float) -> float:
	var k := int(round(y / 0.002))
	if _largura.has(k):
		return _largura[k]
	var mx := 0.004
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in vs:
		if absf(v.y - y) < 0.0025 and v.z > 0.012:
			mx = maxf(mx, absf(v.x))
	_largura[k] = mx
	return mx


## A linha da faca em volta da banda (da barriga até a espinha), no mundo.
func quarto_linha(uid: String, lado: String, n_pts := 16) -> Array:
	var n := banda_no(uid, lado)
	if n == null or not is_instance_valid(n):
		return []
	var rf := _couro_ref(n)
	var mi: MeshInstance3D = rf.mi
	var y := lerpf(float(rf.y_rabo), float(rf.y_pescoco), QUARTO_U)
	var zb := _barriga_z(mi, y)
	var zt := _costas_z(mi, y)
	var zc := (zb + zt) * 0.5
	var rz := (zt - zb) * 0.5
	var wx := _meia_largura(mi, y) + 0.0004
	var sd := 1.0 if lado == "e" else -1.0
	var out := []
	for i in n_pts:
		var th := lerpf(-PI * 0.5, PI * 0.5, float(i) / (n_pts - 1))
		out.append(mi.global_transform * Vector3(sd * wx * cos(th), y, zc + rz * sin(th)))
	return out


## Para onde o lado de fora da banda olha (no mundo).
func banda_fora(uid: String, lado: String) -> Vector3:
	var n := banda_no(uid, lado)
	if n == null or not is_instance_valid(n):
		return Vector3.FORWARD
	var mi := _malha(n)
	return (mi.global_transform.basis.x * (1.0 if lado == "e" else -1.0)).normalized()


## O desenho da banda conforme o corte (a faca andando; partida: só a parte de cima).
func quarto_visual(uid: String, lado: String) -> void:
	var n := banda_no(uid, lado)
	if n == null or not is_instance_valid(n):
		return
	var mi := _malha(n)
	var sm: ShaderMaterial = mi.material_override as ShaderMaterial
	if sm == null:
		return
	var q := quarto_de(uid, lado)
	var caiu := bool(q.get("caiu", false))
	sm.set_shader_parameter("q_faca", 0.0 if caiu else float(q.get("faca", 0.0)) * 1.05)
	sm.set_shader_parameter("u_lo", 99.0 if bool(q.get("solta", false)) else (QUARTO_U if caiu else -9.0))
	if bool(q.get("solta", false)):
		for ba in n.find_children("*", "BoneAttachment3D", true, false):
			(ba as Node3D).visible = false


## Uma machadada na espinha da banda; no último golpe o pedaço de baixo solta e cai.
func quarto_golpe(uid: String, lado: String) -> bool:
	var q := quarto_de(uid, lado)
	var lin := quarto_linha(uid, lado, 16)
	var w: Vector3 = lin[15] if not lin.is_empty() else Vector3.ZERO
	q.golpes = int(q.get("golpes", 0)) + 1
	_pinga(w)
	if int(q.golpes) < QUARTO_GOLPES:
		Sons.play_at(_jogo, "machado_osso", w, 0.0, _rng.randf_range(0.95, 1.12))
		return false
	Sons.play_at(_jogo, "osso_quebra", w, 2.0, 1.05)
	q.caiu = true
	quarto_visual(uid, lado)
	# o pedaço de baixo vira uma peça de carne (do jeito que foi cortada) e cai
	var bn := banda_no(uid, lado)
	var pc := peca_nova(uid, {"lado": lado, "u0": -9.0, "u1": QUARTO_U, "onde": "caindo", "sujo": false,
		"xf": _xf_json(bn.global_transform) if bn else []})
	var no: Node3D = _peca_nodes.get(_pk(uid, int(pc.id)), null)
	if no:
		_caindo.append({"node": no, "vel": Vector3.DOWN * 0.3, "ang": Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 0.5,
			"uid": uid, "tipo": "peca", "peca": int(pc.id), "chao": 0.0, "r": 0.3, "low": no.get_meta("low")})
	return true


## O pedaço de baixo da banda (o quarto que caiu): um desenho da vaca mostrando só ele.
func _quarto_no(uid: String, lado: String, xf_salvo: Array, sujo: bool) -> Node3D:
	var nd: Dictionary = _nodes.get(uid, {})
	var bn := banda_no(uid, lado)
	if nd.is_empty() or bn == null or not is_instance_valid(bn):
		return null
	var c: Dictionary = nd.c
	var p: Dictionary = c.get("p", {})
	var pc: Node3D = VacaModelo.build(float(p.get("s", 1.0)), str(p.get("cor", "branca")), bool(p.get("touro", false)), int(p.get("seed", 1)))
	add_child(pc)
	var mi2 := _malha(pc)
	if mi2:
		mi2.mesh = VacaModelo.malha_sem_ubere(mi2.mesh)
		malha_cab(mi2, pc.get_meta("sk"))
	var sk2: Skeleton3D = pc.get_meta("sk")
	_pose_pendurada(sk2)
	_cortes_escala(sk2, c)
	VacaModelo._cascos(sk2)
	for ba in pc.find_children("*", "BoneAttachment3D", true, false):
		(ba as Node3D).visible = false
	for nm in ["saco", "prepucio"]:
		for ch in pc.find_children(nm, "MeshInstance3D", true, false):
			ch.queue_free()
	pc.global_transform = bn.global_transform
	var bd: Dictionary = c.get("banda", {})
	var cab_e := str(bd.get("cab", "e")) == "e"
	var com_cab: bool = cab_e if lado == "e" else not cab_e
	var sm := _banda_mat(pc, c, 1.0 if lado == "e" else -1.0, false)
	sm.set_shader_parameter("com_rabo", 0.0 if com_cab else 1.0)
	sm.set_shader_parameter("q_parte", 2.0)
	sm.set_shader_parameter("sujo", 1.0 if sujo else 0.0)
	mi2.material_override = sm
	# os pontos de baixo do pedaço (para saber quando encosta no chão)
	var inv := pc.global_transform.affine_inverse()
	var low := []
	for nm2 in ["BackFoot_R", "BackFoot_L", "Tail4", "Hips", "BackUpLeg_R", "BackUpLeg_L", "Back"]:
		low.append(inv * (sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone(nm2)).origin))
	pc.set_meta("low", low)
	pc.set_meta("uid", uid)
	pc.set_meta("tipo", "quarto_" + lado)
	if xf_salvo.size() >= 12:
		pc.global_transform = _xf_de(xf_salvo)
	return pc


## Sujou (caiu na terra).
static func quarto_sujar(pc: Node3D) -> void:
	var mi := _malha(pc)
	if mi and mi.material_override is ShaderMaterial:
		(mi.material_override as ShaderMaterial).set_shader_parameter("sujo", 1.0)


# ---------- partir ao meio (com o machado) ----------
# Aberta e pendurada (cada pata da frente amarrada na sua ponta da corda), a vaca é
# partida ao meio pela espinha com o machado, de cima para baixo. Antes, o jogador escolhe
# em qual banda ficam a cabeça e o pescoço. Partida, são duas bandas (dois desenhos da
# mesma vaca, cada um mostrando só o seu lado; o lado de dentro é a carne e o osso
# partido), cada uma pendurada pela sua pata. c.banda = {cab: "e"/"d", corte: 0..1, feito}.

const BANDA_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float y_rabo;
uniform float y_pescoco;
uniform float lado;
uniform float com_cabeca;
uniform vec3 cor_pelo;
uniform float esc;
uniform vec3 casco0;
uniform vec3 casco1;
uniform vec3 casco2;
uniform vec3 casco3;
uniform float r_casco;
uniform vec3 rabo0;
uniform vec3 rabo1;
uniform vec3 rabo2;
uniform vec3 rabo3;
uniform vec3 rabo4;
uniform vec3 rabo5;
uniform float r_rabo;
uniform float com_rabo;
uniform vec3 cab_p;
uniform vec3 cab_d;
uniform float r_cab;
uniform float corte_q;
uniform float q_faca;
uniform float q_parte;
uniform float u_lo = -9.0;
uniform float u_hi = 9.0;
uniform float q_w;
uniform float zb;
uniform float zt;
uniform float sujo;
uniform float zt_u[24];             // as costas e a barriga (z na malha) de u = -0.25 até 1
uniform float zb_u[24];
uniform vec4 pl[12];                // cortes da mesa: fica onde dot(n, p) >= w
uniform int n_pl = 0;
varying vec3 p;
varying vec3 nn;
varying vec3 cam_l;
varying float wcab;
void vertex() {
	p = VERTEX; nn = NORMAL; wcab = UV2.x;
	cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}
// o raio do olho até o ponto entra no lado que fica deste plano em t (o maior é a tampa)
void entra(vec3 c, vec3 d, vec3 n, float w, inout float tm, inout vec3 nm) {
	float fc = dot(n, c) - w;
	if (fc >= 0.0) { return; }
	float den = dot(n, d);
	if (den <= 1e-9) { return; }
	float t = -fc / den;
	if (t > tm) { tm = t; nm = n; }
}
float seg(vec3 q, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = clamp(dot(q - a, ab) / max(dot(ab, ab), 1e-12), 0.0, 1.0);
	return distance(q, a + ab * t);
}
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float perf(float u, bool topo) {
	float f = clamp((u + 0.25) / 1.25, 0.0, 1.0) * 23.0;
	int i = int(min(floor(f), 22.0));
	float t = f - float(i);
	return topo ? mix(zt_u[i], zt_u[i + 1], t) : mix(zb_u[i], zb_u[i + 1], t);
}
// A banda vista no corte do meio (pela espinha): de cima para baixo, os espinhos das
// vértebras com a carne entre eles, o canal da medula, os corpos das vértebras serrados
// (osso esponjoso, com os discos), o filé (lombo) e a gordura do rim embaixo da espinha
// e, no peito, as costelas por dentro (brancas, curvas, com a pleura brilhando) até o
// esterno; na anca, o osso da bacia. Devolve a cor; rg = a aspereza.
vec3 anatomia(vec3 P, float uP, out float rg) {
	float ztt = perf(uP, true);
	float zbb = perf(uP, false);
	float H = max((ztt - zbb) * esc, 0.05);
	float f = clamp((ztt - P.z) * esc / H, 0.0, 1.2);
	float ym = P.y * esc;
	vec3 qc = P * esc;
	float n1 = ruido(qc * 11.0);
	float n2 = ruido(qc * 26.0 + vec3(2.3, 0.7, 4.1));
	float n3 = ruido(qc * 90.0);
	vec3 carne = mix(vec3(0.36, 0.035, 0.03), vec3(0.54, 0.075, 0.055), n1);
	vec3 osso = mix(vec3(0.86, 0.8, 0.7), vec3(0.95, 0.9, 0.82), n2);
	vec3 esponja = mix(vec3(0.78, 0.55, 0.48), vec3(0.93, 0.85, 0.74), smoothstep(0.35, 0.7, n3));
	vec3 gordura = mix(vec3(0.86, 0.8, 0.66), vec3(0.95, 0.9, 0.78), n2);
	vec3 cor = carne;
	rg = 0.45;
	bool peito = uP > 0.45 && uP < 0.93;
	bool lombo = uP >= 0.1 && uP <= 0.45;
	bool pescoco = uP >= 0.93;
	// a espessura das partes da espinha (fração da altura do corpo)
	float esp_top = peito ? 0.2 : (pescoco ? 0.09 : 0.1);
	float can0 = esp_top;
	float can1 = esp_top + 0.035;
	float cor1 = can1 + (peito ? 0.1 : 0.11);
	// a capa de gordura das costas
	if (f < 0.025 + 0.015 * n2) {
		cor = gordura; rg = 0.6;
	} else if (uP < -0.12) {
		// o rabo e a ponta da anca: carne
		cor = carne;
	} else if (f < can0) {
		// os espinhos: lâminas de osso inclinadas para trás, carne entre elas
		float s1 = fract((ym + f * H * 0.45) / 0.055);
		float lam = 1.0 - smoothstep(0.22, 0.32, abs(s1 - 0.5));
		if (uP < 0.1) { lam = 0.0; }
		cor = mix(carne * 0.9, osso, lam);
		rg = mix(0.5, 0.35, lam);
	} else if (f < can1) {
		// o canal com a medula (branca rosada, as bordas escuras)
		float m = abs((f - can0) / (can1 - can0) - 0.5) * 2.0;
		cor = mix(vec3(0.9, 0.78, 0.74), vec3(0.45, 0.12, 0.1), smoothstep(0.55, 1.0, m));
		rg = 0.3;
	} else if (f < cor1) {
		// os corpos das vértebras serrados: osso esponjoso; os discos entre eles
		float s2 = fract(ym / (pescoco ? 0.07 : 0.052));
		float disco = 1.0 - smoothstep(0.035, 0.075, min(s2, 1.0 - s2));
		float casca = smoothstep(0.75, 0.95, abs((f - can1) / (cor1 - can1) - 0.5) * 2.0);
		cor = mix(esponja, osso, casca * 0.8);
		if (uP > -0.12 && uP < 0.1) { disco = 0.0; }          // o sacro: tudo grudado
		cor = mix(cor, vec3(0.62, 0.4, 0.38), disco);
		rg = 0.55;
	} else if (lombo || uP <= 0.1 || pescoco) {
		if (lombo && f < cor1 + 0.16) {
			// o filé mignon embaixo da espinha (mais escuro e liso)
			cor = mix(vec3(0.3, 0.03, 0.04), vec3(0.42, 0.05, 0.06), n1);
			rg = 0.35;
		} else if (lombo && f < cor1 + 0.28) {
			// a gordura do rim (sebo em gomos, com fiapos de carne)
			float g1 = ruido(qc * 18.0);
			cor = mix(gordura, gordura * 0.8, smoothstep(0.4, 0.6, g1));
			cor = mix(cor, carne, smoothstep(0.72, 0.8, ruido(qc * 40.0 + vec3(5.0))) * 0.6);
			rg = 0.7;
		} else if (uP <= 0.1 && uP > -0.08 && f > 0.42 && f < 0.7) {
			// a bacia serrada (osso branco em volta, esponja no meio)
			float e = length(vec2((uP - 0.01) / 0.09, (f - 0.56) / 0.14));
			cor = e < 0.75 ? esponja : (e < 1.0 ? osso : carne);
		} else {
			// a parede da barriga por dentro: carne fina com a película brilhante
			cor = mix(carne, vec3(0.72, 0.42, 0.4), 0.25 + 0.2 * n2);
			rg = 0.28;
		}
	} else {
		// o peito por dentro: as costelas curvas, a carne entre elas e a pleura brilhando
		float fe = 0.88;                                         // onde as costelas acabam (cartilagem)
		float s3 = (ym - f * H * 0.32 - sin(f * 3.14159) * 0.025) / 0.075;
		float r = fract(s3);
		float lar = 0.13 + 0.035 * sin(floor(s3) * 2.7) + 0.02 * n1;
		float dr = abs(r - 0.5);
		float cost = 1.0 - smoothstep(lar, lar + 0.05, dr);
		// a costela é redonda: clara no meio, mais escura (rosada) nas beiradas
		float meio_c = 1.0 - smoothstep(0.0, lar, dr);
		vec3 c_cost = mix(vec3(0.74, 0.55, 0.5), osso, 0.45 + 0.55 * meio_c);
		c_cost = mix(c_cost, vec3(0.86, 0.8, 0.8), smoothstep(fe - 0.08, fe, f));   // a ponta de cartilagem
		// a carne entre as costelas (o músculo, com fiapos de gordura)
		vec3 entre = mix(carne * 0.8, vec3(0.6, 0.12, 0.1), 0.25 * n2);
		entre = mix(entre, gordura, smoothstep(0.78, 0.9, ruido(qc * 45.0)) * 0.5);
		cor = mix(entre, c_cost, cost * smoothstep(1.0, 0.92, f));
		if (f > 0.92 && uP > 0.6) {
			// o esterno serrado
			float s4 = fract(ym / 0.09);
			cor = mix(esponja, vec3(0.6, 0.38, 0.36), 1.0 - smoothstep(0.04, 0.09, min(s4, 1.0 - s4)));
		}
		// o diafragma (a fraldinha) logo atrás das costelas
		if (uP < 0.5) {
			cor = mix(cor, vec3(0.5, 0.1, 0.09), smoothstep(0.5, 0.46, uP));
		}
		rg = mix(0.22, 0.4, cost);
	}
	return cor;
}
void fragment() {
	float u = (y_rabo - p.y) / (y_rabo - y_pescoco);
	bool cab = u > 0.92;
	float dr = min(min(seg(p, rabo1, rabo2), seg(p, rabo2, rabo3)), min(seg(p, rabo3, rabo4), seg(p, rabo4, rabo5)));
	dr = min(dr, seg(p, rabo0, rabo1) + r_rabo * 0.35);
	bool rabo = dr < r_rabo;
	// a banda partida no meio: em cima (pendurada) ou o pedaço de baixo (que caiu)
	// só o trecho [u_lo, u_hi) do corpo (a banda pendurada depois de partida, ou um pedaço)
	if (u_lo > -5.0 && (u < u_lo || rabo)) { discard; }
	if (u >= u_hi) { discard; }
	if (rabo) {
		if (com_rabo < 0.5) { discard; }      // o rabo inteiro fica numa banda só
	} else if (cab) {
		if (com_cabeca < 0.5) { discard; }
	} else if (p.x * lado < 0.0) {
		discard;
	}
	for (int i = 0; i < 12; i++) {
		if (i < n_pl && dot(pl[i].xyz, p) < pl[i].w) { discard; }
	}
	vec3 q = p * esc;
	float n1 = ruido(q * 11.0);
	float n2 = ruido(q * 34.0 + vec3(3.1, 1.7, 5.3));
	float dc = min(min(distance(p, casco0), distance(p, casco1)), min(distance(p, casco2), distance(p, casco3)));
	bool tampa = false;
	if (!FRONT_FACING) {
		// visto por um corte: a carne é maciça. Pinta o lado de dentro como a face do corte
		// (lisa, virada para o olho, no plano do corte), nunca a casca oca do outro lado.
		vec3 d = p - cam_l;
		float tm = -1.0;
		vec3 nm = vec3(0.0);
		float k = 1.0 / (y_rabo - y_pescoco);
		float ak = abs(k);
		if (abs(lado) > 0.5) { entra(cam_l, d, vec3(lado, 0.0, 0.0), 0.0, tm, nm); }
		if (u_lo > -5.0) { entra(cam_l, d, vec3(0.0, -k, 0.0) / ak, (u_lo - k * y_rabo) / ak, tm, nm); }
		if (u_hi < 5.0) { entra(cam_l, d, vec3(0.0, k, 0.0) / ak, (k * y_rabo - u_hi) / ak, tm, nm); }
		if (com_cabeca < 0.5) { entra(cam_l, d, vec3(0.0, k, 0.0) / ak, (k * y_rabo - 0.92) / ak, tm, nm); }
		for (int i = 0; i < 12; i++) {
			if (i < n_pl) { entra(cam_l, d, normalize(pl[i].xyz), pl[i].w / length(pl[i].xyz), tm, nm); }
		}
		if (tm > 0.0 && tm < 1.0) {
			vec3 P = cam_l + d * tm;
			float uP = (y_rabo - P.y) / (y_rabo - y_pescoco);
			// o meio (espinha) não corta a cabeça da banda que ficou com ela
			if (!(abs(nm.x) > 0.9 && com_cabeca > 0.5 && uP > 0.92)) {
				tampa = true;
				vec3 qc = P * esc;
				float c1 = ruido(qc * 11.0);
				float c2 = ruido(qc * 26.0 + vec3(2.3, 0.7, 4.1));
				vec3 carne = mix(vec3(0.34, 0.03, 0.025), vec3(0.52, 0.07, 0.05), c1);
				float gord = smoothstep(0.68, 0.82, c2) * 0.5;
				vec3 cor = mix(carne, vec3(0.82, 0.74, 0.62), gord);
				float rg = 0.4;
				// no meio da vaca (o corte da espinha): os ossos de verdade
				if (abs(nm.x) > 0.9 && uP <= 0.99) {
					cor = anatomia(P, uP, rg);
				} else {
					// um corte de través: o osso da espinha no meio, em cima
					float ztt = perf(uP, true);
					float zbb = perf(uP, false);
					float f = (ztt - P.z) / max(ztt - zbb, 1e-5);
					float lx = abs(P.x) * esc;
					if (uP > -0.1 && uP < 0.95 && f > 0.1 && f < 0.3 && lx < 0.05) {
						cor = mix(vec3(0.8, 0.6, 0.52), vec3(0.93, 0.87, 0.78), smoothstep(0.3, 0.7, ruido(qc * 90.0)));
					}
				}
				ALBEDO = cor;
				ROUGHNESS = rg;
				NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(-nm, 0.0))).xyz);
			}
		}
		if (!tampa) {
			// por dentro sem corte na frente (a barriga aberta): a parede por dentro
			float rg2 = 0.45;
			ALBEDO = anatomia(p, u, rg2) * 0.8;
			ROUGHNESS = rg2;
		}
	} else if (dc < r_casco) {
		ALBEDO = vec3(0.12, 0.1, 0.08);
		ROUGHNESS = 0.6;
	} else if (wcab > 0.5) {
		ALBEDO = cor_pelo * (0.85 + 0.3 * n2);
		ROUGHNESS = 0.85;
	} else {
		float fio = abs(sin((q.y * 90.0 + n1 * 4.0)));
		vec3 carne = mix(vec3(0.22, 0.02, 0.018), vec3(0.4, 0.045, 0.035), n1 * 0.6 + fio * 0.25);
		float n3 = ruido(q * 70.0 + vec3(7.7, 2.2, 0.4));
		float gord = smoothstep(0.7, 0.85, n2 * 0.7 + n3 * 0.3);
		ALBEDO = mix(carne, vec3(0.74, 0.66, 0.55), gord * 0.45);
		ROUGHNESS = 0.55;
	}
	// o corte da faca em volta da banda (entre as costelas, até a espinha)
	if (q_faca > 0.0 && FRONT_FACING && abs(u - corte_q) < q_w && (p.z - zb) / max(zt - zb, 1e-6) < q_faca) {
		ALBEDO = abs(u - corte_q) < q_w * 0.5 ? vec3(0.05, 0.0, 0.0) : vec3(0.62, 0.16, 0.12);
	}
	// caiu na terra: sujo de barro
	if (sujo > 0.5) {
		float t = ruido(q * 9.0 + vec3(1.3, 4.1, 2.2));
		float t2 = ruido(q * 31.0);
		ALBEDO = mix(ALBEDO, vec3(0.3, 0.22, 0.13), smoothstep(0.35, 0.6, t * 0.7 + t2 * 0.3) * 0.85);
		ROUGHNESS = 0.9;
	}
	SPECULAR = 0.25;
}
"""
static var _banda_sh: Shader
static var _carne_m: StandardMaterial3D
static var _costas: Array = []


static func _carne_mat() -> StandardMaterial3D:
	if _carne_m == null:
		_carne_m = StandardMaterial3D.new()
		_carne_m.albedo_color = Color(0.36, 0.05, 0.04)
		_carne_m.roughness = 0.55
	return _carne_m


## O perfil das costas (o alto da espinha, na linha do meio): [[y, z]].
static func _costas_z(mi: MeshInstance3D, y: float) -> float:
	if _costas.is_empty():
		var bins := {}
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in vs:
			if absf(v.x) > 0.0016:
				continue
			var b := int(round(v.y / 0.002))
			if not bins.has(b) or v.z > float(bins[b]):
				bins[b] = v.z
		var ks := bins.keys()
		ks.sort()
		ks.reverse()
		for b in ks:
			_costas.append([int(b) * 0.002, float(bins[b])])
	var best := 1e9
	var z := 0.035
	for e in _costas:
		var d := absf(float(e[0]) - y)
		if d < best:
			best = d
			z = float(e[1])
	return z


## A linha do machado pela espinha, no mundo (de cima, entre as patas, até o rabo).
func partir_linha(uid: String, n_pts := 20) -> Array:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return []
	var rf := _couro_ref(nd.node)
	var mi: MeshInstance3D = rf.mi
	var out := []
	for i in n_pts:
		var u := lerpf(0.9, 0.02, float(i) / (n_pts - 1))
		var y := lerpf(float(rf.y_rabo), float(rf.y_pescoco), u)
		out.append(mi.global_transform * Vector3(0, y, _costas_z(mi, y) + 0.0006))
	return out


## As duas patas da frente (onde cada ponta da corda amarra), no mundo: [direita, esquerda].
func patas_frente(uid: String) -> Array:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return []
	var out := []
	for k in 2:
		var n: Node3D = nd.node
		if k == 1 and nd.has("n2") and is_instance_valid(nd.n2):
			n = nd.n2
		if not n.has_meta("sk"):
			return []
		var sk: Skeleton3D = n.get_meta("sk")
		var sd: String = ["_R", "_L"][k]
		var a: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("FrontLowLeg" + sd)).origin
		var b: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("FrontFoot" + sd)).origin
		out.append(a.lerp(b, 0.75))
	return out


## O material de uma banda (lado +1: a esquerda; -1: a direita).
func _banda_mat(n: Node3D, c: Dictionary, lado: float, cab: bool) -> ShaderMaterial:
	if _banda_sh == null:
		_banda_sh = Shader.new()
		_banda_sh.code = BANDA_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _banda_sh
	var rf := _couro_ref(n)
	var mi: MeshInstance3D = rf.mi
	var m_por_u: float = mi.global_transform.basis.get_scale().x
	var p: Dictionary = c.get("p", {})
	var cores: Array = VacaModelo.CORES.get(str(p.get("cor", "branca")), VacaModelo.CORES.branca)
	var cp: Color = cores[0]
	sm.set_shader_parameter("y_rabo", rf.y_rabo)
	sm.set_shader_parameter("y_pescoco", rf.y_pescoco)
	sm.set_shader_parameter("lado", lado)
	sm.set_shader_parameter("com_cabeca", 1.0 if cab else 0.0)
	sm.set_shader_parameter("cor_pelo", Vector3(cp.r, cp.g, cp.b))
	sm.set_shader_parameter("esc", m_por_u)
	sm.set_shader_parameter("r_casco", 0.1 / m_por_u)
	for i in 4:
		sm.set_shader_parameter("casco%d" % i, rf.cascos[i])
	# o rabo: os ossos e a ponta (um pouco além do último)
	var rb: Array = rf.rabo
	for i in 5:
		sm.set_shader_parameter("rabo%d" % i, rb[i])
	sm.set_shader_parameter("rabo5", (rb[4] as Vector3) + ((rb[4] as Vector3) - (rb[3] as Vector3)) * 1.2)
	sm.set_shader_parameter("r_rabo", 0.075 / m_por_u)
	sm.set_shader_parameter("cab_p", rf.cab_p)
	sm.set_shader_parameter("cab_d", rf.cab_d)
	sm.set_shader_parameter("r_cab", 0.26 / m_por_u)
	sm.set_shader_parameter("com_rabo", 0.0 if cab else 1.0)     # o rabo vai com a banda sem a cabeça
	var pf := _perfil_pose(mi, n.get_meta("sk"), float(rf.y_rabo), float(rf.y_pescoco))
	sm.set_shader_parameter("zt_u", pf[0])
	sm.set_shader_parameter("zb_u", pf[1])
	var yq := lerpf(float(rf.y_rabo), float(rf.y_pescoco), QUARTO_U)
	sm.set_shader_parameter("corte_q", QUARTO_U)
	sm.set_shader_parameter("q_w", 0.022 / ((float(rf.y_rabo) - float(rf.y_pescoco)) * m_por_u))
	sm.set_shader_parameter("zb", _barriga_z(mi, yq))
	sm.set_shader_parameter("zt", _costas_z(mi, yq))
	sm.set_shader_parameter("q_faca", 0.0)
	sm.set_shader_parameter("q_parte", 0.0)
	sm.set_shader_parameter("sujo", 0.0)
	return sm


## Partida: monta as duas bandas (a carcaça vira uma, e um segundo desenho a outra).
func partir_monta(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return
	var c: Dictionary = nd.c
	var bd: Dictionary = c.get("banda", {})
	if not bool(bd.get("feito", false)):
		return
	var n: Node3D = nd.node
	if not n.has_meta("sk"):
		return
	var cab_e := str(bd.get("cab", "e")) == "e"
	var n2: Node3D = nd.get("n2", null)
	if n2 == null or not is_instance_valid(n2):
		var p: Dictionary = c.get("p", {})
		n2 = VacaModelo.build(float(p.get("s", 1.0)), str(p.get("cor", "branca")), bool(p.get("touro", false)), int(p.get("seed", 1)))
		add_child(n2)
		nd["n2"] = n2
	var mi2 := _malha(n2)
	if mi2 and not mi2.has_meta("sem_ubere"):
		mi2.mesh = VacaModelo.malha_sem_ubere(mi2.mesh)
		mi2.set_meta("sem_ubere", true)
		mi2.remove_meta("cab_marca")
	if mi2:
		malha_cab(mi2, n2.get_meta("sk"))
	var sk2: Skeleton3D = n2.get_meta("sk")
	_pose_pendurada(sk2)
	_cortes_escala(sk2, c)
	VacaModelo._cascos(sk2)
	n2.global_transform = n.global_transform
	# a carcaça é a banda esquerda (+x), o segundo desenho a direita
	(_malha(n) as MeshInstance3D).material_override = _banda_mat(n, c, 1.0, cab_e)
	(_malha(n2) as MeshInstance3D).material_override = _banda_mat(n2, c, -1.0, not cab_e)
	for par in [[n, cab_e], [n2, not cab_e]]:
		var nn: Node3D = par[0]
		for ba in nn.find_children("*", "BoneAttachment3D", true, false):
			if str((ba as BoneAttachment3D).bone_name) == "Head":
				(ba as Node3D).visible = bool(par[1])
			if str((ba as BoneAttachment3D).bone_name) == "Body":
				(ba as Node3D).visible = bool(par[1])     # o cupim e o resto ficam numa banda só
		for nm in ["saco", "prepucio"]:
			for ch in nn.find_children(nm, "MeshInstance3D", true, false):
				ch.queue_free()
	n.remove_meta("couro_mat")
	_partir_afasta(uid)
	for ld in ["e", "d"]:
		if (c.get("quartos", {}) as Dictionary).has(ld):
			quarto_visual(uid, ld)


## As bandas penduradas cada uma pela sua pata: um pouco afastadas para os lados.
func _partir_afasta(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not nd.has("n2") or not is_instance_valid(nd.n2):
		return
	var n: Node3D = nd.node
	var xf: Transform3D = n.get_meta("xf_inteira", n.global_transform)
	if not n.has_meta("xf_inteira"):
		n.set_meta("xf_inteira", xf)
	var lado: Vector3 = (_malha(n) as MeshInstance3D).global_transform.basis.x.normalized() if n.has_meta("sk") else Vector3.RIGHT
	lado.y = 0.0
	lado = lado.normalized() if lado.length() > 0.1 else Vector3.RIGHT
	# cada banda gira para fora em volta da sua pata (abre como um livro) e se afasta
	var rig: Dictionary = n.get_meta("rig", {})
	var piv: Vector3 = xf * (rig.get("pk", Vector3.ZERO) as Vector3)
	for k in 2:
		var sd := 1.0 if k == 0 else -1.0
		var giro := Transform3D(Basis(Vector3.UP, sd * 0.55), Vector3.ZERO)
		var t := Transform3D(Basis(), piv + lado * sd * 0.2) * giro * Transform3D(Basis(), -piv) * xf
		if k == 0:
			n.global_transform = t
		else:
			(nd.n2 as Node3D).global_transform = t


## Uma machadada na espinha: o corte desce um pedaço; no fim a vaca se parte.
func partir_golpe(uid: String, quanto: float) -> bool:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty():
		return false
	var c: Dictionary = nd.c
	if not c.has("banda"):
		c["banda"] = {"cab": "e", "corte": 0.0}
	var bd: Dictionary = c.banda
	var lin := partir_linha(uid, 20)
	var t := float(bd.get("corte", 0.0))
	if not lin.is_empty():
		var w: Vector3 = lin[mini(int(t * 19.0), 19)]
		_pinga(w)
		Sons.play_at(_jogo, "machado_osso", w, 0.0, _rng.randf_range(0.9, 1.1))
	bd.corte = minf(1.0, t + quanto)
	couro_visual(uid)
	if float(bd.corte) >= 1.0:
		bd["feito"] = true
		if not lin.is_empty():
			Sons.play_at(_jogo, "osso_quebra", lin[19], 3.0, 0.9)
		partir_monta(uid)
		return true
	return false


# ---------- abrir e tirar as vísceras (com a faca) ----------
# Esfolada, a vaca é aberta com a faca: o corte da barriga do pescoço até o úbere, o Y em
# volta do úbere (um corte de cada lado, até as pernas de trás) e o corte na garganta.
# Depois as vísceras são puxadas para baixo e saem todas (a buchada, o fígado, os bofes,
# o coração, as tripas e o úbere), caem no chão e ficam lá. A vaca fica com os pés e a
# cabeça. c.evis = {barriga, y_e, y_d, garganta, puxa} (0..1 cada); c.evis.feito = true.

## As linhas da faca no mundo: "barriga" (do pescoço até o úbere), "y_e"/"y_d" (do úbere
## até as pernas de trás, abrindo para o lado) e "garganta" (de um lado ao outro).
func evis_linha(uid: String, qual: String, n_pts := 24) -> Array:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return []
	var rf := _couro_ref(nd.node)
	var mi: MeshInstance3D = rf.mi
	var m_por_u: float = mi.global_transform.basis.get_scale().x
	var yr := float(rf.y_rabo)
	var yp := float(rf.y_pescoco)
	var y_u := func(u: float) -> float:
		return lerpf(yr, yp, u)
	var out := []
	match qual:
		"barriga":
			for i in n_pts:
				var u := lerpf(1.0, float(rf.u_ubere), float(i) / (n_pts - 1))
				var y: float = y_u.call(u)
				out.append(mi.global_transform * Vector3(0, y, _barriga_z(mi, y) - 0.0006))
		"y_e", "y_d":
			var sd := -1.0 if qual == "y_e" else 1.0
			for i in n_pts:
				var k := float(i) / (n_pts - 1)
				var u := lerpf(float(rf.u_ubere), float(rf.u_ini), k)
				var y: float = y_u.call(u)
				out.append(mi.global_transform * Vector3(sd * 0.13 / m_por_u * k, y, _barriga_z(mi, y) + 0.004 * k - 0.0008))
		"garganta":
			var y2: float = y_u.call(0.96)
			var z2 := _barriga_z(mi, y2)
			for i in n_pts:
				var a := lerpf(-1.1, 1.1, float(i) / (n_pts - 1))
				out.append(mi.global_transform * Vector3(sin(a) * 0.0042, y2, z2 + (1.0 - cos(a)) * 0.004 - 0.0006))
	return out


## O monte de vísceras (feito na hora, com volumes): a buchada (o rúmen, verde-acinzentado),
## as tripas rosadas em voltas, o fígado (vinho escuro), os bofes (rosa), o coração e,
## na vaca, o úbere. r: o tamanho (1 = adulta).
static func visceras_no(s: float, ubere: bool, seed_v: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var bola := func(cor: Color, raio: Vector3, pos: Vector3, rough := 0.35) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 16
		sm.rings = 10
		m.mesh = sm
		var mt := StandardMaterial3D.new()
		mt.albedo_color = cor
		mt.roughness = rough
		mt.metallic_specular = 0.3
		m.material_override = mt
		m.scale = raio * s
		m.position = pos * s
		root.add_child(m)
		return m
	# a buchada (rúmen) grande e o barrete
	bola.call(Color(0.26, 0.26, 0.2), Vector3(0.36, 0.3, 0.28), Vector3(0, 0, 0), 0.6)
	bola.call(Color(0.32, 0.3, 0.24), Vector3(0.2, 0.18, 0.17), Vector3(0.28, 0.12, 0.1), 0.6)
	bola.call(Color(0.24, 0.24, 0.19), Vector3(0.16, 0.15, 0.14), Vector3(-0.25, 0.16, -0.1), 0.6)
	# o fígado e os bofes, o coração
	bola.call(Color(0.28, 0.05, 0.05), Vector3(0.22, 0.07, 0.15), Vector3(0.12, 0.3, 0.12), 0.25)
	bola.call(Color(0.68, 0.3, 0.34), Vector3(0.18, 0.14, 0.12), Vector3(-0.15, 0.36, 0.05), 0.5)
	bola.call(Color(0.64, 0.28, 0.32), Vector3(0.16, 0.13, 0.11), Vector3(0.05, 0.4, -0.08), 0.5)
	bola.call(Color(0.42, 0.08, 0.07), Vector3(0.08, 0.1, 0.08), Vector3(-0.02, 0.32, 0.18), 0.3)
	# as tripas: tubos rosados dando voltas por fora da buchada
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var pts := []
		var r0 := 0.26 + k * 0.04
		var a0 := rng.randf() * TAU
		for i in 60:
			var a := a0 + float(i) / 59.0 * TAU * 1.6
			pts.append(Vector3(cos(a) * r0, -0.18 + sin(a * 3.0 + k) * 0.06 + k * 0.03, sin(a) * r0 * 0.8) * s)
		var lados := 6
		var rr := 0.035 * s
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var d := (p1 - p0).normalized()
			var ax := d.cross(Vector3.UP).normalized()
			var bx := d.cross(ax).normalized()
			for j in lados:
				var t0 := TAU * j / lados
				var t1 := TAU * (j + 1) / lados
				var q := [p0 + (ax * cos(t0) + bx * sin(t0)) * rr, p1 + (ax * cos(t0) + bx * sin(t0)) * rr,
					p1 + (ax * cos(t1) + bx * sin(t1)) * rr, p0 + (ax * cos(t1) + bx * sin(t1)) * rr]
				for jj in [0, 1, 2, 0, 2, 3]:
					st.add_vertex(q[jj])
	st.generate_normals()
	var tr := MeshInstance3D.new()
	tr.mesh = st.commit()
	var mtr := StandardMaterial3D.new()
	mtr.albedo_color = Color(0.7, 0.36, 0.36)
	mtr.roughness = 0.45
	mtr.metallic_specular = 0.35
	mtr.cull_mode = BaseMaterial3D.CULL_DISABLED
	tr.material_override = mtr
	root.add_child(tr)
	# o úbere (com as quatro tetas)
	if ubere:
		var ub: MeshInstance3D = bola.call(Color(0.72, 0.5, 0.48), Vector3(0.17, 0.11, 0.14), Vector3(0.05, -0.32, 0.2), 0.6)
		for i in 4:
			var tx := (-0.07 if i % 2 == 0 else 0.07)
			var tz := (0.14 if i < 2 else 0.26)
			bola.call(Color(0.7, 0.46, 0.46), Vector3(0.022, 0.05, 0.022), Vector3(0.05 + tx, -0.43, tz), 0.6)
	return root


## O centro da barriga por dentro, no mundo (onde as vísceras estão).
func evis_centro(uid: String) -> Vector3:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return Vector3.ZERO
	var rf := _couro_ref(nd.node)
	var mi: MeshInstance3D = rf.mi
	var y := lerpf(float(rf.y_rabo), float(rf.y_pescoco), 0.55)
	return mi.global_transform * Vector3(0, y, _barriga_z(mi, y) + 0.006)


## As vísceras saindo (k 0..1). Com a barriga aberta já saltam um pouco para fora do
## corte; puxando a garganta (a goela e a traqueia, cortadas lá em cima) para baixo, a
## ponta vem na mão e tudo sai junto pela barriga, descendo até os pés do jogador (alvo).
## Um tubo liga a garganta ao monte e outro, a membrana, liga o monte ao lado de dentro.
func evis_puxa(uid: String, k: float, alvo: Vector3) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return
	var n: Node3D = nd.node
	var c: Dictionary = nd.c
	var vn: Node3D = n.get_meta("visc") if n.has_meta("visc") and is_instance_valid(n.get_meta("visc")) else null
	var p: Dictionary = c.get("p", {})
	var s := float(p.get("s", 1.0))
	if vn == null:
		vn = visceras_no(s * 0.62, not bool(p.get("touro", false)), int(p.get("seed", 1)))
		add_child(vn)
		n.set_meta("visc", vn)
		var tb := MeshInstance3D.new()
		tb.name = "tubos"
		var mt := StandardMaterial3D.new()
		mt.albedo_color = Color(0.72, 0.42, 0.42)
		mt.roughness = 0.45
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		tb.material_override = mt
		add_child(tb)
		n.set_meta("tubos", tb)
	var tb2: MeshInstance3D = n.get_meta("tubos")
	var ev: Dictionary = c.get("evis", {})
	var fr := couro_frente(uid)
	var c0 := evis_centro(uid)
	var gl: Array = evis_linha(uid, "garganta", 9)
	var tg: Vector3 = gl[4] if gl.size() > 4 else c0 + Vector3.UP
	# saltando pela abertura (já aberta), saindo, descendo até os pés
	var salto := 0.07 * clampf(float(ev.get("barriga", 0.0)) * 1.5 - 0.3, 0.0, 1.0)
	var sai := smoothstep(0.1, 0.55, k)
	var desce := smoothstep(0.35, 1.0, k)
	var fora := c0 + fr * (lerpf(-0.1 * s, 0.3, sai) + salto)
	var chao := alvo + Vector3.UP * 0.3 * s
	var pos := fora.lerp(chao, desce)
	vn.global_position = pos
	vn.visible = salto > 0.0 or k > 0.0
	# a mão com a ponta da garganta: sai da garganta e desce junto, um pouco acima do monte
	var mao := tg.lerp(pos + Vector3.UP * 0.55 * s + fr * 0.12, smoothstep(0.0, 0.35, k)) if k > 0.0 else tg
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var topo := pos + Vector3.UP * 0.32 * s
	if float(ev.get("garganta", 0.0)) >= 1.0 or k > 0.0:
		_tubo_curvo(st, mao, topo, 0.028 * s, fr * 0.1)
		_tubo_curvo(st, mao + Vector3(0.05, 0, 0) * s, topo + Vector3(0.06, -0.05, 0) * s, 0.02 * s, fr * 0.06)
	if k > 0.0 and k < 0.97:
		_tubo_curvo(st, pos + Vector3.UP * 0.1 * s, c0 - fr * 0.05, lerpf(0.06, 0.01, k) * s, Vector3.DOWN * 0.1)
	st.generate_normals()
	tb2.mesh = st.commit()
	tb2.visible = vn.visible


## Um tubo de a até b, barrigudo para o lado de "curva" (as tripas da garganta).
static func _tubo_curvo(st: SurfaceTool, a: Vector3, b: Vector3, r: float, curva: Vector3) -> void:
	var pts := []
	for i in 13:
		var t := float(i) / 12.0
		pts.append(a.lerp(b, t) + curva * sin(t * PI))
	var lados := 7
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := (p1 - p0).normalized()
		if d.length() < 0.5:
			continue
		var ax := d.cross(Vector3(0.3, 0.9, 0.2).normalized()).normalized()
		var bx := d.cross(ax).normalized()
		for j in lados:
			var t0 := TAU * j / lados
			var t1 := TAU * (j + 1) / lados
			var q := [p0 + (ax * cos(t0) + bx * sin(t0)) * r, p1 + (ax * cos(t0) + bx * sin(t0)) * r,
				p1 + (ax * cos(t1) + bx * sin(t1)) * r, p0 + (ax * cos(t1) + bx * sin(t1)) * r]
			for jj in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[jj])


## Saíram todas: o monte cai no chão (e fica); o úbere sai da carcaça.
func evis_solta(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return
	var n: Node3D = nd.node
	var c: Dictionary = nd.c
	(c.evis as Dictionary)["feito"] = true
	_evis_aplica(n, c)
	var vn: Node3D = n.get_meta("visc") if n.has_meta("visc") else null
	n.remove_meta("visc")
	if n.has_meta("tubos"):
		var tb: Node = n.get_meta("tubos")
		if is_instance_valid(tb):
			tb.queue_free()
		n.remove_meta("tubos")
	if vn == null or not is_instance_valid(vn):
		return
	vn.set_meta("uid", uid)
	vn.set_meta("tipo", "buchada")
	_caindo.append({"node": vn, "vel": Vector3.DOWN * 0.8, "ang": Vector3(_rng.randf_range(-1, 1), 0.2, _rng.randf_range(-1, 1)).normalized() * 0.8,
		"uid": uid, "tipo": "buchada", "chao": 0.0, "r": 0.3})
	Sons.play_at(_jogo, "baque", vn.global_position, 4.0, 0.6)
	_fonte(n, evis_centro(uid), Vector3.DOWN, 14.0, 0.8)


## Aberta: a carcaça sem o úbere (e, no boi, sem o saco e o prepúcio).
func _evis_aplica(n: Node3D, c: Dictionary) -> void:
	if not bool((c.get("evis", {}) as Dictionary).get("feito", false)):
		return
	var mi := _malha(n)
	if mi == null or mi.has_meta("sem_ubere"):
		return
	var mats := []
	for k in mi.mesh.get_surface_count():
		mats.append(mi.get_surface_override_material(k))
	mi.mesh = VacaModelo.malha_sem_ubere(mi.mesh)
	mi.remove_meta("cab_marca")
	for k in mini(mats.size(), mi.mesh.get_surface_count()):
		mi.set_surface_override_material(k, mats[k])
	mi.set_meta("sem_ubere", true)
	malha_cab(mi, n.get_meta("sk"))
	for nm in ["saco", "prepucio"]:
		for ch in n.find_children(nm, "MeshInstance3D", true, false):
			ch.queue_free()


# ---------- patas e cabeça (com o machado) ----------
# Pendurada, as canelas (do jarrete/joelho para baixo, com o casco) e a cabeça saem a
# machadadas. A parte cortada vira um pedaço separado (a mesma malha da vaca, só daquela
# parte, na pose de pendurada) que cai, quica e fica no chão; na carcaça fica o toco
# (carne vermelha com o osso branco no meio). c.cortes = [tipo...]; c.partes = [{tipo, xf}].

## A tampa do corte de uma parte solta (pata, cabeça): por dentro da casca, visto pela
## abertura, pinta a face do corte (carne com o osso no meio) em vez do vazio.
const TAMPA_SHADER := """
shader_type spatial;
render_mode cull_front, diffuse_burley, specular_schlick_ggx;
uniform vec3 pc;
uniform vec3 dn;
uniform float r_osso;
uniform float esc;
uniform float sujo;
varying vec3 p;
varying vec3 cam_l;
void vertex() {
	p = VERTEX;
	cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	vec3 d = p - cam_l;
	float fc = dot(dn, cam_l - pc);
	float den = dot(dn, d);
	float t = (fc < 0.0 && den > 1e-9) ? -fc / den : -1.0;
	vec3 P = cam_l + d * max(t, 0.0);
	vec3 qc = P * esc;
	float c1 = ruido(qc * 11.0);
	vec3 cor = mix(vec3(0.34, 0.03, 0.025), vec3(0.52, 0.07, 0.05), c1);
	float ro = distance(P, pc);
	if (t > 0.0 && t < 1.0) {
		cor = mix(cor, vec3(0.9, 0.85, 0.76), 1.0 - smoothstep(r_osso * 0.85, r_osso, ro));
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(-dn, 0.0))).xyz);
	}
	if (sujo > 0.5) {
		float tt = ruido(qc * 9.0 + vec3(1.3, 4.1, 2.2));
		cor = mix(cor, vec3(0.3, 0.22, 0.13), smoothstep(0.35, 0.6, tt) * 0.8);
	}
	ALBEDO = cor;
	ROUGHNESS = 0.45;
	SPECULAR = 0.25;
}
"""
static var _tampa_sh: Shader = null


## Uma cópia da malha só com a tampa do corte (o lado de dentro visto pela abertura).
static func tampa_no(mesh: Mesh, pc: Vector3, dn: Vector3, r_osso: float, esc: float) -> MeshInstance3D:
	if _tampa_sh == null:
		_tampa_sh = Shader.new()
		_tampa_sh.code = TAMPA_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _tampa_sh
	sm.set_shader_parameter("pc", pc)
	sm.set_shader_parameter("dn", dn.normalized())
	sm.set_shader_parameter("r_osso", r_osso)
	sm.set_shader_parameter("esc", esc)
	var t := MeshInstance3D.new()
	t.name = "tampa"
	t.mesh = mesh
	t.material_override = sm
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return t


const PARTES := {
	"pe_td": {"ossos": ["BackLowLeg_R", "BackFoot_R"], "de": "BackLowLeg_R", "ate": "BackFoot_R", "golpes": 3, "r": 0.05},
	"pe_te": {"ossos": ["BackLowLeg_L", "BackFoot_L"], "de": "BackLowLeg_L", "ate": "BackFoot_L", "golpes": 3, "r": 0.05},
	"pe_fd": {"ossos": ["FrontLowLeg_R", "FrontFoot_R"], "de": "FrontLowLeg_R", "ate": "FrontFoot_R", "golpes": 3, "r": 0.045},
	"pe_fe": {"ossos": ["FrontLowLeg_L", "FrontFoot_L"], "de": "FrontLowLeg_L", "ate": "FrontFoot_L", "golpes": 3, "r": 0.045},
	"cabeca": {"ossos": ["Head"], "de": "Head", "ate": "", "golpes": 7, "r": 0.1},
}
static var _partes_cache := {}
var _caindo: Array = []            # pedaços caindo: {node, vel, ang, uid, tipo, chao}


## Os ossos cortados ficam do tamanho de nada (a parte some da carcaça).
static func _cortes_escala(sk: Skeleton3D, c: Dictionary) -> void:
	for t in c.get("cortes", []):
		if PARTES.has(str(t)):
			var bi := sk.find_bone(str(PARTES[str(t)].de))
			if bi >= 0:
				sk.set_bone_pose_scale(bi, Vector3.ONE * 0.001)


## Onde corta (na malha) e para onde a parte sai: [ponto, direção].
static func _corte_ref(sk: Skeleton3D, tipo: String) -> Array:
	var pt: Dictionary = PARTES[tipo]
	var a: Vector3 = sk.get_bone_global_pose(sk.find_bone(str(pt.de))).origin
	var b: Vector3
	if str(pt.ate) != "":
		b = sk.get_bone_global_pose(sk.find_bone(str(pt.ate))).origin
	else:
		b = a + (a - sk.get_bone_global_pose(sk.find_bone("Neck")).origin)
	return [a, (b - a).normalized()]


## A malha da parte (na pose de pendurada, nas medidas de dentro da malha), feita uma vez.
func parte_malha(c: Dictionary, tipo: String) -> Dictionary:
	var p: Dictionary = c.get("p", {})
	var key := "%s_%s_%s_%d" % [tipo, str(p.get("cor", "branca")), str(p.get("touro", false)), int(p.get("seed", 1))]
	if _partes_cache.has(key):
		return _partes_cache[key]
	var tmp: Node3D = VacaModelo.build(1.0, str(p.get("cor", "branca")), bool(p.get("touro", false)), int(p.get("seed", 1)))
	if not tmp.has_meta("sk"):
		tmp.free()
		return {}
	var sk: Skeleton3D = tmp.get_meta("sk")
	_pose_pendurada(sk)
	VacaModelo._cascos(sk)
	var mi := _malha(tmp)
	var skin: Skin = mi.skin
	var ossos: Array = PARTES[tipo].ossos
	var mats := []
	var guarda := {}
	if skin == null:
		tmp.free()
		return {}
	for b in skin.get_bind_count():
		var bi := skin.get_bind_bone(b)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(b))
		mats.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(b))
		if bi >= 0 and sk.get_bone_name(bi) in ossos:
			guarda[b] = true
	var am := ArrayMesh.new()
	var idx := []
	var soma := Vector3.ZERO
	var nv := 0
	for k in mi.mesh.get_surface_count():
		var a: Array = mi.mesh.surface_get_arrays(k)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var bo: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var nb := bo.size() / maxi(vs.size(), 1)
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var dom := PackedByteArray()
		pv.resize(vs.size())
		pn.resize(vs.size())
		dom.resize(vs.size())
		for i in vs.size():
			var v := Vector3.ZERO
			var nn := Vector3.ZERO
			var wmax := -1.0
			var bmax := 0
			for j in nb:
				var w := we[i * nb + j]
				if w <= 0.0:
					continue
				var bb := bo[i * nb + j]
				var m: Transform3D = mats[bb]
				v += (m * vs[i]) * w
				nn += (m.basis * ns[i]) * w
				if w > wmax:
					wmax = w
					bmax = bb
			pv[i] = v
			pn[i] = nn.normalized()
			dom[i] = 1 if guarda.has(bmax) else 0
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			for i in vs.size():
				ix.append(i)
		var ov := PackedVector3Array()
		var on := PackedVector3Array()
		for t in range(0, ix.size() - 2, 3):
			if int(dom[ix[t]]) + int(dom[ix[t + 1]]) + int(dom[ix[t + 2]]) < 2:
				continue
			for q in 3:
				ov.append(pv[ix[t + q]])
				on.append(pn[ix[t + q]])
				soma += pv[ix[t + q]]
				nv += 1
		if ov.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = ov
		arr[Mesh.ARRAY_NORMAL] = on
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		idx.append(k)
	# os chifres presos na cabeça
	var extras := []
	for ba in sk.find_children("*", "BoneAttachment3D", false, false):
		if str((ba as BoneAttachment3D).bone_name) in ossos:
			var bg := sk.get_bone_global_pose(sk.find_bone(str((ba as BoneAttachment3D).bone_name)))
			for ch in ba.get_children():
				if ch is MeshInstance3D:
					extras.append([(ch as MeshInstance3D).mesh, bg * (ch as MeshInstance3D).transform, (ch as MeshInstance3D).material_override])
	var ref := _corte_ref(sk, tipo)
	var out := {"mesh": am, "idx": idx, "extras": extras, "centro": soma / maxf(nv, 1), "corte": ref[0], "dir": ref[1]}
	tmp.free()
	_partes_cache[key] = out
	return out


## O toco: carne vermelha com o osso branco no meio (um disco), virado para dir.
static func _toco(r: float, cor_osso := Color(0.92, 0.88, 0.8)) -> Node3D:
	var root := Node3D.new()
	if true:
		return root                          # (sem a tampa redonda: o corte fica só a carne)
	var carne := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = r * 0.12
	cm.radial_segments = 14
	carne.mesh = cm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.45, 0.04, 0.035)
	mc.roughness = 0.3
	carne.material_override = mc
	root.add_child(carne)
	var osso := MeshInstance3D.new()
	var om := CylinderMesh.new()
	om.top_radius = r * 0.38
	om.bottom_radius = r * 0.38
	om.height = r * 0.2
	om.radial_segments = 10
	osso.mesh = om
	var mo := StandardMaterial3D.new()
	mo.albedo_color = cor_osso
	mo.roughness = 0.6
	osso.material_override = mo
	root.add_child(osso)
	return root


## Base com o eixo y apontando para d.
static func _base_para(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	return Basis(x, y, x.cross(y))


## Os tocos na carcaça (onde já cortou).
func _tocos(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return
	var n: Node3D = nd.node
	var mi := _malha(n)
	if mi == null:
		return
	for ch in mi.get_children():
		if ch.has_meta("toco"):
			ch.queue_free()
	var m_por_u: float = mi.global_transform.basis.get_scale().x
	for t in nd.c.get("cortes", []):
		var pm := parte_malha(nd.c, str(t))
		if pm.is_empty():
			continue
		var tc := _toco(float(PARTES[str(t)].r) / m_por_u)
		tc.set_meta("toco", true)
		mi.add_child(tc)
		tc.transform = Transform3D(_base_para(pm.dir), pm.corte)


## Põe a parte cortada no mundo (caindo, ou já parada com o xf salvo).
func _parte_no(uid: String, tipo: String, xf_salvo := [], base: MeshInstance3D = null) -> Node3D:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return null
	var n: Node3D = nd.node
	var mi := _malha(n) if base == null else base
	var pm := parte_malha(nd.c, tipo)
	if pm.is_empty() or mi == null:
		return null
	var m_por_u: float = mi.global_transform.basis.get_scale().x
	var mxf: Transform3D = mi.global_transform
	var wc: Vector3 = mxf * (pm.centro as Vector3)
	var par := Node3D.new()
	par.name = "parte_" + tipo
	add_child(par)
	par.global_transform = Transform3D(Basis(), wc)
	var rel := Transform3D(mxf.basis, mxf.origin - wc)
	var pmi := MeshInstance3D.new()
	pmi.mesh = pm.mesh
	for i in (pm.idx as Array).size():
		var mat := mi.get_surface_override_material(int(pm.idx[i]))
		if mat:
			pmi.set_surface_override_material(i, mat)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	par.add_child(pmi)
	pmi.transform = rel
	for e in pm.extras:
		var em := MeshInstance3D.new()
		em.mesh = e[0]
		em.material_override = e[2]
		par.add_child(em)
		em.transform = rel * (e[1] as Transform3D)
	var tp := tampa_no(pm.mesh, pm.corte, pm.dir, float(PARTES[tipo].r) * 0.4 / m_por_u, m_por_u)
	par.add_child(tp)
	tp.transform = rel
	par.set_meta("uid", uid)
	par.set_meta("tipo", tipo)
	if xf_salvo.size() >= 12:
		par.global_transform = _xf_de(xf_salvo)
	return par


## As partes já cortadas que ficaram no chão (ao montar a carcaça).
func _partes_monta(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty():
		return
	for ch in get_children():
		if ch.has_meta("tipo") and str(ch.get_meta("uid", "")) == uid:
			ch.queue_free()
	for e in nd.c.get("partes", []):
		if str(e.tipo).begins_with("quarto_"):
			continue                             # (montados depois das bandas)
		if str(e.tipo) == "buchada":
			var p: Dictionary = nd.c.get("p", {})
			var vn := visceras_no(float(p.get("s", 1.0)) * 0.62, not bool(p.get("touro", false)), int(p.get("seed", 1)))
			vn.set_meta("uid", uid)
			vn.set_meta("tipo", "buchada")
			add_child(vn)
			vn.global_transform = _xf_de(e.xf)
		else:
			_parte_no(uid, str(e.tipo), e.xf)
	_tocos(uid)
	if is_instance_valid(nd.node):
		_evis_aplica(nd.node, nd.c)
	partir_monta(uid)
	_pecas_monta(uid)


## Onde a parte vai ser cortada, no mundo (para o machado mirar).
func parte_ponto(uid: String, tipo: String) -> Vector3:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return Vector3.ZERO
	var mi := _malha(nd.node)
	var pm := parte_malha(nd.c, tipo)
	if pm.is_empty() or mi == null:
		return Vector3.ZERO
	return mi.global_transform * (pm.corte as Vector3)


## A machadada na parte: o sangue espirra; devolve true se ela soltou (caiu).
func machadada(uid: String, tipo: String, golpe: int) -> bool:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node) or not PARTES.has(tipo):
		return false
	var c: Dictionary = nd.c
	var w := parte_ponto(uid, tipo)
	_pinga(w)
	if _rng.randf() < 0.6:
		_respingo(Vector3(w.x + _rng.randf_range(-0.3, 0.3), 0, w.z + _rng.randf_range(-0.3, 0.3)), _rng.randf_range(0.06, 0.14), "gota")
	if golpe < int(PARTES[tipo].golpes):
		Sons.play_at(_jogo, "machado_osso", w, 0.0, _rng.randf_range(0.92, 1.08))
		return false
	Sons.play_at(_jogo, "osso_quebra", w, 2.0, _rng.randf_range(0.95, 1.05))
	if not c.has("cortes"):
		c["cortes"] = []
	if tipo in c.cortes:
		return false
	var par := _parte_no(uid, tipo)
	(c.cortes as Array).append(tipo)
	var n: Node3D = nd.node
	var sk: Skeleton3D = n.get_meta("sk")
	_cortes_escala(sk, c)
	VacaModelo._cascos(sk)
	_tocos(uid)
	if par:
		var fora := par.global_position - n.global_position
		fora.y = 0.0
		fora = fora.normalized() if fora.length() > 0.01 else Vector3.RIGHT
		_caindo.append({"node": par, "vel": fora * _rng.randf_range(0.3, 0.9) + Vector3.UP * _rng.randf_range(0.0, 0.6),
			"ang": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(3.0, 7.0),
			"uid": uid, "tipo": tipo, "chao": 0.0, "r": float(PARTES[tipo].r)})
		# o toco e a parte pingando um pouco
		_fonte(par, par.global_position, Vector3.DOWN, 6.0, 0.5)
		_fonte(n, w, Vector3.DOWN, 10.0, 0.6)
	return true


## As partes caindo: gravidade, girando; no chão quicam, rolam um pouco e param.
func _caindo_tick(delta: float) -> void:
	for f in _caindo.duplicate():
		var nd: Node3D = f.node
		if not is_instance_valid(nd):
			_caindo.erase(f)
			continue
		var vel: Vector3 = f.vel
		vel.y -= G * delta
		var ang: Vector3 = f.ang
		var p := nd.global_position + vel * delta
		var b := nd.global_transform.basis
		if ang.length() > 0.001:
			b = Basis(ang.normalized(), ang.length() * delta) * b
		nd.global_transform = Transform3D(b.orthonormalized(), p)
		# o ponto mais baixo (os cantos da caixa da malha)
		var low := 1e9
		var lowp := p
		if f.has("low"):
			for lp in f.low:
				var wpt0: Vector3 = nd.global_transform * (lp as Vector3)
				if wpt0.y < low:
					low = wpt0.y
					lowp = wpt0
		else:
			for ch in nd.find_children("*", "MeshInstance3D", true, false):
				if (ch as MeshInstance3D).mesh:
					var bx: AABB = (ch as MeshInstance3D).get_aabb()
					for i in 8:
						var wpt: Vector3 = (ch as MeshInstance3D).global_transform * bx.get_endpoint(i)
						if wpt.y < low:
							low = wpt.y
							lowp = wpt
		var gy: float = _jogo.ground_at(lowp.x, lowp.z)
		# a peça de carne: o que segura cada ponto é o fundo da caixa do carrinho (se está em
		# cima dela) ou o chão; encostou no carrinho: fica lá
		var no_car := -1
		if str(f.tipo) == "peca" and f.has("low"):
			low = 1e9
			for lp in f.low:
				var w: Vector3 = nd.global_transform * (lp as Vector3)
				var apoio: float = _jogo.ground_at(w.x, w.z)
				var ci: int = _jogo._car_debaixo(w)
				if ci >= 0:
					apoio = maxf(apoio, float(_jogo._car_fundo_y(ci)))
				if w.y - apoio < low:
					low = w.y - apoio
					lowp = w
					gy = w.y - low
					no_car = ci
			low = lowp.y
		if low < gy:
			nd.global_position.y += gy - low
			if vel.y < -1.2:
				Sons.play_at(_jogo, "baque", lowp, -10.0 + minf(-vel.y, 5.0), 1.3 if str(f.tipo) != "cabeca" else 0.85)
				_respingo(Vector3(lowp.x, 0, lowp.z), _rng.randf_range(0.08, 0.16), "gota")
			if str(f.tipo) == "peca" and no_car >= 0:
				f["car"] = no_car                     # caiu dentro do carrinho: limpa
			elif str(f.tipo) == "peca" and not bool(f.get("sujou", false)) and not f.has("car"):
				if _jogo._maq and _jogo._maq.no_forro(lowp):
					pass                              # caiu no forro de folhas: limpa
				else:
					f["sujou"] = true
					quarto_sujar(nd)                  # caiu na terra: sujou
					var pcs := peca_de(str(f.uid), int(f.peca))
					if not pcs.is_empty():
						pcs["sujo"] = true
			vel.y = -vel.y * 0.22 if vel.y < -0.6 else 0.0
			vel.x *= 0.55
			vel.z *= 0.55
			ang *= 0.5
			f.chao = float(f.chao) + delta
		f.vel = vel
		f.ang = ang
		if float(f.chao) > 0.5 and vel.length() < 0.25 and ang.length() < 0.6:
			_caindo.erase(f)
			if str(f.tipo) == "peca":
				var pcp := peca_de(str(f.uid), int(f.peca))
				if not pcp.is_empty():
					if f.has("car") and _jogo._car_debaixo(nd.global_transform * (nd.get_meta("centro") as Vector3) + Vector3.DOWN * 0.1) >= 0:
						var hx: Transform3D = _jogo._peca_host_xf(int(f.car))
						pcp.onde = "carrinho"
						pcp["maq"] = int(f.car)
						pcp["rel"] = _xf_json(hx.affine_inverse() * nd.global_transform)
						pcp.erase("xf")
					else:
						pcp.onde = "chao"
						pcp["xf"] = _xf_json(nd.global_transform)
				continue
			var cc: Dictionary = _nodes.get(str(f.uid), {}).get("c", {})
			if not cc.is_empty():
				if not cc.has("partes"):
					cc["partes"] = []
				var e := {"tipo": str(f.tipo), "xf": _xf_json(nd.global_transform)}
				if str(f.tipo).begins_with("quarto_"):
					e["sujo"] = not bool(f.get("limpo", false))
				(cc.partes as Array).append(e)


# ---------- o couro ----------
# Pendurada, o couro sai com a faca: primeiro o corte pela barriga (dos pés de trás até o
# pescoço), depois vai sendo puxado de cima para baixo. O desenho: por cima do pelo, uma
# segunda passada que pinta o corte (vermelho fino) e a carne onde o couro já saiu
# (vermelha com gordura branca, molhada), deixando os cascos e a cabeça.
# c.couro = {corte: 0..1, pele: 0..1}; c.esfolada quando sai todo.

const COURO_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float y_rabo;
uniform float y_pescoco;
uniform float corte_ini;
uniform float corte;
uniform float pele;
uniform float largura;
uniform float infla;
uniform float esc;
uniform vec3 casco0;
uniform vec3 casco1;
uniform vec3 casco2;
uniform vec3 casco3;
uniform float r_casco;
uniform vec3 cab_p;
uniform vec3 cab_d;
uniform float r_cab;
uniform float ab_y;
uniform float ab;
uniform float y_e;
uniform float y_d;
uniform float y_off;
uniform float garg;
uniform float aberto;
uniform float u_ini2;
uniform float abre_w;
uniform float parte_u;
varying vec3 p;
varying vec3 nn;
varying float wcab;
void vertex() {
	p = VERTEX;
	nn = NORMAL;
	wcab = UV2.x;
	VERTEX += NORMAL * infla;
}
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	// por dentro (o buraco do úbere, os cortes): a carne escura, nunca o outro lado do mundo
	if (!FRONT_FACING) {
		ALBEDO = vec3(0.22, 0.025, 0.02);
		ROUGHNESS = 0.55;
		SPECULAR = 0.2;
	} else {
		float u = (y_rabo - p.y) / (y_rabo - y_pescoco);
		float dc = min(min(distance(p, casco0), distance(p, casco1)), min(distance(p, casco2), distance(p, casco3)));
		if (dc < r_casco || wcab > 0.5) { discard; }   // a cabeça e os cascos ficam com o couro
		vec3 q = p * esc;
		// a vaca aberta: o corte da barriga (do pescoço até o úbere), o Y em volta do úbere
		// (um de cada lado até as pernas de trás) e a garganta; abrindo, vira um rasgo escuro
		float wa = largura * 1.5 * (1.0 + aberto * 2.2);
		bool rasgo = false;
		if (nn.z < -0.35) {
			if (u <= 1.0 && u >= max(ab, ab_y) && abs(p.x) < wa) { rasgo = true; }
			if (u < ab_y && u >= u_ini2) {
				float k = (ab_y - u) / max(ab_y - u_ini2, 0.0001);
				float off = y_off * k;
				if (abs(p.x - off) < wa && k <= y_d) { rasgo = true; }
				if (abs(p.x + off) < wa && k <= y_e) { rasgo = true; }
			}
		}
		if (garg > 0.5 && u > 0.93 && u < 0.99 && nn.z < 0.2) { rasgo = true; }
		// aberta: o interior (a cavidade vermelho-escura, as costelas brancas no peito)
		bool dentro = false;
		vec3 cav = vec3(0.0);
		if (aberto > 0.0 && u > ab_y && u < 1.0 && nn.z < 0.15) {
			float tt = (u - ab_y) / (1.0 - ab_y);
			float wo = wa + abre_w * aberto * sin(3.14159 * clamp(tt, 0.0, 1.0));
			if (abs(p.x) < wo) {
				float fundo = 1.0 - abs(p.x) / max(wo, 0.0001);
				cav = mix(vec3(0.34, 0.05, 0.04), vec3(0.12, 0.015, 0.012), fundo * 0.8);
				if (tt > 0.45) {
					// as costelas por dentro: curvas (sobem para a espinha), largura variando,
					// a carne entre elas e a pleura (a película) por cima
					float s3 = (q.y - abs(p.x) * esc * 0.55) / 0.075;
					float r = fract(s3);
					float lar = 0.2 + 0.06 * sin(floor(s3) * 2.7);
					float c2 = (1.0 - smoothstep(lar, lar + 0.07, abs(r - 0.5))) * smoothstep(0.45, 0.55, tt);
					vec3 osso = mix(vec3(0.84, 0.76, 0.7), vec3(0.93, 0.87, 0.8), ruido(q * 40.0));
					cav = mix(cav, osso, c2 * 0.9);
					cav = mix(cav, vec3(0.7, 0.45, 0.45), 0.12 * (1.0 - fundo));
				}
				float beira = smoothstep(0.75, 1.0, 1.0 - fundo);
				cav = mix(cav, vec3(0.6, 0.12, 0.09), beira * 0.6);
				dentro = true;
			}
		}
		// partindo ao meio: o corte do machado pela espinha (de cima para baixo), o osso no meio
		if (!dentro && u <= 0.9 && u >= parte_u && nn.z > 0.15 && abs(p.x) < wa * 1.3) {
			dentro = true;
			cav = abs(p.x) < wa * 0.45 ? vec3(0.86, 0.8, 0.72) : vec3(0.3, 0.02, 0.02);
		}
		if (dentro) {
			ALBEDO = cav;
			ROUGHNESS = 0.4;
			SPECULAR = 0.35;
		} else if (rasgo) {
			ALBEDO = mix(vec3(0.3, 0.012, 0.012), vec3(0.16, 0.015, 0.012), aberto);
			ROUGHNESS = 0.25;
			SPECULAR = 0.5;
		} else if (u > pele) {
			float n1 = ruido(q * 11.0);
			float n2 = ruido(q * 34.0 + vec3(3.1, 1.7, 5.3));
			float n3 = ruido(q * 70.0 + vec3(7.7, 2.2, 0.4));
			float fio = abs(sin((q.y * 90.0 + n1 * 4.0)));
			vec3 carne = mix(vec3(0.22, 0.02, 0.018), vec3(0.4, 0.045, 0.035), n1 * 0.6 + fio * 0.25 + n3 * 0.15);
			float gord = smoothstep(0.66, 0.8, n2 * 0.7 + n3 * 0.3);
			vec3 col = mix(carne, vec3(0.74, 0.66, 0.55), gord * 0.5);
			float borda = smoothstep(pele + 0.05, pele, u);
			col = mix(col, vec3(0.82, 0.74, 0.7), borda * 0.7);
			ALBEDO = col;
			ROUGHNESS = 0.55;
			SPECULAR = 0.25;
		} else if (u >= corte_ini && u >= corte && nn.z < -0.55 && abs(p.x) < largura) {
			ALBEDO = vec3(0.4, 0.02, 0.02);
			ROUGHNESS = 0.25;
			SPECULAR = 0.5;
		} else {
			discard;
		}
	}
}
"""
static var _couro_sh: Shader
static var _barriga: Array = []       # [[y, z]] a barriga por baixo (na malha, em pé)


## A malha com a marca da cabeça (UV2.x = quanto o osso da cabeça puxa aquele ponto):
## o couro da cabeça fica nela (nunca é tirado), certinho na pele da cabeça.
static var _cab_cache := {}

static func malha_cab(mi: MeshInstance3D, sk: Skeleton3D) -> void:
	if mi == null or sk == null or mi.skin == null or mi.has_meta("cab_marca"):
		return
	var src: Mesh = mi.mesh
	var mats := []
	for k in src.get_surface_count():
		mats.append(mi.get_surface_override_material(k))
	var out: ArrayMesh
	if _cab_cache.has(src):
		out = _cab_cache[src]
	else:
		var hb := sk.find_bone("Head")
		var eh := {}
		for b in mi.skin.get_bind_count():
			var bi := mi.skin.get_bind_bone(b)
			if bi < 0:
				bi = sk.find_bone(mi.skin.get_bind_name(b))
			if bi == hb:
				eh[b] = true
		out = ArrayMesh.new()
		for si in src.get_surface_count():
			var arr: Array = src.surface_get_arrays(si)
			var flags: int = src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bo = arr[Mesh.ARRAY_BONES]
			var we = arr[Mesh.ARRAY_WEIGHTS]
			var uv2 := PackedVector2Array()
			uv2.resize(vs.size())
			if bo != null and we != null and vs.size() > 0:
				var nb: int = (bo as PackedInt32Array).size() / vs.size()
				for i in vs.size():
					var w := 0.0
					for j in nb:
						if eh.has((bo as PackedInt32Array)[i * nb + j]):
							w += (we as PackedFloat32Array)[i * nb + j]
					uv2[i] = Vector2(w, 0.0)
			arr[Mesh.ARRAY_TEX_UV2] = uv2
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
			out.surface_set_material(si, src.surface_get_material(si))
		_cab_cache[src] = out
	mi.mesh = out
	for k in mini(mats.size(), out.get_surface_count()):
		if mats[k] != null:
			mi.set_surface_override_material(k, mats[k])
	mi.set_meta("cab_marca", true)


## As costas e a barriga na linha do meio (z), na pose de agora, de u = -0.25 até 1
## (24 pontos): [zt, zb]. É por elas que os ossos do meio são desenhados no lugar certo.
static var _pf_cache := {}

## Interpola a altura no u (entre os pontos vizinhos; o mais alto/baixo perto dele).
static func _interp_u(l: Array, u: float, topo: bool) -> float:
	if l.is_empty():
		return 0.0
	var best := -1e9 if topo else 1e9
	for q in l:
		var v: Vector2 = q
		if absf(v.x - u) < 0.03:
			best = maxf(best, v.y) if topo else minf(best, v.y)
	if absf(best) < 1e8:
		return best
	var a: Vector2 = l[0]
	var b: Vector2 = l[l.size() - 1]
	for q in l:
		var v: Vector2 = q
		if v.x <= u:
			a = v
		elif v.x > u:
			b = v
			break
	if absf(b.x - a.x) < 1e-6:
		return a.y
	return lerpf(a.y, b.y, clampf((u - a.x) / (b.x - a.x), 0.0, 1.0))


static func _perfil_pose(mi: MeshInstance3D, sk: Skeleton3D, y_rabo: float, y_pes: float) -> Array:
	var key := str(mi.mesh.get_instance_id()) + ":" + str(snappedf(y_rabo, 0.0001)) + ":" + str(snappedf(y_pes, 0.0001))
	if _pf_cache.has(key):
		return _pf_cache[key]
	var zt := PackedFloat32Array()
	var zb := PackedFloat32Array()
	zt.resize(24)
	zb.resize(24)
	for i in 24:
		zt[i] = -1e9
		zb[i] = 1e9
	var skin: Skin = mi.skin
	if skin == null or sk == null:
		return [zt, zb]
	var mats := []
	for b in skin.get_bind_count():
		var bi := skin.get_bind_bone(b)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(b))
		mats.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(b))
	var pts := []
	for si in mini(2, mi.mesh.get_surface_count()):
		var a: Array = mi.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var nb := bo.size() / maxi(vs.size(), 1)
		var pv := PackedVector3Array()
		pv.resize(vs.size())
		for i in vs.size():
			var v := Vector3.ZERO
			for j in nb:
				var w := we[i * nb + j]
				if w > 0.0:
					v += ((mats[bo[i * nb + j]] as Transform3D) * vs[i]) * w
			pv[i] = v
		# onde cada triângulo atravessa o meio (x = 0): o contorno do corpo no corte da espinha
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for t in range(0, ix.size() - 2, 3):
			for e in [[0, 1], [1, 2], [2, 0]]:
				var p0: Vector3 = pv[ix[t + int(e[0])]]
				var p1: Vector3 = pv[ix[t + int(e[1])]]
				if (p0.x < 0.0) == (p1.x < 0.0):
					continue
				var f := p0.x / (p0.x - p1.x)
				pts.append(p0.lerp(p1, f))
	# o de cima (costas) e o de baixo (barriga), cada um ligado ponto a ponto ao longo do corpo
	var zm := 0.0
	for q in pts:
		zm += (q as Vector3).z
	zm /= maxf(pts.size(), 1.0)
	var cima := []
	var baixo := []
	for q in pts:
		var v2: Vector3 = q
		var u := (y_rabo - v2.y) / (y_rabo - y_pes)
		if v2.z >= zm:
			cima.append(Vector2(u, v2.z))
		else:
			baixo.append(Vector2(u, v2.z))
	var srt := func(a2: Vector2, b2: Vector2) -> bool: return a2.x < b2.x
	cima.sort_custom(srt)
	baixo.sort_custom(srt)
	for k in 24:
		var uk := lerpf(-0.25, 1.0, float(k) / 23.0)
		zt[k] = _interp_u(cima, uk, true)
		zb[k] = _interp_u(baixo, uk, false)
	_pf_cache[key] = [zt, zb]
	return [zt, zb]


## A malha da vaca dentro do nó.
static func _malha(n: Node3D) -> MeshInstance3D:
	var l := n.find_children("*", "MeshInstance3D", true, false)
	return l[0] if not l.is_empty() else null


## O perfil da barriga (de cima, na linha do meio), uma vez: [[y, z]] de trás para a frente.
static func _perfil(mi: MeshInstance3D) -> Array:
	if not _barriga.is_empty():
		return _barriga
	var bins := {}
	for k in mini(2, mi.mesh.get_surface_count()):
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
		for v in vs:
			if absf(v.x) > 0.0016 or v.z < 0.012:
				continue
			var b := int(round(v.y / 0.002))
			if not bins.has(b) or v.z < float(bins[b]):
				bins[b] = v.z
	var ks := bins.keys()
	ks.sort()
	ks.reverse()
	var bruto := []
	for b in ks:
		bruto.append([int(b) * 0.002, float(bins[b])])
	# alisa (média de 5 vizinhos): a linha do corte não pode dar saltos
	for i in bruto.size():
		var soma := 0.0
		var n := 0
		for j in range(maxi(0, i - 2), mini(bruto.size(), i + 3)):
			soma += float(bruto[j][1])
			n += 1
		_barriga.append([bruto[i][0], soma / n])
	return _barriga


## Onde a barriga está, na malha, na altura y do corpo.
static func _barriga_z(mi: MeshInstance3D, y: float) -> float:
	var pf := _perfil(mi)
	if pf.is_empty():
		return 0.012
	# (de trás para a frente: y diminuindo)
	for i in pf.size() - 1:
		var y0 := float(pf[i][0])
		var y1 := float(pf[i + 1][0])
		if y <= y0 and y >= y1:
			var t := (y0 - y) / maxf(y0 - y1, 1e-6)
			return lerpf(float(pf[i][1]), float(pf[i + 1][1]), t)
	return float(pf[0][1]) if y > float(pf[0][0]) else float(pf[pf.size() - 1][1])


## Os números do corpo para o couro (na pose de agora): y do rabo, do pescoço, onde o
## corte começa (pés de trás) e os cascos.
func _couro_ref(n: Node3D) -> Dictionary:
	var mi := _malha(n)
	var sk: Skeleton3D = n.get_meta("sk")
	var to := mi.global_transform.affine_inverse() * sk.global_transform
	var pos := func(nm: String) -> Vector3:
		return to * sk.get_bone_global_pose(sk.find_bone(nm)).origin
	var y_rabo: float = (pos.call("Back") as Vector3).y + 0.002
	var y_pes: float = (pos.call("Neck") as Vector3).y
	var y_ini: float = (pos.call("BackUpLeg_R") as Vector3).y
	return {"mi": mi, "y_rabo": y_rabo, "y_pescoco": y_pes, "u_ini": (y_rabo - y_ini) / (y_rabo - y_pes), "u_ubere": (y_rabo - (-0.004)) / (y_rabo - y_pes),
		"cascos": [pos.call("BackFoot_R"), pos.call("BackFoot_L"), pos.call("FrontFoot_R"), pos.call("FrontFoot_L")],
		"rabo": [pos.call("Back"), pos.call("Tail1"), pos.call("Tail2"), pos.call("Tail3"), pos.call("Tail4")],
		# a cabeça: da junta com o pescoço para a frente (fica com o couro)
		"cab_p": (pos.call("Head") as Vector3) - ((pos.call("Head") as Vector3) - (pos.call("Neck") as Vector3)).normalized() * 0.0015,
		"cab_d": ((pos.call("Head") as Vector3) - (pos.call("Neck") as Vector3)).normalized()}


## O couro na pele (o corte e a carne aparecendo). Faz o material da carcaça na primeira vez.
func couro_visual(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node) or not (nd.node as Node3D).has_meta("sk"):
		return
	var c: Dictionary = nd.c
	var cr: Dictionary = c.get("couro", {})
	if cr.is_empty() or bool((c.get("banda", {}) as Dictionary).get("feito", false)):
		return
	var n: Node3D = nd.node
	var rf := _couro_ref(n)
	var mi: MeshInstance3D = rf.mi
	if mi == null:
		return
	var sm: ShaderMaterial
	malha_cab(mi, n.get_meta("sk"))
	if n.has_meta("couro_mat"):
		sm = n.get_meta("couro_mat")
	else:
		if _couro_sh == null:
			_couro_sh = Shader.new()
			_couro_sh.code = COURO_SHADER
		sm = ShaderMaterial.new()
		sm.shader = _couro_sh
		for k in mi.mesh.get_surface_count():
			var m0 := mi.get_surface_override_material(k)
			if m0 == null:
				continue
			var m1: Material = m0.duplicate()
			m1.next_pass = sm
			mi.set_surface_override_material(k, m1)
		n.set_meta("couro_mat", sm)
	var m_por_u: float = mi.global_transform.basis.get_scale().x
	var u_ini := float(rf.u_ini)
	if float(cr.get("pele", 0.0)) >= 1.0:
		for cp in n.find_children("cupim", "MeshInstance3D", true, false):
			(cp as MeshInstance3D).visible = false          # (sem o couro o cupim é só a carne do lombo)
	sm.set_shader_parameter("y_rabo", rf.y_rabo)
	sm.set_shader_parameter("y_pescoco", rf.y_pescoco)
	sm.set_shader_parameter("corte_ini", u_ini)
	var pl := float(cr.get("pele", 0.0))
	if bool(cr.get("junto", false)):
		# o couro novo: a faca vai abrindo a barriga junto com o couro saindo (um pouco à frente)
		var uc := lerpf(1.0, -0.55, pl) - 0.1
		cr["corte"] = clampf((1.0 - uc) / maxf(1.0 - u_ini, 0.01), 0.0, 1.0) if pl > 0.0 else 0.04
	sm.set_shader_parameter("corte", lerpf(1.0, u_ini, float(cr.get("corte", 0.0))) if float(cr.get("corte", 0.0)) > 0.0 else 9.0)
	sm.set_shader_parameter("pele", 9.0 if pl <= 0.0 else lerpf(1.0, -0.55, pl))
	sm.set_shader_parameter("largura", 0.016 / m_por_u)
	sm.set_shader_parameter("infla", 0.0015 / m_por_u)
	sm.set_shader_parameter("esc", m_por_u)
	sm.set_shader_parameter("r_casco", 0.1 / m_por_u)
	sm.set_shader_parameter("cab_p", rf.cab_p)
	sm.set_shader_parameter("cab_d", rf.cab_d)
	sm.set_shader_parameter("r_cab", 0.26 / m_por_u)
	for i in 4:
		sm.set_shader_parameter("casco%d" % i, rf.cascos[i])
	var ev: Dictionary = c.get("evis", {})
	var uy := float(rf.u_ubere)
	sm.set_shader_parameter("ab_y", uy)
	sm.set_shader_parameter("u_ini2", u_ini)
	sm.set_shader_parameter("ab", lerpf(1.0, uy, float(ev.get("barriga", 0.0))) if float(ev.get("barriga", 0.0)) > 0.0 else 9.0)
	sm.set_shader_parameter("y_e", float(ev.get("y_e", 0.0)))
	sm.set_shader_parameter("y_d", float(ev.get("y_d", 0.0)))
	sm.set_shader_parameter("y_off", 0.13 / m_por_u)
	sm.set_shader_parameter("garg", 1.0 if float(ev.get("garganta", 0.0)) >= 1.0 else 0.0)
	sm.set_shader_parameter("aberto", 1.0 if bool(ev.get("feito", false)) else clampf(float(ev.get("puxa", 0.0)) * 1.5, 0.0, 1.0))
	sm.set_shader_parameter("abre_w", 0.12 / m_por_u)
	var bd: Dictionary = c.get("banda", {})
	sm.set_shader_parameter("parte_u", lerpf(0.9, 0.0, float(bd.get("corte", 0.0))) if float(bd.get("corte", 0.0)) > 0.0 else 9.0)


## A linha do corte na barriga, no mundo (n pontos, dos pés de trás até o pescoço).
func couro_linha(uid: String, n_pts := 16) -> Array:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return []
	var rf := _couro_ref(nd.node)
	var mi: MeshInstance3D = rf.mi
	var y0 := float(rf.y_pescoco)
	var y1 := lerpf(float(rf.y_rabo), float(rf.y_pescoco), float(rf.u_ini))
	var out := []
	for i in n_pts:
		var y := lerpf(y0, y1, float(i) / (n_pts - 1))
		out.append(mi.global_transform * Vector3(0, y, _barriga_z(mi, y) - 0.0005))
	return out


## Onde o couro está soltando agora (a borda entre o couro e a carne), no mundo: de um
## lado do corpo ao outro, passando pela barriga (virada para quem está tirando).
func couro_borda_linha(uid: String, n_pts := 11) -> Array:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return []
	var cr: Dictionary = (nd.c as Dictionary).get("couro", {})
	var rf := _couro_ref(nd.node)
	var mi: MeshInstance3D = rf.mi
	var u := clampf(lerpf(1.0, -0.55, float(cr.get("pele", 0.0))), -0.15, 0.97)
	var y := lerpf(float(rf.y_rabo), float(rf.y_pescoco), u)
	var zb := _barriga_z(mi, y)
	var zt := _costas_z(mi, y)
	var wx := _meia_largura(mi, y)
	var out := []
	for i in n_pts:
		var t := lerpf(-1.0, 1.0, float(i) / (n_pts - 1))
		var z := zb + (zt - zb) * 0.5 * (1.0 - sqrt(maxf(0.0, 1.0 - t * t)))
		out.append(mi.global_transform * Vector3(t * wx * 1.02, y, z - 0.0008))
	return out


## Para onde a barriga olha (no mundo).
func couro_frente(uid: String) -> Vector3:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return Vector3.FORWARD
	var mi := _malha(nd.node)
	return (mi.global_transform.basis * Vector3(0, 0, -1)).normalized()


func couro_de(uid: String) -> Dictionary:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty():
		return {}
	return nd.c


## Monta a carcaça salva (deitada, com a mancha e a flecha cravada).
func _monta(c: Dictionary) -> Node3D:
	var esp := str(c.esp)
	var p: Dictionary = c.get("p", {})
	var n: Node3D = null
	match esp:
		"vaca":
			n = VacaModelo.build(float(p.get("s", 1.0)), str(p.get("cor", "branca")), bool(p.get("touro", false)), int(p.get("seed", 1)))
			add_child(n)
			if n.has_meta("ap"):
				var ap: AnimationPlayer = n.get_meta("ap")
				ap.play(VacaModelo.ANIMS.morrer)
				ap.advance(ap.current_animation_length)
				_cortes_escala(n.get_meta("sk"), c)
				VacaModelo._cascos(n.get_meta("sk"))
		"tamandua":
			n = TamModelo.build(float(p.get("s", 1.0)))
			add_child(n)
			TamModelo.pose(n, "parado", 0.0, 0.0)
		"macaco":
			n = MacacoModelo.new()
			add_child(n)
			n.set_process(false)
		"arara":
			n = AraraModelo.new()
			add_child(n)
			n.set_process(false)
		"cobra":
			n = _cobra_morta(c.get("p", {}).get("pts", []))
			add_child(n)
	if n == null:
		return null
	var xf: Array = c.get("xf", [])
	if xf.size() >= 12:
		n.global_transform = _xf_de(xf)
	for w in c.get("feridas", []):
		var pai := _prender(n, Vector3.ZERO, str(w[6])) if w.size() > 6 and str(w[6]) != "" else n
		var ponto: Vector3 = pai.global_transform * Vector3(w[0], w[1], w[2])
		var dir: Vector3 = (pai.global_transform.basis * Vector3(w[3], w[4], w[5])).normalized()
		_mancha_bicho(pai, ponto, dir)
		var fl := MeshInstance3D.new()
		fl.mesh = flecha_mesh()
		pai.add_child(fl)
		_aponta(fl, ponto + dir * 0.12, dir)
		_mancha_chao(Vector3(ponto.x, 0, ponto.z), 0.5, false)
	return n


## A cobra morta: o corpo esticado como ficou (tubo pelos pontos salvos).
func _cobra_morta(pts: Array) -> Node3D:
	var root := Node3D.new()
	if pts.size() < 2:
		return root
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lados := 6
	var rows := []
	for i in pts.size():
		var p := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var q := Vector3(pts[mini(i + 1, pts.size() - 1)][0], pts[mini(i + 1, pts.size() - 1)][1], pts[mini(i + 1, pts.size() - 1)][2])
		var d := (q - p).normalized() if q != p else Vector3.FORWARD
		var a := d.cross(Vector3.UP).normalized()
		if a.length() < 0.1:
			a = Vector3.RIGHT
		var b := a.cross(d).normalized()
		var r := 0.04 * (1.0 - 0.8 * pow(float(i) / pts.size(), 3.0))
		var row := []
		for k in lados:
			var t := TAU * k / lados
			row.append(p + (a * cos(t) + b * sin(t)) * r)
		rows.append(row)
	for i in rows.size() - 1:
		for k in lados:
			var qq := [rows[i][k], rows[i + 1][k], rows[i + 1][(k + 1) % lados], rows[i][(k + 1) % lados]]
			var cor := Color(0.55, 0.42, 0.25) if (i / 4) % 2 == 0 else Color(0.2, 0.13, 0.07)
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_color(cor)
				st.add_vertex(qq[j])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root.add_child(mi)
	return root


## Refaz o que mudou: carcaça nova aparece, a que sumiu sai (as que já estão ficam).
func _rebuild() -> void:
	var tem := {}
	for c in carcacas:
		tem[str(c.uid)] = c
	for uid in _nodes.keys():
		if not tem.has(uid):
			if is_instance_valid(_nodes[uid].node):
				(_nodes[uid].node as Node).queue_free()
			if _nodes[uid].has("n2") and is_instance_valid(_nodes[uid].n2):
				(_nodes[uid].n2 as Node).queue_free()
			_nodes.erase(uid)
	for ch in get_children():
		if ch.has_meta("tipo") and not tem.has(str(ch.get_meta("uid", ""))):
			ch.queue_free()                  # (as patas e a cabeça somem com a carcaça)
	for k in _peca_nodes.keys():
		if not tem.has(str(k).split(":")[0]):
			if is_instance_valid(_peca_nodes[k]):
				(_peca_nodes[k] as Node).queue_free()
			_peca_nodes.erase(k)
	for uid in tem:
		if _nodes.has(uid):
			# (veio de outro celular: os dados novos, o mesmo desenho)
			var cv: Dictionary = tem[uid]
			var mudou: bool = JSON.stringify([cv.get("couro", {}), cv.get("evis", {})]) != JSON.stringify([(_nodes[uid].c as Dictionary).get("couro", {}), (_nodes[uid].c as Dictionary).get("evis", {})])
			var cortou: bool = JSON.stringify(cv.get("cortes", [])) != JSON.stringify((_nodes[uid].c as Dictionary).get("cortes", [])) or (cv.get("partes", []) as Array).size() != ((_nodes[uid].c as Dictionary).get("partes", []) as Array).size()
			_nodes[uid].c = cv
			if mudou:
				couro_visual(str(uid))
			var pmud: bool = JSON.stringify(cv.get("pecas", [])) != JSON.stringify((_nodes[uid].c as Dictionary).get("pecas", []))
			var qmud: bool = JSON.stringify(cv.get("quartos", {})) != JSON.stringify((_nodes[uid].c as Dictionary).get("quartos", {}))
			if pmud:
				_nodes[uid].c = cv
				_pecas_monta(str(uid))
			if qmud:
				_nodes[uid].c = cv
				for ld in ["e", "d"]:
					quarto_visual(str(uid), ld)
			if bool((cv.get("banda", {}) as Dictionary).get("feito", false)) and not _nodes[uid].has("n2"):
				partir_monta(str(uid))
			elif (cv.get("banda", {}) as Dictionary).has("corte"):
				couro_visual(str(uid))
			if cortou:
				var n0: Node3D = _nodes[uid].node
				if is_instance_valid(n0) and n0.has_meta("sk"):
					_cortes_escala(n0.get_meta("sk"), cv)
					VacaModelo._cascos(n0.get_meta("sk"))
				_partes_monta(str(uid))
			continue
		var c: Dictionary = tem[uid]
		if (c.get("xf", []) as Array).size() < 12:
			continue                         # (ainda caindo em outro celular)
		var n := _monta(c)
		if n:
			_nodes[uid] = {"node": n, "c": c}
			if c.has("couro"):
				couro_visual(str(uid))
			_partes_monta(str(uid))
	_mortes_locais()


## Os bichos que morreram em outro celular saem da vida aqui também.
func _mortes_locais() -> void:
	var j = _jogo
	if j == null:
		return
	for c in carcacas:
		var id := int(c.get("id", -1))
		match str(c.esp):
			"vaca":
				if j._vacas and not j._vacas._find(id).is_empty():
					j._vacas.matar(id)
			"tamandua":
				if j._tamanduas and not j._tamanduas._find(id).is_empty():
					j._tamanduas.matar(id)
			"arara":
				if j._araras and j._araras._bird(id) != null:
					j._araras.matar(id)
			"cobra":
				if j._cobras:
					j._cobras.matar(id)


func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		var lst := []
		for c in carcacas:
			if (c.get("xf", []) as Array).size() >= 12:
				lst.append(c)
		f.store_string(JSON.stringify({"versao": 1, "carcacas": lst}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	var novas: Array = d.get("carcacas", [])
	# as que estão caindo agora (ainda sem posição final) ficam
	for c in carcacas:
		if (c.get("xf", []) as Array).size() < 12:
			novas.append(c)
	carcacas = novas
	return true


# ---------- o couro tirado, estendido no chão ----------
# Saiu todo: o couro fica estendido no chão do lado do tripé, do tamanho da vaca (o pelo
# para cima, com as abas das pernas, o pescoço e o rabo). "Enrolar o couro" enrola ele
# (vira um rolo) e "Pegar o couro" leva o rolo. c.couro_chao = {x, z, yaw, rolo 0..1, enrolando}

var _cchao := {}                  # uid -> MeshInstance3D
static var _cchao_mat: ShaderMaterial


## Dentro do formato do couro aberto? (x de lado, z ao comprido: + o pescoço, - o rabo; em m numa vaca de tamanho 1)
static func _couro_forma(x: float, z: float) -> bool:
	var ax := absf(x)
	if pow(ax / 0.72, 4.0) + pow(absf(z) / 0.85, 4.0) < 1.0:
		return true
	if z > 0.75 and z < 1.25 and ax < 0.34 - (z - 0.75) * 0.25:
		return true
	if z < -0.8 and z > -1.45 and ax < 0.045:
		return true
	for e in [[Vector2(0.6, 0.6), Vector2(1.22, 0.88), 0.13], [Vector2(0.6, -0.55), Vector2(1.28, -0.98), 0.16]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var q := Vector2(ax, z)
		var t := clampf((q - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if q.distance_to(a + (b - a) * t) < float(e[2]) * (1.0 - t * 0.45):
			return true
	return false


func couro_chao_por(uid: String, pos: Vector3, yaw: float) -> void:
	var c := couro_de(uid)
	if c.is_empty():
		return
	c["couro_chao"] = {"x": pos.x, "z": pos.z, "yaw": yaw, "rolo": 0.0}
	_couro_chao_monta(uid)


func _couro_chao_monta(uid: String) -> void:
	if _cchao.has(uid) and is_instance_valid(_cchao[uid]):
		(_cchao[uid] as Node).queue_free()
	_cchao.erase(uid)
	var c := couro_de(uid)
	var cc: Dictionary = c.get("couro_chao", {})
	if cc.is_empty():
		return
	if _cchao_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec3 cor;
varying vec3 lp;
void vertex() { cor = COLOR.rgb; lp = VERTEX; }
float hh(vec2 q) { return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	// o pelo: fiozinhos de tom diferente, deitados para o mesmo lado
	float f = hh(floor(vec2(lp.x * 160.0, lp.z * 45.0)));
	vec3 c = pow(cor, vec3(2.2)) * (0.82 + 0.3 * f);
	ALBEDO = FRONT_FACING ? c : vec3(0.62, 0.5, 0.45);
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
"""
		_cchao_mat = ShaderMaterial.new()
		_cchao_mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = "couro_chao"
	mi.material_override = _cchao_mat
	add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, float(cc.yaw)), Vector3(float(cc.x), 0.0, float(cc.z)))
	_cchao[uid] = mi
	_couro_chao_malha(uid)


## O desenho: a grade no formato do couro, deitada no chão; enrolando, o rolo vai
## comendo do pescoço para o rabo.
func _couro_chao_malha(uid: String) -> void:
	var mi: MeshInstance3D = _cchao.get(uid, null)
	if mi == null or not is_instance_valid(mi):
		return
	var c := couro_de(uid)
	var cc: Dictionary = c.get("couro_chao", {})
	var p: Dictionary = c.get("p", {})
	var s := float(p.get("s", 1.0)) * 1.15
	var cores: Array = VacaModelo.CORES.get(str(p.get("cor", "branca")), VacaModelo.CORES.branca)
	var malhada := str(p.get("cor", "")) == "malhada"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid)
	var sx := rng.randf_range(0.0, 50.0)
	var r := clampf(float(cc.get("rolo", 0.0)), 0.0, 1.0)
	var z0 := -1.45
	var z1 := 1.25
	var zf := lerpf(z1, z0, r)              # até onde já enrolou
	var R := (0.03 + 0.15 * sqrt(r)) * s
	var xf := mi.global_transform
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.05
	var nx := 80
	var nz := 80
	var dx := 2.7 / nx
	var dz := (z1 - z0) / nz
	var alt := func(lx: float, lz: float, lift: float) -> Vector3:
		var w := xf * Vector3(lx * s, 0.0, lz * s)
		return Vector3(lx * s, _jogo.ground_at(w.x, w.z) + 0.025 + lift, lz * s)
	var cor := func(lx: float, lz: float) -> Color:
		var k: Color = (cores[0] as Color).darkened(0.18)
		var n := sin(lx * 4.1 + sx) * sin(lz * 3.3 + sx * 0.7) + sin(lx * 9.0 - lz * 7.0 + sx) * 0.35
		if malhada and n > 0.25:
			k = cores[1]
		# o pelo amassado e o meio (o lombo) um pouco mais escuro
		var pelo := sin(lx * 37.0 + lz * 11.0) * sin(lz * 29.0 - lx * 5.0) * 0.05
		k = k.darkened(clampf(n * 0.06 + pelo + (0.08 - absf(lx) * 0.08), -0.08, 0.25))
		return k
	if not mi.has_meta("tris"):
		# cada quadradinho: inteiro se os 4 cantos estão no couro, meio (um triângulo) se 3
		# (a beirada sai lisa, sem degraus). Feito uma vez: [pos, cor, z] por vértice.
		var tv := []
		for iz in nz:
			for ix in nx:
				var xa := -1.35 + ix * dx
				var xb := xa + dx
				var za := z0 + iz * dz
				var zb := za + dz
				var cs := [Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb)]
				var dentro := []
				var nd := 0
				for cq in cs:
					var dq := _couro_forma(cq.x, cq.y)
					dentro.append(dq)
					if dq:
						nd += 1
				if nd < 3:
					continue
				var tris := [[0, 1, 2], [0, 2, 3]]
				if nd == 3:
					var fora := dentro.find(false)
					tris = [[(fora + 1) % 4, (fora + 2) % 4, (fora + 3) % 4]]
				for tr in tris:
					var zmax := maxf(maxf((cs[tr[0]] as Vector2).y, (cs[tr[1]] as Vector2).y), (cs[tr[2]] as Vector2).y)
					for t in tr:
						var cq2: Vector2 = cs[t]
						var k: Color = cor.call(cq2.x, cq2.y)
						if nd == 3:
							k = k.darkened(0.12)       # a beirada um pouco mais escura (seca)
						tv.append([alt.call(cq2.x, cq2.y, 0.0), k, zmax])
		mi.set_meta("tris", tv)
	if r < 0.999:
		for v in (mi.get_meta("tris") as Array):
			if float(v[2]) > zf + 0.0001:
				continue
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	if r > 0.0:
		# o rolo: o lado de dentro (a carne, branca e rosada) para fora
		var meia := 0.0
		for i in 40:
			var lzz := lerpf(zf, z1, float(i) / 39.0)
			for j in 28:
				var lxx := float(j) / 27.0 * 1.35
				if _couro_forma(lxx, lzz):
					meia = maxf(meia, lxx)
		meia = clampf(meia, 0.3, 0.72) * s        # (as abas das pernas dobram para dentro)
		var cz := zf * s
		var base: Vector3 = alt.call(0.0, zf, 0.0)
		var n := 14
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var p0 := Vector3(0, base.y + R + sin(a0) * R, cz + cos(a0) * R)
			var p1 := Vector3(0, base.y + R + sin(a1) * R, cz + cos(a1) * R)
			var kk := Color(0.86, 0.76, 0.7) if i % 2 == 0 else Color(0.8, 0.66, 0.6)
			var q2 := [p0 + Vector3(-meia, 0, 0), p0 + Vector3(meia, 0, 0), p1 + Vector3(meia, 0, 0), p1 + Vector3(-meia, 0, 0)]
			var nr := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
			for t in [0, 1, 2, 0, 2, 3]:
				st.set_color(kk)
				st.set_normal(nr)
				st.add_vertex(q2[t])
			# as pontas do rolo (a espiral do couro: o pelo por dentro)
			for sg in [-1.0, 1.0]:
				var cen := Vector3(sg * meia, base.y + R, cz)
				for t2 in [[cen, p0 + Vector3(sg * meia, 0, 0), p1 + Vector3(sg * meia, 0, 0)]]:
					for v in t2:
						st.set_color((cores[0] as Color).darkened(0.25))
						st.set_normal(Vector3(sg, 0, 0))
						st.add_vertex(v)
	mi.mesh = st.commit()


## O couro no chão mais perto (uid ou "").
func couro_chao_perto(pos: Vector3, reach: float) -> String:
	var best := ""
	var bd := reach
	for uid in _cchao:
		var mi: MeshInstance3D = _cchao[uid]
		if not is_instance_valid(mi):
			continue
		var cc: Dictionary = couro_de(str(uid)).get("couro_chao", {})
		if cc.is_empty():
			continue
		# perto de qualquer ponto do couro (ele é grande)
		var l := mi.global_transform.affine_inverse() * pos
		var d := Vector2(clampf(l.x, -0.9, 0.9) - l.x, clampf(l.z, -1.2, 1.1) - l.z).length()
		if d < bd:
			bd = d
			best = str(uid)
	return best


func couro_chao_rolo(uid: String) -> float:
	return float((couro_de(uid).get("couro_chao", {}) as Dictionary).get("rolo", 0.0))


func couro_chao_enrolar(uid: String) -> void:
	var cc: Dictionary = couro_de(uid).get("couro_chao", {})
	if not cc.is_empty():
		cc["enrolando"] = true
		Sons.play_at(_jogo, "fibra_puxa", Vector3(float(cc.x), _jogo.ground_at(float(cc.x), float(cc.z)), float(cc.z)), -8.0, 0.6)


func _couro_chao_tick(delta: float) -> void:
	for uid in _cchao:
		var cc: Dictionary = couro_de(str(uid)).get("couro_chao", {})
		if cc.is_empty() or not bool(cc.get("enrolando", false)):
			continue
		cc.rolo = minf(1.0, float(cc.rolo) + delta / 2.2)
		if float(cc.rolo) >= 1.0:
			cc.erase("enrolando")
		_couro_chao_malha(str(uid))


## O rolo foi pego (sai do chão).
func couro_chao_tirar(uid: String) -> void:
	var c := couro_de(uid)
	c.erase("couro_chao")
	if _cchao.has(uid) and is_instance_valid(_cchao[uid]):
		(_cchao[uid] as Node).queue_free()
	_cchao.erase(uid)


# ================== A DECOMPOSIÇÃO (e o que os urubus comem) ==================
# Tudo o que morreu apodrece pelo tempo do jogo (Podre): a carcaça inteira, os pedaços
# de carne, a buchada, as patas e a cabeça. O que os urubus comem soma em "comido"
# (0..1 do peso): c.comido na carcaça, pc.comido na peça, e.comido na parte.

var _podre_t := 0.5
const PODRE_K := {"vaca": 1.0, "tamandua": 1.3, "macaco": 1.6, "arara": 2.2, "cobra": 1.8}


## Horas do jogo desde o começo do mundo.
func agora_h() -> float:
	if _jogo == null or _jogo.sim == null:
		return 0.0
	return float(_jogo.sim.steps) / float(_jogo.sim.STEPS_DAY) * 24.0


## Horas desde a morte.
func idade_h(c: Dictionary) -> float:
	var t0 := float(c.get("t0", float(c.get("dia", 0)) * 24.0 + 12.0))
	return maxf(0.0, agora_h() - t0)


## A carcaça inteira, deitada no chão (não a que está sendo trabalhada no tripé)?
func _inteira(c: Dictionary) -> bool:
	return not c.has("couro") and (c.get("xf", []) as Array).size() >= 12


## Quanto da carcaça já foi (0..1) e o estágio.
func podre_de(c: Dictionary, comido: float, k: float) -> Array:
	var h := idade_h(c)
	var cons := clampf(Podre.consumo_tempo(h, k) + comido, 0.0, 1.0)
	return [Podre.estagio(h, cons, k), cons]


## O estágio de podre de uma peça (0 fresca .. 4).
func peca_podre(uid: String, pc: Dictionary) -> float:
	var c := couro_de(uid)
	if c.is_empty():
		return 0.0
	var k := float(PODRE_K.get(str(c.esp), 1.0)) * 1.2
	return float(podre_de(c, float(pc.get("comido", 0.0)), k)[0])


## Peso (kg) da carcaça inteira.
func carcaca_kg(c: Dictionary) -> float:
	var p: Dictionary = c.get("p", {})
	var s := float(p.get("s", 1.0))
	match str(c.esp):
		"vaca":
			return (450.0 if bool(p.get("touro", false)) else 380.0) * s * s * s
		"tamandua":
			return 30.0 * s * s * s
		"macaco":
			return 8.0
		"arara":
			return 1.2
		"cobra":
			return 1.5
	return 20.0


func _podre_tick() -> void:
	var cam_p: Vector3 = _jogo._player.global_position if _jogo and _jogo._player else Vector3.ZERO
	for uid in _nodes:
		var nd: Dictionary = _nodes[uid]
		var c: Dictionary = nd.c
		var n: Node3D = nd.node
		if not is_instance_valid(n) or nd.has("corre") or nd.has("cai"):
			continue
		var k := float(PODRE_K.get(str(c.esp), 1.0))
		if _inteira(c):
			var pr := podre_de(c, float(c.get("comido", 0.0)), k)
			_podre_no(nd, n, float(pr[0]), float(pr[1]), c, cam_p)
		# os pedaços de carne (onde estiverem) e as partes no chão
		for pc in c.get("pecas", []):
			var pn := peca_no(str(uid), int(pc.id))
			if pn == null:
				continue
			var pr2 := podre_de(c, float(pc.get("comido", 0.0)), k * 1.2)
			if float(pr2[0]) > 0.05:
				Podre.atualiza(pn, minf(float(pr2[0]), 3.3), float(pr2[1]))
			if float(pr2[1]) >= 1.0 and str(pc.onde) == "chao":
				peca_tirar(str(uid), int(pc.id))
				break
		var partes: Array = c.get("partes", [])
		for e in partes.duplicate():
			if not (e as Dictionary).has("xf"):
				continue
			var pn2 := _parte_node(str(uid), str(e.tipo))
			if pn2 == null:
				continue
			var kb := 1.8 if str(e.tipo) == "buchada" else 1.2
			var pr3 := podre_de(c, float(e.get("comido", 0.0)), k * kb)
			if float(pr3[1]) >= 1.0:
				if str(e.tipo) == "buchada":
					partes.erase(e)
					pn2.queue_free()
				elif not pn2.has_meta("ossos"):
					_vira_osso_generico(pn2)
				continue
			if float(pr3[0]) > 0.05:
				Podre.atualiza(pn2, minf(float(pr3[0]), 3.3), float(pr3[1]))


func _parte_node(uid: String, tipo: String) -> Node3D:
	for ch in get_children():
		if ch is Node3D and ch.has_meta("tipo") and str(ch.get_meta("uid", "")) == uid and str(ch.get_meta("tipo")) == tipo:
			return ch
	return null


## A carcaça no estágio dela: a passada de podre, o inchaço, as moscas, a mancha e, no
## fim, só o esqueleto.
func _podre_no(nd: Dictionary, n: Node3D, est: float, cons: float, c: Dictionary, cam_p: Vector3) -> void:
	if not n.has_meta("esc0"):
		n.set_meta("esc0", n.scale)
	var tam := carcaca_kg(c)
	var r := clampf(pow(tam, 0.33) * 0.13, 0.15, 1.0)
	if est >= 3.9 or cons >= 0.999:
		if not n.has_meta("ossos"):
			n.scale = n.get_meta("esc0")
			if str(c.esp) == "vaca" and n.has_meta("sk"):
				var sk: Skeleton3D = n.get_meta("sk")
				for m in n.find_children("*", "MeshInstance3D", true, false):
					if (m as MeshInstance3D).material_override != VacaModelo._mat_chifre():
						(m as MeshInstance3D).visible = false
				var oss := Podre.esqueleto_vaca(sk, c.get("cortes", []))
				sk.add_child(oss)
			else:
				_vira_osso_generico(n)
			n.set_meta("ossos", true)
		if nd.has("moscas") and is_instance_valid(nd.moscas):
			(nd.moscas as CPUParticles3D).emitting = false
		if nd.has("zum") and is_instance_valid(nd.zum):
			(nd.zum as AudioStreamPlayer3D).stop()
		if nd.has("mancha") and is_instance_valid(nd.mancha):
			var mm: MeshInstance3D = nd.mancha
			mm.scale = Vector3.ONE * maxf(0.3, 1.0 - (est - 3.9) * 0.5)
		return
	if n.has_meta("ossos"):
		return
	if est > 0.05 or cons > 0.0:
		Podre.atualiza(n, est, cons)
	# inchado: a barriga estufa; depois murcha e achata
	var b := smoothstep(0.6, 1.6, est) * (1.0 - smoothstep(2.0, 2.6, est))
	var f := (1.0 + 0.08 * b) * (1.0 - 0.1 * smoothstep(2.4, 3.8, est))
	n.scale = (n.get_meta("esc0") as Vector3) * f
	# as moscas (e o zumbido perto)
	var com_mosca := est > 0.12 and est < 3.4
	if com_mosca and not nd.has("moscas"):
		var mo := Podre.moscas(r)
		add_child(mo)
		nd["moscas"] = mo
	if nd.has("moscas") and is_instance_valid(nd.moscas):
		var mo2: CPUParticles3D = nd.moscas
		mo2.global_position = _centro_bicho(n) + Vector3.UP * r * 0.4
		mo2.emitting = com_mosca
		var perto := mo2.global_position.distance_to(cam_p) < 14.0
		if com_mosca and perto:
			if not nd.has("zum") or not is_instance_valid(nd.zum):
				var z := AudioStreamPlayer3D.new()
				var stv := Sons.pick("moscas")
				if stv is AudioStreamOggVorbis:
					(stv as AudioStreamOggVorbis).loop = true
				z.stream = stv
				z.volume_db = -14.0 + minf(est, 2.5) * 3.0
				z.unit_size = 2.0
				z.max_distance = 16.0
				add_child(z)
				nd["zum"] = z
			var zz: AudioStreamPlayer3D = nd.zum
			zz.global_position = mo2.global_position
			if not zz.playing:
				zz.play()
		elif nd.has("zum") and is_instance_valid(nd.zum):
			(nd.zum as AudioStreamPlayer3D).stop()
	# o líquido escuro no chão quando estoura
	if est >= 1.9 and not nd.has("mancha"):
		var ms := Podre.mancha(r * 1.4)
		add_child(ms)
		var cp := _centro_bicho(n)
		ms.global_position = Vector3(cp.x, _jogo.ground_at(cp.x, cp.z) + 0.012, cp.z)
		nd["mancha"] = ms


func _centro_bicho(n: Node3D) -> Vector3:
	var ab := AABB()
	var tem := false
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		ab = a if not tem else ab.merge(a)
		tem = true
	return ab.get_center() if tem else n.global_position


## Sem carne: o corpo some e ficam uns ossos do tamanho dele.
func _vira_osso_generico(n: Node3D) -> void:
	var ab := AABB()
	var tem := false
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		ab = a if not tem else ab.merge(a)
		tem = true
		mi.visible = false
	if not tem:
		return
	var fr := n.global_transform.basis.x if ab.size.x >= ab.size.z else n.global_transform.basis.z
	var cy: float = _jogo.ground_at(ab.get_center().x, ab.get_center().z)
	var o := Podre.ossada_generica(ab, fr, cy)
	add_child(o)
	o.reparent(n, true)
	n.set_meta("ossos", true)


## O que tem para os urubus comerem: [{key, pos, kg (o que sobra), uid}]. Só o que está
## no chão (não a vaca pendurada no tripé nem a carne na mesa ou no carrinho).
func comidas() -> Array:
	var out := []
	for uid in _nodes:
		var nd: Dictionary = _nodes[uid]
		var c: Dictionary = nd.c
		if not is_instance_valid(nd.node) or nd.has("corre") or nd.has("cai"):
			continue
		var k := float(PODRE_K.get(str(c.esp), 1.0))
		if _inteira(c) and idade_h(c) >= 1.5:
			var pr := podre_de(c, float(c.get("comido", 0.0)), k)
			if float(pr[1]) < 0.97:
				out.append({"key": str(uid), "pos": _centro_bicho(nd.node), "kg": carcaca_kg(c) * (1.0 - float(pr[1])), "uid": str(uid), "r": clampf(pow(carcaca_kg(c), 0.33) * 0.13, 0.15, 1.0)})
		for pc in c.get("pecas", []):
			if str(pc.onde) != "chao":
				continue
			var cp := peca_centro(str(uid), int(pc.id))
			if cp == Vector3.INF:
				continue
			out.append({"key": "%s:p:%d" % [uid, int(pc.id)], "pos": cp, "kg": peca_kg(str(uid), pc) * (1.0 - float(pc.get("comido", 0.0))), "uid": str(uid), "r": 0.35})
		for e in c.get("partes", []):
			if not (e as Dictionary).has("xf"):
				continue
			var pn := _parte_node(str(uid), str(e.tipo))
			if pn == null or pn.has_meta("ossos"):
				continue
			out.append({"key": "%s:t:%s" % [uid, str(e.tipo)], "pos": _centro_bicho(pn), "kg": _parte_kg(c, str(e.tipo)) * (1.0 - float(e.get("comido", 0.0))), "uid": str(uid), "r": 0.25})
	return out


func _parte_kg(c: Dictionary, tipo: String) -> float:
	var s := float((c.get("p", {}) as Dictionary).get("s", 1.0))
	match tipo:
		"buchada":
			return 55.0 * s * s * s
		"cabeca":
			return 18.0 * s * s * s
	return 4.0 * s * s * s


## Um urubu comeu kg do que tem em key (só no dono do mundo: os outros recebem).
func comer(key: String, kg: float) -> void:
	if _jogo and _jogo._mp_client():
		return
	var ps := key.split(":")
	var c := couro_de(ps[0])
	if c.is_empty():
		return
	if ps.size() == 1:
		c["comido"] = minf(1.0, float(c.get("comido", 0.0)) + kg / maxf(carcaca_kg(c), 0.5))
	elif ps[1] == "p":
		var pc := peca_de(ps[0], int(ps[2]))
		if not pc.is_empty():
			pc["comido"] = minf(1.0, float(pc.get("comido", 0.0)) + kg / maxf(peca_kg(ps[0], pc), 0.2))
	elif ps[1] == "t":
		for e in c.get("partes", []):
			if str(e.tipo) == ps[2]:
				e["comido"] = minf(1.0, float(e.get("comido", 0.0)) + kg / maxf(_parte_kg(c, ps[2]), 0.2))


## Um bicho que morreu sozinho (fome, velhice): fica a carcaça deitada onde caiu.
func morte_natural(esp: String, id: int, params: Dictionary, pos: Vector3, yaw: float) -> void:
	if _jogo == null or _jogo._mp_client():
		return
	var s := float(params.get("s", 1.0))
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(pos.x, _jogo.ground_at(pos.x, pos.z), pos.z))
	var uid := "%d_%d" % [Time.get_ticks_msec(), _rng.randi() % 100000]
	carcacas.append({"uid": uid, "esp": esp, "id": id, "p": params, "dia": int(_jogo.sim.elapsed_days()), "t0": agora_h(),
		"feridas": [], "xf": _xf_json(xf), "natural": true})
	_rebuild()

