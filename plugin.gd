@tool
extends EditorPlugin

const UNode = ALibRuntime.Utils.UNode

const ScriptListContextMenu = preload("res://addons/script_tabs/src/editor_plugins/context_menu.gd")

var unselected_split_stylebox:StyleBoxFlat

func _get_plugin_name() -> String:
	return "Script Tabs"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")

var script_editor_tab_container:TabContainer


var script_list_context_menu:ScriptListContextMenu
var script_list_manager:ScriptListManager

var main_split_container:HSplitContainer
var tab_containers:Array[DummyEditorTabContainer] = []

var _script_editor_history := []

var _script_data_dirty:= true


func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree() -> void:
	await get_tree().create_timer(1).timeout
	EditorNodeRef.call_on_ready(_on_editor_node_ref_ready)

func _exit_tree() -> void:
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
	
	var side_bar = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.SCRIPT_EDITOR_SIDEBAR_V_SPLIT)
	script_list_manager = ScriptListManager.new()
	script_list_manager.script_list = side_bar.get_child(0).get_child(1)
	script_list_manager.filter_line_edit = side_bar.get_child(0).get_child(0)
	
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
	
	script_editor_tab_container.child_order_changed.connect(_on_script_editor_tab_container_child_changed, 1)
	
	_create_current_tabs()


func _create_current_tabs():
	if tab_containers.is_empty():
		_new_tab_container()
	var tab = tab_containers[0]
	var script_list = script_list_manager.script_list
	for i in range(script_list.item_count):
		var item_data = script_list_manager.get_item_data(i)
		var editor = script_editor_tab_container.get_child(i)
		tab.new_tab_script_editor(item_data, editor)
	
	if tab.get_tab_count() > 0:
		tab.current_tab = 0


func _on_editor_tab_changed():
	var current = script_editor_tab_container.get_current_tab_control()
	script_list_manager.current_script_editor = current
	
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
	await script_list_manager.update_cache()
	for t in tab_containers:
		t.update_tab_data()

func _on_new_tab_container(script_editor:Control, target_tab:int):
	if target_tab == tab_containers.size():
		_new_tab_container()
	select_or_add_new_tab(script_editor, target_tab)

func _new_tab_container():
	var tab = DummyEditorTabContainer.new()
	main_split_container.add_child(tab)
	tab.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.script_list_manager = script_list_manager
	tab.empty_container.connect(_on_empty_container.bind(tab))
	tab_containers.append(tab)

func _on_empty_container(container:DummyEditorTabContainer):
	tab_containers.erase(container)

func clean_up_tab_containers():
	for t in tab_containers:
		for editor_node in t.dummy_editors.keys():
			if not is_instance_valid(editor_node):
				var dummy_editor = t.dummy_editors.get(editor_node)
				t.dummy_editors.erase(editor_node)
				dummy_editor.queue_free()


func _on_script_editor_tab_container_child_changed():
	_clean_script_editor_history() #^r not sure about this here, I guess things can be removed without tab changing
	
	# get last split and put it in a different one, this makes sense when opening from a link
	# maybe not when opening from filesystem
	var target_tab = 0
	var last_split = get_last_split()
	if is_instance_valid(last_split):
		var last_split_idx = last_split.get_index()
		if target_tab == last_split_idx:
			target_tab += 1
	
	for node in script_editor_tab_container.get_children():
		if not Utils.is_node_script_editor(node):
			continue
		#if node.visible:
			#script_list_manager.current_script_editor = node
		
		var dummy_editor = get_dummy_editor_from_editor(node)
		if not is_instance_valid(dummy_editor):
			select_or_add_new_tab(node, target_tab)
	
	clean_up_tab_containers()


func select_or_add_new_tab(editor_node:Node, target_tab:int=0):
	print("YUYUYU")
	print("PAR::", editor_node.get_parent())
	print("INDEX::", editor_node.get_index(), "::CHILD COUNT::", editor_node.get_parent().get_child_count())
	var script_list_data = script_list_manager.get_item_data(editor_node.get_index())
	print(script_list_data)
	var dummy_editor = get_dummy_editor_from_editor(editor_node) as DummyEditor
	print(dummy_editor)
	print("YUYUYU")
	
	if tab_containers.is_empty() or target_tab >= tab_containers.size():
		_new_tab_container()
		target_tab = tab_containers.size() - 1
	
	var target_tab_control = tab_containers[target_tab]
	if not is_instance_valid(dummy_editor):
		dummy_editor = target_tab_control.new_tab_script_editor(script_list_data, editor_node)
	else:
		if dummy_editor.get_parent() != target_tab_control:
			dummy_editor.set_active(false)
			var old_tab = dummy_editor.get_parent() as DummyEditorTabContainer
			old_tab.move_tab_to_new_container(dummy_editor, target_tab_control)
			target_tab_control.set_tab_data(dummy_editor.get_index(), script_list_data)
	
	dummy_editor.set_active(true)
	dummy_editor.show()


func get_dummy_editor_from_editor(editor_node:Node):
	var dummy_editor
	for t in tab_containers:
		dummy_editor = t.get_tab_by_editor(editor_node)
		if is_instance_valid(dummy_editor):
			break
	return dummy_editor

func get_current_split():
	return _get_split()

func get_last_split():
	return _get_split(2)

func _get_split(offset:int=1):
	var last_editor:Node
	if _script_editor_history.size() < offset:
		last_editor = script_editor_tab_container.get_current_tab_control()
	else:
		last_editor = _script_editor_history[_script_editor_history.size() - offset]
	
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
	var script_list_manager:ScriptListManager
	var dummy_editors:Dictionary = {}
	
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
		
		child_order_changed.connect(_child_order_changed)
	
	
	func _child_order_changed():
		dummy_editors.clear()
		for tab in get_children():
			if not tab is DummyEditor:
				continue
			dummy_editors[tab.script_editor] = tab
		
		check_container_valid()
	
	func check_container_valid():
		if dummy_editors.is_empty():
			empty_container.emit()
			queue_free()
	
	
	func _on_tab_selected(_tab:int):
		activate_current.call_deferred()
	
	func _on_tab_changed(tab:int):
		var dummy_editor = get_tab_control(tab) as DummyEditor
		if not dummy_editor.is_active: # if it hasn't been activated, will move contents over
			dummy_editor.soft_activate() # then reselect the current editor, stops empty tabs on close
	
	func activate_current():
		var dummy_editor = get_current_tab_control() as DummyEditor
		if not is_instance_valid(dummy_editor):
			return
		for d in get_children():
			d.set_active(d == dummy_editor)
	
	
	func _on_tab_closed(tab:int):
		var dummy_editor = get_tab_control(tab) as DummyEditor
		script_list_manager.close_script_by_idx(dummy_editor.get_script_index())
	
	func _on_tab_rmb_clicked(tab:int):
		var dummy_editor = get_tab_control(tab) as DummyEditor
		script_list_manager.right_click_by_idx(dummy_editor.get_script_index(), get_global_mouse_position())
	
	
	func new_tab_script_editor(script_list_data:Dictionary, editor):
		var dummy_editor = get_or_add_empty_tab(script_list_data, editor)
		return dummy_editor
	
	func get_or_add_empty_tab(script_list_data:Dictionary, editor) -> DummyEditor:
		var dummy_editor = dummy_editors.get(editor)
		if not is_instance_valid(dummy_editor):
			dummy_editor = DummyEditor.new_empty(script_list_data)
			dummy_editor.script_list_manager = script_list_manager
			dummy_editor.set_script_editor(editor)
			add_child(dummy_editor)
			
		var index = dummy_editor.get_index()
		set_tab_data(index, script_list_data)
		dummy_editors[editor] = dummy_editor
		return dummy_editor
	
	
	func update_tab_data():
		for tab:DummyEditor in get_children():
			var tooltip = tab.get_script_list_tooltip()
			var data = script_list_manager.item_cache.get(tooltip)
			if data != null:
				set_tab_data(tab.get_index(), data)
			if tab.script_editor == script_list_manager.current_script_editor:
				
				pass
		
	
	func set_tab_data(idx:int, script_list_data:Dictionary):
		set_tab_title(idx, script_list_data.get(Keys.NAME))
		set_tab_icon(idx, script_list_data.get(Keys.ICON))
		set_tab_tooltip(idx, script_list_data.get(Keys.TOOLTIP))
		#add_theme_icon_override() # modulate somehow?
	
	
	
	func get_tab_by_data(script_list_data:Dictionary):
		var tooltip = script_list_data.get(Keys.TOOLTIP)
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
	
	func move_tab_to_new_container(dummy_editor:DummyEditor, new_parent:DummyEditorTabContainer):
		dummy_editor.reparent(new_parent)
	
	func clean_up():
		for d in dummy_editors.values():
			d.clean_up()



class DummyEditor extends VBoxContainer:
	var script_list_manager:ScriptListManager
	
	var script_list_data:= {}
	
	enum EditorType {
		TEXT_EDITOR,
		SCRIPT_EDITOR,
		EDITOR_HELP,
	}
	
	var editor_type:EditorType
	
	var script_editor:Control
	
	var code_edit:CodeEdit
	var script_resource:GDScript
	var script_path:String
	
	var _dummy_vsplit:VSplitContainer
	var _dummy_code_text_editor:DummyCTE
	var is_text_editor:bool
	
	var is_active:=false
	var _current_editor_check_debounce:=false
	
	var _editor_replace_nodes := []
	
	static func new_empty(_script_list_data:Dictionary) -> DummyEditor:
		var ins = new()
		ins.script_list_data = _script_list_data
		return ins
	
	
	func set_script_editor(_script_editor:Control):
		script_editor = _script_editor
		script_editor.visibility_changed.connect(_on_script_editor_visibility_changed)
		
		var script_ed_class = script_editor.get_class()
		if script_ed_class == &"ScriptTextEditor":
			editor_type = EditorType.SCRIPT_EDITOR
			_create_vsplit()
			_create_code_text(_dummy_vsplit)
			is_code_edit()
		elif script_ed_class == &"TextEditor":
			editor_type = EditorType.TEXT_EDITOR
			_create_code_text(self)
			#code_edit = script_editor.get_base_editor()
			is_code_edit()
		elif script_ed_class == &"EditorHelp":
			editor_type = EditorType.EDITOR_HELP
			var rich_text = script_editor.get_child(0)
			rich_text.gui_input.connect(_on_rich_text_gui_input)
	
	
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
			return
		
		if is_active and active:
			ensure_script_editor_selected()
			return
		
		is_active = active
		if active:
			activate_script_editor()
		move_children(active)
	
	
	func move_children(active:bool):
		var left_split = get_parent().get_index() == 0
		
		if editor_type == EditorType.EDITOR_HELP:
			if active:
				Utils.reparent_children(script_editor, self)
				
				if not left_split:
					get_child(2).get_child(0).hide()
				var rich_text = get_child(0) as RichTextLabel
				#var sb = rich_text.get_theme_stylebox(&"normal").duplicate()
				#sb.content_margin_left = 50
				#sb.content_margin_right = 50
				#rich_text.add_theme_stylebox_override(&"normal", sb)
			else:
				if get_child_count() > 0:
					get_child(2).get_child(0).show()
					var rich_text = get_child(0) as RichTextLabel
					rich_text.remove_theme_stylebox_override(&"normal")
				
				Utils.reparent_children(self, script_editor)
			
		elif editor_type == EditorType.TEXT_EDITOR:
			var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
			if not is_instance_valid(code_text_editor):
				return
			
			if active:
				_dummy_code_text_editor.set_script_editor(script_editor)
				Utils.reparent_children(code_text_editor, _dummy_code_text_editor)
				Utils.reparent_children(script_editor, self, [code_text_editor])
				
				_dummy_code_text_editor.set_side_panel_button_vis(false, left_split)
			else:
				_dummy_code_text_editor.set_side_panel_button_vis(true)
				
				Utils.reparent_children(_dummy_code_text_editor, code_text_editor)
				Utils.reparent_children(self, script_editor, [_dummy_code_text_editor])
			
			_dummy_code_text_editor.set_active(active)
			if is_instance_valid(code_edit):
				Utils.ensure_connect(code_edit.gui_input, _on_code_edit_gui_input, active)
			
		elif editor_type == EditorType.SCRIPT_EDITOR:
			var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
			var vsplit_container = script_editor.find_children("*","VSplitContainer", true, false).pop_front()
			if not is_instance_valid(vsplit_container):
				return
			
			if active:
				_dummy_code_text_editor.set_script_editor(script_editor)
				Utils.reparent_children(code_text_editor, _dummy_code_text_editor)
				Utils.reparent_children(vsplit_container, _dummy_vsplit, [code_text_editor])
				Utils.reparent_children(script_editor, self, [vsplit_container])
				
				var to_add_nodes = [script_editor, vsplit_container]
				for i in range(2): # HACK: these just stop an error from firing when closing a editor. Trying to get_child that isn't there
					for par in to_add_nodes:
						var node = Node.new()
						par.add_child(node)
						_editor_replace_nodes.append(node)
				
				_dummy_code_text_editor.set_side_panel_button_vis(false, left_split)
			else:
				_dummy_code_text_editor.set_side_panel_button_vis(true)
				
				Utils.reparent_children(_dummy_code_text_editor, code_text_editor)
				Utils.reparent_children(_dummy_vsplit, vsplit_container, [_dummy_code_text_editor])
				Utils.reparent_children(self, script_editor, [_dummy_vsplit])
			
			_dummy_code_text_editor.set_active(active)
			if is_instance_valid(code_edit):
				Utils.ensure_connect(code_edit.gui_input, _on_code_edit_gui_input, active)
		
		if not active:
			for node in _editor_replace_nodes:
				if is_instance_valid(node):
					node.queue_free()
			_editor_replace_nodes.clear()
	
	
	func _on_script_editor_visibility_changed():
		#return
		if script_editor.visible:
			show()
	
	func is_code_edit():
		code_edit = script_editor.get_base_editor()
		for node in script_editor.get_children():
			if node is Popup:
				node.about_to_popup.connect(_about_to_popup.bind(node))
	
	
	
	func _about_to_popup(popup:Popup):
		var mouse_pos = DisplayServer.mouse_get_position()
		if popup.get_class() == "GotoLinePopup":
			await get_tree().process_frame
			mouse_pos -= Vector2i(popup.size / 2.0)
		popup.position = mouse_pos
	
	func _on_rich_text_gui_input(event:InputEvent) -> void:
		if event is InputEventMouseButton:
			activate_script_editor()
			#ensure_script_editor_selected()
			return
	
	func _on_code_edit_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			ensure_script_editor_selected()
		if event is InputEventKey:
			if event.keycode == Key.KEY_ENTER:
				_dummy_code_text_editor.timer.stop()
	
	func ensure_script_editor_selected():
		if _current_editor_check_debounce:
			return
		_current_editor_check_debounce = true
		var current_idx = script_list_manager.current_script_editor.get_index()
		if current_idx > -1 and current_idx != get_script_index():
			move_children(false)
			activate_script_editor()
			move_children(true)
		_current_editor_check_debounce = false
	
	func soft_activate():
		var current_editor_idx = script_list_manager.current_script_editor.get_index()
		var self_idx = get_script_index()
		move_children(false)
		set_active(true)
		if current_editor_idx != self_idx:
			script_list_manager.activate_item_by_idx(current_editor_idx)
	
	func activate_script_editor():
		#var tooltip = get_script_list_tooltip()
		#script_list_manager.activate_item_by_tooltip(tooltip)
		script_list_manager.activate_item_by_idx(get_script_index())
	
	func get_script_index():
		return script_editor.get_index()
	
	func get_script_list_tooltip():
		return script_list_data.get(Keys.TOOLTIP)
	
	func get_script_list_name():
		return script_list_data.get(Keys.NAME)
	
	func get_script_list_icon():
		return script_list_data.get(Keys.ICON)
	
	func clean_up():
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
		#Utils.ensure_connect(, _on_text_changed, state)
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
	
	


class ScriptListManager:
	var script_list:ItemList
	var filter_line_edit:LineEdit
	
	var current_script_editor:Node
	
	var item_cache:= {}
	
	func update_cache():
		var current_text = filter_line_edit.text
		if current_text != "":
			filter_line_edit.clear()
		
		item_cache = get_all_script_data()
		
		if current_text != "":
			filter_line_edit.text = current_text
			filter_line_edit.text_changed.emit(current_text)
		
	func get_current_item():
		var sel = -1
		var items = script_list.get_selected_items()
		if not items.is_empty():
			sel = items[0]
		return sel
	
	func get_item_by_tooltip(tooltip:String):
		var data = item_cache.get(tooltip)
		if data == null:
			return -1
		return data.get(Keys.IDX, -1)
		
		for i in range(script_list.item_count):
			if tooltip == script_list.get_item_tooltip(i):
				return i
		return -1
	
	func get_current_item_data():
		var sel = get_current_item()
		if sel > -1:
			return get_item_data(sel)
		return {}
	
	func get_item_data(idx:int):
		var text = script_list.get_item_text(idx)
		var tooltip = script_list.get_item_tooltip(idx)
		var icon = script_list.get_item_icon(idx)
		var icon_mod = script_list.get_item_icon_modulate(idx)
		return {Keys.NAME:text, Keys.TOOLTIP:tooltip, Keys.ICON: icon, Keys.ICON_MOD: icon_mod, Keys.IDX: idx}
	
	
	func close_script_by_idx(idx:int):
		script_list.item_clicked.emit(idx, Vector2(), MOUSE_BUTTON_MIDDLE)
	
	func right_click_by_idx(idx:int, position:Vector2):
		script_list.item_clicked.emit(idx, position, MOUSE_BUTTON_RIGHT)
	
	func activate_item_by_idx(idx:int):
		script_list.item_selected.emit(idx)
	
	
	func close_script_by_tooltip(tooltip:String):
		var idx = get_item_by_tooltip(tooltip)
		if idx == -1:
			printerr("COULD NOT GET SCRIPT::CLOSE::", tooltip)
			return
		script_list.item_clicked.emit(idx, Vector2(), MOUSE_BUTTON_MIDDLE)
	
	func right_click_by_tooltip(tooltip:String, position:Vector2):
		var idx = get_item_by_tooltip(tooltip)
		if idx == -1:
			printerr("COULD NOT GET SCRIPT::RIGHT CLICK::", tooltip)
			return
		script_list.item_clicked.emit(idx, position, MOUSE_BUTTON_RIGHT)
	
	func activate_item_by_tooltip(tooltip:String):
		var idx = get_item_by_tooltip(tooltip)
		if idx == -1:
			printerr("COULD NOT GET SCRIPT::ACTIVATE::", tooltip)
			return
		
		script_list.item_selected.emit(idx)
	
	func get_all_script_data():
		var all_data = {}
		for i in range(script_list.item_count):
			var tooltip = script_list.get_item_tooltip(i)
			all_data[tooltip] = get_item_data(i)
		return all_data


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


class Keys:
	const NAME = &"name"
	const TOOLTIP = &"tooltip"
	const ICON = &"icon"
	const ICON_MOD = &"icon_mod"
	const IDX = &"idx"
	
	const CODE_COMPLETE_CALLABLE = &"CodeTextEditor::_code_complete_timer_timeout"
	
	const SCRIPT_EDITOR_CLASSES = [&"ScriptTextEditor", &"TextEditor", &"EditorHelp"]
