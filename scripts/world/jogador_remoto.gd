extends Node3D
## O personagem de outro jogador (multiplayer): o mesmo modelo e as mesmas animações,
## andando suave até a posição que chega pela rede, com o nome em cima da cabeça.

const ANIMS := {"Idle": "parado", "Walk": "andando", "Run": "correndo"}

var nome := ""
var skin := "homem"
var _anim: AnimationPlayer
var _anim_now := ""
var _label: Label3D
var _body: Node3D
var _alvo := Vector3.ZERO
var _yaw_alvo := 0.0
var _tem_alvo := false


func setup(n: String, s: String) -> void:
	nome = n
	skin = s if s in ["homem", "mulher"] else "homem"
	_body = Node3D.new()
	add_child(_body)
	var bytes := FileAccess.get_file_as_bytes("res://personagem/%s.glbin" % skin)
	var model: Node3D = null
	if not bytes.is_empty():
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) == OK:
			model = doc.generate_scene(state)
	if model == null:
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.7
		cap.mesh = cm
		cap.position.y = 0.85
		_body.add_child(cap)
	else:
		model.rotation.y = PI
		_body.add_child(model)
		for old in model.find_children("*", "AnimationPlayer", true, false):
			old.queue_free()
		_anim = AnimationPlayer.new()
		model.add_child(_anim)
		_anim.root_node = NodePath("..")
		var lib := AnimationLibrary.new()
		for k in ANIMS:
			var a: Animation = load("res://personagem/%s_%s.tres" % [skin, ANIMS[k]])
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(k, a)
		_anim.add_animation_library("", lib)
		play("Idle")
	# o nome em cima da cabeça (sempre virado para quem olha, do mesmo tamanho)
	_label = Label3D.new()
	_label.text = nome
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0018
	_label.font_size = 30
	_label.outline_size = 10
	_label.modulate = Color(1, 0.96, 0.85)
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.no_depth_test = false
	_label.position = Vector3(0, 1.98, 0)
	add_child(_label)


func play(n: String, speed := 1.0) -> void:
	if _anim == null or not _anim.has_animation(n):
		return
	if _anim_now != n:
		_anim.play(n, 0.25)
		_anim_now = n
	_anim.speed_scale = speed


## Estado novo da rede: {p: [x,y,z], y: yaw, a: animação, c: agachado}
func aplicar(e: Dictionary) -> void:
	var p: Array = e.get("p", [0, 0, 0])
	_alvo = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_yaw_alvo = float(e.get("y", 0.0))
	if not _tem_alvo:
		position = _alvo
		rotation.y = _yaw_alvo
		_tem_alvo = true
	play(str(e.get("a", "Idle")), float(e.get("s", 1.0)))
	_body.rotation.x = 0.45 * float(e.get("c", 0.0))      # abaixado (pegando algo do chão)


func _process(delta: float) -> void:
	if not _tem_alvo:
		return
	var k := minf(1.0, delta * 10.0)
	if position.distance_to(_alvo) > 6.0:
		position = _alvo
	else:
		position = position.lerp(_alvo, k)
	rotation.y = lerp_angle(rotation.y, _yaw_alvo, k)
