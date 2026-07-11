extends VBoxContainer

const UtilsRemote = preload("res://addons/script_tabs/src/utils/utils_remote.gd")
const UNode = UtilsRemote.UNode

const UtilsLocal = preload("res://addons/script_tabs/src/utils/utils_local.gd")
const Keys = UtilsLocal.Keys

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
	code_edit.code_completion_enabled = state
	UtilsLocal.ensure_connect(code_edit.code_completion_requested, _on_text_changed, state)
	UtilsLocal.ensure_connect(code_edit.text_changed, _on_text_changed, state) # using code comp request seems better
	UtilsLocal.ensure_connect(timer.timeout, _on_code_complete_timeout, state)

## Needs to be called after moving to, or before moving from
func set_side_panel_button_vis(vis:bool, first_tab:=true):
	if first_tab:
		vis = true
	if get_child_count() > 0:
		get_child(1).get_child(0).visible = vis

func _on_code_completion_requested():
	timer.start()

func _on_text_changed():
	return
	timer.start()

func _on_code_complete_timeout():
	code_edit.request_code_completion()

func _on_code_edit_sig():
	timer.stop()
