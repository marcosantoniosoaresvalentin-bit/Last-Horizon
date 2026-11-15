extends SceneTree
## Junta todas as malhas animadas de um personagem numa malha só, com um único "skin".
## Tira partes que não aparecem (dentes, língua, sombra dos olhos, cílios) e troca
## transparências pesadas por recorte simples. Muitos celulares Android travam com
## várias malhas animadas separadas.
const DROP := ["teeth", "tongue", "eyeao", "eyelash"]

func _init():
	var src = OS.get_environment("ENTRADA"); var dst = OS.get_environment("SAIDA")
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.append_from_buffer(FileAccess.get_file_as_bytes(src), "", st)
	var sc: Node = doc.generate_scene(st)
	root.add_child(sc)
	var mis = sc.find_children("*", "MeshInstance3D", true, false)
	var first: MeshInstance3D = null
	var skin := Skin.new()
	var mesh := ArrayMesh.new()
	for mi: MeshInstance3D in mis:
		var low := String(mi.name).to_lower()
		var skip := false
		for d in DROP:
			if d in low: skip = true
		if skip:
			continue
		if first == null:
			first = mi
		var sk: Skin = mi.skin
		var remap := PackedInt32Array(); remap.resize(sk.get_bind_count())
		for b in sk.get_bind_count():
			var bone := sk.get_bind_bone(b)
			var nm := sk.get_bind_name(b)
			var pose := sk.get_bind_pose(b)
			var found := -1
			for j in skin.get_bind_count():
				if skin.get_bind_bone(j) == bone and skin.get_bind_name(j) == nm and skin.get_bind_pose(j).is_equal_approx(pose):
					found = j; break
			if found < 0:
				skin.add_bind(bone, pose)
				found = skin.get_bind_count() - 1
				if nm != &"":
					skin.set_bind_name(found, nm)
			remap[b] = found
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			arr[Mesh.ARRAY_TANGENT] = null
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			for k in bones.size():
				bones[k] = remap[bones[k]]
			arr[Mesh.ARRAY_BONES] = bones
			# posição da malha no modelo (algumas têm deslocamento próprio)
			mesh.add_surface_from_arrays(m.surface_get_primitive_type(s), arr)
			var mat = m.surface_get_material(s)
			if mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.4
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	first.mesh = mesh
	first.skin = skin
	for mi in mis:
		if mi != first:
			mi.get_parent().remove_child(mi)
			mi.free()
	print("superficies ", mesh.get_surface_count(), " binds ", skin.get_bind_count())
	var out := GLTFDocument.new(); var os := GLTFState.new()
	out.image_format = "JPEG"
	out.lossy_quality = 0.82
	sc.get_parent().remove_child(sc)
	out.append_from_scene(sc, os)
	print("salvo ", out.write_to_filesystem(os, dst))
	quit()
