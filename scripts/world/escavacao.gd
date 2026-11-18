extends Node3D
## Escavação com a pá: a terra do próprio chão sai de onde a pá bate e vai para onde
## o jogador joga. Dá para moldar o terreno do jeito que quiser (valas, tanques para
## peixe, rampas, montes).
##
## O chão normal tem pontos a cada 2,5 m, grosso demais para a pá. Por cima dele há uma
## grade fina (25 cm) só onde a terra foi mexida: cada ponto guarda quanto o chão desceu
## (cavado) ou subiu (terra jogada). Ali o chão normal some (máscara) e é desenhado este
## chão de terra mexida no lugar.

const RES := 0.2                # tamanho de cada quadradinho da grade (m)
const CH := 16                  # quadradinhos por bloco (4 m)
const MAX_DEPTH := 10.0
const DIG_R := 0.36             # raio da pá de terra
const DIG_D := 0.22             # quanto a pá entra na terra (m): fundo quase reto, parede íngreme
const REPOSE := 0.75            # terra solta escorre se o desnível passar disso por quadradinho (≈37°)

var d := {}                     # Vector2i (ponto da grade) -> quanto subiu (+) ou desceu (-) (m)
var mask_tex: ImageTexture
var _mask: Image
var _jogo: Node
var _chunks := {}               # Vector2i (bloco) -> MeshInstance3D
var _mat: Material
var _mw := 0
var _mh := 0


func build(jogo: Node, soil_mat: Material, save_path := "") -> void:
	_jogo = jogo
	_mat = soil_mat
	_mw = int(jogo.MundoSim.W * jogo.CELL / RES)
	_mh = int(jogo.MundoSim.H * jogo.CELL / RES)
	_mask = Image.create(_mw, _mh, false, Image.FORMAT_R8)
	if save_path != "":
		_load(save_path)
	for k in d:
		_mark(k)
	mask_tex = ImageTexture.create_from_image(_mask)
	var keys := {}
	for k in d:
		keys[_chunk_of(k)] = true
	for ck in keys:
		_rebuild_chunk(ck)


# ================== ALTURA ==================

func _v(k: Vector2i) -> float:
	return float(d.get(k, 0.0))


## Quanto o chão subiu/desceu num ponto qualquer (entre os pontos da grade).
func delta_at(x: float, z: float) -> float:
	var fx := x / RES
	var fz := z / RES
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_v(Vector2i(ix, iz)), _v(Vector2i(ix + 1, iz)), tx)
	var b := lerpf(_v(Vector2i(ix, iz + 1)), _v(Vector2i(ix + 1, iz + 1)), tx)
	return lerpf(a, b, tz)


## Altura do chão de verdade (com o que foi cavado ou aterrado).
func ground_at(x: float, z: float) -> float:
	return _jogo.surface_at(x, z) + delta_at(x, z)


# ================== CAVAR E JOGAR TERRA ==================

## Uma pá de terra em c: o chão desce ali (mais no meio). Devolve o volume tirado (m³).
func dig(c: Vector3) -> float:
	var vol := 0.0
	var touched := {}
	var r := int(ceil(DIG_R * 1.2 / RES))
	var cx := roundi(c.x / RES)
	var cz := roundi(c.z / RES)
	for ix in range(cx - r, cx + r + 1):
		for iz in range(cz - r, cz + r + 1):
			var p := Vector2(ix * RES, iz * RES)
			var dist := p.distance_to(Vector2(c.x, c.z))
			var k := Vector2i(ix, iz)
			# a beira de cada pá é irregular (torrão que sai junto ou fica)
			var wob := 1.0 + 0.18 * sin(atan2(p.y - c.z, p.x - c.x) * 3.0 + c.x * 7.0 + c.z * 5.0)
			var u := clampf(dist / (DIG_R * wob), 0.0, 1.0)
			if u >= 1.0:
				continue
			var amount := DIG_D * (1.0 - pow(u, 4.0))
			var now := _v(k)
			var nv := maxf(now - amount, -MAX_DEPTH)
			vol += (now - nv) * RES * RES
			d[k] = nv
			touched[k] = true
	_changed(touched)
	return vol


## Joga a terra (vol, m³) em c: o chão sobe ali; terra solta escorre se ficar em pé demais.
func dump(c: Vector3, vol: float) -> void:
	var touched := {}
	var r := int(ceil(DIG_R / RES))
	var cx := roundi(c.x / RES)
	var cz := roundi(c.z / RES)
	var ws := {}
	var wsum := 0.0
	for ix in range(cx - r, cx + r + 1):
		for iz in range(cz - r, cz + r + 1):
			var dist := Vector2(ix * RES, iz * RES).distance_to(Vector2(c.x, c.z))
			if dist > DIG_R:
				continue
			var w := 1.0 - pow(dist / DIG_R, 2.0)
			ws[Vector2i(ix, iz)] = w
			wsum += w
	for k in ws:
		d[k] = _v(k) + vol * float(ws[k]) / wsum / (RES * RES)
		touched[k] = true
	_slump(touched)
	_changed(touched)


## Terra solta escorre para os lados até ficar com uma inclinação que se segura.
func _slump(touched: Dictionary) -> void:
	var lim := REPOSE * RES
	var todo := touched.keys()
	var it := 0
	while not todo.is_empty() and it < 4000:
		it += 1
		var k: Vector2i = todo.pop_back()
		var hk := _v(k)
		for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + nb
			var diff := hk - _v(n)
			if diff > lim:
				var move := (diff - lim) * 0.5
				d[k] = _v(k) - move
				d[n] = _v(n) + move
				hk = _v(k)
				touched[n] = true
				todo.append(n)


func _changed(touched: Dictionary) -> void:
	var cks := {}
	for k in touched:
		if absf(_v(k)) < 0.002:
			d.erase(k)
		_mark(k)
		# os blocos vizinhos também (o ponto da grade fica na borda de até 4 blocos)
		for ox in [-2, -1, 0, 1]:
			for oz in [-2, -1, 0, 1]:
				cks[_chunk_of(k + Vector2i(ox, oz))] = true
	if mask_tex:
		mask_tex.update(_mask)
	for ck in cks:
		_rebuild_chunk(ck)


## Os quadradinhos em volta de um ponto mexido ficam marcados (o chão normal some ali).
func _mark(k: Vector2i) -> void:
	for o in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var c: Vector2i = k + o
		if c.x < 0 or c.y < 0 or c.x >= _mw or c.y >= _mh:
			continue
		var any := false
		for q in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			if d.has(c + q):
				any = true
				break
		_mask.set_pixel(c.x, c.y, Color(1, 0, 0) if any else Color(0, 0, 0))


func _chunk_of(k: Vector2i) -> Vector2i:
	return Vector2i(floori(float(k.x) / CH), floori(float(k.y) / CH))


# ================== DESENHO ==================

## O chão de terra mexida de um bloco: só os quadradinhos mexidos, colados no chão normal.
func _rebuild_chunk(ck: Vector2i) -> void:
	if _chunks.has(ck) and is_instance_valid(_chunks[ck]):
		_chunks[ck].free()
	_chunks.erase(ck)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var x0 := ck.x * CH
	var z0 := ck.y * CH
	for ix in range(x0, x0 + CH):
		for iz in range(z0, z0 + CH):
			var c := Vector2i(ix, iz)
			if ix < 0 or iz < 0 or ix >= _mw or iz >= _mh or not _near_mark(c):
				continue
			any = true
			var ps := []
			var cs := []
			for q in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var k: Vector2i = c + q
				var x := k.x * RES
				var z := k.y * RES
				var dv := _v(k)
				# um tiquinho abaixo: na borda fica por baixo do chão normal (que é recortado redondo)
				ps.append(Vector3(x, _jogo.surface_at(x, z) + dv - 0.015, z))
				cs.append(_soil_color(dv, k))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for t in tri:
					st.set_color(cs[t])
					st.add_vertex(ps[t])
	if not any:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	add_child(mi)
	_chunks[ck] = mi


## Quadradinho mexido ou vizinho de um mexido (a terra é desenhada com uma margem).
func _near_mark(c: Vector2i) -> bool:
	for ox in [-1, 0, 1]:
		for oz in [-1, 0, 1]:
			var q: Vector2i = c + Vector2i(ox, oz)
			if q.x >= 0 and q.y >= 0 and q.x < _mw and q.y < _mh and _mask.get_pixel(q.x, q.y).r > 0.5:
				return true
	return false


## Cor da terra: em cima o húmus escuro, mais fundo a terra amarelada/avermelhada com
## faixas de camadas; terra jogada (solta) mais clara e grumosa.
static func _soil_color(dv: float, k: Vector2i) -> Color:
	var h := absi(hash(k)) % 100
	if dv >= 0.0:
		return Color(0.33, 0.24, 0.16).darkened(h * 0.0015)
	var depth := -dv
	var c := Color(0.2, 0.15, 0.1).lerp(Color(0.38, 0.27, 0.17), smoothstep(0.05, 0.4, depth))
	c = c.lerp(Color(0.45, 0.3, 0.18), smoothstep(1.0, 3.0, depth))
	c = c.darkened(0.06 * float(int(depth * 10.0) % 2) + h * 0.0012)
	return c.darkened(0.45 * smoothstep(0.1, 2.5, depth))       # o fundo pega menos luz


# ================== SALVAR ==================

func save(path: String) -> void:
	var out := []
	for k in d:
		out.append([k.x, k.y, snappedf(float(d[k]), 0.001)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "res": RES, "pontos": out}))
		f.close()


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not j is Dictionary:
		return
	var r0 := float(j.get("res", 0.25))
	for e in j.get("pontos", []):
		var k := Vector2i(roundi(float(e[0]) * r0 / RES), roundi(float(e[1]) * r0 / RES))
		d[k] = minf(float(d.get(k, 0.0)), float(e[2])) if float(e[2]) < 0.0 else maxf(float(d.get(k, 0.0)), float(e[2]))
