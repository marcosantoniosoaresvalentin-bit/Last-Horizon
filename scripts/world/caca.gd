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
var _pingos: Array = []           # bichos feridos pingando: {node, t, resto}
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
	# carcaças caindo e a vaca morrendo
	for uid in _nodes:
		var nd: Dictionary = _nodes[uid]
		if nd.has("cai"):
			_cair(nd, delta)
	# poças de sangue crescendo
	for p in _poças.duplicate():
		p.r = move_toward(float(p.r), float(p.alvo), delta * 0.03)
		(p.node as Node3D).scale = Vector3(float(p.r), 1.0, float(p.r))
		if float(p.r) >= float(p.alvo):
			_poças.erase(p)
	# o bicho ferido pingando sangue no chão enquanto foge
	for pg in _pingos.duplicate():
		if not is_instance_valid(pg.node):
			_pingos.erase(pg)
			continue
		pg.t = float(pg.t) - delta
		pg.resto = float(pg.resto) - delta
		if float(pg.t) <= 0.0:
			pg.t = _rng.randf_range(0.25, 0.7)
			var q: Vector3 = (pg.node as Node3D).global_position + Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))
			_mancha_chao(q, _rng.randf_range(0.03, 0.07), false)
		if float(pg.resto) <= 0.0:
			_pingos.erase(pg)


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
			for pt in [[Vector3(0.4, 0.95, 0), 0.3, 80.0, "peito"], [Vector3(-0.02, 0.95, 0), 0.34, 35.0, "barriga"], [Vector3(-0.48, 1.0, 0), 0.3, 30.0, "anca"],
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
	# o sangue: a mancha onde entrou e o escorrido
	_mancha_bicho(pai, ponto, dir)
	hit["pai"] = pai
	if total >= float(hit.vida):
		_morrer(hit, ponto, dir)
	else:
		_assusta(hit)
		_pingos.append({"node": n, "t": 0.2, "resto": clampf(dano / 6.0, 4.0, 25.0)})


func _assusta(hit: Dictionary) -> void:
	var j = _jogo
	var pp: Vector3 = j._player.global_position
	match str(hit.esp):
		"vaca":
			var v: Dictionary = j._vacas._find(int(hit.id))
			if not v.is_empty():
				j._vacas._assusta(int(v.reb), pp)
		"tamandua":
			var a: Dictionary = j._tamanduas._agents.get(int(hit.id), {})
			if not a.is_empty():
				var b: Dictionary = j._tamanduas._find(int(hit.id))
				var pos := Vector3(float(b.x), 0, float(b.z))
				a.alvo = pos + Vector3(pos.x - pp.x, 0, pos.z - pp.z).normalized() * 25.0
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
	if esp == "vaca" and n.has_meta("ap"):
		var ap: AnimationPlayer = n.get_meta("ap")
		ap.play(VacaModelo.ANIMS.morrer, 0.15)
		nd["ap"] = ap
	_nodes[uid] = nd
	Sons.play_at(j, "baque", n.global_position, -2.0, 0.7)


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

static func _mat(k: String) -> StandardMaterial3D:
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	match k:
		"sangue":
			m.albedo_color = Color(0.36, 0.02, 0.025)
			m.roughness = 0.35
			m.metallic_specular = 0.35
		"poca":
			m.albedo_color = Color(0.46, 0.04, 0.025)
			m.roughness = 0.55
			m.metallic_specular = 0.2
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
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


## A mancha de sangue no couro onde a flecha entrou, e o sangue escorrendo para baixo.
func _mancha_bicho(n: Node3D, ponto: Vector3, dir: Vector3) -> void:
	var inv := n.global_transform.affine_inverse()
	var sc := n.global_transform.basis.get_scale().x
	# a mancha achatada contra o couro (o eixo fino na direção da flecha), com respingos
	var yax := -dir.normalized()
	var xax := yax.cross(Vector3.UP if absf(yax.y) < 0.95 else Vector3.RIGHT).normalized()
	var zax := xax.cross(yax)
	for k in 5:
		var mancha := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := 0.05 if k == 0 else _rng.randf_range(0.012, 0.025)
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 10
		sm.rings = 4
		mancha.mesh = sm
		mancha.material_override = _mat("sangue")
		n.add_child(mancha)
		var off := Vector3.ZERO if k == 0 else (xax * _rng.randf_range(-1, 1) + zax * _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.05, 0.09)
		mancha.global_transform = Transform3D(Basis(xax, yax * 0.12, zax), ponto - dir * 0.005 + off)
	if false:
		var lp := inv * ponto
		print(lp)
	# escorrendo: uns filetes descendo pelo couro
	for k in _rng.randi_range(2, 4):
		var fio := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var L := _rng.randf_range(0.08, 0.22)
		cm.top_radius = 0.009
		cm.bottom_radius = 0.004
		cm.height = L
		cm.radial_segments = 5
		cm.rings = 1
		fio.mesh = cm
		fio.material_override = _mat("sangue")
		var off := Vector3(_rng.randf_range(-0.03, 0.03), 0, _rng.randf_range(-0.03, 0.03))
		var base_w := ponto - dir * 0.015 + off + Vector3.DOWN * L * 0.5
		n.add_child(fio)
		fio.global_transform = Transform3D(Basis.from_euler(Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))), base_w)


## Mancha de sangue no chão (gota ou poça que vai crescendo).
func _mancha_chao(p: Vector3, r: float, cresce: bool) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _poca_mesh(_rng.randi() % 1000)
	n.material_override = _mat("poca")
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	var gy: float = _jogo.ground_at(p.x, p.z)
	n.global_position = Vector3(p.x, gy + 0.012, p.z)
	n.rotation.y = _rng.randf() * TAU
	if cresce:
		n.scale = Vector3(0.05, 1, 0.05)
		_poças.append({"node": n, "r": 0.05, "alvo": r})
	else:
		n.scale = Vector3(r, 1, r)
	_manchas.append(n)
	while _manchas.size() > 120:
		var velha: Node3D = _manchas.pop_front()
		if is_instance_valid(velha):
			velha.queue_free()

var _manchas: Array = []


## Disco irregular de raio ~1 (a escala dá o tamanho).
static func _poca_mesh(seed_: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var n := 28
	var rs := []
	for k in n:
		rs.append(0.0)
	# borda irregular mas lisa (somando ondas)
	var f1 := rng.randf() * TAU
	var f2 := rng.randf() * TAU
	for k in n:
		var a := TAU * k / n
		rs[k] = 0.85 + 0.12 * sin(a * 3.0 + f1) + 0.07 * sin(a * 5.0 + f2)
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * float(rs[(k + 1) % n]))
		st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * float(rs[k]))
	return st.commit()


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
			continue
		var c: Dictionary = tem[uid]
		if (c.get("xf", []) as Array).size() < 12:
			continue                         # (ainda caindo em outro celular)
		var n := _monta(c)
		if n:
			_nodes[uid] = {"node": n, "c": c}
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
