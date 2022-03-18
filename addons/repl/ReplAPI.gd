extends Node
tool


signal loaded()
signal plugin_registered(instance)
signal binding_added(binding_name, value)


const DPRINT := preload('./util/logger.gd')

var dprint := dprint_for(self, DPRINT.Colorful.RED_BRIGHT)
var plugin: EditorPlugin
var interface: EditorInterface setget, get_interface
var _editor_code_font: DynamicFont
var _loaded := false
var _settings: EditorSettings


#section Lifecycle


func _init() -> void:
	if not Engine.editor_hint: return


func _ready() -> void:
	if not Engine.editor_hint: return
	_settings = EditorScript.new().get_editor_interface().get_editor_settings()
	_loaded = true
	emit_signal("loaded")


#section setget


func get_plugin() -> EditorPlugin:
	if is_instance_valid(plugin):
		return plugin
	else:
		dprint.error('invalid plugin instance', 'get:plugin')
		return null


func get_interface() -> EditorInterface:
	if not OS.has_feature("editor"): return null
	if is_instance_valid(plugin):
		return plugin.get_editor_interface()
	else:
		return EditorScript.new().get_editor_interface()


func register_plugin(instance, reemit := true):
	if is_instance_valid(plugin):
		#print('[ReplAPI:register_plugin] Already initialized.')
		emit_signal("plugin_registered", plugin)
	else:
		plugin = instance
		emit_signal("plugin_registered", plugin)


func request_plugin(instance: Node):
	if instance.has_signal('set_plugin') \
			and not is_connected("plugin_registered", instance, "set_plugin"):
		self.connect("plugin_registered", instance, "set_plugin", [], CONNECT_ONESHOT)


# Interface for external code
func add_binding(binding_name: String, value):
	get_signal_list()
	emit_signal("binding_added", binding_name, value)


#func get_editor_code_font(force := false) -> DynamicFont:
#	if not force and is_instance_valid(_editor_code_font):
#		return _editor_code_font
#
#	var _editor_code_font = .('source', 'EditorFonts')
#
#	return _editor_code_font
	#var fp = _settings.get('interface/editor/code_font')
	#if fp:
	#	var font_data = DynamicFontData.new()
	#	font_data.set_font_path(ProjectSettings.globalize_path(fp))
	#	_editor_code_font = DynamicFont.new()
	#	#_editor_code_font.size = _settings.get('interface/editor/code_font_size')
	#	_editor_code_font.set_font_data(font_data)
	#
	#	return _editor_code_font
	#else:
	#	return null


#section statics


# Main dprint constructor interface
static func dprint_for(obj, base_color = DPRINT.DEFAULT_COLORS.BASE) -> DPRINT.DebugPrintBase:
	return DPRINT.Builder.get_for(obj, null, base_color)
