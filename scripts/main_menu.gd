extends Control
## Menu principal: escolha do personagem (masculino ou feminino) e entrar no jogo.
## Também avisa se o jogo fechou sozinho da última vez, e em que momento.

const Diag := preload("res://scripts/diagnostico.gd")
const SAVE := "user://personagem.txt"
const PASSO_NOME := {
	"gerando mundo": "a geração do mundo",
	"moldando terreno": "a montagem do terreno",
	"enchendo lagoas": "a montagem das lagoas",
	"carregando personagem": "o carregamento do personagem",
	"plantando grama": "a montagem da grama",
	"entrando no mundo": "a entrada no mundo",
	"jogando": "o jogo",
}


func _ready() -> void:
	var last := Diag.ultimo()
	var caiu := not Diag.PASSOS_OK.has(last)

	%MapButton.visible = false
	var box: VBoxContainer = %MapButton.get_parent()

	if caiu:
		var warn := Label.new()
		var onde: String = PASSO_NOME.get(last, last)
		warn.text = "O jogo fechou sozinho da última vez, durante %s." % onde
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 17)
		warn.add_theme_color_override("font_color", Color(1.0, 0.62, 0.45))
		box.add_child(warn)
	else:
		Diag.limpar_erros()
	Diag.marcar("menu")

	var ask := Label.new()
	ask.text = "Escolha seu personagem"
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.add_theme_font_size_override("font_size", 22)
	ask.add_theme_color_override("font_color", Color(0.91, 0.86, 0.77))
	box.add_child(ask)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var last_who := FileAccess.get_file_as_string(SAVE).strip_edges() if FileAccess.file_exists(SAVE) else "homem"
	for opt in [["homem", "Masculino"], ["mulher", "Feminino"]]:
		var b := Button.new()
		b.text = opt[1]
		b.custom_minimum_size = Vector2(240, 72)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_play.bind(opt[0]))
		row.add_child(b)
		if opt[0] == last_who:
			b.call_deferred("grab_focus")


func _play(who: String) -> void:
	Engine.set_meta("personagem", who)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(who)
		f.close()
	Diag.marcar("gerando mundo")
	get_tree().change_scene_to_file("res://scenes/jogo3d.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Diag.marcar("ok")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		Diag.marcar("menu")
