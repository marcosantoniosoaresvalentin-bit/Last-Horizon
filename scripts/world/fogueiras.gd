extends Node3D
## Fogueiras: o fogo aceso (com o arco de fogo, no capim seco) só continua com lenha.
## A lenha no fogo é o combustível: quanto mais lenha, mais forte (chama maior, mais luz)
## e mais tempo queima; mas fogo forte come a lenha mais depressa (o tempo não cresce na
## mesma conta). Parou de pôr lenha: vai baixando e apaga. Apagou: fica a brasa por uns
## minutos (pondo capim seco nela, o fogo reacende sem o arco); a brasa acabou: fria, só
## acende de novo com o arco. A chuva apaga o fogo e a brasa. Fria, a cinza tem o carvão
## da lenha que queimou. Tudo conta pelo relógio do jogo (o mesmo em todos os jogadores).
##
## Combustível F (em lenhas) queimando: dF/dt = -(A + B*F) por minuto (de verdade, no
## jogo): 1 lenha dura uns 3 min; 4 lenhas, uns 8 min; 8 lenhas, uns 12 min. Só o capim
## (0,15) uns 35 s.

const PASSOS_S := 6.0            # passos do relógio por segundo
const A := 0.25                  # lenha por minuto que um fogo bem pequeno gasta
const B := 0.15                  # e o quanto a mais, pelo tamanho do fogo
const CAPIM := 0.15              # o capim seco (em "lenhas")
const MAX_F := 10.0
const BRASA_MIN := 2.0           # minutos de brasa depois que as chamas apagam (mais com mais lenha)
const BRASA_MAX := 6.0
const CARVAO_POR_LENHA := 0.6

## Cada fogueira: {x, z, f0 (combustível no t0), t0 (passo), aceso (chamas desde o t0),
## lenha (queimada, total), pendente (posta com ela fria), carvao_tirado, frio_em (passo
## em que apagou de vez: chuva)}
var items: Array = []
var _jogo: Node
var _nodes := {}                 # índice -> {root, fogo, luz, brasa, ...}


func build(jogo: Node, save_path := "") -> void:
	_jogo = jogo
	if save_path != "":
		_load(save_path)
	_rebuild()


func _agora() -> int:
	return int(_jogo.sim.steps)


func _min_desde(t0: int) -> float:
	return maxf(0.0, float(_agora() - t0)) / PASSOS_S / 60.0


## Quanto tempo (min) as chamas duram com f de combustível.
static func dura(f: float) -> float:
	if f <= 0.0:
		return 0.0
	return log((f + A / B) / (A / B)) / B


## Combustível queimando agora (0: sem chamas).
func fogo(i: int) -> float:
	var it: Dictionary = items[i]
	if not bool(it.get("aceso", false)):
		return 0.0
	var t := _min_desde(int(it.t0))
	var f := (float(it.f0) + A / B) * exp(-B * t) - A / B
	return maxf(0.0, f)


func acesa(i: int) -> bool:
	return fogo(i) > 0.001


## Só brasa (as chamas apagaram há pouco).
func brasa(i: int) -> bool:
	var it: Dictionary = items[i]
	if not bool(it.get("aceso", false)) or acesa(i):
		return false
	var fim_chama := float(it.t0) + dura(float(it.f0)) * 60.0 * PASSOS_S
	var bmin := clampf(BRASA_MIN + float(it.get("lenha_ciclo", 0)) * 0.4, BRASA_MIN, BRASA_MAX)
	return float(_agora()) < fim_chama + bmin * 60.0 * PASSOS_S


func fria(i: int) -> bool:
	return not acesa(i) and not brasa(i)


## Segundos de chama que ainda tem (se ninguém puser mais lenha).
func resta(i: int) -> float:
	var f := fogo(i)
	return dura(f) * 60.0


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


## Começa as chamas com f de combustível (o que já tinha posto entra junto).
func _pega(i: int, f: float) -> void:
	var it: Dictionary = items[i]
	var pend := int(it.get("pendente", 0))
	it.lenha = int(it.get("lenha", 0)) + pend
	it.lenha_ciclo = pend
	it.pendente = 0
	it.f0 = minf(f + float(pend), MAX_F)
	it.t0 = _agora()
	it.aceso = true


## Acendeu com o arco (nova fogueira, ou a que está ali).
func acender(pos: Vector3) -> int:
	var i := near(pos, 0.8)
	if i < 0:
		items.append({"x": snappedf(pos.x, 0.01), "z": snappedf(pos.z, 0.01), "f0": 0.0, "t0": 0, "aceso": false, "lenha": 0, "pendente": 0, "carvao_tirado": 0})
		i = items.size() - 1
	_pega(i, CAPIM)
	_rebuild()
	return i


## Capim seco na brasa: o fogo volta.
func reacender(i: int) -> void:
	_pega(i, CAPIM)
	_rebuild()


## Põe uma lenha: queimando, o fogo cresce; fria ou só brasa, fica esperando o fogo.
func por_lenha(i: int, acha := {}) -> void:
	var it: Dictionary = items[i]
	if not acha.is_empty():
		if not it.has("achas"):
			it["achas"] = []
		(it.achas as Array).append(acha)       # a mesma acha que o jogador rachou
		while (it.achas as Array).size() > 12:
			(it.achas as Array).pop_front()
	if acesa(i):
		it.f0 = minf(fogo(i) + 1.0, MAX_F)
		it.t0 = _agora()
		it.lenha = int(it.lenha) + 1
		it.lenha_ciclo = int(it.get("lenha_ciclo", 0)) + 1
	else:
		it.pendente = int(it.get("pendente", 0)) + 1
	_rebuild()


## A chuva apaga (o fogo e a brasa).
func apagar(i: int) -> void:
	var it: Dictionary = items[i]
	it.aceso = false
	it.f0 = 0.0
	_rebuild()


## Carvão da lenha que queimou (só com a cinza fria).
func carvao(i: int) -> int:
	if not fria(i):
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
			m.albedo_color = Color(0.16, 0.15, 0.14)       # cinza e chão queimado
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
	# a cinza no meio
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.3
	cm.height = 0.012
	var cz := MeshInstance3D.new()
	cz.mesh = cm
	cz.material_override = _mat("cinza")
	cz.position.y = 0.005
	root.add_child(cz)
	# as achas (as mesmas que o jogador rachou e pôs): deitadas em volta, com a ponta de
	# dentro (a que vai no fogo) um pouco levantada em cima do meio
	var lenhas := Node3D.new()
	root.add_child(lenhas)
	var achas: Array = f.get("achas", [])
	var nl := _n_achas(i)
	var arv = _jogo._arvores
	for k in nl:
		var acha: Dictionary = achas[achas.size() - nl + k] if achas.size() >= nl else {}
		if acha.is_empty() or arv == null:
			continue
		var ln: Node3D = arv.free_log_node(acha)
		var L: float = arv.free_log_length(acha)
		var r: float = arv.free_log_radius(acha)
		var a2 := TAU * k / maxf(nl, 1) + 0.35 + (0.25 if k % 2 == 1 else 0.0)
		var fora := Vector3(cos(a2), 0, sin(a2))
		var p_in := fora * 0.05 + Vector3.UP * (0.1 + r * 0.6)          # a ponta do fogo, levantada
		var horiz := sqrt(maxf(L * L - pow(p_in.y - r * 0.8, 2.0), 0.01))
		var p_out := fora * (0.05 + horiz) + Vector3.UP * (r * 0.8)        # a outra ponta no chão
		var x := (p_in - p_out).normalized()
		var zz := x.cross(Vector3.UP).normalized()
		var yy := zz.cross(x).normalized()
		ln.transform = Transform3D(Basis(x, yy, zz) * Basis(Vector3.RIGHT, float(k) * 1.3), (p_in + p_out) * 0.5)
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
	# o chama: chamas (partículas que sobem e somem), faíscas e a luz
	var chama := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.26)
	chama.mesh = qm
	chama.material_override = _mat("chama")
	chama.amount = 40
	chama.lifetime = 0.7
	chama.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chama.emission_sphere_radius = 0.12
	chama.direction = Vector3.UP
	chama.spread = 12.0
	chama.gravity = Vector3(0, 1.2, 0)
	chama.initial_velocity_min = 0.3
	chama.initial_velocity_max = 0.7
	chama.scale_amount_min = 0.6
	chama.scale_amount_max = 1.4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 0.95), Color(1.0, 0.45, 0.08, 0.8), Color(0.6, 0.1, 0.02, 0.0)])
	chama.color_ramp = grad
	chama.position.y = 0.08
	root.add_child(chama)
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
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA       # com luz: o fogo clareia a fumaça por baixo
	fm.roughness = 1.0
	fm.disable_fog = true
	fm.emission_enabled = true
	fm.emission = Color(0.22, 0.21, 0.2)       # nunca fica preta (de noite, cinza escura)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = soft_tex()
	fumaca.material_override = fm
	fumaca.amount = 14
	fumaca.lifetime = 3.0
	fumaca.direction = Vector3.UP
	fumaca.spread = 15.0
	fumaca.gravity = Vector3(0.15, 0.5, 0)
	fumaca.initial_velocity_min = 0.5
	fumaca.initial_velocity_max = 0.8
	fumaca.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fumaca.emission_sphere_radius = 0.15
	fumaca.scale_amount_min = 1.0
	fumaca.scale_amount_max = 2.5
	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g2.colors = PackedColorArray([Color(0.75, 0.75, 0.75, 0.0), Color(0.75, 0.75, 0.75, 0.3), Color(0.8, 0.8, 0.8, 0.0)])
	fumaca.color_ramp = g2
	fumaca.position.y = 0.75
	root.add_child(fumaca)
	return {"root": root, "fogo": chama, "luz": luz, "fumaca": fumaca, "brasa": br, "lenhas": lenhas, "carv": carv, "n": nl}


## Quantas achas aparecem: as que ainda estão queimando (ou as postas esperando o fogo).
func _n_achas(i: int) -> int:
	var f: Dictionary = items[i]
	var n := int(ceil(fogo(i) - 0.15)) if acesa(i) else 0
	n += int(f.get("pendente", 0))
	return clampi(n, 0, mini(8, (f.get("achas", []) as Array).size()))


## O fogo conforme o relógio (chamada sempre: barata): o tamanho da chama e a luz vão
## com a lenha no fogo; só brasa, o vermelho pulsando; fria, a cinza com o carvão.
func atualizar() -> void:
	for i in _nodes:
		if i >= items.size():
			continue
		var nd: Dictionary = _nodes[i]
		if int(nd.get("n", -1)) != _n_achas(i):
			_rebuild()                        # uma acha acabou de queimar (ou entrou mais uma)
			return
		var f := fogo(i)
		var on := f > 0.001
		var br := brasa(i)
		var est := "fogo" if on else ("brasa" if br else "fria")
		if nd.get("est", "") != est:
			nd.est = est
			(nd.fogo as CPUParticles3D).emitting = on
			(nd.fumaca as CPUParticles3D).emitting = on or br
			(nd.lenhas as Node3D).visible = on or int(items[i].get("pendente", 0)) > 0
			(nd.carv as Node3D).visible = est == "fria" and carvao(i) > 0
			(nd.brasa as Node3D).visible = on or br
		var forca := clampf(0.35 + f * 0.22, 0.35, 1.6)          # mais lenha, fogo maior
		if on:
			(nd.luz as OmniLight3D).visible = true
			(nd.luz as OmniLight3D).light_energy = (1.2 + 0.5 * sin(Time.get_ticks_msec() / 90.0) + 0.25 * sin(Time.get_ticks_msec() / 37.0)) * forca
			(nd.luz as OmniLight3D).omni_range = 3.5 + 3.0 * forca
			(nd.fogo as CPUParticles3D).scale = Vector3.ONE * forca
			(nd.fogo as CPUParticles3D).amount = 40
			(nd.brasa as Node3D).scale = Vector3.ONE
		elif br:
			# só brasa: um vermelhinho pulsando, quase sem luz
			(nd.luz as OmniLight3D).visible = true
			(nd.luz as OmniLight3D).light_energy = 0.35 + 0.2 * sin(Time.get_ticks_msec() / 400.0)
			(nd.luz as OmniLight3D).omni_range = 1.6
			(nd.brasa as Node3D).scale = Vector3(1.0, 0.6, 1.0)
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
	for it in items:
		if not it.has("f0"):
			it["f0"] = 0.0                 # fogueira da versão anterior: fria
			it["t0"] = 0
			it["aceso"] = false
	return true
