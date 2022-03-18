tool
class_name ReplInputTextEdit
extends TextEdit


signal submit_eval(text)


onready var repl_control := $"../../.."

var dprint := REPL.dprint_for(self)
var syntax


#section Lifecycle


func _init() -> void:
	set_syntax_coloring(true)


func _ready() -> void:
	update_colors()


#section general


func initialize_input() -> void:
	self.set_text("")
	reset_position()


func reset_position() -> void:
	cursor_set_column(0, true)
	cursor_set_line(0, true)


# @TODO
# For acquiring symbol_lookup signal symbol parameter
func resolve_symbol(row: int, col: int) -> String:
	return ""


func update_colors() -> void:
	if not is_inside_tree(): return

	if not is_instance_valid(syntax):
		var control = get_node('../../..')
		if not is_instance_valid(control):
			dprint.warn('Failed to get scene base node.', 'update_colors')
			return

		control.call("build_syntax_colors", true)
		syntax = control.SYNTAX

	if not syntax:
		dprint.warn('Failed to get syntax color dictionary.', 'update_colors')
		return

	add_color_region('"', '"', syntax.STRING)
	add_color_region("'", "'", syntax.STRING)
	add_keyword_color("\\'", syntax.STRING)
	add_keyword_color("\\'", syntax.STRING)
	add_keyword_color("root", syntax.INTRINSIC)
	add_keyword_color("scene", syntax.INTRINSIC)
	add_keyword_color("&", syntax.KEYWORD)
	add_keyword_color("&&", syntax.PUNCT)
	add_keyword_color(">=", syntax.PUNCT)
	add_keyword_color("|", syntax.KEYWORD)
	add_keyword_color("||", syntax.PUNCT)
	add_keyword_color("<=", syntax.PUNCT)
	add_keyword_color("==", syntax.PUNCT)
	add_keyword_color("=", syntax.PUNCT)
	add_keyword_color("var", syntax.KEYWORD)
	add_keyword_color("export", syntax.KEYWORD)
	add_keyword_color("int", syntax.KEYWORD)
	add_keyword_color("float", syntax.KEYWORD)


#section handlers


# Leaving this here in case its useful later
# https://github.com/godotengine/godot/issues/15071#issuecomment-562807400
func _gui_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return

	# No mouse input atm
	elif not event is InputEventKey:
		return

	if has_focus():
		var kev := event as InputEventKey
		if kev.pressed:
			match kev.get_scancode():
				KEY_ENTER:
					if not (kev.shift or kev.command or kev.control or kev.alt):
						if not text.lstrip(' \t\n').rstrip(' \t\n').empty():
							emit_signal("submit_eval", get_text())
							get_tree().set_input_as_handled()
							accept_event()
						else:
							text = ""
						call_deferred('initialize_input')

			var code := kev.get_scancode_with_modifiers()

			if code == KEY_SPACE | KEY_MASK_CTRL | KEY_MASK_ALT:
				# emit_signal("symbol_lookup")
				accept_event()
				get_tree().set_input_as_handled()

			elif code == KEY_SPACE | KEY_MASK_CTRL:
				emit_signal("request_completion")
				accept_event()
				get_tree().set_input_as_handled()
		else:
			match kev.get_scancode():
				KEY_ENTER:
					if not (kev.shift or kev.command or kev.control or kev.alt):
						accept_event()
						get_tree().set_input_as_handled()
