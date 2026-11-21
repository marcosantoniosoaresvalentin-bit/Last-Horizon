extends Node
## Multiplayer na mesma rede (Wi-Fi): um jogador abre o mundo dele (o "dono", que é o
## servidor) e os outros que estão na mesma internet veem o mundo na lista e entram.
##
## - Descoberta: o dono avisa pela rede (UDP, broadcast) o nome do mundo, o nome dele e
##   quantos jogadores tem; quem está na tela de multiplayer pergunta pela rede e ouve.
## - Jogo: ENet (até 8 jogadores). Quem entra recebe uma cópia do mundo do dono (os
##   arquivos salvos) e aparece nele. Cada um manda a própria posição, para onde olha,
##   a animação e o que tem na mão; os outros desenham o personagem com o nome em cima.
## O nó fica em /root/Rede e passa de uma cena para outra (criado na hora: get_rede()).

const PORT_GAME := 37652
const PORT_HOST := 37650           # o dono ouve perguntas aqui
const PORT_LIST := 37651           # quem procura ouve os avisos aqui
const MAX_PLAYERS := 8
const CHUNK := 48000

signal lista_mudou
signal conectou_e_baixou(world_id: String)
signal falhou(msg: String)
signal jogadores_mudou
signal reconectando
signal reconectou
signal voltou(novo: int, antigo: int)   # (no dono) um convidado caiu e voltou com outro id

## Tempo sem resposta até dar a conexão por perdida (ms). Alto: o celular às vezes trava
## uns segundos (salvando, carregando, recebendo o mundo, indo para segundo plano) e a
## conexão não pode cair por isso.
const TIMEOUT_MIN := 15000
const TIMEOUT_MAX := 45000
const RECONECTAR_S := 40.0          # o convidado tenta voltar sozinho por até 40 s

var modo := ""                     # "", "dono" ou "convidado"
var mundo_id := ""
var mundo_nome := ""
var jogadores := {}                # peer id -> {nome, skin}
var estados := {}                  # peer id -> {p, y, a, m, c, t}
var achados := {}                  # "ip:porta" -> {nome, dono, n, max, ip, porta, visto}
var hook_salvar := Callable()      # o jogo do dono salva antes de mandar o mundo
var hook_tempo := Callable()       # o jogo devolve os passos da simulação (tempo do jogo)
var hook_mandou := Callable()      # (quem) o dono mandou o mundo: o jogo guarda como ficou
var _ip := ""
var _porta := 0
var _no_jogo := false              # o convidado já está jogando (caiu: tenta voltar)
var _volta_t := -1.0               # reconectando: segundos que ainda tenta
var _tentar_t := 0.0
var _id_antigo := 0
var tempo_recebido := -1

var _udp: PacketPeerUDP
var _anuncio_t := 0.0
var _procurando := false
var _baixando := {}                # nome do arquivo -> PackedByteArray
var _faltam := -1


static func get_rede(tree: SceneTree) -> Node:
	var r := tree.root.get_node_or_null("Rede")
	if r == null:
		r = load("res://scripts/rede.gd").new()
		r.name = "Rede"
		tree.root.add_child(r)
	return r


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_caiu)


func meu_nome() -> String:
	return preload("res://scripts/perfil.gd").nome()


func meu_skin() -> String:
	return preload("res://scripts/perfil.gd").skin()


# ================== DONO (servidor) ==================

func abrir_mundo(id: String, nome: String) -> bool:
	parar()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT_GAME, MAX_PLAYERS - 1) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	modo = "dono"
	mundo_id = id
	mundo_nome = nome
	jogadores = {1: {"nome": meu_nome(), "skin": meu_skin()}}
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.bind(PORT_HOST)
	return true


func _anunciar() -> void:
	var msg := JSON.stringify({"t": "mundo", "nome": mundo_nome, "dono": meu_nome(), "n": jogadores.size(),
		"max": MAX_PLAYERS, "porta": PORT_GAME, "v": 1}).to_utf8_buffer()
	for addr in _broadcasts():
		_udp.set_dest_address(addr, PORT_LIST)
		_udp.put_packet(msg)


## 255.255.255.255 e o broadcast de cada rede local deste celular (x.y.z.255).
func _broadcasts() -> Array:
	var out := ["255.255.255.255"]
	for ip in IP.get_local_addresses():
		var parts: PackedStringArray = ip.split(".")
		if parts.size() == 4 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	return out


func meus_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.split(".").size() == 4 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return out


# ================== PROCURAR MUNDOS ==================

func procurar(on: bool) -> void:
	if on == _procurando:
		return
	_procurando = on
	if on and modo == "":
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		if _udp.bind(PORT_LIST) != OK:
			_udp.bind(0)
	elif not on and modo == "" and _udp:
		_udp.close()
		_udp = null


func _process(delta: float) -> void:
	_anuncio_t -= delta
	if _volta_t >= 0.0:
		_reconectar_tick(delta)
	if _udp == null:
		return
	if modo == "dono":
		if _anuncio_t <= 0.0:
			_anuncio_t = 1.0
			_anunciar()
		while _udp.get_available_packet_count() > 0:
			var pk := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var port := _udp.get_packet_port()
			var d = JSON.parse_string(pk.get_string_from_utf8())
			if d is Dictionary and str(d.get("t", "")) == "procura":
				# responde direto para quem perguntou
				var msg := JSON.stringify({"t": "mundo", "nome": mundo_nome, "dono": meu_nome(), "n": jogadores.size(),
					"max": MAX_PLAYERS, "porta": PORT_GAME, "v": 1}).to_utf8_buffer()
				_udp.set_dest_address(ip, PORT_LIST)
				_udp.put_packet(msg)
				if port != PORT_LIST:
					_udp.set_dest_address(ip, port)
					_udp.put_packet(msg)
	elif _procurando:
		if _anuncio_t <= 0.0:
			_anuncio_t = 1.0
			var q := JSON.stringify({"t": "procura"}).to_utf8_buffer()
			for addr in _broadcasts():
				_udp.set_dest_address(addr, PORT_HOST)
				_udp.put_packet(q)
			# tira da lista quem sumiu
			var now := Time.get_ticks_msec()
			var changed := false
			for k in achados.keys():
				if now - int(achados[k].visto) > 4500:
					achados.erase(k)
					changed = true
			if changed:
				lista_mudou.emit()
		while _udp.get_available_packet_count() > 0:
			var pk := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var d = JSON.parse_string(pk.get_string_from_utf8())
			if d is Dictionary and str(d.get("t", "")) == "mundo":
				if ip in meus_ips() and modo == "" and not Engine.has_meta("mp_teste"):
					continue          # o meu próprio aviso
				var key := "%s:%d" % [ip, int(d.get("porta", PORT_GAME))]
				var novo := not achados.has(key)
				d["ip"] = ip
				d["visto"] = Time.get_ticks_msec()
				achados[key] = d
				if novo or true:
					lista_mudou.emit()


# ================== CONVIDADO (cliente) ==================

func entrar(ip: String, porta: int) -> bool:
	procurar(false)
	parar()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, porta) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	modo = "convidado"
	_ip = ip
	_porta = porta
	_baixando = {}
	_faltam = -1
	return true


## O jogo do convidado começou (a partir daqui, se a conexão cair, tenta voltar).
func no_jogo() -> void:
	_no_jogo = true


func _on_connected() -> void:
	_ajustar_timeout(1)
	if _volta_t >= 0.0:
		# voltou depois de cair: o dono já sabe do mundo; só se apresenta de novo
		_volta_t = -1.0
		rpc_id(1, "_volta_dono", meu_nome(), meu_skin(), _id_antigo)
		reconectou.emit()
		return
	# conectou: se apresenta e pede o mundo
	rpc_id(1, "_ola_dono", meu_nome(), meu_skin())


func _ajustar_timeout(id: int) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (mp as ENetMultiplayerPeer).get_peer(id)
		if pp:
			pp.set_timeout(64, TIMEOUT_MIN, TIMEOUT_MAX)


func _on_conn_failed() -> void:
	if _volta_t >= 0.0:
		_tentar_t = 1.5                 # tenta de novo daqui a pouco
		return
	_fail("Não conseguiu conectar no mundo.")


## A conexão com o dono caiu. Jogando: tenta voltar sozinho (sem sair do mundo).
func _on_server_caiu() -> void:
	if modo == "convidado" and _no_jogo and _ip != "":
		_id_antigo = multiplayer.get_unique_id()
		_volta_t = RECONECTAR_S
		_tentar_t = 0.0
		estados = {}
		reconectando.emit()
		return
	_fail("O dono do mundo saiu.")


func _reconectar_tick(delta: float) -> void:
	_volta_t -= delta
	if _volta_t <= 0.0:
		_volta_t = -1.0
		_fail("A conexão com o dono do mundo caiu.")
		return
	_tentar_t -= delta
	if _tentar_t > 0.0:
		return
	_tentar_t = 4.0
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(_ip, _porta) == OK:
		multiplayer.multiplayer_peer = peer


@rpc("any_peer", "reliable")
func _volta_dono(nome: String, skin: String, antigo: int) -> void:
	if modo != "dono":
		return
	var who := multiplayer.get_remote_sender_id()
	jogadores.erase(antigo)
	estados.erase(antigo)
	jogadores[who] = {"nome": nome.left(24), "skin": skin}
	for p in jogadores:
		if int(p) != 1:
			rpc_id(int(p), "_lista", jogadores)
	jogadores_mudou.emit()
	voltou.emit(who, antigo)


@rpc("any_peer", "reliable")
func _ola_dono(nome: String, skin: String) -> void:
	if modo != "dono":
		return
	var who := multiplayer.get_remote_sender_id()
	if jogadores.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(who)
		return
	jogadores[who] = {"nome": nome.left(24), "skin": skin}
	# manda quem já está no mundo, e avisa os outros do novo
	rpc_id(who, "_lista", jogadores)
	for p in jogadores:
		if int(p) != 1 and int(p) != who:
			rpc_id(int(p), "_lista", jogadores)
	jogadores_mudou.emit()
	_mandar_mundo(who)


@rpc("authority", "reliable")
func _lista(l: Dictionary) -> void:
	jogadores = {}
	for k in l:
		jogadores[int(k)] = l[k]
	jogadores_mudou.emit()


func _mandar_mundo(who: int) -> void:
	if hook_salvar.is_valid():
		hook_salvar.call()
	if hook_mandou.is_valid():
		hook_mandou.call(who)
	var dir := preload("res://scripts/mundos.gd").dir(mundo_id)
	var files := []
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".tmp"):
				continue
			files.append(f)
	var meta := preload("res://scripts/mundos.gd").read_meta(mundo_id)
	rpc_id(who, "_mundo_inicio", files.size(), meta, int(hook_tempo.call()) if hook_tempo.is_valid() else -1)
	for f in files:
		var bytes := FileAccess.get_file_as_bytes(dir + "/" + f)
		var parts := maxi(1, int(ceil(bytes.size() / float(CHUNK))))
		for k in parts:
			rpc_id(who, "_mundo_parte", f, k, parts, bytes.slice(k * CHUNK, mini((k + 1) * CHUNK, bytes.size())))


var _meta_recebida := {}

@rpc("authority", "reliable", "call_remote", 2)
func _mundo_inicio(n: int, meta: Dictionary, tempo: int) -> void:
	_faltam = n
	_meta_recebida = meta
	tempo_recebido = tempo
	_baixando = {}
	if n == 0:
		_terminou_download()


@rpc("authority", "reliable", "call_remote", 2)
func _mundo_parte(f: String, k: int, parts: int, data: PackedByteArray) -> void:
	if not _baixando.has(f):
		_baixando[f] = {"n": parts, "partes": {}}
	_baixando[f].partes[k] = data
	if (_baixando[f].partes as Dictionary).size() == parts:
		_faltam -= 1
		if _faltam <= 0:
			_terminou_download()


func _terminou_download() -> void:
	var Mundos = preload("res://scripts/mundos.gd")
	var id := "mp_convidado"
	var dir: String = Mundos.dir(id)
	# limpa a cópia antiga e grava a nova
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			d.remove(f)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in _baixando:
		var out := PackedByteArray()
		var parts: Dictionary = _baixando[f].partes
		for k in int(_baixando[f].n):
			out.append_array(parts[k])
		if f == "jogador.json":
			continue          # o jogador do dono não é o meu: eu começo do lado dele
		var fa := FileAccess.open(dir + "/" + f, FileAccess.WRITE)
		if fa:
			fa.store_buffer(out)
			fa.close()
	var meta := _meta_recebida.duplicate()
	meta["nome"] = str(meta.get("nome", "Mundo"))
	meta["mp"] = true
	Mundos.write_meta(id, meta)
	mundo_id = id
	mundo_nome = str(meta.nome)
	conectou_e_baixou.emit(id)


# ================== DURANTE O JOGO ==================

func ativo() -> bool:
	return modo != "" and multiplayer.multiplayer_peer is ENetMultiplayerPeer and _volta_t < 0.0 \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Caiu e está tentando voltar (o jogo continua, sem mandar nada).
func reconectando_agora() -> bool:
	return _volta_t >= 0.0


## Manda o meu estado para os outros (posição, para onde olha, animação, mão, agachado).
func mandar_estado(e: Dictionary) -> void:
	if not ativo():
		return
	rpc("_estado", e)


@rpc("any_peer", "unreliable_ordered")
func _estado(e: Dictionary) -> void:
	var who := multiplayer.get_remote_sender_id()
	e["t"] = Time.get_ticks_msec()
	estados[who] = e


## Uma parte do mundo mudou aqui: manda para os outros (compactada).
signal parte_mundo(nome: String, dados: String, quem: int)

func mandar_parte(nome: String, dados: String) -> void:
	if not ativo():
		return
	var raw := dados.to_utf8_buffer()
	rpc("_parte", nome, raw.compress(FileAccess.COMPRESSION_GZIP), raw.size())


@rpc("any_peer", "reliable", "call_remote", 1)
func _parte(nome: String, z: PackedByteArray, n: int) -> void:
	var raw := z.decompress(n, FileAccess.COMPRESSION_GZIP)
	parte_mundo.emit(nome, raw.get_string_from_utf8(), multiplayer.get_remote_sender_id())     # (o dono repassa sozinho: server_relay)


## O convidado terminou de carregar: pede ao dono o mundo como está agora (o que
## mudou enquanto ele carregava não tinha chegado).
signal pediram_mundo

func pedir_mundo_atual() -> void:
	if modo == "convidado" and ativo():
		rpc_id(1, "_pedir_mundo")


@rpc("any_peer", "reliable")
func _pedir_mundo() -> void:
	if modo == "dono":
		pediram_mundo.emit()


## Tempo do jogo do dono (os convidados acertam o relógio).
func mandar_tempo(steps: int) -> void:
	if modo == "dono" and ativo():
		rpc("_tempo", steps)


@rpc("authority", "unreliable")
func _tempo(steps: int) -> void:
	tempo_recebido = steps


func _on_peer_connected(id: int) -> void:
	_ajustar_timeout(id)


func _on_peer_disconnected(id: int) -> void:
	jogadores.erase(id)
	estados.erase(id)
	if modo == "dono":
		for p in jogadores:
			if int(p) != 1:
				rpc_id(int(p), "_lista", jogadores)
	jogadores_mudou.emit()


func _fail(msg: String) -> void:
	var was := modo
	parar()
	if was != "":
		falhou.emit(msg)


func parar() -> void:
	_no_jogo = false
	_volta_t = -1.0
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if _udp and modo == "dono":
		_udp.close()
		_udp = null
	modo = ""
	jogadores = {}
	estados = {}
	tempo_recebido = -1
