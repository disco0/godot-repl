#region Original Copyright
# GDScript REPL plugin
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
#endregion Original Copyright
tool
class_name ReplPlugin
extends EditorPlugin


const plugin_name := 'REPL'
const plugin_node_name := 'REPL' + 'Plugin'
const plugin_path := 'res://addons/repl'
const ReplControlRes := preload("./ui/ReplControl.tscn")

var control
var dprint := preload('./util/logger.gd').Builder.get_for(plugin_node_name)
var syntax := preload("./SyntaxColorsNode.gd").new()


#section Lifecycle


func _init() -> void:
	if not Engine.editor_hint: return
	name = plugin_node_name


func _enter_tree():
	dprint.write('Initializing control', 'on:enter-tree')
	dprint.write('Loading ReplAPI singleton (REPL)', 'on:enter-tree')
	add_autoload_singleton('REPL', plugin_path.plus_file('ReplAPI.gd'))
	if not REPL._loaded:
		yield(REPL, "loaded")
	REPL.register_plugin(self)


func _ready():
	dprint.write('', 'on:ready')
	control = ReplControlRes.instance()
	control.set_plugin(self) # .connect("ready", ReplUtil, "PassInstance", [ self, 'plugin', control ])

	dprint.write('Attaching control to editor', 'on:ready')
	# As a dock:
	#add_control_to_dock(DOCK_SLOT_RIGHT_BL, control)
	# In the bottom panel:
	add_control_to_bottom_panel(control, 'REPL')


func _exit_tree():
	if is_instance_valid(control):
		# As a dock:
		#remove_control_from_docks(control)
		# In the bottom panel:
		dprint.write('Freeing control', 'on:exit-tree')
		control.queue_free()
		dprint.write('Detaching control from editor', 'on:exit-tree')
		remove_control_from_bottom_panel(control)

	dprint.write('Unloading ReplAPI singleton (REPL)', 'on:exit-tree')


#section setget


func get_plugin_name() -> String:
	return plugin_name


func get_plugin_icon() -> Texture:
	return get_editor_interface().get_base_control().theme.get_icon('EditorIcons', 'Script')
