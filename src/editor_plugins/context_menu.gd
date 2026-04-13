extends EditorContextMenuPlugin

const UTexture = preload("uid://ddu76iygjkxih") #! resolve ALibRuntime.Utils.UTexture

var menu_icon:Texture2D

var script_editor_tab_container:TabContainer
var tab_containers := []

signal new_tab_container(path:String, target_split:int)

func _popup_menu(paths: PackedStringArray) -> void:
	var valid_items = {}
	
	if not is_instance_valid(menu_icon):
		var raw_icon = EditorInterface.get_editor_theme().get_icon(&"HBoxContainer", &"EditorIcons")
		menu_icon = UTexture.get_modulated_icon(raw_icon)
	
	var current_editor = script_editor_tab_container.get_current_tab_control()
	
	var new_valid = true
	for i in range(tab_containers.size()):
		var tab = tab_containers[i]
		if not tab.has_tab_by_editor(current_editor):
			valid_items["Open in Split/" + str(i + 1)] = {PopupWrapper.ItemParams.ICON: [menu_icon, null]}
		else:
			new_valid = tab.get_child_count() > 1
	
	if new_valid:
		valid_items["Open in Split/New"] = {PopupWrapper.ItemParams.ICON: [menu_icon, null]}
	
	PopupWrapper.create_context_plugin_items(self, paths, valid_items, _callback)


func _callback(_selected_script, popup_path:String):
	var current_editor = script_editor_tab_container.get_current_tab_control()
	var popup_path_end = popup_path.get_file()
	if popup_path_end == "New":
		new_tab_container.emit(current_editor, tab_containers.size())
	else:
		var target = int(popup_path_end) - 1
		new_tab_container.emit(current_editor, target)
