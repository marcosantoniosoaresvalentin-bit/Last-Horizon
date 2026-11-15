extends SceneTree
## Diminui as texturas de um .glb para 1024 px e salva de novo (fica leve para celular).
func _init():
	var src = OS.get_environment("ENTRADA"); var dst = OS.get_environment("SAIDA")
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.append_from_buffer(FileAccess.get_file_as_bytes(src), "", st)
	var sc: Node = doc.generate_scene(st)
	var done := {}
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		# tira as expressões do rosto (blend shapes): pesam muito e o jogo não usa
		var old: ArrayMesh = mi.mesh
		var nm := ArrayMesh.new()
		for s in old.get_surface_count():
			nm.add_surface_from_arrays(old.surface_get_primitive_type(s), old.surface_get_arrays(s))
			nm.surface_set_material(s, old.surface_get_material(s))
		mi.mesh = nm
		for s in nm.get_surface_count():
			var m = nm.surface_get_material(s)
			if not (m is BaseMaterial3D):
				continue
			# no celular fica só a cor: sem mapas de relevo, brilho e metal
			for p in ["normal_texture", "roughness_texture", "metallic_texture", "orm_texture", "emission_texture", "ao_texture", "clearcoat_texture", "subsurf_scatter_texture"]:
				if p in m: m.set(p, null)
			if "normal_enabled" in m: m.normal_enabled = false
			if "ao_enabled" in m: m.ao_enabled = false
			if "emission_enabled" in m: m.emission_enabled = false
			m.roughness = 0.75
			m.metallic = 0.0
			var t = m.albedo_texture
			if t == null:
				continue
			var key = t.get_rid()
			if done.has(key):
				m.albedo_texture = done[key]
				continue
			var img: Image = t.get_image()
			if img == null:
				continue
			if img.is_compressed(): img.decompress()
			if img.get_width() > 512:
				img.resize(512, int(img.get_height() * 512.0 / img.get_width()), Image.INTERPOLATE_LANCZOS)
			var nt := ImageTexture.create_from_image(img)
			done[key] = nt
			m.albedo_texture = nt
	var out := GLTFDocument.new(); var os := GLTFState.new()
	out.image_format = "JPEG"
	out.lossy_quality = 0.82
	out.append_from_scene(sc, os)
	print("salvo ", out.write_to_filesystem(os, dst))
	quit()
