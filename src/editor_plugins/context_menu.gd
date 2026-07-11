extends EditorContextMenuPlugin

const SLOT = CONTEXT_SLOT_SCRIPT_EDITOR

const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const UtilsLocal = preload("res://addons/script_tabs/src/utils/utils_local.gd")

signal new_tab_container(path:String, target_split:int)

func _popup_menu(paths: PackedStringArray) -> void:
	var ins = ScriptTabSingleton.get_instance()
	var current_editor = ins.script_editor_tab_container.get_current_tab_control()
	var valid_items = UtilsLocal.get_valid_containers(current_editor, ins.tab_containers)
	PopupWrapper.create_context_plugin_items(self, paths, valid_items, _callback)


func _callback(_selected_script, popup_path:String):
	var ins = ScriptTabSingleton.get_instance()
	var current_editor = ins.script_editor_tab_container.get_current_tab_control()
	var target_tab = UtilsLocal.get_target_tab_from_popup(popup_path)
	new_tab_container.emit(current_editor, target_tab)
