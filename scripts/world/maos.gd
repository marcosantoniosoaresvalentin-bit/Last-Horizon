extends RefCounted
## Mão em primeira pessoa (na hora de modelar pedra só aparece a mão e a pedra de bater).
##
## Espaço da mão: X = direita, Y = para cima, Z = para trás (os dedos apontam para -Z).
## A mão direita está de palma para baixo, fechada em volta da pedra de bater.

const Lascar := preload("res://scripts/world/lascar.gd")
const STONE := Vector3(0.0, -0.05, -0.055)      # centro da pedra de bater (na mão)
const CONTACT := Vector3(0.0, -0.09, -0.07)     # onde a pedra encosta quando bate


static func _mat(c: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.2
	return m


## Um "osso" arredondado de a até b (cápsula).
static func _bone(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = (b - a).length() + 2.0 * r
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Monta a mão direita segurando a pedra de bater (Node3D com as peças).
static func right_hand(skin: Color, sleeve: Color, with_stone := true) -> Node3D:
	var root := Node3D.new()
	var sk := _mat(skin, 0.65)
	var cl := _mat(sleeve, 0.9)
	# antebraço e manga (somem para fora da tela, para trás)
	_bone(root, Vector3(0, 0.012, 0.03), Vector3(0.01, 0.04, 0.3), 0.036, sk)
	var sl := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.05
	cy.bottom_radius = 0.056
	cy.height = 1.1
	sl.mesh = cy
	sl.material_override = cl
	var d := (Vector3(0.012, 0.05, 0.48) - Vector3(0.006, 0.03, 0.18)).normalized()
	var x := d.cross(Vector3.RIGHT).normalized()
	sl.transform = Transform3D(Basis(x, d, x.cross(d).normalized()), Vector3(0.012, 0.06, 0.71))
	root.add_child(sl)
	# palma (meio achatada) e as costas da mão
	var palm := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.05
	sp.height = 0.1
	palm.mesh = sp
	palm.material_override = sk
	palm.transform = Transform3D(Basis().scaled(Vector3(0.95, 0.5, 1.05)), Vector3(0, 0.004, -0.01))
	root.add_child(palm)
	# quatro dedos fechados em volta da pedra (de cima, descendo e voltando por baixo)
	for k in 4:
		var fx := -0.03 + k * 0.02
		var lr := 1.0 - absf(k - 1.5) * 0.08
		var kn := Vector3(fx, 0.006, -0.055)
		var j1 := Vector3(fx, -0.02, -0.085 * lr)
		var j2 := Vector3(fx * 0.95, -0.058, -0.088 * lr)
		var tip := Vector3(fx * 0.9, -0.08, -0.07 * lr)
		_bone(root, kn, j1, 0.0105, sk)
		_bone(root, j1, j2, 0.0098, sk)
		_bone(root, j2, tip, 0.009, sk)
	# polegar (do lado esquerdo da mão direita), segurando a pedra pelo lado
	_bone(root, Vector3(-0.035, -0.005, 0.005), Vector3(-0.05, -0.03, -0.03), 0.012, sk)
	_bone(root, Vector3(-0.05, -0.03, -0.03), Vector3(-0.04, -0.05, -0.06), 0.011, sk)
	if not with_stone:
		return root
	# a pedra de bater, presa na mão
	var st := MeshInstance3D.new()
	st.mesh = Lascar.cobble_mesh(77, 0.1)
	st.material_override = Lascar.material()
	st.position = STONE
	st.rotation = Vector3(0.3, 0.4, 0.2)
	root.add_child(st)
	return root
