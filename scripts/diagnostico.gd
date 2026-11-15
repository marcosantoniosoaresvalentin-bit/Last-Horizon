extends RefCounted
## Diagnóstico: guarda por onde o jogo passou.
## Se o jogo fechar sozinho, na próxima vez o menu mostra onde foi.

const PASSO := "user://ultimo_passo.txt"
const ERROS := "user://erros.txt"

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
