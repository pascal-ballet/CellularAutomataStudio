## BehaviorTreeForGroups
## ******************
## Editor plugin configuration

@tool
extends EditorPlugin

func _enter_tree():
	# Initialization of the plugin goes here.
	# Main Node
	add_custom_type("CellularAutomata2D", "Node",\
			preload("res://addons/cellular_automata_studio/cellular_automata_studio_2d.gd"),preload("icon.png"))

func _exit_tree():
	# Clean-up of the plugin goes here.
	# Main Node
	remove_custom_type("CellularAutomata2D")
