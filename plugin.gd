@tool
extends EditorPlugin

const UFile = ALibRuntime.Utils.UFile
const UNode = ALibRuntime.Utils.UNode

const ScriptListManager = ALibEditor.Singletons.ScriptListManager
const SLKeys = ScriptListManager.Keys

const ScriptListContextMenu = preload("res://addons/script_tabs/src/editor_plugins/context_menu.gd")

var _plugin_initialized:=false

# editor
var script_editor_tab_container:TabContainer
#

var script_list_context_menu:ScriptListContextMenu
var script_list_manager:ScriptListManager
var _script_editor_history:Array= []

var main_split_container:HSplitContainer
var tab_containers:Array[DummyEditorTabContainer] = []

var unselected_split_stylebox:StyleBoxFlat

var _symbol_lookup_flag:=false

var _script_data_dirty:= true

func _get_plugin_name() -> String:
	return "Script Tabs"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")

func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree() -> void:
	await get_tree().create_timer(1).timeout
	EditorNodeRef.call_on_ready(_on_editor_node_ref_ready)

func _exit_tree() -> void:
	Utils.save_cache_data(tab_containers)
	
	remove_context_menu_plugin(script_list_context_menu)
	
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
	
	script_list_context_menu = ScriptListContextMenu.new()
	script_list_context_menu.new_tab_container.connect(_on_new_tab_container)
	script_list_context_menu.script_editor_tab_container = script_editor_tab_container
	script_list_context_menu.tab_containers = tab_containers
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR, script_list_context_menu)
	
	
	main_split_container = HSplitContainer.new()
	main_split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var script_tab_par = script_editor_tab_container.get_parent()
	script_tab_par.add_child(main_split_container)
	script_tab_par.move_child(main_split_container, 0)
	
	EditorNodeRef.refresh_dynamic_refs()
	
	_create_current_tabs()
	
	script_editor_tab_container.child_order_changed.connect(_on_script_editor_tab_container_child_changed, 1)
	_plugin_initialized = true


func _create_current_tabs():
	script_list_manager.clear_script_list_filter()
	script_list_manager.update_cache()
	var current_editor = script_editor_tab_container.get_current_tab_control()
	var current_editor_index = -1
	if is_instance_valid(current_editor):
		current_editor_index = current_editor.get_index()
	
	var saved_tab_tooltips = Utils.get_tab_data() # data is Dictionary[path, {tab, idx}]
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
	
	var current_dummy:DummyEditor
	for tooltip in saved_tooltip_arr:
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
	
	for t in tab_containers:
		t.check_container_valid()
	
	#script_list_manager.activate_item_by_idx(current_dummy.script_editor.get_index())
	#current_dummy.ensure_script_editor_selected.call_deferred()
	if is_instance_valid(current_dummy):
		current_dummy.show()
	#current_dummy.activate_script_editor()
	


func _on_editor_tab_changed():
	print("TAB CHANGED")
	var current = script_editor_tab_container.get_current_tab_control()
	if current in _script_editor_history:
		_script_editor_history.erase(current)
	_script_editor_history.append(current)
	
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


func _on_filesystem_changed():
	#_script_data_dirty = true
	_set_script_tab_data.call_deferred()

func _on_validate():
	#_script_data_dirty = true
	_set_script_tab_data.call_deferred()

func _set_script_tab_data():
	#await script_list_manager.update_cache()
	for t in tab_containers:
		t.update_tab_data()

func _on_new_tab_container(script_editor:Control, target_tab:int):
	select_or_add_new_tab(script_editor, target_tab)
	Utils.save_cache_data(tab_containers)

func select_or_add_new_tab(editor_node:Node, target_tab:int=0, activate:=true):
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
	
	Utils.ensure_connect(dummy_editor.symbol_lookup, _on_symbol_lookup, true)
	if activate:
		dummy_editor.set_active(true)
		dummy_editor.show()
	
	return dummy_editor


func _new_tab_container():
	var tab = DummyEditorTabContainer.new()
	if not _plugin_initialized:
		tab._defer_connection = true
	
	main_split_container.add_child(tab)
	var panel_sb = StyleBoxEmpty.new()
	panel_sb.content_margin_top = 2 * EditorInterface.get_editor_scale()
	tab.add_theme_stylebox_override(&"panel", panel_sb)
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.script_list_manager = script_list_manager
	tab.empty_container.connect(_on_empty_container.bind(tab))
	tab.tabs_changed.connect(_on_container_tab_changed)
	tab_containers.append(tab)

func _on_empty_container(container:DummyEditorTabContainer):
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
	
	#print("TARGET TAB::", target_tab, "::SYMBOL::", _symbol_lookup_flag)
	
	
	for node in script_editor_tab_container.get_children():
		if not Utils.is_node_script_editor(node):
			continue
		
		var dummy_editor = get_dummy_editor_from_editor(node)
		if not is_instance_valid(dummy_editor):
			select_or_add_new_tab(node, target_tab)
	
	clean_up_tab_containers()


func get_dummy_editor_from_editor(editor_node:Node):
	var dummy_editor
	for t in tab_containers:
		dummy_editor = t.get_tab_by_editor(editor_node)
		if is_instance_valid(dummy_editor):
			break
	return dummy_editor

func get_current_split() -> DummyEditorTabContainer:
	return _get_split()

func get_last_split() -> DummyEditorTabContainer:
	return _get_split(2)

func _get_split(offset:int=1) -> DummyEditorTabContainer:
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


class DummyEditorTabContainer extends TabContainer:
	var _defer_connection:=false
	
	var tab_history:=[]
	
	var script_list_manager:ScriptListManager
	var dummy_editors:Dictionary = {}
	
	#var _close_queued:=""
	
	signal tabs_changed
	signal empty_container
	
	func _ready() -> void:
		var tab_bar = get_tab_bar()
		tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
		tab_bar.select_with_rmb = true
		tab_bar.tab_close_pressed.connect(_on_tab_closed)
		tab_bar.tab_rmb_clicked.connect(_on_tab_rmb_clicked, 1)
		
		drag_to_rearrange_enabled = true
		tabs_rearrange_group = 100
		tab_selected.connect(_on_tab_selected)
		tab_changed.connect(_on_tab_changed, 1)
		
		if _defer_connection: # defer connection during plugin startup to speed things up
			child_order_changed.connect.call_deferred(_child_order_changed)
		else:
			child_order_changed.connect(_child_order_changed)
	
	func _child_order_changed():
		dummy_editors.clear()
		for tab in get_children():
			if not tab is DummyEditor:
				continue
			dummy_editors[tab.script_editor] = tab
		
		check_container_valid()
		tabs_changed.emit.call_deferred()
	
	func check_container_valid():
		if dummy_editors.is_empty():
			empty_container.emit()
			queue_free()
	
	func new_tab_script_editor(script_list_data:Dictionary, editor) -> DummyEditor:
		var dummy_editor = dummy_editors.get(editor)
		if not is_instance_valid(dummy_editor):
			dummy_editor = DummyEditor.new()
			dummy_editor.script_list_data = script_list_data
			dummy_editor.script_list_manager = script_list_manager
			dummy_editor.set_script_editor(editor)
			add_child(dummy_editor)
			
		var index = dummy_editor.get_index()
		set_tab_data(index, script_list_data)
		dummy_editors[editor] = dummy_editor
		return dummy_editor
	
	func _on_tab_selected(_tab:int):
		activate_current.call_deferred()
	
	func _on_tab_changed(tab:int):
		var dummy_editor = get_tab_control(tab) as DummyEditor
		if not is_instance_valid(dummy_editor):
			return
		if not dummy_editor.is_active: # if it hasn't been activated, will move contents over
			dummy_editor.soft_activate() # then reselect the current editor, stops empty tabs on close
		#dummy_editor.set_doc_style_box(true)
		
		if dummy_editor in tab_history:
			tab_history.erase(dummy_editor)
		tab_history.append(dummy_editor)
	
	func activate_current():
		var dummy_editor = get_current_tab_control() as DummyEditor
		if not is_instance_valid(dummy_editor):
			return
		for d in get_children():
			d.set_active(d == dummy_editor)
	
	
	func _on_tab_closed(tab:int):
		var dummy_editor = get_tab_control(tab) as DummyEditor
		script_list_manager.close_script_by_idx(dummy_editor.get_script_index())
		
		await get_tree().process_frame
		if is_instance_valid(dummy_editor):
			return
		
		#^r this needs to account for when the dialog shows
		#^r early exit above at least stops accidental tab changes
		var last_tab = _get_previous_tab()
		if is_instance_valid(last_tab):
			print("SHOWING LAST")
			last_tab.show()
	
	func _on_tab_rmb_clicked(tab:int):
		var dummy_editor = get_tab_control(tab) as DummyEditor
		script_list_manager.right_click_by_idx(dummy_editor.get_script_index(), get_global_mouse_position())
	
	
	func update_tab_data():
		for tab:DummyEditor in get_children():
			var data = script_list_manager.item_cache.get(tab.get_script_index())
			if data != null:
				set_tab_data(tab.get_index(), data)
	
	
	func set_tab_data(idx:int, script_list_data:Dictionary):
		set_tab_title(idx, script_list_data.get(SLKeys.NAME))
		set_tab_icon(idx, script_list_data.get(SLKeys.ICON))
		set_tab_tooltip(idx, script_list_data.get(SLKeys.TOOLTIP))
	
	
	func get_tab_by_data(script_list_data:Dictionary):
		var tooltip = script_list_data.get(SLKeys.TOOLTIP)
		return dummy_editors.get(tooltip)
	
	func get_tab_by_editor(editor):
		return dummy_editors.get(editor)
	
	func has_tab_by_editor(editor):
		return dummy_editors.has(editor)
	
	func remove_tab_by_editor(editor):
		var dummy = dummy_editors.get(editor)
		dummy_editors.erase(editor)
		remove_child(dummy)
		dummy.queue_free()
	
	
	func _get_previous_tab():
		var prev_idx = tab_history.size() - 2
		if prev_idx > -1:
			return tab_history[prev_idx]
	
	func clean_up():
		for d in dummy_editors.values():
			d.clean_up()



class DummyEditor extends VBoxContainer:
	
	enum EditorType {
		TEXT_EDITOR,
		SCRIPT_EDITOR,
		EDITOR_HELP,
	}
	var editor_type:EditorType
	
	var _initialized:= false
	var is_active:=false
	
	var script_list_manager:ScriptListManager
	var script_list_data:= {}
	
	# editor
	var script_editor:Control
	var code_edit:CodeEdit
	var rich_text:RichTextLabel
	var bottom_panel:Control
	
	# this is the size of the warnings button
	var bottom_panel_min_size:= 33 * EditorInterface.get_editor_scale()
	
	var _stylebox_doc:StyleBox
	var _stylebox_doc_overide:StyleBox
	
	var _dummy_vsplit:VSplitContainer
	var _dummy_code_text_editor:DummyCTE
	var _editor_replace_nodes := []
	
	var _current_editor_check_debounce:=false
	
	signal symbol_lookup
	
	func set_script_editor(_script_editor:Control):
		script_editor = _script_editor
		script_editor.visibility_changed.connect(_on_script_editor_visibility_changed)
		#visibility_changed.connect(_on_visibility_changed)
		
		var script_ed_class = script_editor.get_class()
		if script_ed_class == &"ScriptTextEditor":
			editor_type = EditorType.SCRIPT_EDITOR
		elif script_ed_class == &"TextEditor":
			editor_type = EditorType.TEXT_EDITOR
		elif script_ed_class == &"EditorHelp":
			editor_type = EditorType.EDITOR_HELP
	
	
	func _initialize():
		_initialized = true
		if editor_type == EditorType.EDITOR_HELP:
			rich_text = script_editor.get_child(0)
			bottom_panel = script_editor.get_child(2)
		else:
			if editor_type == EditorType.SCRIPT_EDITOR:
				_create_vsplit()
				_create_code_text(_dummy_vsplit)
			elif editor_type == EditorType.TEXT_EDITOR:
				_create_code_text(self)
			
			code_edit = script_editor.get_base_editor()
			for node in script_editor.get_children():
				if node is Popup:
					Utils.ensure_connect(node.about_to_popup, _about_to_popup.bind(node), true)
			var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
			bottom_panel = code_text_editor.get_child(1)
	
	func _create_vsplit():
		_dummy_vsplit = VSplitContainer.new()
		_dummy_vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_dummy_vsplit.name = "DummyVSplit"
		add_child(_dummy_vsplit)
	
	func _create_code_text(parent:Node):
		_dummy_code_text_editor = DummyCTE.new()
		parent.add_child(_dummy_code_text_editor)
		_dummy_code_text_editor.name = "DummyCTE"
		_dummy_code_text_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	
	func set_active(active:bool):
		if not is_instance_valid(script_editor):
			return # necessary for when being deleted
		if not active and not _initialized:
			return
		
		if active: # ensure factory script list has all items for activating
			script_list_manager.clear_script_list_filter()
		
		var hide_sidebar_button = _get_hide_sidebar_button()
		if is_instance_valid(hide_sidebar_button):
			var in_left_split = get_parent().get_index() == 0
			hide_sidebar_button.visible = not active or in_left_split
		
		if is_active and active:
			ensure_script_editor_selected()
			return
		
		is_active = active
		if active:
			activate_script_editor()
		move_children(active)
	
	
	func move_children(active:bool):
		if not active and not _initialized:
			return
		
		if active:
			if is_instance_valid(_dummy_code_text_editor):
				_dummy_code_text_editor.set_script_editor(script_editor)
		
		if editor_type == EditorType.EDITOR_HELP:
			if active:
				if get_child_count() == 0:
					Utils.reparent_children(script_editor, self)
				set_doc_style_box.call_deferred(active)
			#else: # commenting this stops RichTextLabel from redrawing, seems ok to just free everything
				#Utils.reparent_children(self, script_editor)
			
		elif editor_type == EditorType.TEXT_EDITOR:
			var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
			if not is_instance_valid(code_text_editor):
				return
			
			if active:
				Utils.reparent_children(code_text_editor, _dummy_code_text_editor)
				Utils.reparent_children(script_editor, self, [code_text_editor])
			else:
				Utils.reparent_children(_dummy_code_text_editor, code_text_editor)
				Utils.reparent_children(self, script_editor, [_dummy_code_text_editor])
			
		elif editor_type == EditorType.SCRIPT_EDITOR:
			var vsplit_container = script_editor.find_children("*","VSplitContainer", true, false).pop_front()
			var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
			if not is_instance_valid(vsplit_container):
				return
			
			if active:
				Utils.reparent_children(code_text_editor, _dummy_code_text_editor)
				Utils.reparent_children(vsplit_container, _dummy_vsplit, [code_text_editor])
				Utils.reparent_children(script_editor, self, [vsplit_container])
				
				 # HACK: these just stop an error from firing when closing a editor. Trying to get_child that isn't there
				Utils.add_filler_nodes([script_editor, vsplit_container], _editor_replace_nodes)
			else:
				Utils.reparent_children(_dummy_code_text_editor, code_text_editor)
				Utils.reparent_children(_dummy_vsplit, vsplit_container, [_dummy_code_text_editor])
				Utils.reparent_children(self, script_editor, [_dummy_vsplit])
		
		if is_instance_valid(_dummy_code_text_editor):
			_dummy_code_text_editor.set_active(active)
		
		_set_bottom_panel_size(active)
		
		if is_instance_valid(code_edit):
			Utils.ensure_connect(code_edit.symbol_lookup, _on_symbol_lookup, active)
			Utils.ensure_connect(code_edit.gui_input, _on_code_edit_gui_input, active)
		elif is_instance_valid(rich_text):
			Utils.ensure_connect(rich_text.meta_clicked, _on_rich_text_meta_clicked, active)
			Utils.ensure_connect(rich_text.gui_input, _on_rich_text_gui_input, active)
		
		if active:
			_code_edit_grab_focus()
		else:
			for node in _editor_replace_nodes:
				if is_instance_valid(node):
					node.queue_free()
			_editor_replace_nodes.clear()
	
	
	func ensure_script_editor_selected():
		if _current_editor_check_debounce:
			return
		_current_editor_check_debounce = true
		var current_idx = script_list_manager.get_current_script_editor_index()
		if current_idx > -1 and current_idx != get_script_index():
			move_children(false)
			is_active = false
			set_active(true)
		_current_editor_check_debounce = false
	
	func soft_activate():
		var current_editor_idx = script_list_manager.get_current_script_editor_index()
		var self_idx = get_script_index()
		move_children(false)
		set_active(true)
		if current_editor_idx != self_idx:
			script_list_manager.activate_item_by_idx(current_editor_idx)
	
	
	func set_doc_style_box(active:bool):
		if editor_type != EditorType.EDITOR_HELP or not _initialized:
			return
		if active:
			if not is_instance_valid(_stylebox_doc):
				_stylebox_doc = rich_text.get_theme_stylebox(&"normal")
				_stylebox_doc_overide = _stylebox_doc.duplicate()
			
			var wrapper_size = max(rich_text.size.x * 0.15, 50)
			_stylebox_doc_overide.content_margin_left = wrapper_size
			_stylebox_doc_overide.content_margin_right = wrapper_size
			rich_text.add_theme_stylebox_override(&"normal", _stylebox_doc_overide)
		else:
			if is_instance_valid(_stylebox_doc):
				rich_text.add_theme_stylebox_override(&"normal", _stylebox_doc)
	
	func _get_hide_sidebar_button():
		if is_instance_valid(bottom_panel):
			return bottom_panel.get_child(0)
	
	func _set_bottom_panel_size(active:bool):
		if active:
			bottom_panel.custom_minimum_size.y = bottom_panel_min_size
		else:
			bottom_panel.custom_minimum_size.y = 0
	
	
	func _on_script_editor_visibility_changed():
		if script_editor.visible:
			show()
	
	func _on_visibility_changed():
		print("SET VIS::", visible, "::", get_script_list_tooltip())
		#set_doc_style_box.call_deferred(visible)
	
	func _about_to_popup(popup:Popup):
		var mouse_pos = DisplayServer.mouse_get_position()
		if popup.get_class() == "GotoLinePopup":
			await get_tree().process_frame
			mouse_pos -= Vector2i(popup.size / 2.0)
		popup.position = mouse_pos
	
	func _on_rich_text_gui_input(event:InputEvent) -> void:
		if event is InputEventMouseButton:
			activate_script_editor()
	
	func _on_code_edit_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			ensure_script_editor_selected()
		if event is InputEventKey:
			if event.keycode == Key.KEY_ENTER:
				_dummy_code_text_editor.timer.stop()
	
	func _on_symbol_lookup(_symbol:String, _line:int, _col:int):
		symbol_lookup.emit()
	
	func _on_rich_text_meta_clicked(_arg):
		if Input.is_key_pressed(KEY_CTRL):
			symbol_lookup.emit()
	
	
	func activate_script_editor():
		script_list_manager.activate_item_by_idx(get_script_index())
		if not _initialized:
			_initialize()
	
	func _code_edit_grab_focus():
		if is_instance_valid(code_edit):
			code_edit.grab_focus()
	
	func get_script_index():
		return script_editor.get_index()
	
	func get_script_list_tooltip():
		return script_list_data.get(SLKeys.TOOLTIP)
	
	func get_script_list_name():
		return script_list_data.get(SLKeys.NAME)
	
	func get_script_list_icon():
		return script_list_data.get(SLKeys.ICON)
	
	func clean_up():
		set_doc_style_box(false)
		if is_instance_valid(script_editor):
			set_active(false)
		queue_free()


class DummyCTE extends VBoxContainer:
	var code_edit:CodeEdit
	var timer:Timer
	
	func set_script_editor(script_editor):
		if is_instance_valid(code_edit) and is_instance_valid(timer):
			return
		
		code_edit = script_editor.find_children("*", "CodeEdit", true, false).pop_front()
		var timers = script_editor.find_children("*", "Timer", true, false)
		for t:Timer in timers:
			var callable = UNode.get_signal_callable(t, "timeout", Keys.CODE_COMPLETE_CALLABLE)
			if callable:
				timer = t
				break
	
	func set_active(state:bool):
		if not is_instance_valid(code_edit):
			return
		Utils.ensure_connect(code_edit.text_changed, _on_text_changed, state)
		Utils.ensure_connect(timer.timeout, _on_code_complete_timeout, state)
	
	## Needs to be called after moving to, or before moving from
	func set_side_panel_button_vis(vis:bool, first_tab:=true):
		if first_tab:
			vis = true
		if get_child_count() > 0:
			get_child(1).get_child(0).visible = vis
	
	func _on_text_changed():
		timer.start()
	
	func _on_code_complete_timeout():
		code_edit.request_code_completion()
	
	func _on_code_edit_sig():
		timer.stop()



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
	
	static func save_cache_data(tab_container_array:Array[DummyEditorTabContainer]):
		DirAccess.make_dir_recursive_absolute(Keys.TAB_CACHE_PATH.get_base_dir())
		var data = {}
		for i in range(tab_container_array.size()):
			var tab_container = tab_container_array[i]
			var dummy_editors = tab_container.dummy_editors.values()
			for ni in range(dummy_editors.size()):
				var dummy = dummy_editors[ni] as DummyEditor
				var tooltip = dummy.get_script_list_tooltip()
				if tooltip.begins_with("res://"):
					tooltip = UFile.path_to_uid(tooltip)
				data[tooltip] = {Keys.TAB: i, Keys.TAB_IDX: ni}
		
		UFile.write_to_json(data, Keys.TAB_CACHE_PATH)


class Keys:
	
	const TAB_IDX = &"tab_idx"
	const TAB = &"tab"
	
	const STYLEBOX_DOC = &"stylebox_doc"
	
	const CODE_COMPLETE_CALLABLE = &"CodeTextEditor::_code_complete_timer_timeout"
	
	const SCRIPT_EDITOR_CLASSES = [&"ScriptTextEditor", &"TextEditor", &"EditorHelp"]
	
	const TAB_CACHE_PATH = &"res://.godot/addons/script_tabs/current_layout.json"
