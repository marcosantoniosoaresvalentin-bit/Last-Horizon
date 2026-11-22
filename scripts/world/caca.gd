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
# A vaca morta amarrada pelos pés de trás: as pernas de trás esticadas para trás (a corda
# puxa as duas juntas), as da frente soltas. Enquanto a cabeça ainda está no chão o corpo
# gira em volta dela (a traseira sobe e vem para baixo da roldana); levantada a altura do
# corpo, fica pendurada de cabeça para baixo.

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
	for nm in ["BackFoot_R", "BackFoot_L"]:
		var bi := sk.find_bone(nm)
		soma += sk.global_transform * sk.get_bone_global_pose(bi).origin
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


## A pose de pendurada nos ossos (uma vez): devolve os pontos dela no corpo.
func _rig(n: Node3D) -> Dictionary:
	if n.has_meta("rig"):
		return n.get_meta("rig")
	var sk: Skeleton3D = n.get_meta("sk")
	sk.reset_bone_poses()
	for sd in ["_R", "_L"]:
		VacaModelo._dobra(sk, "BackUpLeg" + sd, 1.5)
		VacaModelo._dobra(sk, "BackLowLeg" + sd, 0.35)
		VacaModelo._dobra(sk, "FrontUpLeg" + sd, -0.9)
		VacaModelo._dobra(sk, "FrontLowLeg" + sd, -0.3)
	VacaModelo._dobra(sk, "Neck", 0.55)
	VacaModelo._dobra(sk, "Head", 0.35)
	VacaModelo._dobra(sk, "Tail1", -0.6)
	VacaModelo._cascos(sk)
	var inv := n.global_transform.affine_inverse()
	var pk := Vector3.ZERO
	for nm in ["BackFoot_R", "BackFoot_L"]:
		pk += inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm)).origin) * 0.5
	var ph: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)
	var cr: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Body")).origin)
	var rig := {"pk": pk, "l": pk.distance_to(ph) + 0.3, "cr": cr}
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
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -a) * Basis(Vector3.RIGHT, PEND_ROLL)
	return {"h": h, "alt0": alt0, "l": L, "xf": Transform3D(b.scaled(Vector3.ONE * s), h - b * pk)}


## Põe a vaca na pose de pendurada; devolve onde estão os pés de trás (onde a corda amarra).
func pendurar(uid: String, roldana: Vector3, alt: float, base: Dictionary) -> Dictionary:
	var r := pendura_calc(uid, roldana, alt, base)
	if r.is_empty():
		return r
	(_nodes[uid].node as Node3D).global_transform = r.xf
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
			VacaModelo._cascos(n.get_meta("sk"))
	if (base.get("xf0", []) as Array).size() >= 12:
		n.global_transform = _xf_de(base.xf0)
	if (nd.c as Dictionary).has("couro"):
		couro_visual(uid)


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
	if (u < pele) {
		float n1 = ruido(q * 7.0);
		float n2 = ruido(q * 19.0 + vec3(3.1, 1.7, 5.3));
		float fio = abs(sin((q.y * 40.0 + n1 * 3.0)));
		vec3 carne = mix(vec3(0.36, 0.035, 0.03), vec3(0.58, 0.1, 0.075), n1 * 0.7 + fio * 0.3);
		float gord = smoothstep(0.58, 0.74, n2 * 0.65 + n1 * 0.35);
		vec3 col = mix(carne, vec3(0.83, 0.76, 0.64), gord * 0.75);
		float borda = smoothstep(pele - 0.05, pele, u);
		col = mix(col, vec3(0.82, 0.74, 0.7), borda * 0.7);
		ALBEDO = col;
		ROUGHNESS = 0.3;
		SPECULAR = 0.45;
	} else if (u >= corte_ini && u < corte && nn.z < -0.55 && abs(p.x) < largura) {
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
	for b in ks:
		_barriga.append([int(b) * 0.002, float(bins[b])])
	return _barriga


## Onde a barriga está, na malha, na altura y do corpo.
static func _barriga_z(mi: MeshInstance3D, y: float) -> float:
	var pf := _perfil(mi)
	if pf.is_empty():
		return 0.012
	var best := 1e9
	var z := float(pf[0][1])
	for e in pf:
		var d := absf(float(e[0]) - y)
		if d < best:
			best = d
			z = float(e[1])
	return z


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
	return {"mi": mi, "y_rabo": y_rabo, "y_pescoco": y_pes, "u_ini": (y_rabo - y_ini) / (y_rabo - y_pes),
		"cascos": [pos.call("BackFoot_R"), pos.call("BackFoot_L"), pos.call("FrontFoot_R"), pos.call("FrontFoot_L")]}


## O couro na pele (o corte e a carne aparecendo). Faz o material da carcaça na primeira vez.
func couro_visual(uid: String) -> void:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node) or not (nd.node as Node3D).has_meta("sk"):
		return
	var c: Dictionary = nd.c
	var cr: Dictionary = c.get("couro", {})
	if cr.is_empty():
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
	sm.set_shader_parameter("y_rabo", rf.y_rabo)
	sm.set_shader_parameter("y_pescoco", rf.y_pescoco)
	sm.set_shader_parameter("corte_ini", u_ini)
	sm.set_shader_parameter("corte", lerpf(u_ini, 1.0, float(cr.get("corte", 0.0))))
	var pl := float(cr.get("pele", 0.0))
	sm.set_shader_parameter("pele", -9.0 if pl <= 0.0 else lerpf(-0.55, 1.0, pl))
	sm.set_shader_parameter("largura", 0.012 / m_por_u)
	sm.set_shader_parameter("infla", 0.0015 / m_por_u)
	sm.set_shader_parameter("esc", m_por_u)
	sm.set_shader_parameter("r_casco", 0.1 / m_por_u)
	for i in 4:
		sm.set_shader_parameter("casco%d" % i, rf.cascos[i])


## A linha do corte na barriga, no mundo (n pontos, dos pés de trás até o pescoço).
func couro_linha(uid: String, n_pts := 16) -> Array:
	var nd: Dictionary = _nodes.get(uid, {})
	if nd.is_empty() or not is_instance_valid(nd.node):
		return []
	var rf := _couro_ref(nd.node)
	var mi: MeshInstance3D = rf.mi
	var y0 := lerpf(float(rf.y_rabo), float(rf.y_pescoco), float(rf.u_ini))
	var y1 := float(rf.y_pescoco)
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
			_nodes.erase(uid)
	for uid in tem:
		if _nodes.has(uid):
			# (veio de outro celular: os dados novos, o mesmo desenho)
			var cv: Dictionary = tem[uid]
			var mudou: bool = JSON.stringify(cv.get("couro", {})) != JSON.stringify((_nodes[uid].c as Dictionary).get("couro", {}))
			_nodes[uid].c = cv
			if mudou:
				couro_visual(str(uid))
			continue
		var c: Dictionary = tem[uid]
		if (c.get("xf", []) as Array).size() < 12:
			continue                         # (ainda caindo em outro celular)
		var n := _monta(c)
		if n:
			_nodes[uid] = {"node": n, "c": c}
			if c.has("couro"):
				couro_visual(str(uid))
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
