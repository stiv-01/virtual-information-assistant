extends Control

func _on_acceder_pressed() -> void:
	get_tree().change_scene_to_file("res://levi_animation.scn")


func _on_salir_pressed() -> void:
	get_tree().quit()
	
