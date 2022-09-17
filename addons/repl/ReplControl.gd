# REPL editor control
# Copyright (C) 2021  Sylvain Beucler

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

tool
class_name ReplControl
extends Control


signal acquired_plugin_instance(plugin_instance)


var dprint = DebugPrint.Builder.get_for(self)
var syntax = preload('./SyntaxColors.gd').new()
var plugin: EditorPlugin
var interface := EditorScript.new().get_editor_interface()


export (bool) var use_bb = true setget set_use_bb, get_use_bb
# https://github.com/godotengine/godot/issues/16974#issuecomment-907549837
export (bool) var _reload = false setget _on_reload


onready var input  := $IOVBox/InputHBox/input as TextEdit # LineEdit
onready var output := $IOVBox/output          as RichTextLabel
onready var env    := $ReplEnvironment        as ReplEnvironment


func set_plugin(value: EditorPlugin) -> void:
	print('[REPLControl:set:plugin]')
	if is_instance_valid(value):
		plugin = value
		interface = plugin.get_editor_interface()
		if not (env and is_instance_valid(env.plugin)):
			env.set_plugin(value)
	else:
		push_warning('value is not valid instance.')


func ensure_plugin() -> void:
	if not is_instance_valid(plugin):
		set_plugin(REPL.get_plugin())


func get_plugin() -> EditorPlugin:
	return plugin if plugin else null


var hist := [''];
var hist_index = 0;

# Debugging
var last_event_stage := '<NONE>'

func _init() -> void:
	print('[ReplControl:on:init]')
	last_event_stage = 'INIT'

func _enter_tree() -> void:
	print('[ReplControl:on:enter-tree]')
	last_event_stage = 'IN-TREE'
	set_plugin(REPL.get_plugin())
	connect("ready", self, "rebuild_mono_font", [ ], CONNECT_ONESHOT)
	
func _ready():
	last_event_stage = 'READY'
	_env_build_bindings()
	set_use_bb(true)
	
	if not is_instance_valid(plugin):
		input.connect("focus_entered", self, "_env_init_custom_bindings", [ ], CONNECT_ONESHOT)

	input.grab_focus()

func _exit_tree() -> void:
	last_event_stage = 'EXIT-TREE'
	#set_use_bb(true)

class BBCodeText:
	static func ColorTag(color) -> String:
		return '[color=#%s]' % [ 
				(color as Color).to_html() if color is Color else color.trim_prefix('#') ]
		
	class Format:
		const UnescapedLeftBracketPattern := '[\\[](?!\u200B)'
		
		var regex: RegEx
		
		func _init():
			regex = RegEx.new()
			var compile_err = regex.compile(UnescapedLeftBracketPattern)
			if compile_err != OK:
				push_error('Failed to compile regex: %s' % [ compile_err ])
				
				
		# Inserts ZWSP characters around characters that would otherwise change formatting.
		func escape(text: String) -> String:
			return regex.sub(text, '[\u200B', true)

var fmt := BBCodeText.Format.new()
	
# Wrapper for setting text color, inner contents are not sanitized unless `escape` passed true. 
# `color` accepts any of the following: 
#   - Color object
#   - HTML hex format string
#   - 
static func colorize(text, color, escape := false) -> String:
	return '%s%s[/color]' % [ BBCodeText.ColorTag(color), text ]

#region BBCode Sanitization

const ZWSP := '\u200B'
# Original escape function, 
static func BBCodeEscape(text: String) -> String:
	# Keeping it simple here
	return text.replacen('[', '[\u200B').replacen(']', '\u200B]')

#endregion BBCode Sanitization


const TextFG := {
	CMD_LOG_PREFIX  = Color('#AAA'),
	CMD_LOG         = Color('#68C'),
	REPL_LOG        = Color("#888"),
}

func set_use_bb(new_value: bool) -> void:
	if not is_inside_tree():
		push_error('set_use_bb >> called outside of tree.')
		return
	
	if not is_instance_valid(output):
		return
		
	if typeof(new_value) == TYPE_BOOL:
		if output.is_using_bbcode() != new_value:
			output.set_use_bbcode(new_value)
		use_bb = new_value

func get_use_bb() -> bool:
	if not is_inside_tree():
		push_error('get_use_bb >> called outside of tree.')
		return false
		
	if not is_instance_valid(output):
		# push_error("set_use_bb [%s] >> Can't read use_bb, output member value is not a valid instance" % [ last_event_stage ])
		return false

	if output.is_using_bbcode() != use_bb:
		output.set_use_bbcode(use_bb)
	return output.bbcode_enabled


func output_text_raw(text: String, eol := false) -> void:
	if use_bb:
		# Append breaks tags :c
#		output.append_bbcode(text + "\n" if eol == true else text)
		output.bbcode_text += text + "\n" if eol == true else text
	else:
		output.text += text + "\n" if eol == true else text

func output_line_raw(text: String) -> void:
	output_text_raw(text, true)

func output_text(text: String, eol := false) -> void:
	if use_bb:
		text = BBCodeEscape(text)
		# output.append_bbcode(text + "\n" if eol == true else text)
		output.bbcode_text += text + "\n" if eol == true else text
	else:
		output.text += text + "\n" if eol == true else text

func output_line(text: String) -> void:
	output_text(text, true)

func clear_repl_input() -> void:
	print('[ReplControl:clear_repl_input]')
	
	# Just started trying out TextEdit so keeping this behind a guard for now
	if input is TextEdit: 
		clear_repl_textedit_input()
	else:
		input.text = ""


func clear_repl_textedit_input() -> void:
	input.set_text("")
	input.set_v_scroll(0)
	input.update()


# Stores result from last successful evaluation.
var last_return
func store_result(value):
	last_return = value
	variables['last'] = value


func gd_eval(gd_expr: String) -> Array:
	var errstr = 'Error: '
	var expression = Expression.new()
	var error = expression.parse(gd_expr, variables.keys())
	if error != OK:
		errstr += 'invalid expression: '
		errstr += expression.get_error_text()
		return [false, errstr]
	var result = expression.execute(variables.values(), env, true)
	if expression.has_execute_failed():
		errstr += 'execute failed: '
		var gderr = expression.get_error_text()
		if gderr == "self can't be used because instance is null (not passed)":
			gderr += ' [variable not declared?]'
		errstr += gderr
		return [false, errstr]
		
	store_result(result)
	return [true, result]


func _on_eval_pressed():
	if not is_instance_valid(input):
		push_warning('input node not initialized.')
		return

	var dedented := input.text.lstrip(' \t').rstrip(' \t')
		
	if dedented.begins_with("!reload"):
		build_syntax_colors(true)
		# output_line_raw('[color=#888]%sReinitialzing Environment[/color]' % [ ZWSP ])
		output_line_raw(colorize('Reinitialzing Environment', TextFG.REPL_LOG))
		clear_repl_input()
		_env_rebuild()
		return
		
	if dedented.begins_with("?bb"):
		output_line_raw(colorize(
				fmt.escape('[BBCode mode %sabled]' % 
								[ 'en' if output.bbcode_enabled else 'dis' ]),
				TextFG.REPL_LOG))
		clear_repl_input()
		return
		
	if dedented == "?":
		output_line_raw(colorize(env.help_output, TextFG.REPL_LOG))
		clear_repl_input()
		return

	if dedented == '':
		output_line_raw(colorize(' > ', TextFG.CMD_LOG_PREFIX))
		clear_repl_input()
		return

	hist[len(hist) - 1] = input.text
	hist.push_back('')
	hist_index = hist.size() - 1

	output_line_raw('\n'
		+ colorize(' > ', TextFG.CMD_LOG_PREFIX)
		+ colorize(fmt.escape(input.text), TextFG.CMD_LOG))

	var ret = null

	var var_name = null
	var regex = RegEx.new()
	var result
	regex.compile("^\\s*(var\\s+)?(?<variable>[a-zA-Z_][a-zA-Z_0-9]*)\\s*?=\\s*?(?<rest>.*)")
	result = regex.search(input.text)
	if result:
		var_name = result.get_string('variable')
		input.text = result.get_string('rest')

	var path = null
	regex.compile("^[\\s]*(load[\\(])[\\s]*(['\"])(?<path>(?:[^\\n'\"\\\\]+|[\\\\]\\2|(?!\\2).)+)(\\2)[\\s]*([\\)])")
	result = regex.search(input.text)
	if result:
		path = result.get_string('path')
		ret = load(path)
		ret = [true, ret]

	if ret == null:
		ret = gd_eval(input.text)

	if var_name != null and ret[0]:
		output_line('* setting variable %s *' % var_name)
		variables[var_name] = ret[1]
		# Clear input after assign
		
	# Rough check for error message
	if typeof(ret[1]) == TYPE_STRING and ret[1].begins_with('Error: '):
		output_line_raw(colorize(ret[1], SYNTAX.ERROR))
	# Skip top level null returns
	elif typeof(ret[1]) == TYPE_NIL:
		pass
	else:
		output_line_raw(pretty_print_value(ret[1]))

	clear_repl_input()
	#input.text = ''
	#input.grab_focus()
	
# Theme values should be edited here
const SyntaxTagMap := {
	KEYWORD   = "keyword",
	PUNCT     = "text",
	NUMERIC   = "number",
	NODE_STR  = "gdscript/node_path",
	STRING    = "string",
	TYPE      = "engine_type",
	INTRINSIC = "base_type",
	ERROR     = "brace_mismatch",
	# Used for node's prefixed name
	TAG       = "control_flow",
}

# Copy of original for autocompletion (don't modify)
const SYNTAX = SyntaxTagMap

var syntax_colors: Dictionary
var syntax_colors_initialized := false
func build_syntax_colors(force := true) -> void:
	if force == true: clear_syntax_colors()
	
	# Load colors
	for key in SyntaxTagMap.keys():
		print('[ReplControl:build_syntax_colors] Initializing key: %s' % [ key ])
		syntax_colors[key] = syntax.resolve(SyntaxTagMap[key])
	
	# Mutate interface dict - can SYNTAX members these into colorize
	var keys := SyntaxTagMap.keys()
	for i in keys.size():
		SYNTAX[keys[i]] = syntax_colors[keys[i]]


func clear_syntax_colors() -> void:
	syntax_colors = { }

# @TODO: Currently only used to limit element count at single level, add
#        some form of recursive total cap/depth limit
const PRETTY_PRINT_MAX_ELS = 10
const PRETTY_PRINT_STARTING_DEPTH_LIMIT = 3

# For type-specific formatting of return values
func pretty_print_value(value, depth := PRETTY_PRINT_STARTING_DEPTH_LIMIT) -> String:
	if syntax_colors_initialized == false or syntax_colors.keys().empty():
		#print('[pretty_print_value] Initializing colors')
		build_syntax_colors(true)
		#print('[pretty_print_value] Values: %s' % [ to_json(syntax_colors) ])
		syntax_colors_initialized = true
		
	var value_str := "%s" % [ value ]
#	var value_type := 
	
	match typeof(value):
		TYPE_BOOL, TYPE_NIL:
			dprint.write('Resolved => bool | null', 'pretty_print_value')
			return colorize(value_str, SYNTAX.KEYWORD)
			
		TYPE_INT, TYPE_REAL:
			dprint.write('Resolved => int | real', 'pretty_print_value')
			return colorize(value_str, SYNTAX.NUMERIC)
			
		TYPE_STRING, TYPE_NODE_PATH:
			dprint.write('Resolved => string | NodePath', 'pretty_print_value')
			return colorize(to_json(value), SYNTAX.STRING)
			
		TYPE_COLOR:
				var values := value_str.split_floats(',', false)
				var expr := PoolStringArray([
					colorize('Color', SYNTAX.INTRINSIC),
					colorize('(', SYNTAX.PUNCT)
				])
				var styled_values := PoolStringArray()
				var sep := colorize(',', SYNTAX.PUNCT)
				for unstyled in values:
					styled_values.push_back(colorize(String(unstyled), SYNTAX.NUMERIC))
					
				expr.push_back(styled_values.join(sep + ' '))
				expr.push_back(colorize(')', SYNTAX.PUNCT))
				return expr.join('')
			
		TYPE_ARRAY:
			dprint.write('Resolved => array', 'pretty_print_value')
			var length := (value as Array).size()
			if length == 0: return colorize('[ ]', SYNTAX.PUNCT)
			# Exit out early with simple form if depth parameter reaches 0
			if depth < 1:
				return PoolStringArray([
					colorize('Array', SYNTAX.INTRINSIC),
					colorize('[', SYNTAX.PUNCT),
					colorize(String(length), SYNTAX.NUMERIC),
					colorize(']', SYNTAX.PUNCT)
				]).join('')

			
			var colorized := PoolStringArray()
			colorized.push_back(colorize('[ ', SYNTAX.PUNCT))
			for i in length:
				# Recurse
				colorized.push_back(pretty_print_value(value[i], depth - 1))
				if i > PRETTY_PRINT_MAX_ELS and length > i + 1:
					colorized.push_back(colorize(', ...', SYNTAX.PUNCT))
					break
				elif i != length - 1:
					colorized.push_back(colorize(', ', SYNTAX.PUNCT))
			
			colorized.push_back(colorize(' ]', SYNTAX.PUNCT))
			
			return colorized.join('')

		TYPE_DICTIONARY:
			dprint.write('Resolved => dict', 'pretty_print_value')
			var keys   := (value as Dictionary).keys()
			var length := keys.size()
		
			if length == 0: return colorize('{ }', SYNTAX.PUNCT)
			# Exit out early with simple form if depth parameter reaches 0
			if depth < 1:
				return PoolStringArray([
					colorize('Dictionary', SYNTAX.INTRINSIC),
					colorize('{', SYNTAX.PUNCT),
					colorize(String(length), SYNTAX.NUMERIC),
					colorize('}', SYNTAX.PUNCT)
				]).join('')
			
			var colorized := PoolStringArray()
			colorized.push_back(colorize('{ ', SYNTAX.PUNCT))
			for i in length:
				var key = keys[i]
				var key_str = to_json(key if typeof(key) == TYPE_STRING else String(key))
				colorized.push_back(
						colorize(key_str, SYNTAX.NODE_STR) + 
						colorize(":", SYNTAX.PUNCT) + 
						" ")
				
				colorized.push_back(pretty_print_value(value[key], depth - 1))
				
				if i > PRETTY_PRINT_MAX_ELS and length > i + 1:
					colorized.push_back(colorize(', ...', SYNTAX.PUNCT))
					break
				elif i != length - 1:
					colorized.push_back(colorize(', ', SYNTAX.PUNCT))
			
			colorized.push_back(colorize(' }', SYNTAX.PUNCT))
			
			return colorized.join('')
			
	if value is Reference or value is Node:
		dprint.write('Resolved => Reference | Node', 'pretty_print_value')
		var out_string: String = ""
		# Get index of non-prefix content (e.g. `[` * `]`)
		var base_idx := value_str.find('[')
		
		# Get body of base node syntax, minus surrounding brackets
		var node_base := value_str.substr(base_idx + 1).trim_suffix(']')
		var prefix := "" if base_idx == 0 else value_str.substr(0, base_idx - 1)
		
		# Attempt to split base node body into type and reference id
		var base_contents := PoolStringArray()
		var node_base_id_punct_idx := node_base.find(':')
		
		if node_base_id_punct_idx == -1:
			# Treat as single fragment 
			base_contents.push_back(colorize(node_base, SYNTAX.TYPE))
		else:
			# Treat as <type> + ':' + <id>
			# Nothing _should_ need to be escaped here
			var parts := node_base.split(':')
			base_contents.push_back(colorize(parts[0], SYNTAX.TYPE))
			base_contents.push_back(colorize(':',      SYNTAX.PUNCT))
			base_contents.push_back(colorize(parts[1], SYNTAX.NUMERIC * Color(1, 1, 1, 0.7)))
			
		
		# Build output fragments. Anything beyond simple equality checks and expressions should
		# remain before this if possible
		var pool := PoolStringArray()
		
		# Name/@ prefix content
		if prefix != "":
			pool.push_back(colorize(prefix, SYNTAX.TAG))
			
		# Main body
		pool.push_back(colorize(fmt.escape('['), SYNTAX.PUNCT))
		pool.append_array(base_contents)
		pool.push_back(colorize(fmt.escape(']'), SYNTAX.PUNCT))
		
		return pool.join('')
	
	else: 
		dprint.warn('Reached end of resolution logic, failed to get pattern for %s' % [ value ], 'pretty_print_value')	
	
	return value_str


# For original input[LineEditor]
func _on_input_text_entered(new_text):
	_on_eval_pressed()


func _on_input_submit_eval(text) -> void:
	print('[ReplControl:input-submit-eval] Repl input: %s' % [ text ])
	_on_input_text_entered(text)


# Testing input[TextEdit]
func _on_input_text_changed() -> void:
	#_on_input_text_entered("")
	pass


func _on_import_pressed():
	if input.text.empty():
		output_line('Please type a variable name.')
		input.grab_focus()
		return
	find_node('import_filedialog').popup()


func _on_import_filedialog_file_selected(path):
	var name = input.text
	variables[name] = load(path).instance()
	output_line('> %s = %s\n' % [name, variables[name]])
	input.text = ''
	input.grab_focus()


func bin2int(bin_str: String) -> int:
	var out = 0
	for c in bin_str:
		out = (out << 1) + int(c == "1")
	return out

	 
func int2bin(value: int, bit_count: int = -1) -> String:
	var out = ""
	if bit_count > 0:
		var bit_idx := 0
		while (value > 0):
			out = str(value & 1) + out
			value = (value >> 1)
			bit_idx += 1
		return out.insert(0, '0'.repeat(bit_count - bit_idx))
	else:
		while (value > 0):
			out = str(value & 1) + out
			value = (value >> 1)
		return out


const DEBUG_SCANCODE_BIN_LEN := 32
func _debug_dump_scancode_info(event: InputEventKey, ctx := 'debug-dump'):
	dprint.write('  Scancode data:\n%s\n%s\n' % [ 
			int2bin(event.get_scancode(), DEBUG_SCANCODE_BIN_LEN),
			int2bin(event.get_scancode_with_modifiers(), DEBUG_SCANCODE_BIN_LEN) + ' [With Modified]'
		], ctx)

func _input(event: InputEvent):
	if not (is_inside_tree() and is_instance_valid(input)):
		return
	if input.has_focus():
		var kev := event as InputEventKey
		
		if is_instance_valid(kev) and kev.is_pressed():
			match kev.get_scancode():
				KEY_ENTER:
					if not (kev.shift or kev.command or kev.control or kev.alt):
						#dprint.write('Detected unmodified shift press.', 'on:gui-input')
						if not input.text.lstrip(' \t').rstrip(' \t').empty():
							_on_input_text_entered(input.text)
						get_tree().set_input_as_handled()
		if event.is_action_pressed("ui_up"):
			hist[hist_index] = input.text
			hist_index = hist_index - 1 if (hist_index > 0) else hist_index
			input.text = hist[hist_index]
			input.cursor_set_column(clamp(input.cursor_get_column(), 0, input.text.length() - 1))
			get_tree().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			hist[hist_index] = input.text
			hist_index = hist_index + 1 if (hist_index < len(hist) - 1) else hist_index
			input.cursor_set_column(clamp(input.cursor_get_column(), 0, input.text.length() - 1))
			input.text = hist[hist_index]
			get_tree().set_input_as_handled()


var eval_env
var variables: Dictionary


func _env_init_self():
	eval_env = env

func _env_apply_binding_dict(bindings: Dictionary) -> void:
	for key in bindings.keys():
		variables[key] = bindings[key] 


func _env_build_bindings() -> void:
	_env_init_base_bindings()
	_env_init_custom_bindings()


func _env_rebuild() -> void:
	_env_init_self()
	variables = { }
	_env_build_bindings()


# Add extended variable bindings
func _env_init_custom_bindings() -> void:
	var additions := {
		'editor':   env,
		'instance': REPL.interface,
		'syntax':   syntax,
		'repl':     self,
	}
	_env_apply_binding_dict(additions)
	
	
func _env_init_base_bindings() -> void:
	_env_apply_binding_dict(preload('./ReplGlobalsBase.gd').Variables)


var orig_mono_font_size

func rebuild_mono_font():
	var font := DynamicFont.new()
	font.font_data = load('res://addons/repl/iosevka-term-ss10-regular.ttf')
	if typeof(orig_mono_font_size) != TYPE_INT:
		orig_mono_font_size = font.size
	var scale = OS.get_screen_max_scale()
	if scale > 0:
		font.size = orig_mono_font_size * scale
	
	output.add_font_override("mono_font", font)
	input.add_font_override("mono_font", font)
	output.add_font_override("normal_font", font)
	input.add_font_override("normal_font", font)
	input.add_font_override("font", font)
	output.add_font_override("font", font)


func _on_reload(_value) -> void:
	if not Engine.editor_hint: return
	
	#print('[ReplControl:on:reload] Editor context reload detected.')
	
	input  = get_node_or_null("IOVBox/InputHBox/input")
	if not is_instance_valid(input):
		var input_instance := preload('./ui/ReplInputTextEdit.tscn').instance()
		input_instance.name = 'input'
		get_node("IOVBox/InputHBox").add_child(input_instance)
		
	output = $IOVBox/output
	env    = $ReplEnvironment
	
	return 
	
	for prop in 'input output env'.split(" "):
		print('[ReplControl:on:reload]   %s:%s %s' % [ 
			prop, ' '.repeat(7 - prop.length()),
			self[prop]
		])
