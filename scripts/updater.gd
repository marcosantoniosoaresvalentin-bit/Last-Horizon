extends Node
## Atualizador automático do jogo.
##
## Ao abrir o jogo, baixa o manifest.json do GitHub. Se houver uma versão
## mais nova que a instalada, baixa o pacote de atualização (.zip) para
## user://updates, confere o tamanho e o SHA-256 e carrega o pacote por
## cima dos arquivos do APK com ProjectSettings.load_resource_pack().
##
## Sem internet, o jogo abre normalmente com a versão que já está no celular.

signal status_changed(text: String)
signal progress_changed(done_bytes: int, total_bytes: int)
signal finished(updated: bool, message: String)

const REPO_RAW := "https://raw.githubusercontent.com/marcosantoniosoaresvalentin-bit/Last-Horizon/ccr-5a916500-dbxvjv/updates/"
const MANIFEST_URL := REPO_RAW + "manifest.json"
const DIR := "user://updates"
const INSTALLED_PATH := DIR + "/installed.json"
const BOOT_PATH := DIR + "/boot.json"
const MANIFEST_TIMEOUT := 10.0

var _manifest_http: HTTPRequest
var _download_http: HTTPRequest
var _remote: Dictionary = {}
var _part_path := ""
var _total := 0
var _downloading := false
var _done := false


## Versão (build) que veio dentro do APK.
static func base_build() -> int:
	return int(ProjectSettings.get_setting("application/config/build", 1))


static func read_installed() -> Dictionary:
	if not FileAccess.file_exists(INSTALLED_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(INSTALLED_PATH))
	return data if data is Dictionary else {}


## Proteção: se uma versão baixada fez o jogo fechar antes de chegar no menu
## duas vezes seguidas, ela não é mais carregada (o jogo abre com a versão do
## APK) até chegar uma atualização mais nova.
static func _read_boot() -> Dictionary:
	if not FileAccess.file_exists(BOOT_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(BOOT_PATH))
	return data if data is Dictionary else {}


static func _write_boot(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(BOOT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


## Chamado pelo menu: a versão atual abriu direitinho.
static func mark_ok() -> void:
	var b := _read_boot()
	b["ok"] = true
	b["fails"] = 0
	_write_boot(b)


static func is_broken(version: int) -> bool:
	var b := _read_boot()
	return int(b.get("broken", 0)) == version and version > 0


## Antes de abrir: se a última abertura não chegou ao menu, conta como falha.
static func check_last_boot() -> void:
	var b := _read_boot()
	if b.is_empty() or bool(b.get("ok", true)):
		return
	var fails := int(b.get("fails", 0)) + 1
	b["fails"] = fails
	if fails >= 2:
		b["broken"] = int(b.get("version", 0))
	_write_boot(b)


## Carrega a última atualização baixada, antes de qualquer cena do jogo.
## Devolve a build que está valendo agora.
static func apply_installed() -> int:
	var info := read_installed()
	var version := int(info.get("version", 0))
	var path := str(info.get("file", ""))
	var b := _read_boot()
	if is_broken(version):
		return base_build()
	b["version"] = version if version > base_build() else base_build()
	b["ok"] = false
	_write_boot(b)
	if version <= base_build():
		# O APK instalado já é igual ou mais novo que a atualização baixada.
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		if FileAccess.file_exists(INSTALLED_PATH):
			DirAccess.remove_absolute(INSTALLED_PATH)
		return base_build()
	if FileAccess.file_exists(path) and ProjectSettings.load_resource_pack(path):
		return version
	return base_build()


static func current_build() -> int:
	var version := int(read_installed().get("version", 0))
	return maxi(version, base_build())


func start() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_manifest_http = HTTPRequest.new()
	_manifest_http.timeout = MANIFEST_TIMEOUT
	add_child(_manifest_http)
	_manifest_http.request_completed.connect(_on_manifest)
	status_changed.emit("Procurando atualizações…")
	var err := _manifest_http.request(MANIFEST_URL + "?t=%d" % int(Time.get_unix_time_from_system()))
	if err != OK:
		_finish(false, "Sem conexão. Abrindo a versão atual.")


func _process(_delta: float) -> void:
	if not _downloading:
		return
	var total := _download_http.get_body_size()
	if total <= 0:
		total = _total
	progress_changed.emit(_download_http.get_downloaded_bytes(), total)


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(false, "Sem conexão. Abrindo a versão atual.")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		_finish(false, "Não foi possível ler as atualizações.")
		return
	_remote = data
	var version := int(_remote.get("version", 0))
	var file := str(_remote.get("file", ""))
	if version <= current_build() or file == "":
		_finish(false, "Jogo atualizado.")
		return
	if base_build() < int(_remote.get("min_build", 0)):
		_finish(false, "Existe um app novo. Instale o APK mais recente.")
		return

	_total = int(_remote.get("size", 0))
	_part_path = DIR + "/update_%d.zip.part" % version
	if FileAccess.file_exists(_part_path):
		DirAccess.remove_absolute(_part_path)

	_download_http = HTTPRequest.new()
	_download_http.download_file = _part_path
	_download_http.use_threads = true
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download)
	status_changed.emit("Baixando atualização…")
	var err := _download_http.request(REPO_RAW + file + "?t=%d" % int(Time.get_unix_time_from_system()))
	if err != OK:
		_finish(false, "Falha ao baixar. Abrindo a versão atual.")
		return
	_downloading = true


func _on_download(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(_part_path)
		_finish(false, "Falha ao baixar. Abrindo a versão atual.")
		return
	progress_changed.emit(_total, _total)
	status_changed.emit("Instalando atualização…")

	var expected := str(_remote.get("sha256", "")).to_lower()
	if expected != "" and FileAccess.get_sha256(_part_path) != expected:
		DirAccess.remove_absolute(_part_path)
		_finish(false, "Download corrompido. Tente de novo mais tarde.")
		return

	var version := int(_remote.get("version", 0))
	var final_path := DIR + "/update_%d.zip" % version
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	DirAccess.rename_absolute(_part_path, final_path)

	if not ProjectSettings.load_resource_pack(final_path):
		DirAccess.remove_absolute(final_path)
		_finish(false, "Atualização inválida. Abrindo a versão atual.")
		return

	var old := read_installed()
	var old_file := str(old.get("file", ""))
	if old_file != "" and old_file != final_path and FileAccess.file_exists(old_file):
		DirAccess.remove_absolute(old_file)
	var f := FileAccess.open(INSTALLED_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": version, "file": final_path}))
		f.close()
	_finish(true, "Atualização instalada!")


func _finish(updated: bool, message: String) -> void:
	if _done:
		return
	_done = true
	_downloading = false
	finished.emit.call_deferred(updated, message)
