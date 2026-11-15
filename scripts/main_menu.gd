extends Control
## Menu principal.


func _ready() -> void:
	%MapButton.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/jogo3d.tscn"))
