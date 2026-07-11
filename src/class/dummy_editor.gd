extends VBoxContainer

const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys

const UtilsLocal = preload("res://addons/script_tabs/src/utils/utils_local.gd")
const DummyCTE = UtilsLocal.DummyCTE

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
				UtilsLocal.ensure_connect(node.about_to_popup, _about_to_popup.bind(node), true)
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


func set_active(active:bool, is_cleanup:bool = false):
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
	move_children(active, is_cleanup)


func move_children(active:bool, is_cleanup:bool=false):
	if not active and not _initialized:
		return
	
	if active:
		if is_instance_valid(_dummy_code_text_editor):
			_dummy_code_text_editor.set_script_editor(script_editor)
	
	if editor_type == EditorType.EDITOR_HELP:
		if active:
			if get_child_count() == 0:
				UtilsLocal.reparent_children(script_editor, self)
			set_doc_style_box.call_deferred(active)
		elif is_cleanup: # only on clean_up stops RichTextLabel from redrawing, seems ok to just free everything when closing regularly
			UtilsLocal.reparent_children(self, script_editor)
		
	elif editor_type == EditorType.TEXT_EDITOR:
		var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
		if not is_instance_valid(code_text_editor):
			return
		
		if active:
			UtilsLocal.reparent_children(code_text_editor, _dummy_code_text_editor)
			UtilsLocal.reparent_children(script_editor, self, [code_text_editor])
		else:
			UtilsLocal.reparent_children(_dummy_code_text_editor, code_text_editor)
			UtilsLocal.reparent_children(self, script_editor, [_dummy_code_text_editor])
		
	elif editor_type == EditorType.SCRIPT_EDITOR:
		var vsplit_container = script_editor.find_children("*","VSplitContainer", true, false).pop_front()
		var code_text_editor = script_editor.find_children("*","CodeTextEditor", true, false).pop_front()
		if not is_instance_valid(vsplit_container):
			return
		
		if active:
			UtilsLocal.reparent_children(code_text_editor, _dummy_code_text_editor)
			UtilsLocal.reparent_children(vsplit_container, _dummy_vsplit, [code_text_editor])
			UtilsLocal.reparent_children(script_editor, self, [vsplit_container])
			
			 # HACK: these just stop an error from firing when closing a editor. Trying to get_child that isn't there
			UtilsLocal.add_filler_nodes([script_editor, vsplit_container], _editor_replace_nodes)
		else:
			UtilsLocal.reparent_children(_dummy_code_text_editor, code_text_editor)
			UtilsLocal.reparent_children(_dummy_vsplit, vsplit_container, [_dummy_code_text_editor])
			UtilsLocal.reparent_children(self, script_editor, [_dummy_vsplit])
	
	if is_instance_valid(_dummy_code_text_editor):
		_dummy_code_text_editor.set_active(active)
	
	_set_bottom_panel_size(active)
	
	if is_instance_valid(code_edit):
		UtilsLocal.ensure_connect(code_edit.symbol_lookup, _on_symbol_lookup, active)
		UtilsLocal.ensure_connect(code_edit.gui_input, _on_code_edit_gui_input, active)
	elif is_instance_valid(rich_text):
		UtilsLocal.ensure_connect(rich_text.meta_clicked, _on_rich_text_meta_clicked, active)
		UtilsLocal.ensure_connect(rich_text.gui_input, _on_rich_text_gui_input, active)
	
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
	#print("SET VIS::", visible, "::", get_script_list_tooltip())
	pass
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
	if not is_instance_valid(script_editor):
		return -1
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
		set_active(false, true)
	queue_free()
