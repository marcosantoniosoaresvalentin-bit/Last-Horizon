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
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var m = mesh.surface_get_material(s)
			if m is BaseMaterial3D:
				for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "orm_texture", "emission_texture"]:
					if not p in m: continue
					var t = m.get(p)
					if t == null or done.has(t): continue
					var img: Image = t.get_image()
					if img == null: continue
					if img.is_compressed(): img.decompress()
					var mx := 1024 if p == "albedo_texture" else 512
					if img.get_width() > mx:
						img.resize(mx, int(img.get_height() * float(mx) / img.get_width()), Image.INTERPOLATE_LANCZOS)
					var nt := ImageTexture.create_from_image(img)
					m.set(p, nt); done[nt] = true
	var out := GLTFDocument.new(); var os := GLTFState.new()
	out.image_format = "JPEG"
	out.lossy_quality = 0.82
	out.append_from_scene(sc, os)
	print("salvo ", out.write_to_filesystem(os, dst))
	quit()
