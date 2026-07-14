extends EditorContextMenuPlugin

const SLOT = CONTEXT_SLOT_FILESYSTEM

const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const ScriptListManager = UtilsRemote.ScriptListManager
const UtilsLocal = preload("res://addons/script_tabs/src/utils/utils_local.gd")

func _popup_menu(paths: PackedStringArray) -> void:
	if paths.size() != 1:
		return
	
	var selected = paths[0]
	var text_types = ScriptListManager.get_text_file_types()
	if selected.ends_with("/") or not selected.get_extension() in text_types:
		return
	
	var valid_items = ScriptTabSingleton.get_valid_containers_for_path(selected)
	PopupWrapper.create_context_plugin_items(self, paths, valid_items, _callback)


func _callback(paths, popup_path:String):
	var target = UtilsLocal.get_target_tab_from_popup(popup_path)
	ScriptTabSingleton.open_script(paths[0], target)
