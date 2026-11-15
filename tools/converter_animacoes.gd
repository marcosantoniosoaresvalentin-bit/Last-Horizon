extends SceneTree
## Converte as animações do Soldier (Mixamo) para o esqueleto de outro personagem Mixamo.
func load_glb(f):
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.append_from_buffer(FileAccess.get_file_as_bytes(f), "", st)
	return doc.generate_scene(st)

func _init():
	var tgt_file = OS.get_environment("ALVO")
	var src = load_glb("res://Soldier.glb"); root.add_child(src)
	var tgt = load_glb(tgt_file); root.add_child(tgt)
	await process_frame
	var sk_s: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var sk_t: Skeleton3D = tgt.find_children("*", "Skeleton3D", true, false)[0]
	var aps_t = tgt.find_children("*", "AnimationPlayer", true, false)
	var ap_t: AnimationPlayer = aps_t[0] if aps_t.size() else null
	var pre := "mixamorig_" if sk_t.find_bone("mixamorig_Hips") >= 0 else ""
	var ap_s: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var gs: Transform3D = sk_s.global_transform
	var gt: Transform3D = sk_t.global_transform
	# pose de referência (T) dos dois personagens, em vez da pose de repouso
	ap_s.play("TPose"); ap_s.seek(0.0, true); sk_s.force_update_all_bone_transforms()
	var ref_s := {}
	for b in sk_s.get_bone_count(): ref_s[b] = gs * sk_s.get_bone_global_pose(b)
	var ref_t := {}
	if ap_t and ap_t.has_animation("TPose"):
		ap_t.play("TPose"); ap_t.seek(0.0, true); sk_t.force_update_all_bone_transforms()
		for b in sk_t.get_bone_count(): ref_t[b] = gt * sk_t.get_bone_global_pose(b)
		ap_t.stop()
	else:
		# sem animação de pose T: o modelo já vem em pose T no repouso
		for b in sk_t.get_bone_count(): ref_t[b] = gt * sk_t.get_bone_global_rest(b)
	# alinha a "frente" dos dois corpos (eles podem estar virados para lados diferentes)
	var frame = func(ref: Dictionary, sk: Skeleton3D) -> Basis:
		var p := "mixamorig_" if sk.find_bone("mixamorig_Hips") >= 0 else ""
		var x: Vector3 = (ref[sk.find_bone(p + "LeftHand")].origin - ref[sk.find_bone(p + "RightHand")].origin).normalized()
		var y: Vector3 = (ref[sk.find_bone(p + "Head")].origin - ref[sk.find_bone(p + "Hips")].origin).normalized()
		var z := x.cross(y).normalized()
		y = z.cross(x).normalized()
		return Basis(x, y, z)
	var F_s: Basis = frame.call(ref_s, sk_s)
	var F_t: Basis = frame.call(ref_t, sk_t)
	var Mb: Basis = F_t * F_s.inverse()
	# mapa de ossos pelo nome
	var map := {}
	for b in sk_t.get_bone_count():
		var sb := sk_s.find_bone("mixamorig_" + sk_t.get_bone_name(b).trim_prefix(pre))
		if sb >= 0: map[b] = sb
	var hips_t := sk_t.find_bone(pre + "Hips"); var hips_s := sk_s.find_bone("mixamorig_Hips")
	var rest_s_h: Vector3 = ref_s[hips_s].origin
	var rest_t_h: Vector3 = ref_t[hips_t].origin
	var ratio := rest_t_h.y / rest_s_h.y
	print("ossos mapeados ", map.size(), "/", sk_t.get_bone_count(), " altura quadril ", rest_s_h.y, " -> ", rest_t_h.y)
	var skel_path := String(tgt.get_path_to(sk_t))
	var names = {"Idle": "parado", "Walk": "andando", "Run": "correndo"}
	for name in names:
		var a_s: Animation = ap_s.get_animation(name)
		var out := Animation.new()
		out.length = a_s.length
		out.loop_mode = Animation.LOOP_LINEAR
		var tr := {}
		for b in map:
			var t := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t, NodePath(skel_path + ":" + sk_t.get_bone_name(b)))
			tr[b] = t
		var tp := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(tp, NodePath(skel_path + ":" + pre + "Hips"))
		ap_s.play(name)
		var fps := 30.0
		var frames := int(ceil(a_s.length * fps))
		for f in frames + 1:
			var time := minf(f / fps, a_s.length)
			ap_s.seek(time, true)
			sk_s.force_update_all_bone_transforms()
			var target_skel := {}   # pose no espaço do esqueleto alvo (base)
			for b in sk_t.get_bone_count():   # ossos em ordem: pais antes dos filhos
				var parent := sk_t.get_bone_parent(b)
				var rest_t_g: Basis = ref_t[b].basis.orthonormalized()
				var g_t: Basis
				if map.has(b):
					var sb: int = map[b]
					var g_s: Basis = (gs * sk_s.get_bone_global_pose(sb)).basis.orthonormalized()
					var rest_s_g: Basis = ref_s[sb].basis.orthonormalized()
					g_t = (Mb * (g_s * rest_s_g.inverse()) * Mb.inverse()) * rest_t_g
				else:
					var par_rest: Basis = ref_t[parent].basis.orthonormalized() if parent >= 0 else gt.basis.orthonormalized()
					var par_now: Basis = target_skel[parent] if parent >= 0 else gt.basis.orthonormalized()
					g_t = (par_now * par_rest.inverse()) * rest_t_g
				target_skel[b] = g_t
				if map.has(b):
					var par_g: Basis = target_skel[parent] if parent >= 0 else gt.basis.orthonormalized()
					var local := (par_g.inverse() * g_t).orthonormalized()
					out.rotation_track_insert_key(tr[b], time, local.get_rotation_quaternion())
			# quadril: mesma variação de altura/posição, na escala do novo corpo
			var hs_now: Vector3 = (gs * sk_s.get_bone_global_pose(hips_s)).origin
			var d := Mb * (hs_now - rest_s_h) * ratio
			var world_pos := rest_t_h + d
			var skel_space := gt.affine_inverse() * world_pos
			var par := sk_t.get_bone_parent(hips_t)
			var local_pos := skel_space if par < 0 else (sk_t.get_bone_global_rest(par).affine_inverse() * skel_space)
			out.position_track_insert_key(tp, time, local_pos)
		var err = ResourceSaver.save(out, "res://out_%s_%s.tres" % [OS.get_environment("NOME"), names[name]])
		print(name, " -> ", names[name], " quadros ", frames + 1, " salvo ", err)
	quit()
