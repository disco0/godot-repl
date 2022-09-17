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


export (bool) var use_bb = true setget set_use_bb, get_use_bb
# https://github.com/godotengine/godot/issues/16974#issuecomment-907549837
export (bool) var _reload = false setget _on_reload

onready var syntax_node := $SyntaxColors
onready var input: ReplInputTextEdit = $IOVBox/InputHBox/input as TextEdit
onready var output: RichTextLabel = $IOVBox/output
onready var env := $ReplEnvironment

var dprint := preload('../util/logger.gd').Builder.get_for(self)
var syntax := preload('../SyntaxColorsNode.gd').new()
var plugin: EditorPlugin
var interface := EditorScript.new().get_editor_interface()
var env_first_init := false
var hist := [''];
var hist_index = 0;
var fmt := BBCodeText.Format.new()


#section Lifecycle


func _init() -> void:
	dprint.write('', 'on:init')


func _enter_tree() -> void:
	dprint.write('', 'on:enter-tree')


func _ready():
	if not is_instance_valid(plugin):
		set_plugin(REPL.get_plugin())

	rebuild_mono_font()

	build_syntax_colors(true)
	_env_rebuild()

	# Add bindings update interface
	# TODO: Actually implement _on_external_binding_definition, or get rid of it
	if not REPL.is_connected("binding_added", self, "_on_external_binding_definition"):
		REPL.connect("binding_added", self, "_on_external_binding_definition")

	set_use_bb(use_bb)

	if not is_instance_valid(plugin):
		input.connect("focus_entered", self, "_env_init_custom_bindings", [ ], CONNECT_ONESHOT)

	input.grab_focus()


func _exit_tree() -> void:
	dprint.write('', 'on:exit-tree')
	pass


#section setgets


func set_plugin(value: EditorPlugin) -> void:
	dprint.write('', 'set:plugin')
	if is_instance_valid(value):
		plugin = value
		interface = plugin.get_editor_interface()

		if not is_inside_tree():
			if not env:
				dprint.warn('env not defined yet.', 'set:plugin')
			elif not is_instance_valid(env.plugin):
				env.set_plugin(value)
	else:
		dprint.warn('value is not valid instance.', 'set:plugin')


func ensure_plugin() -> void:
	if not is_instance_valid(plugin):
		set_plugin(REPL.get_plugin())


func get_plugin() -> EditorPlugin:
	if not plugin is EditorPlugin:
		if is_instance_valid(REPL.plugin):
			plugin = REPL.plugin
		else:
			dprint.warn('Failed fallback assignment to REPL.plugin', 'get:plugin')

	return plugin


func set_use_bb(new_value: bool) -> void:
	if not is_inside_tree():
		dprint.error('called outside of tree',  'set:use_bb')
		return

	if not is_instance_valid(output):
		return

	if typeof(new_value) == TYPE_BOOL:
		if output.is_using_bbcode() != new_value:
			output.set_use_bbcode(new_value)
		use_bb = new_value


func get_use_bb() -> bool:
	if not is_inside_tree():
		dprint.error('called outside of tree',  'get:use_bb')
		return false

	if not is_instance_valid(output):
		return false

	if output.is_using_bbcode() != use_bb:
		output.set_use_bbcode(use_bb)

	return output.bbcode_enabled


#section output


func output_clear_buffer() -> void:
	if use_bb:
		output.bbcode_text = ""
	else:
		output.set_text("")


func output_text_raw(text: String, eol := false) -> void:
	if use_bb:
		# Append breaks tags :c
		#output.append_bbcode(text + "\n" if eol == true else text)
		output.bbcode_text += text + "\n" if eol == true else text
	else:
		output.text += text + "\n" if eol == true else text


func output_line_raw(text: String) -> void:
	output_text_raw(text, true)


func output_text(text: String, eol := false) -> void:
	if use_bb:
		text = fmt.escape(text)
		output.bbcode_text += text + "\n" if eol == true else text
	else:
		output.text += text + "\n" if eol == true else text


func output_line(text: String) -> void:
	output_text(text, true)


func write_error(msg: String) -> void:
	output_line_raw(Colorize(fmt.escape(msg), SYNTAX.ERROR))


#section input


func clear_repl_input() -> void:
	dprint.write('', 'clear_repl_input')
	input.set_text("")
	input.set_v_scroll(0)
	input.update()


#section eval


# Stores result from last successful evaluation
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


# TODO: Consider moving from directly reading evaluated text from input control to passing via
#       param, handle anything related to input control outside
# TODO: Pull out regexes and do some kind of pseudo-static init block to set them up
func eval() -> void:
	if not env_first_init:
		_env_rebuild()
		env_first_init = true

	if not is_instance_valid(input):
		dprint.warn('input node not initialized', 'eval')
		return

	var raw := input.text
	var dedented := raw.lstrip(' \t').rstrip(' \t')

	if dedented.begins_with("!reload"):
		repl_full_init()
		return

	elif dedented.begins_with("!clear"):
		output_clear_buffer()
		output_line_raw(Colorize('Cleared REPL', TextFG.REPL_LOG))
		return

	if dedented.begins_with("?bb"):
		output_line_raw(Colorize(
				fmt.escape('[BBCode mode %sabled]' %
						[ 'en' if output.bbcode_enabled else 'dis' ]),
				TextFG.REPL_LOG))
		clear_repl_input()
		input.reset_position()
		return

	if dedented == "?":
		output_line_raw(Colorize(env.help_output, TextFG.REPL_LOG))
		clear_repl_input()
		input.reset_position()
		return

	if dedented == '':
		output_line_raw(Colorize(' > ', TextFG.CMD_LOG_PREFIX))
		clear_repl_input()
		input.reset_position()
		return

	hist[hist.size() - 1] = raw.rstrip('\n\t ')
	hist.push_back('')
	hist_index = hist.size() - 1

	output_line_raw('\n'
		+ Colorize(' > ', TextFG.CMD_LOG_PREFIX)
		+ Colorize(fmt.escape(raw.rstrip('\n\t ')), TextFG.CMD_LOG))

	var var_name = null
	var ret = null
	var regex = RegEx.new()
	var result: RegExMatch
	#regex.compile(EXPR_REGEX.VAR.PATTERN)
	#result = regex.search(input.text)
	result = eval_regex(input.text, EXPR_REGEX_TYPE.VAR)
	if result:
		var_name = result.get_string('variable')
		input.text = result.get_string('rest')
		dprint.write('Parsed var statement lhs: <%s>' % [ var_name ], 'eval')
		dprint.write('Parsed var statement rhs: <%s>' % [ input.text ], 'eval')

	dprint.write('Searching for load call in <%s>' % [ input.text ], 'eval')
	var path = null
	#regex.compile(EXPR_REGEX.LOAD.PATTERN)
	result = eval_regex(input.text, EXPR_REGEX_TYPE.LOAD)  # regex.search(input.text)
	if result:
		dprint.write('Load expression matched.', 'eval')
		var groups = result.get_names()
		match groups:
			# $0
			{ "dollar_alias": var index, ..}:
				dprint.write('Matched $0 alias in load')
				var current_dock_file_path := interface.get_current_path()
				if not ResourceLoader.exists(current_dock_file_path):
					#output_line_raw(Colorize(
					write_error('File matched in dock by token %s is not loadable: <%s>'
										% [ result.get_string(index), current_dock_file_path ])
					# , TextFG.ERR))
				path = current_dock_file_path

			{ "path": var index, .. }:
				var path_string: String = result.get_string(index)
				dprint.write('Matched path literal in load')
				if not ResourceLoader.exists(path_string):
					#output_line_raw(Colorize(
					write_error('Literal path string is not loadable: <%s>'
										% [ path_string ])
					# , TextFG.ERR))

				path = path_string

			_ :
				dprint.write('Reached end of load parse regex.', 'eval')
				dprint.write('Matched groups: %s' % [ JSON.print(groups, '  ', true) ], 'eval')
				path = null

		if path:
			ret = load(path)
			ret = [true, ret]

	if ret == null:
		ret = gd_eval(input.text)

	if var_name != null and ret[0]:
		output_line_raw(Colorize('* setting variable %s *' % [ var_name ], TextFG.CMD_LOG_PREFIX))
		variables[var_name] = ret[1]
		# Clear input after assign

	# Rough check for error message
	if typeof(ret[1]) == TYPE_STRING and ret[1].begins_with('Error: '):
		output_line_raw(Colorize(ret[1], TextFG.ERR))
	# Skip top level null returns
	elif typeof(ret[1]) == TYPE_NIL:
		pass
	else:
		output_line_raw(pretty_print_value(ret[1]))

	clear_repl_input()
	input.reset_position()


enum EXPR_REGEX_TYPE { LOAD, VAR }
const EXPR_REGEX := {
	EXPR_REGEX_TYPE.LOAD: {
		PATTERN = "^[\\s]*(load[\\(])[\\s]*(?<params>(?<dollar_alias>[$][\\d]+)|(['\"])(?<path>(?:[^\\n'\"\\\\]+|[\\\\]\\4|(?!\\4).)+)(\\4))[\\s]*([\\)])"
	},
	EXPR_REGEX_TYPE.VAR: {
		PATTERN = "^\\s*(var\\s+)?(?<variable>[a-zA-Z_][a-zA-Z_0-9]*)\\s*?=\\s*?(?<rest>.*)"
	}
}

var _regex_cache := { }
# Takes an enum key in EXPR_REGEX
func eval_regex(string: String, pattern_type: int, uncached := false) -> RegExMatch:
	if pattern_type in EXPR_REGEX:
		# (Re)initialization check
		if uncached or not (pattern_type in _regex_cache):
			var regex := RegEx.new()
			var pattern: String = EXPR_REGEX[pattern_type].PATTERN

			if regex.compile(pattern) != OK:
				dprint.error('Failed to compile regex source: /%s/' % [ pattern ], 'eval_regex')
				return null

			_regex_cache[pattern_type] = regex

		return (_regex_cache[pattern_type] as RegEx).search(string)

	dprint.error('Unknown pattern enum index: %d' % [ pattern_type ], 'eval_regex')
	return null


func repl_full_init(clear_buf := false) -> void:
	build_syntax_colors(true)
	# If buffer clear requested do it _before_ info message
	if clear_buf == true:
		output_clear_buffer()
	output_line_raw(Colorize('Reinitialzing Environment', TextFG.REPL_LOG))
	clear_repl_input()
	_env_rebuild()
	input.reset_position()


#section Syntax Colors


# Wrapper for setting text color, inner contents are not sanitized unless `escape` passed true.
# `color` accepts any of the following:
#   - Color object
#   - HTML hex format string
static func Colorize(text, color, escape := false) -> String:
	return '%s%s[/color]' % [ BBCodeText.ColorTag(color), text ]


const TextFG := {
	CMD_LOG_PREFIX  = Color('#AAA'),
	CMD_LOG         = Color('#68C'),
	REPL_LOG        = Color("#888"),
	ERR             = Color('#C55'),
}

# Syntax theme values should be edited here
# TODO: Make a separate resource, configurable from settings
var SyntaxTagMap := {
	KEYWORD   = "keyword",
	PUNCT     = "text",
	NUMERIC   = "number",
	NODE_STR  = "gdscript/node_path",
	STRING    = "string",
	TYPE      = "engine_type",
	INTRINSIC = "base_type",
	ERROR     = "brace_mismatch_color",
	COMMENT   = "comment",
	# Used for node's prefixed name
	TAG       = "control_flow",
	BG        = "background",
	TEXT      = "text",
	PROP_LIT  = "symbol",
}

# Copy of SyntaxTagMap for autocompletion, keep keys in sync
# TODO: Find a less absurd way to do this
var SYNTAX := {
	KEYWORD   = "",
	PUNCT     = "",
	NUMERIC   = "",
	NODE_STR  = "",
	STRING    = "",
	TYPE      = "",
	INTRINSIC = "",
	ERROR     = "",
	COMMENT   = "",
	TAG       = "",
	BG        = "",
	TEXT      = "",
	PROP_LIT  = "",
}

var syntax_colors: Dictionary
var syntax_colors_initialized := false


func build_syntax_colors(force := true) -> void:
	if force == true: clear_syntax_colors()

	var keys := SyntaxTagMap.keys()
	# Load colors
	for i in keys.size():
		var key: String = keys[i]
		# Don't pass Color values
		if typeof(SyntaxTagMap[key]) == TYPE_STRING:
			syntax_colors[key] = syntax.resolve(SyntaxTagMap[key])
			SYNTAX[key] = syntax_colors[key]


func clear_syntax_colors() -> void:
	syntax_colors = { }


#section Pretty Print
# TODO: Consider moving to separate file


# TODO: Currently only used to limit element count at single level, add
#        some form of recursive total cap/depth limit
const PRETTY_PRINT := {
	MAX_ELS = 10,
	DEPTH_LIMIT = 3,

	MULTILINE = true,
	MULTILINE_DEPTH_LIMIT = 1,

	COLOR_PREVIEW = true,
	COLOR_PREVIEW_DELIM = [ '[', ']' ],

	INDENT = "  ",
	FMT = {
		X_MORE = '# %d more items',
	},

	SIMPLE_BUILDER = true,
}


func inc_indent(indent: String) -> String:
	return indent + PRETTY_PRINT.INDENT


func color_sample_text(color: Color,
					   delim_color = null,
					   text := 'sample',
					   delim := PRETTY_PRINT.COLOR_PREVIEW_DELIM,
					   sep :=  "") -> String:
	if not delim_color or typeof(delim_color) != TYPE_COLOR:
		delim_color = SYNTAX.COMMENT
		delim_color.a *= 0.4

	return PoolStringArray([
			Colorize(fmt.escape(delim[0]), delim_color),
				Colorize(fmt.escape(text), color),
			Colorize(fmt.escape(delim[1]), delim_color),
	]).join(sep)


func pretty_print_color(value, depth := 0, indent := "") -> PoolStringArray:
	var out := PoolStringArray([])
	var values := ("%s" % [ value ]).split_floats(',', false)

	out.append_array(PoolStringArray([
			Colorize('Color', SYNTAX.INTRINSIC),
			Colorize('(', SYNTAX.PUNCT),
	]))

	# Place preview inside of left paren
	if PRETTY_PRINT.COLOR_PREVIEW:
		out.push_back(color_sample_text(value) + " ")

	var styled_values := PoolStringArray()
	var sep := Colorize(',', SYNTAX.PUNCT)
	for unstyled in values:
		styled_values.push_back(Colorize(String(unstyled), SYNTAX.NUMERIC))

	out.push_back(styled_values.join(sep + ' '))
	out.push_back(Colorize(')', SYNTAX.PUNCT))

	return out


func pretty_print_vec(value, depth := 0, indent := "") -> PoolStringArray:
	var out := PoolStringArray([
			Colorize(ReplUtil.TypeStringOf(value), SYNTAX.INTRINSIC),
			Colorize('(', SYNTAX.PUNCT),
	])

	var values := ReplUtil.StripParens(str(value)).split_floats(',', false)

	var styled_values := PoolStringArray()
	var sep := Colorize(',', SYNTAX.PUNCT)
	for unstyled in values:
		styled_values.push_back(Colorize(str(unstyled), SYNTAX.NUMERIC))

	out.push_back(styled_values.join(sep + ' '))
	out.push_back(Colorize(')', SYNTAX.PUNCT))

	return out


func pool_tag(string: String = "") -> String:
	return Colorize(fmt.escape('<pool>'), SYNTAX.TYPE) + string


func pretty_print_arraylike(value, depth := 0, indent := "") -> PoolStringArray:
	var out := PoolStringArray()
	var is_pool := typeof(value) >= TYPE_RAW_ARRAY

	var length := (value as Array).size()
	if length == 0:
		if is_pool:
			out.push_back(pool_tag())
		out.push_back(Colorize('[ ]', SYNTAX.PUNCT))
		return out

	var prefix := inc_indent(indent)
	var postfix := "\n" if PRETTY_PRINT.MULTILINE else ""
	var key_indent := inc_indent(prefix) if PRETTY_PRINT.MULTILINE else " "

	if depth > 0:
		out.push_back(" ")

	if depth > PRETTY_PRINT.DEPTH_LIMIT:
		out.append_array([
				pool_tag(prefix) if is_pool else prefix,
				Colorize(ReplUtil.TypeStringOf(value), SYNTAX.INTRINSIC),
				Colorize('[', SYNTAX.PUNCT),
					Colorize(str(length), SYNTAX.NUMERIC),
				Colorize(']', SYNTAX.PUNCT)
		])
		return out

	out.push_back(pool_tag(indent) if is_pool else indent)
	out.push_back("%s%s" % [ Colorize('[', SYNTAX.PUNCT), postfix ])

	for i in length:
		# Push indent + content
		# TODO: This is gonna be bad on gigantic strings in a string array or something,
		#        probably should do a length check on strings or do it here
		out.push_back("%s%s" % [
				prefix,
				pretty_print_value(value[i], depth + 1, prefix).lstrip('\t\n ') ])

		# On limit reached
		if i >= PRETTY_PRINT.MAX_ELS and length >= i:
			# Push comma, and etc. symbol
			out.push_back("%s%s%s%s\n" % [
					Colorize(',', SYNTAX.PUNCT),
					postfix, prefix,
					Colorize(PRETTY_PRINT.FMT.X_MORE % [ length - PRETTY_PRINT.MAX_ELS ], SYNTAX.COMMENT),
				])
			break
		elif PRETTY_PRINT.MULTILINE:
			out.push_back("%s%s" % [
					Colorize(',', SYNTAX.PUNCT),
					postfix if i <= length else "" ])

	out.push_back("%s%s" % [
			indent,
			Colorize(']', SYNTAX.PUNCT) ])

	return out


func pretty_print_dict(value: Dictionary, depth := 0, indent := "") -> PoolStringArray:
	var keys := value.keys()
	var length := keys.size()

	if length == 0:
		return PoolStringArray([Colorize('{ }', SYNTAX.PUNCT)])

	if depth > PRETTY_PRINT.DEPTH_LIMIT:
		return PoolStringArray([
				Colorize('Dictionary', SYNTAX.INTRINSIC),
				Colorize('{', SYNTAX.PUNCT),
					Colorize(str(length), SYNTAX.NUMERIC),
				Colorize('}', SYNTAX.PUNCT)
		])

	var prefix := inc_indent(indent)
	var postfix := "\n" if PRETTY_PRINT.MULTILINE else ""
	var key_indent := inc_indent(prefix) if PRETTY_PRINT.MULTILINE else " "

	var out := PoolStringArray([ "%s%s" % [
			Colorize('{', SYNTAX.PUNCT),
			"\n" if PRETTY_PRINT.MULTILINE else " ", ] ])

	for i in length:
		var key = keys[i]
		var key_str: String
		var key_str_color = SYNTAX.STRING
		match typeof(key):
			TYPE_INT, TYPE_REAL:
				key_str = str(key)
				key_str_color = SYNTAX.NUMERIC

			TYPE_STRING:
				if ReplUtil.NeedsQuot(key):
					key_str = to_json(key)
				else:
					key_str = key
					key_str_color = SYNTAX.PROP_LIT
			_:
				key_str = to_json(key)

		# Push indent + content
		out.push_back("%s%s%s %s" % [
				prefix,
				Colorize(key_str, key_str_color),
				Colorize(":", SYNTAX.PUNCT),
				pretty_print_value(value[key], depth + 1, prefix).lstrip(' \t') ])

		# On limit reached
		if i > PRETTY_PRINT.MAX_ELS and length > i + 1:
			# Push comma, and etc. symbol
			var x_more: String = PRETTY_PRINT.FMT.X_MORE % [ length - PRETTY_PRINT.MAX_ELS ]
			out.push_back("%s%s%s%s%s" % [
					Colorize(',', SYNTAX.PUNCT), postfix,
					key_indent,
					Colorize(x_more, SYNTAX.COMMENT), postfix ])
			break

		# On last reached but not at limit
		elif PRETTY_PRINT.MULTILINE or i != length - 1:
			out.push_back("%s%s" % [ Colorize(',', SYNTAX.PUNCT), postfix ])

	out.push_back("%s%s" % [ indent, Colorize('}', SYNTAX.PUNCT) ])

	return out


func pretty_print_classlike(value, depth := 0, indent := "") -> PoolStringArray:
	dprint.debug('Resolved => Reference | Node | MainLoop', 'pretty_print_value')

	if PRETTY_PRINT.SIMPLE_BUILDER:
		var out := PoolStringArray(["%s%s%s%s:%s%s" % [
				indent,
				(Colorize(value.get("name"), SYNTAX.TAG)
						if typeof(value.get("name")) == TYPE_STRING
					else ""),
				Colorize(fmt.escape('['), SYNTAX.PUNCT),
				Colorize(value.get_class(), SYNTAX.TYPE),
				Colorize(value.get_instance_id(), SYNTAX.NUMERIC * Color(1, 1, 1, 0.7)),
				Colorize(fmt.escape(']'), SYNTAX.PUNCT)
		]])
		var node := value as Node
		# Print first n nodes of tree
		if depth == 0 and is_instance_valid(node) and node.get_child_count() > 0:
			indent = "\n%s" % [ inc_indent(indent) ]
			var child_count := node.get_child_count()
			var count := int(min(child_count, PRETTY_PRINT.MAX_ELS))

			for i in count:
				out.push_back("%s- %s" % [
						indent,
						pretty_print_value(node.get_child(i), depth + 1, "") ])

			if count < child_count:
				out.push_back(Colorize(
						indent + PRETTY_PRINT.FMT.X_MORE % [ child_count - count ],
						SYNTAX.COMMENT))

			return out
		else:
			return out

	else:
		return pretty_print_classlike_parse(value, depth, indent)


func pretty_print_classlike_parse(value, depth := 0, indent := "") -> PoolStringArray:
	var value_str := "%s" % [ value ]
	var out_string: String = ""
	# Get index of non-prefix content (e.g. `[` * `]`)
	var base_idx := value_str.find('[')
	# If not found return unstyled value string
	if base_idx == -1:
		return PoolStringArray([value_str])

	# Get body of base node syntax, minus surrounding brackets
	var node_base := value_str.substr(base_idx + 1).trim_suffix(']')
	var prefix := "" if base_idx == 0 else value_str.substr(0, base_idx - 1)

	# Attempt to split base node body into type and reference id
	var base_contents := PoolStringArray()

	if node_base.find(':') == -1:
		# Treat as single fragment
		base_contents.push_back(Colorize(node_base, SYNTAX.TYPE))
	else:
		# Treat as <type> + ':' + <id>
		# Nothing _should_ need to be escaped here
		var parts := node_base.split(':')
		base_contents.push_back(Colorize(parts[0], SYNTAX.TYPE))
		base_contents.push_back(Colorize(':',      SYNTAX.PUNCT))
		base_contents.push_back(Colorize(parts[1], SYNTAX.NUMERIC * Color(1, 1, 1, 0.7)))


	# Build output fragments. Anything beyond simple equality checks and expressions should
	# remain before this if possible
	var pool := PoolStringArray()

	# Name/@ prefix content
	if prefix != "":
		pool.push_back(Colorize(prefix, SYNTAX.TAG))

	# Main body
	pool.push_back(Colorize(fmt.escape('['), SYNTAX.PUNCT))
	pool.append_array(base_contents)
	pool.push_back(Colorize(fmt.escape(']'), SYNTAX.PUNCT))

	return pool


# For type-specific formatting of return values
func pretty_print_value(value, depth := 0, indent := "") -> String:
	if syntax_colors_initialized == false or syntax_colors.empty():
		build_syntax_colors(true)
		syntax_colors_initialized = true

	match typeof(value):
		TYPE_BOOL, TYPE_NIL:
			#dprint.write('Resolved => bool | null', 'pretty_print_value')
			return Colorize("%s" % [ value ], SYNTAX.KEYWORD)

		TYPE_INT, TYPE_REAL:
			#dprint.write('Resolved => int | real', 'pretty_print_value')
			return Colorize("%s" % [ value ],
						SYNTAX.INTRINSIC
							if (is_inf(value) or is_nan(value))
						else SYNTAX.NUMERIC
					)

		TYPE_STRING, TYPE_NODE_PATH:
			#dprint.write('Resolved => string | NodePath', 'pretty_print_value')
			return Colorize(to_json(value), SYNTAX.STRING)

		TYPE_COLOR:
			#dprint.write('Resolved => Color', 'pretty_print_value')
			return pretty_print_color(value, depth, indent).join('')

		TYPE_VECTOR2, TYPE_VECTOR3:
			#dprint.write('Resolved => Vector2 | Vector3', 'pretty_print_value')
			return pretty_print_vec(value, depth, indent).join('')

		TYPE_ARRAY, TYPE_STRING_ARRAY, TYPE_INT_ARRAY, TYPE_REAL_ARRAY, TYPE_VECTOR2_ARRAY, TYPE_VECTOR3_ARRAY:
			#dprint.write('Resolved => Array | PoolStringArray | PoolIntArray | PoolRealArray', 'pretty_print_value')
			return pretty_print_arraylike(value, depth, indent).join('')

		TYPE_DICTIONARY:
			#dprint.write('Resolved => Dictionary', 'pretty_print_value')
			return pretty_print_dict(value, depth, indent).join('')

	if (value is Reference) or (value is Node) or (value is MainLoop):
		return pretty_print_classlike(value, depth, indent).join('')

	dprint.warn('Reached end of resolution logic, failed to get pattern for %s' % [ value ], 'pretty_print_value')
	return str(value)


#section Handlers


func _on_input_text_entered(new_text):
	eval()


func _on_input_submit_eval(text) -> void:
	dprint.write('Repl input: %s' % [ text ], 'input-submit-eval')
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


func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return

	# No mouse input atm
	elif not event is InputEventKey:
		return

	elif is_instance_valid(input) and input.has_focus():
		var prev := input.text
		var prev_col :=  input.cursor_get_column()
		if event.is_action_pressed("ui_up"):
			hist[hist_index] = prev
			hist_index = hist_index - 1 if (hist_index > 0) else hist_index
			input.text = hist[hist_index]
			input.cursor_set_column(
					# prev.empty will only properly work for first move. To detect and handle
					# up/down movement from empty prompt differently you neeed to add a state var
					input.text.length()
						if prev.empty() else
							clamp(input.cursor_get_column(), 0, input.text.length() - 1))
			get_tree().set_input_as_handled()
			accept_event()

		elif event.is_action_pressed("ui_down"):
			hist[hist_index] = prev
			hist_index = hist_index + 1 if (hist_index < hist.size() - 1) else hist_index
			input.cursor_set_column(clamp(input.cursor_get_column(), 0, input.text.length() - 1))
			input.text = hist[hist_index]
			get_tree().set_input_as_handled()
			accept_event()


func _on_reload(_value) -> void:
	if not Engine.editor_hint: return

	input  = get_node_or_null("IOVBox/InputHBox/input")
	if not is_instance_valid(input):
		var input_instance := preload('./ReplInputTextEdit.tscn').instance()
		input_instance.name = 'input'
		get_node("IOVBox/InputHBox").add_child(input_instance)

	output = $IOVBox/output
	env    = $ReplEnvironment

	return

	for prop in 'input output env'.split(" "):
		dprint.write('', 'on:reload]   %s:%s %s' % [
			prop, ' '.repeat(7 - prop.length()),
			self[prop]
		])


func _on_input_request_completion() -> void:
	dprint.write('', 'on:request-completion')


#section Env


var eval_env
var variables: Dictionary
var external_bindings: Dictionary = { }


func _on_external_binding_definition(binding_name: String, value):
	external_bindings[binding_name] = value
	# Update immedately for now
	_env_apply_binding_dict({ binding_name: value })


func _env_init_self():
	eval_env = env


func _env_apply_binding_dict(bindings: Dictionary) -> void:
	for key in bindings.keys():
		variables[key] = bindings[key]


func _env_build_bindings() -> void:
	_env_init_base_bindings()
	_env_init_custom_bindings()
	_env_init_external_bindings()
	_env_init_plugin_singletons()


func _env_rebuild() -> void:
	_env_init_self()
	variables = { }
	_env_build_bindings()


func _env_init_plugin_singletons() -> void:
	_env_apply_binding_dict(env.get_plugin_singletons_dict())


func _env_init_external_bindings() -> void:
	_env_apply_binding_dict(external_bindings)


# Add extended variable bindings
func _env_init_custom_bindings() -> void:
	dprint.write('', 'env:init-custom-bindings')
	var additions := {
		'editor':   env,
		'instance': REPL.interface,
		'syntax':   syntax,
		'repl':     self,
		'settings': env.get_settings()
	}
	_env_apply_binding_dict(additions)


func _env_init_base_bindings() -> void:
	_env_apply_binding_dict(preload('../ReplGlobalsBase.gd').GetVariables())


#section Custom monospace font
# TODO: Load editor via editor's theme (see Nous settings for example, if the impl is still there)

var orig_mono_font_size


# TODO: Move to resource
const OPTIONS := {
	FONT_SIZE = 14
}

func rebuild_mono_font():
	var font := DynamicFont.new()
	font.font_data = load('res://addons/repl/iosevka-term-ss10-regular.ttf')
	if typeof(orig_mono_font_size) != TYPE_INT:
		orig_mono_font_size = OPTIONS.FONT_SIZE
	var scale = OS.get_screen_max_scale()
	if scale > 0:
		font.size = orig_mono_font_size * scale

	output.add_font_override("font", font)
	output.add_font_override("normal_font", font)
	output.add_font_override("mono_font", font)
	input.add_font_override("font", font)
	input.add_font_override("normal_font", font)
	input.add_font_override("mono_font", font)


#section general statics/etc.


const DEBUG_SCANCODE_BIN_LEN := 32
func _debug_dump_scancode_info(event: InputEventKey, ctx := 'debug-dump'):
	dprint.write('  Scancode data:\n%s\n%s\n' % [
			ReplUtil.int2bin(event.get_scancode(), DEBUG_SCANCODE_BIN_LEN),
			ReplUtil.int2bin(event.get_scancode_with_modifiers(), DEBUG_SCANCODE_BIN_LEN) + ' [With Modified]'
		], ctx)
