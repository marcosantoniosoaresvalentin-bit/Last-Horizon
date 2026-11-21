extends Node3D
## Fogueiras: o fogo aceso com o arco de fogo (na palha do capim seco) pega na lenha.
## Cada lenha posta queima uns 4 minutos; o fogo conta pelo relógio do jogo (o mesmo em
## todos os jogadores), sem precisar mandar nada enquanto queima. Apagada, fica a cinza
## com o carvão (dá para pegar: vai na peneira de água).

const PASSOS_S := 6.0            # passos do relógio por segundo
const LENHA_S := 240.0           # segundos de fogo por lenha
const CAPIM_S := 35.0            # só o capim (sem lenha): logo apaga
const MAX_S := 1500.0
const CARVAO_POR_LENHA := 0.6

## Cada fogueira: {x, z, ate (passo em que apaga), lenha (posta, total), carvao_tirado}
var items: Array = []
var _jogo: Node
var _nodes := {}                 # índice -> {root, fogo, luz, brasa}


func build(jogo: Node, save_path := "") -> void:
	_jogo = jogo
	if save_path != "":
		_load(save_path)
	_rebuild()


func _agora() -> int:
	return int(_jogo.sim.steps)


func acesa(i: int) -> bool:
	return _agora() < int(items[i].ate)


## Segundos de fogo que ainda tem.
func resta(i: int) -> float:
	return maxf(0.0, float(int(items[i].ate) - _agora()) / PASSOS_S)


func near(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in items.size():
		var f: Dictionary = items[i]
		var d := Vector2(float(f.x) - pos.x, float(f.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func center(i: int) -> Vector3:
	var f: Dictionary = items[i]
	return Vector3(float(f.x), _jogo.height_at(float(f.x), float(f.z)), float(f.z))


## Acende (nova, ou a apagada que já está ali). Só o capim queima pouco; com lenha, mais.
func acender(pos: Vector3) -> int:
	var i := near(pos, 0.8)
	if i < 0:
		items.append({"x": snappedf(pos.x, 0.01), "z": snappedf(pos.z, 0.01), "ate": 0, "lenha": 0, "pendente": 0, "carvao_tirado": 0})
		i = items.size() - 1
	var f: Dictionary = items[i]
	var s := CAPIM_S + LENHA_S * float(f.get("pendente", 0))
	f.lenha = int(f.lenha) + int(f.get("pendente", 0))
	f.pendente = 0
	f.ate = _agora() + int(minf(s, MAX_S) * PASSOS_S)
	_rebuild()
	return i


## Põe uma lenha: acesa, queima mais; apagada, fica esperando o fogo.
func por_lenha(i: int) -> void:
	var f: Dictionary = items[i]
	if acesa(i):
		f.lenha = int(f.lenha) + 1
		f.ate = _agora() + int(minf(resta(i) + LENHA_S, MAX_S) * PASSOS_S)
	else:
		f.pendente = int(f.get("pendente", 0)) + 1
	_rebuild()


## Carvão que dá para pegar (só com o fogo apagado, da lenha que queimou).
func carvao(i: int) -> int:
	if acesa(i):
		return 0
	var f: Dictionary = items[i]
	return maxi(0, int(floor(float(f.lenha) * CARVAO_POR_LENHA)) - int(f.carvao_tirado))


func tirar_carvao(i: int) -> int:
	var n := carvao(i)
	items[i].carvao_tirado = int(items[i].carvao_tirado) + n
	_rebuild()
	return n


# ================== DESENHO ==================

static var _mats := {}
static var _soft: GradientTexture2D


## Bolinha macia (o meio claro, a beira some): chama e fumaça sem quadrado.
static func soft_tex() -> GradientTexture2D:
	if _soft == null:
		_soft = GradientTexture2D.new()
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft

static func _mat(k: String) -> StandardMaterial3D:
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	match k:
		"pedra":
			m.albedo_color = Color(0.4, 0.38, 0.35)
			m.roughness = 0.95
		"lenha":
			m.albedo_color = Color(0.36, 0.25, 0.15)
			m.roughness = 0.9
		"carvao":
			m.albedo_color = Color(0.05, 0.05, 0.05)
			m.roughness = 0.8
		"cinza":
			m.albedo_color = Color(0.32, 0.31, 0.3)
			m.roughness = 1.0
		"brasa":
			m.albedo_color = Color(0.2, 0.05, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.3, 0.05)
			m.emission_energy_multiplier = 2.5
		"chama":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.albedo_color = Color(1.0, 0.55, 0.15)
			m.albedo_texture = soft_tex()
	_mats[k] = m
	return m


func _rebuild() -> void:
	for k in _nodes:
		if is_instance_valid(_nodes[k].root):
			(_nodes[k].root as Node).queue_free()
	_nodes.clear()
	for i in items.size():
		_nodes[i] = _fogueira_node(i)
	atualizar()


## A roda de pedras, as achas em cone, a cinza; o fogo (chamas, faíscas e luz) e as
## brasas ligam e desligam em atualizar().
func _fogueira_node(i: int) -> Dictionary:
	var f: Dictionary = items[i]
	var root := Node3D.new()
	add_child(root)
	root.position = center(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(float(f.x) * 31.0 + float(f.z) * 17.0))
	# a roda de pedras
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf() * 0.2
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.06, 0.09)
		sm.radius = r
		sm.height = r * 1.3
		sm.radial_segments = 8
		sm.rings = 4
		var n := MeshInstance3D.new()
		n.mesh = sm
		n.material_override = _mat("pedra")
		n.position = Vector3(cos(a) * 0.36, r * 0.35, sin(a) * 0.36)
		root.add_child(n)
	# a cinza no meio
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.3
	cm.height = 0.02
	var cz := MeshInstance3D.new()
	cz.mesh = cm
	cz.material_override = _mat("cinza")
	cz.position.y = 0.005
	root.add_child(cz)
	# as achas de lenha em cone (as que ainda não queimaram de todo)
	var nl := mini(6, int(f.lenha) + int(f.get("pendente", 0)))
	var lenhas := Node3D.new()
	root.add_child(lenhas)
	for k in maxi(nl, 0):
		var a2 := TAU * k / maxf(nl, 1) + 0.3
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.4, 0.05)
		var ln := MeshInstance3D.new()
		ln.mesh = bm
		ln.material_override = _mat("lenha")
		ln.transform = Transform3D(Basis(Vector3(-sin(a2), 0, cos(a2)), -0.55), Vector3(cos(a2) * 0.1, 0.16, sin(a2) * 0.1))
		lenhas.add_child(ln)
	# carvão na cinza (apagada)
	var carv := Node3D.new()
	root.add_child(carv)
	for k in 7:
		var bm2 := BoxMesh.new()
		var s := rng.randf_range(0.03, 0.05)
		bm2.size = Vector3(s, s * 0.7, s * 1.3)
		var cv := MeshInstance3D.new()
		cv.mesh = bm2
		cv.material_override = _mat("carvao")
		cv.position = Vector3(rng.randf_range(-0.15, 0.15), 0.02, rng.randf_range(-0.15, 0.15))
		cv.rotation.y = rng.randf() * 3.0
		carv.add_child(cv)
	# brasas
	var br := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.12
	bsm.height = 0.06
	br.mesh = bsm
	br.material_override = _mat("brasa")
	br.position.y = 0.03
	root.add_child(br)
	# o fogo: chamas (partículas que sobem e somem), faíscas e a luz
	var fogo := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.26)
	fogo.mesh = qm
	fogo.material_override = _mat("chama")
	fogo.amount = 40
	fogo.lifetime = 0.7
	fogo.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fogo.emission_sphere_radius = 0.12
	fogo.direction = Vector3.UP
	fogo.spread = 12.0
	fogo.gravity = Vector3(0, 1.2, 0)
	fogo.initial_velocity_min = 0.3
	fogo.initial_velocity_max = 0.7
	fogo.scale_amount_min = 0.6
	fogo.scale_amount_max = 1.4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 0.95), Color(1.0, 0.45, 0.08, 0.8), Color(0.6, 0.1, 0.02, 0.0)])
	fogo.color_ramp = grad
	fogo.position.y = 0.08
	root.add_child(fogo)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.6, 0.25)
	luz.light_energy = 2.2
	luz.omni_range = 6.0
	luz.position.y = 0.5
	root.add_child(luz)
	var fumaca := CPUParticles3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(0.3, 0.3)
	fumaca.mesh = qm2
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = soft_tex()
	fumaca.material_override = fm
	fumaca.amount = 14
	fumaca.lifetime = 3.0
	fumaca.direction = Vector3.UP
	fumaca.spread = 15.0
	fumaca.gravity = Vector3(0.15, 0.5, 0)
	fumaca.initial_velocity_min = 0.3
	fumaca.initial_velocity_max = 0.5
	fumaca.scale_amount_min = 1.0
	fumaca.scale_amount_max = 2.5
	var g2 := Gradient.new()
	g2.colors = PackedColorArray([Color(0.5, 0.5, 0.5, 0.35), Color(0.6, 0.6, 0.6, 0.0)])
	fumaca.color_ramp = g2
	fumaca.position.y = 0.6
	root.add_child(fumaca)
	return {"root": root, "fogo": fogo, "luz": luz, "fumaca": fumaca, "brasa": br, "lenhas": lenhas, "carv": carv, "aceso": null}


## Liga/desliga o fogo conforme o relógio (chamada sempre: barata).
func atualizar() -> void:
	for i in _nodes:
		if i >= items.size():
			continue
		var nd: Dictionary = _nodes[i]
		var on := acesa(i)
		var fim := clampf(resta(i) / 30.0, 0.15, 1.0)          # nos últimos 30 s vai baixando
		if nd.aceso != on:
			nd.aceso = on
			(nd.fogo as CPUParticles3D).emitting = on
			(nd.fumaca as CPUParticles3D).emitting = on
			(nd.lenhas as Node3D).visible = on or int(items[i].get("pendente", 0)) > 0
			(nd.carv as Node3D).visible = not on and carvao(i) > 0
			(nd.brasa as Node3D).visible = on
		if on:
			(nd.luz as OmniLight3D).visible = true
			(nd.luz as OmniLight3D).light_energy = (1.6 + 0.6 * sin(Time.get_ticks_msec() / 90.0) + 0.3 * sin(Time.get_ticks_msec() / 37.0)) * fim
			(nd.fogo as CPUParticles3D).scale = Vector3.ONE * lerpf(0.5, 1.0, fim)
		else:
			(nd.luz as OmniLight3D).visible = false


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "fogueiras": items}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	items = d.get("fogueiras", [])
	return true
