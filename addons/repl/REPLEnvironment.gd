tool
class_name ReplEnvironment
extends Node


###
### Introduces additional methods/value bindings in top level repl scope.
###


signal reinit_required(instance)


const INSPECT_ENTRY_INDENT_LEVEL := 2

var dprint := preload('./util/logger.gd').Builder.get_for(self)
var root: Viewport setget, get_root
var scene: Node setget, get_scene
var settings: EditorSettings setget, get_settings
var selected_nodes: Array setget, get_selected_nodes
var selected_node: Node setget, get_selected_node
var help_output: String setget, get_help_output
var info_lines := PoolStringArray([
	'var editor',
	'  Properties:',
	'    root  => Viewport',
	'    scene => Edited Scene Root',
	'  Methods:',
	'    collect_prop(obj): PoolStringArray',
	'      Returns sorted PoolStringArray of properties on `obj`',
	'    collect_method(obj): PoolStringArray',
	'      Returns sorted PoolStringArray of methods on `obj`',
	'    help():',
	'      Displays this text.',
])
var _plugin: EditorPlugin
var _interface: EditorInterface

onready var plugin setget set_plugin, get_plugin
onready var interface: EditorInterface setget, get_interface
onready var syntax setget, get_syntax
onready var control := $"../"


#section Lifecycle


func _init():
	if not Engine.editor_hint: return
	dprint.write('', 'on:init')
	REPL.request_plugin(self)


func _enter_tree() -> void:
	dprint.write('', 'enter-tree')
	set_plugin(REPL.get_plugin())
	_check_control_initialized()


func _ready() -> void:
	_check_control_initialized()
	#_debug_dump_members('on:ready')
	dprint.write('', 'ready')


#section Repl Utils


func _check_control_initialized() -> void:
	if is_instance_valid(control):
		return
	if is_inside_tree():
		control = get_parent()


func lazy_quote(text: String) -> String:
	if (' ' in text) or ("\n" in text) or ("\t" in text):
		return to_json(text)
	return text


func props(obj: Object, filter := "", usage_mask = ReplUtil.IGNORED_PROP_USAGE) -> PoolStringArray:
	var list = [ ]
	for prop_item in obj.get_property_list():
		if not 'usage' in prop_item:
			list.push_back(prop_item)
			continue

		print('%s: %s' % [ prop_item.name, int2bin(prop_item.usage, 16) ])
		print('  usage & usage_mask => %s' % [
			(prop_item['usage'] & usage_mask)
		])
		if (prop_item['usage'] & usage_mask) == 0:
			list.push_back(prop_item)

	var arr := Array(ReplUtil.CollectProp(list, 'name', filter))
	arr.sort()
	return PoolStringArray(arr)


func inspect_prop(prop_dict_arr: Array, prop: String, filter := "", prop_full_name := "") -> void:
	var names := Array(ReplUtil.CollectProp(prop_dict_arr, prop, filter))
	names.sort()
	var lines := PoolStringArray()
	lines.push_back(
			control.Colorize('%s:' % [
					(prop_full_name if prop_full_name.length() > 0 else prop).capitalize() ],
			control.SYNTAX.TYPE))
	for name in names:
		lines.push_back(
				' '.repeat(INSPECT_ENTRY_INDENT_LEVEL)
				+ control.Colorize("-", control.SYNTAX.PUNCT)
				+ " "
				+ control.Colorize(lazy_quote(name), control.SYNTAX.STRING))
	control.output_line_raw(lines.join("\n"))
	control.clear_repl_input()


func p(obj, filter := "") -> void:
	match typeof(obj):
		TYPE_NIL:
			control.write_error('Value is null')
			return
		TYPE_DICTIONARY:
			print('Pretty printing dict')
			if filter.empty():
				control.output_line_raw(control.pretty_print_value(obj))
				return

			var out = { }
			for k in obj:
				if (k as String).findn(filter) != -1:
					out[k] = obj[k]

			control.output_line_raw(control.pretty_print_value(out))
			return

		TYPE_ARRAY:
			if filter.empty():
				control.output_line_raw(control.pretty_print_value(obj))
				return

			var out = [ ]
			for item in obj:
				if (item as String).findn(filter) != -1:
					out.push_back(item)

			control.output_line_raw(control.pretty_print_value(out))
			return

		TYPE_OBJECT:
			if not is_instance_valid(obj):
				control.write_error('Value is invalid instance.')
				return

			inspect_prop(
					ReplUtil.PropFilterNonRegion(obj.get_property_list()),
					"name",
					filter,
					"Properties")

			return


func m(obj: Object, filter := "") -> void:
	if typeof(obj) != TYPE_OBJECT:
		control.write_error('obj is not an Object.')
	elif is_instance_valid(obj):
		inspect_prop(obj.get_method_list(), "name", filter, "Methods")
	else:
		control.write_error('obj is not a valid instance.')


func methods(obj: Object, filter := "") -> PoolStringArray:
	var list = obj.get_method_list()
	var arr := Array(ReplUtil.CollectProp(list, 'name', filter))
	arr.sort()
	return PoolStringArray(arr)


func copy(content) -> void:
	OS.set_clipboard(content if typeof(content) == TYPE_STRING else String(content))


func paste() -> String: return OS.get_clipboard()


func inspect(obj) -> void:
	if typeof(obj) != TYPE_OBJECT:
		# Get control and display error
		control.output_line_raw(control.Colorize("Can only inspect Objects.", control.SYNTAX.ERROR))
		return
	get_interface().inspect_object(obj)


func i(obj) -> void:
	inspect(obj)


func bin2int(value: String) -> int:
	return ReplUtil.bin2int(value)


func int2bin(value: int, bit_count: int = -1) -> String:
	return ReplUtil.int2bin(value, bit_count)


# NOTE: Clears godot process' terminal, _not_ the repl output
func clear_term():
	printraw("\u001B[​2J\u001B[​;H")


func find(path, recurse := true, owned := false, base: Node = get_root()) -> Node:
	return base.find_node(path, recurse, owned)


func stringify(value, indent = 4, sort = true) -> String:
	return JSON.print(value, indent, sort)


#section setget


func set_plugin(plugin_instance: EditorPlugin) -> void:
	if is_instance_valid(plugin_instance):
		dprint.write('Updating plugin/interface/syntax', 'set:plugin')
		_plugin = plugin_instance
		interface = _plugin.get_editor_interface()
		syntax = _plugin.syntax
		_debug_dump_members('set:plugin')
	else:
		dprint.warn('Passed plugin instance is not valid.', 'set:plugin')


func get_plugin() -> EditorPlugin:
	if is_instance_valid(_plugin):
		return _plugin
	elif is_instance_valid(REPL.plugin):
		_plugin = REPL.plugin
		return _plugin
	else:
		dprint.warn('_plugin instance not valid.', 'get:plugin')
		return null


func get_syntax():
	if is_instance_valid(_plugin):
		return _plugin.syntax
	else:
		dprint.warn('_plugin instance not valid.', 'get:syntax')
		return null


func get_interface() -> EditorInterface:
	return EditorScript.new().get_editor_interface()


func get_help_output() -> String:
	return info_lines.join('\n')


func get_root() -> Viewport:
	return get_interface().get_tree().root


func get_scene() -> Node:
	return get_interface().get_edited_scene_root()


func get_settings() -> EditorSettings:
	return get_interface().get_editor_settings()


func get_selected_nodes() -> Array:
	return get_interface().get_selection().get_selected_nodes()


# Returns first node of selected nodes from _get_selected_nodes
func get_selected_node() -> Node:
	return get_interface().get_selection().get_selected_nodes().front()


func get_singleton(name: String):
	if Engine.has_singleton(name):
		return Engine.get_singleton(name)
	return get_root().get_node_or_null(name)


func get_global_scope() -> Dictionary:
	return get_parent().variables.GetEngineSingletons()


func get_plugin_singletons() -> Array:
	var count := get_root().get_child_count()
	if count <= 1:
		return [ ]

	var singletons := [ ]
	var start := 1
	for idx in range(start, count):
		singletons.push_back(get_root().get_child(idx))

	return singletons


func get_plugin_singletons_dict() -> Dictionary:
	dprint.write('', 'get_plugin_singletons_dict')
	var count := get_root().get_child_count()
	if count <= 1:
		return { }

	var singletons := Dictionary()
	var idx := -1
	for child in get_root().get_children():
		idx += 1
		if not is_instance_valid(child):
			dprint.warn('Invalid root child index %2d' % [ idx ])
		dprint.write(' [%02d] %s: %s' % [ idx, child.name, child ], 'get_plugin_singletons_dict')
		singletons[child.name] = child

	return singletons


const REPL_SCRIPT_INSTANCE_GROUP = 'repl-script-instance'
const RUN_TARGET_METHOD_NAME := 'run'
var last_ran

func _prepare_run_instance() -> void:
	if not is_instance_valid(last_ran):
		last_ran = null
		return

	if (last_ran as Node) != null:
		if last_ran.is_inside_tree():
			dprint.write('Removing last script instance from tree.', '_prepare_run')
			last_ran.get_parent().remove_child(last_ran)

		last_ran.queue_free()

	last_ran = null

func _store_run_instance(instance) -> void:
	if not is_instance_valid(instance): return

	last_ran = instance

	if not instance is Node: return

	(instance as Node).add_to_group(REPL_SCRIPT_INSTANCE_GROUP)
	REPL.add_child(instance)


func reset_run() -> void:
	var base := REPL as Node
	for node in base.get_children():
		if (node as Node).is_in_group(REPL_SCRIPT_INSTANCE_GROUP):
			base.remove_child(node)

func run(script_path: String = "") -> void:
	# TODO: Picker on fallback or exists check fail, also in general
	if script_path.empty():
		control.write_error('Empty script_path argument.')
		return
	if not ResourceLoader.exists(script_path, 'GDScript'):
		control.write_error('Path does not resolve to script: <%s>' % [ script_path ])
		return

	var script_res := ResourceLoader.load(script_path, "GDScript", true) as GDScript
	if not script_res.is_tool():
		control.write_error('Non-tool script: <%s>' % [ script_path ])
		return
	var method_info_list := script_res.get_script_method_list()
	if not ReplUtil.HasItemWithProp(method_info_list, 'name', RUN_TARGET_METHOD_NAME):
		var method_list := ReplUtil.CollectProp(method_info_list, 'name')
		var method_list_indent = "\n\t - "
		control.write_error('Script does not contain %s method.\nFound Methods:%s' % [
				RUN_TARGET_METHOD_NAME,
				method_list_indent + PoolStringArray(method_list).join(method_list_indent)
		])
		return

	# TODO: Add API to pass in env to init?
	var instance = script_res.new()

	if not is_instance_valid(instance):
		control.write_error('Returned invalid instance from .new()' % [ RUN_TARGET_METHOD_NAME ])
		return

	control.output_line_raw(
			control.Colorize('# Running %s' % [ script_path ], control.SYNTAX.COMMENT))

	instance.call(RUN_TARGET_METHOD_NAME)

	control.output_line_raw(
			control.Colorize('# %s call complete' % [ RUN_TARGET_METHOD_NAME ],
							 control.SYNTAX.COMMENT))

	_store_run_instance(instance)

#section etc


func _debug_dump_members(ctx: String) -> void:
	return
	for member in 'plugin interface syntax'.split(' '):
		dprint.write('%s: %s' % [ member, self[member]], ctx)
