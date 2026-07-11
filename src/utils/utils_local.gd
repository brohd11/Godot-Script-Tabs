
const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const UTexture = UtilsRemote.UTexture
const UFile = UtilsRemote.UFile

const DummyTab = preload("res://addons/script_tabs/src/class/dummy_tab.gd")
const DummyEditor = preload("res://addons/script_tabs/src/class/dummy_editor.gd")
const DummyCTE = preload("res://addons/script_tabs/src/class/dummy_cte.gd")


static var menu_icon:Texture2D

static func get_valid_containers(current_editor:Variant, script_tab_containers:Array, callable:=Callable()):
	var valid_items = {}
	
	if not is_instance_valid(menu_icon):
		var raw_icon = EditorInterface.get_editor_theme().get_icon(&"HBoxContainer", &"EditorIcons")
		menu_icon = UTexture.get_modulated_icon(raw_icon)
	
	var valid_callable = not callable.is_null()
	var new_valid = true
	for i in range(script_tab_containers.size()):
		var tab = script_tab_containers[i]
		if not is_instance_valid(current_editor) or not tab.has_tab_by_editor(current_editor):
			var menu_path = "Open in Split/" + str(i + 1)
			valid_items[menu_path] = {PopupWrapper.ItemParams.ICON: [menu_icon, null]}
			if valid_callable:
				valid_items[menu_path][PopupWrapper.ItemParams.CALLABLE] = callable.bind(i)
		else:
			new_valid = tab.get_child_count() > 1
	
	if new_valid:
		valid_items["Open in Split/New"] = {PopupWrapper.ItemParams.ICON: [menu_icon, null]}
		if valid_callable:
			valid_items["Open in Split/New"][PopupWrapper.ItemParams.CALLABLE] = callable.bind(script_tab_containers.size())
	
	return valid_items

static func get_target_tab_from_popup(menu_path:String) -> int:
	var tab_containers = ScriptTabSingleton.get_instance().tab_containers
	var end = menu_path.get_file()
	if end == "New":
		return tab_containers.size()
	return end.to_int() - 1


static func ensure_connect(_signal:Signal, callable:Callable, _connect:bool):
	if _connect:
		if not _signal.is_connected(callable):
			_signal.connect(callable)
	else:
		if _signal.is_connected(callable):
			_signal.disconnect(callable)

static func is_node_script_editor(node:Node):
	var c = node.get_class()
	return c.ends_with(&"TextEditor") or c == (&"EditorHelp")

static func reparent_children(from:Node, to:Node, excludes:=[]):
	for c in from.get_children():
		if c in excludes:
			continue
		c.reparent(to)

static func add_filler_nodes(nodes_to_add_to:Array, reference_array:Array, amount:=2):
	for i in range(amount): # HACK: these just stop an error from firing when closing a editor. Trying to get_child that isn't there
		for par in nodes_to_add_to:
			var node = Node.new()
			par.add_child(node)
			reference_array.append(node)

static func get_tab_data():
	DirAccess.make_dir_recursive_absolute(Keys.TAB_CACHE_PATH.get_base_dir())
	if not FileAccess.file_exists(Keys.TAB_CACHE_PATH):
		return {}
	var data = UFile.read_from_json(Keys.TAB_CACHE_PATH)
	for key in data.keys():
		if key.begins_with("uid"):
			data[UFile.uid_to_path(key)] = data[key]
	return data


class Keys:
	const META_DATA = &"meta_data"
	const SELECTED_SCRIPTS = &"selected_scripts"
	const SPLIT_OFFSETS = &"split_offsets"
	
	const TAB_IDX = &"tab_idx"
	const TAB = &"tab"
	
	const STYLEBOX_DOC = &"stylebox_doc"
	
	const CODE_COMPLETE_CALLABLE = &"CodeTextEditor::_code_complete_timer_timeout"
	
	const SCRIPT_EDITOR_CLASSES = [&"ScriptTextEditor", &"TextEditor", &"EditorHelp"]
	
	const TAB_CACHE_PATH = &"res://.godot/addons/script_tabs/current_layout.json"
