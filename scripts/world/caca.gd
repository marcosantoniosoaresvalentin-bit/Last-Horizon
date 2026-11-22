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

const G := 9.8
const FLECHA_L := 0.78
const APODRECE := 20              # dias que a carcaça fica

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
	var c := {"uid": uid, "esp": esp, "id": id, "p": params, "dia": int(j.sim.elapsed_days()),
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
	sm.set_shader_parameter("q_faca", float(q.get("faca", 0.0)) * 1.05)
	sm.set_shader_parameter("q_parte", 1.0 if bool(q.get("caiu", false)) else 0.0)


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
	var pc := _quarto_no(uid, lado, [], false)
	if pc:
		_caindo.append({"node": pc, "vel": Vector3.DOWN * 0.3, "ang": Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 0.6,
			"uid": uid, "tipo": "quarto_" + lado, "chao": 0.0, "r": 0.3, "low": pc.get_meta("low")})
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
uniform float corte_q;
uniform float q_faca;
uniform float q_parte;
uniform float q_w;
uniform float zb;
uniform float zt;
uniform float sujo;
varying vec3 p;
varying vec3 nn;
void vertex() { p = VERTEX; nn = NORMAL; }
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
void fragment() {
	float u = (y_rabo - p.y) / (y_rabo - y_pescoco);
	bool cab = u > 0.92;
	float dr = min(min(seg(p, rabo1, rabo2), seg(p, rabo2, rabo3)), min(seg(p, rabo3, rabo4), seg(p, rabo4, rabo5)));
	dr = min(dr, seg(p, rabo0, rabo1) + r_rabo * 0.35);
	bool rabo = dr < r_rabo;
	// a banda partida no meio: em cima (pendurada) ou o pedaço de baixo (que caiu)
	if (q_parte > 0.5 && q_parte < 1.5 && (u < corte_q || rabo)) { discard; }
	if (q_parte > 1.5 && u >= corte_q) { discard; }
	if (rabo) {
		if (com_rabo < 0.5) { discard; }      // o rabo inteiro fica numa banda só
	} else if (cab) {
		if (com_cabeca < 0.5) { discard; }
	} else if (p.x * lado < 0.0) {
		discard;
	}
	vec3 q = p * esc;
	float n1 = ruido(q * 11.0);
	float n2 = ruido(q * 34.0 + vec3(3.1, 1.7, 5.3));
	float dc = min(min(distance(p, casco0), distance(p, casco1)), min(distance(p, casco2), distance(p, casco3)));
	if (!FRONT_FACING) {
		// o lado de dentro da banda: a carne partida e, perto do meio, o osso da espinha
		vec3 carne = mix(vec3(0.3, 0.025, 0.02), vec3(0.46, 0.06, 0.045), n1);
		float osso = smoothstep(0.55, 0.8, abs(sin(q.y * 3.14159 / 0.05))) * step(0.0, nn.z);
		ALBEDO = mix(carne, vec3(0.88, 0.82, 0.74), osso * 0.8);
		ROUGHNESS = 0.45;
	} else if (dc < r_casco) {
		ALBEDO = vec3(0.12, 0.1, 0.08);
		ROUGHNESS = 0.6;
	} else if (u > 1.0) {
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
	if (q_parte < 0.5 && FRONT_FACING && abs(u - corte_q) < q_w && (p.z - zb) / max(zt - zb, 1e-6) < q_faca) {
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
	sm.set_shader_parameter("com_rabo", 0.0 if cab else 1.0)     # o rabo vai com a banda sem a cabeça
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
	for k in mini(mats.size(), mi.mesh.get_surface_count()):
		mi.set_surface_override_material(k, mats[k])
	mi.set_meta("sem_ubere", true)
	for nm in ["saco", "prepucio"]:
		for ch in n.find_children(nm, "MeshInstance3D", true, false):
			ch.queue_free()


# ---------- patas e cabeça (com o machado) ----------
# Pendurada, as canelas (do jarrete/joelho para baixo, com o casco) e a cabeça saem a
# machadadas. A parte cortada vira um pedaço separado (a mesma malha da vaca, só daquela
# parte, na pose de pendurada) que cai, quica e fica no chão; na carcaça fica o toco
# (carne vermelha com o osso branco no meio). c.cortes = [tipo...]; c.partes = [{tipo, xf}].

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
func _parte_no(uid: String, tipo: String, xf_salvo := []) -> Node3D:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return null
	var n: Node3D = nd.node
	var mi := _malha(n)
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
	var tc := _toco(float(PARTES[tipo].r) / m_por_u)
	par.add_child(tc)
	tc.transform = rel * Transform3D(_base_para(-(pm.dir as Vector3)), pm.corte)
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
	for e in nd.c.get("partes", []):
		if str(e.tipo).begins_with("quarto_"):
			_quarto_no(uid, str(e.tipo).substr(7), e.xf, bool(e.get("sujo", false)))


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
		# o quarto caindo num carrinho de mão (posto embaixo): vai para dentro dele, limpo
		if str(f.tipo).begins_with("quarto_") and _jogo.has_method("quarto_no_carrinho") and f.has("low"):
			# o meio do pedaço (a perna pendurada não conta) na altura do ponto mais baixo
			var meio := Vector3.ZERO
			for lp2 in f.low:
				meio += nd.global_transform * (lp2 as Vector3)
			meio /= maxf(1.0, (f.low as Array).size())
			meio.y = low
			if _jogo.quarto_no_carrinho(meio, str(f.uid), str(f.tipo).substr(7)):
				_caindo.erase(f)
				nd.queue_free()
				continue
		var gy: float = _jogo.ground_at(lowp.x, lowp.z)
		if low < gy:
			nd.global_position.y += gy - low
			if vel.y < -1.2:
				Sons.play_at(_jogo, "baque", lowp, -10.0 + minf(-vel.y, 5.0), 1.3 if str(f.tipo) != "cabeca" else 0.85)
				_respingo(Vector3(lowp.x, 0, lowp.z), _rng.randf_range(0.08, 0.16), "gota")
			if str(f.tipo).begins_with("quarto_") and not bool(f.get("sujou", false)) and not bool(f.get("limpo", false)):
				if _jogo._maq and _jogo._maq.no_forro(lowp):
					f["limpo"] = true                 # caiu no forro de folhas: limpo
				else:
					f["sujou"] = true
					quarto_sujar(nd)                  # caiu na terra: sujou
			vel.y = -vel.y * 0.22 if vel.y < -0.6 else 0.0
			vel.x *= 0.55
			vel.z *= 0.55
			ang *= 0.5
			f.chao = float(f.chao) + delta
		f.vel = vel
		f.ang = ang
		if float(f.chao) > 0.5 and vel.length() < 0.25 and ang.length() < 0.6:
			_caindo.erase(f)
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
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
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
void vertex() {
	p = VERTEX;
	nn = NORMAL;
	VERTEX += NORMAL * infla;
}
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	float u = (y_rabo - p.y) / (y_rabo - y_pescoco);
	float dc = min(min(distance(p, casco0), distance(p, casco1)), min(distance(p, casco2), distance(p, casco3)));
	if (dc < r_casco || u > 1.0) { discard; }
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
				float cost = abs(sin(q.y * 3.14159 / 0.085));
				float c2 = smoothstep(0.72, 0.93, cost) * smoothstep(0.45, 0.55, tt);
				cav = mix(cav, vec3(0.86, 0.78, 0.72), c2 * 0.85);
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
"""
static var _couro_sh: Shader
static var _barriga: Array = []       # [[y, z]] a barriga por baixo (na malha, em pé)


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
		"rabo": [pos.call("Back"), pos.call("Tail1"), pos.call("Tail2"), pos.call("Tail3"), pos.call("Tail4")]}


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
			(cp as MeshInstance3D).material_override = _carne_mat()
	sm.set_shader_parameter("y_rabo", rf.y_rabo)
	sm.set_shader_parameter("y_pescoco", rf.y_pescoco)
	sm.set_shader_parameter("corte_ini", u_ini)
	sm.set_shader_parameter("corte", lerpf(1.0, u_ini, float(cr.get("corte", 0.0))) if float(cr.get("corte", 0.0)) > 0.0 else 9.0)
	var pl := float(cr.get("pele", 0.0))
	sm.set_shader_parameter("pele", 9.0 if pl <= 0.0 else lerpf(1.0, -0.55, pl))
	sm.set_shader_parameter("largura", 0.016 / m_por_u)
	sm.set_shader_parameter("infla", 0.0015 / m_por_u)
	sm.set_shader_parameter("esc", m_por_u)
	sm.set_shader_parameter("r_casco", 0.1 / m_por_u)
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
	for uid in tem:
		if _nodes.has(uid):
			# (veio de outro celular: os dados novos, o mesmo desenho)
			var cv: Dictionary = tem[uid]
			var mudou: bool = JSON.stringify([cv.get("couro", {}), cv.get("evis", {})]) != JSON.stringify([(_nodes[uid].c as Dictionary).get("couro", {}), (_nodes[uid].c as Dictionary).get("evis", {})])
			var cortou: bool = JSON.stringify(cv.get("cortes", [])) != JSON.stringify((_nodes[uid].c as Dictionary).get("cortes", [])) or (cv.get("partes", []) as Array).size() != ((_nodes[uid].c as Dictionary).get("partes", []) as Array).size()
			_nodes[uid].c = cv
			if mudou:
				couro_visual(str(uid))
			var qmud: bool = JSON.stringify(cv.get("quartos", {})) != JSON.stringify((_nodes[uid].c as Dictionary).get("quartos", {}))
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
