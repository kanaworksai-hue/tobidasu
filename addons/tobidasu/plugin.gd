@tool
extends EditorPlugin
# Node and resource types register themselves through class_name.
# Adds the tile tagging panel to the bottom dock; it follows the selection
# (a Tobidasu3D, or a TileMapLayer to tag its TileSet without rebuilding).

var _panel: TobidasuPanel


func _enter_tree() -> void:
	_panel = TobidasuPanel.new()
	_panel.undo_redo = get_undo_redo()
	add_control_to_bottom_panel(_panel, "Tobidasu")
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	remove_control_from_bottom_panel(_panel)
	_panel.queue_free()


func _on_selection_changed() -> void:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is Tobidasu3D:
			_panel.target = n
			return
		if n is TileMapLayer and n.tile_set != null:
			_panel.target = null
			_panel.set_tile_set(n.tile_set)
			return
