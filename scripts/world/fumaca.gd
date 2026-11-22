extends Node3D
## Fumaça feita à mão (sem CPUParticles): uns poucos "flocos" (quadrados virados para a
## câmera com uma textura redonda e suave) que nascem no ponto, sobem, se espalham com o
## vento e somem. Cada floco tem o próprio material com cor cinza fixa, então a cor nunca
## depende das cores de partícula (que em alguns celulares saíam verdes).

var emitting := false
var n := 24                  # quantos flocos ao mesmo tempo
var vida := 12.0             # segundos que cada floco dura
var tam0 := 0.5              # tamanho ao nascer (m)
var tam1 := 4.2              # tamanho no fim
var subida := 0.9            # m/s para cima
var vento := Vector3(0.35, 0.0, 0.08)
var cor := Color(0.68, 0.67, 0.65)
var alfa := 0.75

var _fl: Array = []          # [{mi, idade, x, z}]
var _acum := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(get_instance_id())
	var tex: Texture2D = load("res://scripts/world/fogueiras.gd").soft_tex()
	for i in n:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = tex
		m.albedo_color = Color(cor.r, cor.g, cor.b, 0.0)
		m.disable_fog = true
		m.no_depth_test = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_fl.append({"mi": mi, "idade": -1.0, "x": 0.0, "z": 0.0, "v": 1.0})


func _process(dt: float) -> void:
	if emitting:
		_acum += dt * float(n) / vida
		while _acum >= 1.0:
			_acum -= 1.0
			_nasce()
	var ativo := false
	for f in _fl:
		if float(f.idade) < 0.0:
			continue
		f.idade = float(f.idade) + dt
		var mi: MeshInstance3D = f.mi
		var k := float(f.idade) / vida
		if k >= 1.0:
			f.idade = -1.0
			mi.visible = false
			continue
		ativo = true
		var t := float(f.idade)
		# sobe cada vez mais devagar e o vento leva cada vez mais
		mi.position = Vector3(float(f.x), subida * float(f.v) * t * (1.0 - 0.3 * k), float(f.z)) + vento * t * t * 0.12
		var s := lerpf(tam0, tam1, sqrt(k))
		mi.scale = Vector3(s, s, s)
		# aparece rápido, fica e vai sumindo devagar
		var a := alfa * clampf(k / 0.08, 0.0, 1.0) * (1.0 - k) * (1.0 - k * 0.3)
		var c := cor.lerp(Color(0.85, 0.85, 0.84), k)
		(mi.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, a)
	set_process(emitting or ativo)


func _nasce() -> void:
	for f in _fl:
		if float(f.idade) < 0.0:
			f.idade = 0.0
			f.x = _rng.randf_range(-0.08, 0.08)
			f.z = _rng.randf_range(-0.08, 0.08)
			f.v = _rng.randf_range(0.8, 1.2)
			(f.mi as MeshInstance3D).visible = true
			return


func set_emitting(on: bool) -> void:
	emitting = on
	if on:
		set_process(true)
