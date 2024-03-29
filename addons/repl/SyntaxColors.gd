tool
class_name SyntaxColors
extends EditorScript

# @TODO: Signal for indicating color changes?
 
const SYNTAX_COLOR_SETTING_BASE =  'text_editor/highlighting/'

var editor_settings := EditorScript.new().get_editor_interface().get_editor_settings()

func resolve(name: String, default: Color = Color(1,1,1,1)) -> Color:
	var leaf = name.to_lower().rstrip('*')
	var pat = SYNTAX_COLOR_SETTING_BASE + leaf + "*"
	#print('[SyntaxColors:resolve] %s -> %s -> "%s"' % [ name, leaf, pat ])
	var matched_keys := ReplUtil.CollectProp(
			editor_settings.get_property_list(), 'name', pat)
	if matched_keys.empty():
		#print('[SyntaxColors:resolve]  -> <default: %s>' % [ default ])
		return default
	else:
		var resolved_key = matched_keys[0]
		#print('[SyntaxColors:resolve]  -> %s' % [ resolved_key ])
		# Just return first for now
		var value = editor_settings.get(resolved_key)
		print('[resolve] Resolved: %s' % [ value ])
		return value

func get_color_props() -> PoolStringArray:
	var matched_keys := ReplUtil.CollectProp(
			editor_settings.get_property_list(), 
			'name',
			SYNTAX_COLOR_SETTING_BASE + "*")
	var out := PoolStringArray()
	for key in matched_keys:
		out.push_back(key.trim_prefix(SYNTAX_COLOR_SETTING_BASE).trim_suffix('_color'))
	return out

#func _get_property_list():
#	var prop_list := editor_settings.get_property_list()
#	var syntax_prop_names := ReplEnvironment.CollectProp(prop_list, 'name', SYNTAX_COLOR_SETTING_BASE+'*')
#

# Key bases as of writing this:
# background
# base_type
# bookmark
# brace_mismatch
# breakpoint
# caret
# caret_background
# code_folding
# comment
# completion_background
# completion_existing
# completion_font
# completion_scroll
# completion_selected
# control_flow_keyword
# current_line
# engine_type
# executing_line
# function
# gdscript/function_definition
# gdscript/node_path
# highlight_all_occurrences
# highlight_current_line
# highlight_type_safe_lines
# keyword
# line_length_guideline
# line_number
# mark
# member_variable
# number
# safe_line_number
# search_result
# search_result_border
# selection
# string
# symbol
# syntax_highlighting
# text
# text_selected
# user_type
# word_highlighted
