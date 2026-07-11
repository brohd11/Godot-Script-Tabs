@tool
class_name ScriptTabSingleton
extends SingletonRefCount
const SingletonRefCount = Singletons.RefCount

const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys
const SplitWrapper = UtilsRemote.SplitWrapper

const UtilsLocal = preload("res://addons/script_tabs/src/utils/utils_local.gd")

# These are now in their own scripts
# Arch: self -> DummyTab -> DummyEditor -> DummyCTE
const DummyTab = UtilsLocal.DummyTab
const DummyEditor = UtilsLocal.DummyEditor
const DummyCTE = UtilsLocal.DummyCTE

const ScriptListContextMenu = preload("res://addons/script_tabs/src/editor_plugins/context_menu.gd")
const FileSystemContextMenu = preload("res://addons/script_tabs/src/editor_plugins/fs_context_menu.gd")


#region SingletonAPI

const PE_STRIP_CAST_SCRIPT = preload("res://addons/script_tabs/src/script_tab_singleton.gd")
static func get_singleton_name() -> String:
	return "ScriptTabSingleton"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func register_node(node:Node):
	return _register_node(PE_STRIP_CAST_SCRIPT, node)

static func unregister_node(node:Node):
	_unregister_node(PE_STRIP_CAST_SCRIPT, node)

static func call_on_ready(callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)

func _init(node):
	pass

func _all_unregistered_callback():
	_plugin_clean_up()

func _get_ready_bool() -> bool:
	return is_node_ready()

#endregion


var _plugin_initialized:=false

# editor
var script_editor_tab_container:TabContainer
#

var script_list_context_menu:ScriptListContextMenu
var file_system_context_menu:FileSystemContextMenu

var script_list_manager:ScriptListManager
var _script_editor_history:Array= []

var main_split_container:Container
var tab_containers:Array[DummyTab] = []

var unselected_split_stylebox:StyleBoxFlat

var _setup_complete_flag:=false
var _symbol_lookup_flag:=false
var _open_script_tab_flag:=-1

#region PublicAPI


static func get_valid_containers_for_path(path:String, callable:=Callable()):
	var ins = get_instance()
	var idx = ins.script_list_manager.get_script_index(path)
	var current_editor
	if idx > -1:
		current_editor = ins.script_editor_tab_container.get_child(idx)
	
	return UtilsLocal.get_valid_containers(current_editor, ins.tab_containers, callable)

static func open_script(path:String, tab:int=0, fs_singleton=null):
	var ins = get_instance()
	ins._open_script(path, tab, fs_singleton)

func _open_script(path:String, tab:int=0, fs_singleton=null):
	_open_script_tab_flag = tab
	var idx = script_list_manager.get_script_index_or_open(path, fs_singleton)
	if idx != -1: # -1 will be opened, and flag will set it
		_open_script_tab_flag = -1
		var editor_node = script_editor_tab_container.get_child(idx)
		select_or_add_new_tab(editor_node, tab)

#endregion

func _plugin_init():
	var pl = EditorPlugin.new()
	script_list_context_menu = ScriptListContextMenu.new()
	script_list_context_menu.new_tab_container.connect(_on_new_tab_container)
	pl.add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR, script_list_context_menu)
	
	file_system_context_menu = FileSystemContextMenu.new()
	pl.add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, file_system_context_menu)
	
	pl.queue_free()

func _plugin_clean_up():
	var pl = EditorPlugin.new()
	pl.remove_context_menu_plugin(script_list_context_menu)
	pl.remove_context_menu_plugin(file_system_context_menu)
	pl.queue_free()


func _ready() -> void:
	await get_tree().create_timer(1).timeout
	EditorNodeRef.call_on_ready(_on_editor_node_ref_ready)

func _exit_tree() -> void:
	if _setup_complete_flag: # attempt to stop a crash or early exit from writing default tabs
		save_cache_data()
	
	for t in tab_containers:
		t.clean_up()
	
	script_editor_tab_container.show()
	main_split_container.queue_free()


func _on_editor_node_ref_ready():
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.VALIDATE_SCRIPT, _on_validate)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TAB_CHANGED, _on_editor_tab_changed)
	
	var theme = EditorInterface.get_editor_theme()
	unselected_split_stylebox = theme.get_stylebox(&"tab_selected", &"TabContainer").duplicate() as StyleBoxFlat
	unselected_split_stylebox.bg_color = theme.get_color(&"disabled_bg_color", &"Editor")
	
	script_editor_tab_container = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.SCRIPT_EDITOR_TAB_CONTAINER)
	script_editor_tab_container.hide()
	
	#var side_bar = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.SCRIPT_EDITOR_SIDEBAR_V_SPLIT)
	script_list_manager = ScriptListManager.get_instance()
	script_list_manager.cache_updated.connect(_on_script_list_manager_cache_updated)
	
	
	main_split_container = SplitWrapper.new()
	#main_split_container = HSplitContainer.new()
	main_split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var script_tab_par = script_editor_tab_container.get_parent()
	script_tab_par.add_child(main_split_container)
	script_tab_par.move_child(main_split_container, 0)
	
	EditorNodeRef.refresh_dynamic_refs()
	
	_create_current_tabs()
	
	_plugin_init() # create context menus
	
	script_editor_tab_container.child_order_changed.connect(_on_script_editor_tab_container_child_changed, 1)
	_plugin_initialized = true


func _create_current_tabs():
	#script_list_manager.clear_script_list_filter()
	script_list_manager.update_cache(true)
	var current_editor = script_editor_tab_container.get_current_tab_control()
	var current_editor_index = -1
	if is_instance_valid(current_editor):
		current_editor_index = current_editor.get_index()
	
	var saved_tab_tooltips = UtilsLocal.get_tab_data() # data is Dictionary[path, {tab, idx}] # also includes meta
	var metadata = saved_tab_tooltips.get(Keys.META_DATA, {})
	saved_tab_tooltips.erase(Keys.META_DATA)
	var current_tabs = script_list_manager.get_all_script_data_tooltip_key()
	for tooltip in current_tabs.keys():
		if not saved_tab_tooltips.has(tooltip): # converted to uid in get_tab_data
			saved_tab_tooltips[tooltip] = {}
	
	var tooltip_arr_size = saved_tab_tooltips.size()
	var saved_tooltip_arr = saved_tab_tooltips.keys()
	saved_tooltip_arr.sort_custom(
		func(a,b):
			var a_data = saved_tab_tooltips.get(a)
			var b_data = saved_tab_tooltips.get(b)
			var a_tab = a_data.get(Keys.TAB, 0)
			var b_tab = b_data.get(Keys.TAB, 0)
			if a_tab != b_tab:
				return a_tab < b_tab
			
			var a_idx = a_data.get(Keys.TAB_IDX, tooltip_arr_size)
			var b_idx = b_data.get(Keys.TAB_IDX, tooltip_arr_size)
			if a_idx != b_idx:
				return a_idx < b_idx
			
			var a_current_data = current_tabs.get(a, {})
			var b_current_data = current_tabs.get(b, {})
			var a_curr_idx = a_current_data.get(Keys.TAB_IDX, tooltip_arr_size)
			var b_curr_idx = b_current_data.get(Keys.TAB_IDX, tooltip_arr_size)
			if a_curr_idx != b_curr_idx:
				return a_curr_idx < b_curr_idx
			
			return a.get_file() < b.get_file()
			
			)
	
	var selected_scripts = metadata.get(Keys.SELECTED_SCRIPTS, {})
	
	for key in selected_scripts.keys(): # path is key, value is split
		if key.is_absolute_path():
			selected_scripts[UFile.uid_to_path(key)] = selected_scripts[key]
		selected_scripts.erase(key)
	
	var tabs_to_show := []
	var current_dummy:DummyEditor
	for tooltip in saved_tooltip_arr: # this has uids in it too, but they will just pull meta
		var data = current_tabs.get(tooltip)
		if data == null:
			continue # if not open, just skip
		var saved_data = saved_tab_tooltips.get(tooltip)
		var target_saved_tab = int(saved_data.get(Keys.TAB, 0))
		
		var idx = data.get(SLKeys.SCRIPT_IDX)
		var editor = script_editor_tab_container.get_child(idx)
		var dummy = select_or_add_new_tab(editor, target_saved_tab, false)
		if current_editor_index == idx:
			current_dummy = dummy
		elif selected_scripts.has(tooltip):
			tabs_to_show.append(dummy)
	
	for t in tab_containers:
		t._selected_flag = false # set this false so it can properly select below
		t.check_container_valid()
	
	for dummy in tabs_to_show:
		dummy.show()
	
	if is_instance_valid(current_dummy):
		current_dummy.show()
	
	_set_split_styles()
	set_deferred(&"_setup_complete_flag", true)


func _on_editor_tab_changed():
	#print("TAB CHANGED")
	var current = script_editor_tab_container.get_current_tab_control()
	if current in _script_editor_history:
		_script_editor_history.erase(current)
	_script_editor_history.append(current)
	
	#if script_list_manager.script_list_filtering():
		#script_list_manager.clear_script_list_filter()
		#script_list_manager.update_cache()
	
	_clean_script_editor_history()
	_set_split_styles()

func _clean_script_editor_history():
	var to_erase = []
	for i in range(_script_editor_history.size()):
		var editor = _script_editor_history[i]
		if not is_instance_valid(editor):
			to_erase.append(i)
	
	if not to_erase.is_empty():
		to_erase.reverse()
		for i in to_erase:
			_script_editor_history.remove_at(i)
	
	while _script_editor_history.size() > 5:
		_script_editor_history.pop_front()

func _on_script_list_manager_cache_updated():
	#print("UPDATED")
	_set_script_tab_data()

func _on_filesystem_changed():
	return
	_set_script_tab_data.call_deferred()

func _on_validate():
	return
	_set_script_tab_data.call_deferred()

func _set_script_tab_data():
	#await script_list_manager.update_cache()
	for t in tab_containers:
		t.update_tab_data()

func _on_new_tab_container(script_editor:Control, target_tab:int):
	select_or_add_new_tab(script_editor, target_tab)
	save_cache_data()

func select_or_add_new_tab(editor_node:Node, target_tab:int=0, activate:=true):
	if script_list_manager.script_list_filtering():
		script_list_manager.clear_script_list_filter()
		script_list_manager.update_cache()
	
	var script_list_data = script_list_manager.get_item_data(editor_node.get_index())
	var dummy_editor = get_dummy_editor_from_editor(editor_node) as DummyEditor
	
	if tab_containers.is_empty() or target_tab >= tab_containers.size():
		_new_tab_container()
		target_tab = tab_containers.size() - 1
	
	var target_tab_control = tab_containers[target_tab]
	if not is_instance_valid(dummy_editor):
		dummy_editor = target_tab_control.new_tab_script_editor(script_list_data, editor_node)
	else:
		if dummy_editor.get_parent() != target_tab_control:
			dummy_editor.set_active(false)
			dummy_editor.reparent(target_tab_control)
			target_tab_control.set_tab_data(dummy_editor.get_index(), script_list_data)
	
	UtilsLocal.ensure_connect(dummy_editor.symbol_lookup, _on_symbol_lookup, true)
	if activate:
		dummy_editor.set_active(true)
		dummy_editor.show()
	
	return dummy_editor


func _new_tab_container():
	var tab = DummyTab.new()
	if not _plugin_initialized:
		tab._defer_connection = true
	
	main_split_container.add_split(tab)
	#main_split_container.add_child(tab)
	var panel_sb = StyleBoxEmpty.new()
	panel_sb.content_margin_top = 2 * EditorInterface.get_editor_scale()
	tab.add_theme_stylebox_override(&"panel", panel_sb)
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.script_list_manager = script_list_manager
	tab.empty_container.connect(_on_empty_container.bind(tab))
	tab.tabs_changed.connect(_on_container_tab_changed)
	tab_containers.append(tab)

func _on_empty_container(container:DummyTab):
	tab_containers.erase(container)

func _on_container_tab_changed():
	_set_split_styles()

func clean_up_tab_containers():
	for t in tab_containers:
		for editor_node in t.dummy_editors.keys():
			if not is_instance_valid(editor_node):
				var dummy_editor = t.dummy_editors.get(editor_node)
				t.dummy_editors.erase(editor_node)
				dummy_editor.queue_free()

func _on_symbol_lookup():
	if _symbol_lookup_flag: return
	_symbol_lookup_flag = true
	await get_tree().process_frame
	_symbol_lookup_flag = false

func _on_script_editor_tab_container_child_changed():
	_clean_script_editor_history() #^r not sure about this here, I guess things can be removed without tab changing
	
	# TEST this will make sure all tabs are correct label right away?
	if script_list_manager.script_list_filtering():
		script_list_manager.clear_script_list_filter()
	script_list_manager.update_cache()
	
	# get last split and put it in a different one, this makes sense when opening from a link
	# maybe not when opening from filesystem
	var target_tab = 0
	var current_split = get_current_split()
	if is_instance_valid(current_split):
		target_tab = current_split.get_index()
	
	var last_split = get_last_split()
	if not is_instance_valid(last_split):
		target_tab = 0
	else:
		target_tab = last_split.get_index()
		if _symbol_lookup_flag:
			#var last_split_idx = last_split.get_index()
			#if target_tab == last_split_idx:
			target_tab += 1
		elif _open_script_tab_flag > -1:
			target_tab = _open_script_tab_flag
	
	#print("TARGET TAB::", target_tab, "::SYMBOL::", _symbol_lookup_flag)
	
	
	for node in script_editor_tab_container.get_children():
		if not UtilsLocal.is_node_script_editor(node):
			continue
		
		var dummy_editor = get_dummy_editor_from_editor(node)
		if not is_instance_valid(dummy_editor):
			select_or_add_new_tab(node, target_tab)
	
	clean_up_tab_containers()
	_open_script_tab_flag = -1


func get_dummy_editor_from_editor(editor_node:Node):
	var dummy_editor
	for t in tab_containers:
		dummy_editor = t.get_tab_by_editor(editor_node)
		if is_instance_valid(dummy_editor):
			break
	return dummy_editor

func get_current_split() -> DummyTab:
	return _get_split()

func get_last_split() -> DummyTab:
	return _get_split(2)

func _get_split(offset:int=1) -> DummyTab:
	var last_editor:Node
	if _script_editor_history.size() < offset:
		last_editor = script_editor_tab_container.get_current_tab_control()
	else:
		last_editor = _script_editor_history[_script_editor_history.size() - offset]
	
	if tab_containers.is_empty():
		return
	
	var split = tab_containers[0]
	for t in tab_containers:
		if t.has_tab_by_editor(last_editor):
			split = t
			break
	return split


func _set_split_styles():
	if tab_containers.size() == 1:
		var t = tab_containers[0]
		t.remove_theme_color_override(&"font_selected_color")
		t.remove_theme_stylebox_override(&"tab_selected")
		return
	
	var disabled_font_color = EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor")
	var current_split = get_current_split()
	for t in tab_containers:
		if t == current_split:
			t.remove_theme_color_override(&"font_selected_color")
			t.remove_theme_stylebox_override(&"tab_selected")
		else:
			t.add_theme_color_override(&"font_selected_color", disabled_font_color)
			t.add_theme_stylebox_override(&"tab_selected", unselected_split_stylebox)



func save_cache_data():
	DirAccess.make_dir_recursive_absolute(Keys.TAB_CACHE_PATH.get_base_dir())
	var data = {}
	var meta = {
		Keys.SELECTED_SCRIPTS: {},
		#Keys.SPLIT_OFFSETS: = main_split_container.spl # wrapper doesn't have split_offsets, would need  to create a getter
	}
	
	for i in range(tab_containers.size()):
		var tab_container = tab_containers[i]
		var dummy_editors = tab_container.dummy_editors.values()
		for ni in range(dummy_editors.size()):
			var dummy = dummy_editors[ni] as DummyEditor
			var tooltip = dummy.get_script_list_tooltip()
			if tooltip.begins_with("res://"):
				tooltip = UFile.path_to_uid(tooltip)
			data[tooltip] = {Keys.TAB: i, Keys.TAB_IDX: ni}
			if ni == tab_container.current_tab:
				meta[Keys.SELECTED_SCRIPTS][tooltip] = i
	
	
	data[Keys.META_DATA] = meta
	UFile.write_to_json(data, Keys.TAB_CACHE_PATH)



class Utils:
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
