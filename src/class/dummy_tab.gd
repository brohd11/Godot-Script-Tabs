extends TabContainer

const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const ScriptListManager = UtilsRemote.ScriptListManager
const SLKeys = ScriptListManager.Keys

const UtilsLocal = preload("res://addons/script_tabs/src/utils/utils_local.gd")
const DummyEditor = UtilsLocal.DummyEditor

var _defer_connection:=false

var tab_history:=[]

var script_list_manager:ScriptListManager
var dummy_editors:Dictionary = {}

var _selected_flag:bool = false

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
	activate_current()

func activate_current():
	if _selected_flag:
		return
	
	var dummy_editor = get_current_tab_control() as DummyEditor
	if not is_instance_valid(dummy_editor):
		return
	
	_selected_flag = true
	for d in get_children():
		d.set_active(d == dummy_editor)
	
	await get_tree().process_frame
	_selected_flag = false


func _on_tab_changed(tab:int):
	if _selected_flag:
		return

	var dummy_editor = get_tab_control(tab) as DummyEditor
	if not is_instance_valid(dummy_editor):
		return
	if not dummy_editor.is_active: # if it hasn't been activated, will move contents over
		dummy_editor.soft_activate() # then reselect the current editor, stops empty tabs on close
	#dummy_editor.set_doc_style_box(true)
	
	if dummy_editor in tab_history:
		tab_history.erase(dummy_editor)
	tab_history.append(dummy_editor)


func _on_tab_closed(tab:int):
	var dummy_editor = get_tab_control(tab) as DummyEditor
	script_list_manager.close_script_by_idx(dummy_editor.get_script_index())
	
	script_list_manager.update_cache()
	await get_tree().process_frame
	if is_instance_valid(dummy_editor):
		return
	
	#script_list_manager.update_cache()
	#^r this needs to account for when the dialog shows
	#^r early exit above at least stops accidental tab changes
	var last_tab = _get_previous_tab()
	if is_instance_valid(last_tab):
		#print("SHOWING LAST")
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
	var title = script_list_data.get(SLKeys.NAME) as String
	if title.count("/") > 2 or title.length() > 40: # super long names can be trimmed
		title = "..." + "/" + title.get_file()
	set_tab_title(idx, title)
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
