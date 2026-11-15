extends RefCounted
## Diagnóstico: guarda por onde o jogo passou e os erros que aconteceram.
## Se o jogo fechar sozinho, na próxima vez o menu mostra onde foi
## e liga o modo leve automaticamente.

const PASSO := "user://ultimo_passo.txt"
const ERROS := "user://erros.txt"
const LEVE := "user://modo_leve.txt"

## Passos em que o jogo estava funcionando normalmente (não é queda).
const PASSOS_OK := ["", "ok", "menu"]


static func marcar(passo: String) -> void:
	var f := FileAccess.open(PASSO, FileAccess.WRITE)
	if f:
		f.store_string(passo)
		f.close()


static func ultimo() -> String:
	if not FileAccess.file_exists(PASSO):
		return ""
	return FileAccess.get_file_as_string(PASSO).strip_edges()


static func ultimos_erros(n: int) -> PackedStringArray:
	if not FileAccess.file_exists(ERROS):
		return PackedStringArray()
	var linhas := FileAccess.get_file_as_string(ERROS).strip_edges().split("\n", false)
	return linhas.slice(maxi(0, linhas.size() - n))


static func limpar_erros() -> void:
	if FileAccess.file_exists(ERROS):
		DirAccess.remove_absolute(ERROS)


static func modo_leve() -> bool:
	return FileAccess.file_exists(LEVE) and FileAccess.get_file_as_string(LEVE).strip_edges() == "1"


static func set_modo_leve(on: bool) -> void:
	var f := FileAccess.open(LEVE, FileAccess.WRITE)
	if f:
		f.store_string("1" if on else "0")
		f.close()


static func instalar_registro() -> void:
	if Engine.has_meta("registro_erros"):
		return
	var r := Registro.new()
	Engine.set_meta("registro_erros", r)
	OS.add_logger(r)


## Guarda as mensagens de erro do motor do jogo num arquivo.
class Registro extends Logger:
	var _mx := Mutex.new()
	var _escrevendo := false

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var texto := rationale if rationale != "" else code
		_write("%s (%s:%d)" % [texto, file.get_file(), line])

	func _log_message(message: String, error: bool) -> void:
		if error:
			_write(message)

	func _write(t: String) -> void:
		_mx.lock()
		if not _escrevendo:
			_escrevendo = true
			var f: FileAccess
			if FileAccess.file_exists(ERROS):
				f = FileAccess.open(ERROS, FileAccess.READ_WRITE)
			else:
				f = FileAccess.open(ERROS, FileAccess.WRITE)
			if f:
				f.seek_end()
				f.store_line(t.strip_edges().left(240))
				f.close()
			_escrevendo = false
		_mx.unlock()
