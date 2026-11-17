extends Node3D
## Macaco-prego (Sapajus): modelo feito em código e as animações (andar de quatro,
## subir no tronco, sentar e comer).
##
## Corpo uns 40 cm, rabo uns 40 cm. Pelo marrom, mãos/pés e rabo mais escuros,
## rosto e peito claros, o "boné" de pelo escuro em cima da cabeça.
## A frente do macaco é -Z (como o personagem).

var mode := "walk"          # "walk", "sit", "climb"
var speed := 0.0            # m/s (para o passo)
var _t := randf() * 10.0
var _body: Node3D
var _head: Node3D
var _limbs := {}            # "fl", "fr", "bl", "br" -> [ombro/quadril, cotovelo/joelho]
var _tail: Array = []
var _eat := 0.0             # comendo: mão na boca

static var _mats := {}


static func _m(name: String, c: Color, rough := 0.95) -> StandardMaterial3D:
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[name] = m
	return _mats[name]


static func _ball(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cap(parent: Node3D, length: float, r: float, mat: Material) -> MeshInstance3D:
	# cápsula pendurada para baixo (-Y) a partir do pivô
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = length + 2.0 * r
	cm.radial_segments = 8
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(0, -length * 0.5, 0)
	parent.add_child(mi)
	return mi


func _ready() -> void:
	var fur := _m("pelo", Color(0.36, 0.24, 0.13))
	var dark := _m("escuro", Color(0.14, 0.1, 0.07))
	var light := _m("claro", Color(0.78, 0.66, 0.48))
	var skin := _m("pele", Color(0.55, 0.4, 0.3), 0.7)
	var eye := _m("olho", Color(0.05, 0.03, 0.02), 0.2)
	_body = Node3D.new()
	add_child(_body)
	# tronco: meio comprido, deitado ao longo de Z (de quatro)
	_ball(_body, Vector3(0, 0, 0.02), Vector3(0.17, 0.16, 0.34), fur)
	_ball(_body, Vector3(0, -0.03, -0.1), Vector3(0.13, 0.12, 0.16), light)      # peito claro
	# cabeça
	_head = Node3D.new()
	_head.position = Vector3(0, 0.06, -0.2)
	_body.add_child(_head)
	_ball(_head, Vector3.ZERO, Vector3(0.12, 0.12, 0.12), fur)
	_ball(_head, Vector3(0, 0.045, 0.005), Vector3(0.105, 0.05, 0.1), dark)       # boné de pelo
	_ball(_head, Vector3(0, -0.015, -0.045), Vector3(0.085, 0.075, 0.05), light) # rosto
	_ball(_head, Vector3(0, -0.035, -0.065), Vector3(0.045, 0.035, 0.035), skin)  # focinho
	for sx in [-1.0, 1.0]:
		_ball(_head, Vector3(sx * 0.022, -0.002, -0.07), Vector3(0.016, 0.016, 0.01), eye)
		_ball(_head, Vector3(sx * 0.06, 0.01, 0.0), Vector3(0.025, 0.035, 0.015), dark)   # orelha
	# patas: ombro/quadril -> cotovelo/joelho
	for key in ["fl", "fr", "bl", "br"]:
		var front: bool = key.begins_with("f")
		var sx := -1.0 if key.ends_with("l") else 1.0
		var top := Node3D.new()
		top.position = Vector3(sx * 0.065, -0.04, -0.12 if front else 0.15)
		_body.add_child(top)
		_cap(top, 0.1, 0.028, fur)
		var low := Node3D.new()
		low.position = Vector3(0, -0.1, 0)
		top.add_child(low)
		_cap(low, 0.1, 0.022, dark)
		_ball(low, Vector3(0, -0.11, -0.015), Vector3(0.04, 0.025, 0.055), dark)   # mão/pé
		_limbs[key] = [top, low]
	# rabo: 5 pedaços, enrolando na ponta
	var parent: Node3D = _body
	var pos := Vector3(0, 0.03, 0.19)
	for k in 5:
		var seg := Node3D.new()
		seg.position = pos
		parent.add_child(seg)
		var c := _cap(seg, 0.085, 0.022 - k * 0.002, fur if k < 3 else dark)
		c.rotation.x = -PI * 0.5
		c.position = Vector3(0, 0, 0.045)
		_tail.append(seg)
		parent = seg
		pos = Vector3(0, 0, 0.09)


func _process(delta: float) -> void:
	_t += delta
	match mode:
		"walk":
			_pose_walk()
		"climb":
			_pose_climb()
		_:
			_pose_sit(delta)


func _set_limb(key: String, a: float, b: float) -> void:
	var l: Array = _limbs[key]
	(l[0] as Node3D).rotation = Vector3(a, 0, 0)
	(l[1] as Node3D).rotation = Vector3(b, 0, 0)


## De quatro: patas em diagonal juntas, corpo balança um pouco; o rabo em S para cima.
func _pose_walk() -> void:
	var f := _t * (2.0 + speed * 4.5)
	var amp := clampf(speed * 0.6, 0.08, 0.7)
	_body.position = Vector3(0, 0.22 + absf(sin(f)) * 0.015 * amp, 0)
	_body.rotation = Vector3(0, 0, 0)
	_head.rotation = Vector3(0.1 + sin(_t * 0.7) * 0.1, sin(_t * 0.5) * 0.3, 0)
	_set_limb("fl", sin(f) * amp, -0.2 - maxf(0.0, -sin(f)) * amp)
	_set_limb("br", sin(f) * amp, 0.3 + maxf(0.0, -sin(f)) * amp)
	_set_limb("fr", -sin(f) * amp, -0.2 - maxf(0.0, sin(f)) * amp)
	_set_limb("bl", -sin(f) * amp, 0.3 + maxf(0.0, sin(f)) * amp)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(-0.55 if k == 0 else 0.3, sin(_t * 1.5 + k) * 0.15, 0)


## Subindo no tronco: corpo em pé, colado na casca, braços e pernas alternando.
func _pose_climb() -> void:
	var f := _t * 5.0
	_body.position = Vector3(0, 0.0, 0.0)
	_body.rotation = Vector3(PI * 0.5 - 0.1, 0, 0)
	_head.rotation = Vector3(-1.0, 0, 0)
	_set_limb("fl", 1.6 + sin(f) * 0.5, -0.6)
	_set_limb("fr", 1.6 - sin(f) * 0.5, -0.6)
	_set_limb("bl", 1.2 - sin(f) * 0.5, 0.8)
	_set_limb("br", 1.2 + sin(f) * 0.5, 0.8)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(-0.3 if k < 3 else 0.6, sin(_t + k) * 0.1, 0)


## Sentado: corpo em pé, pernas dobradas na frente, de vez em quando leva a mão à boca
## (comendo fruta), olha em volta; o rabo enrola no chão/galho.
func _pose_sit(delta: float) -> void:
	_eat = move_toward(_eat, 1.0 if fmod(_t, 4.0) < 1.6 else 0.0, delta * 3.0)
	_body.position = Vector3(0, 0.16, 0.05)
	_body.rotation = Vector3(1.15, 0, 0)
	_head.rotation = Vector3(-1.0, sin(_t * 0.6) * 0.6, 0)
	_set_limb("bl", 2.2, -2.0)
	_set_limb("br", 2.2, -2.0)
	_set_limb("fl", 0.9, -0.4)
	_set_limb("fr", lerpf(0.9, 2.3, _eat), lerpf(-0.4, -2.2, _eat) + sin(_t * 9.0) * 0.08 * _eat)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(0.9 if k == 0 else 0.25, 0.35, 0)
