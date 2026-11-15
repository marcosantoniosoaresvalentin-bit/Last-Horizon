extends Control
## Menu principal: escolha do personagem (masculino ou feminino) e entrar no jogo.

const SAVE := "user://personagem.txt"


func _ready() -> void:
	%MapButton.visible = false
	var box: VBoxContainer = %MapButton.get_parent()
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
	var last := FileAccess.get_file_as_string(SAVE).strip_edges() if FileAccess.file_exists(SAVE) else "homem"
	for opt in [["homem", "Masculino"], ["mulher", "Feminino"]]:
		var b := Button.new()
		b.text = opt[1]
		b.custom_minimum_size = Vector2(240, 72)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_play.bind(opt[0]))
		row.add_child(b)
		if opt[0] == last:
			b.call_deferred("grab_focus")


func _play(who: String) -> void:
	Engine.set_meta("personagem", who)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(who)
	get_tree().change_scene_to_file("res://scenes/jogo3d.tscn")
