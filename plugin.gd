@tool
extends EditorPlugin

func _enter_tree() -> void:
	ScriptTabSingleton.register_node(self)

func _exit_tree() -> void:
	ScriptTabSingleton.unregister_node(self)
