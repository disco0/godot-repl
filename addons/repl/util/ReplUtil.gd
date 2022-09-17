tool
class_name ReplUtil


const PROPERTY_USED_REGION_FLAGS = PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY


static func PassInstance(instance, prop, target) -> void:
	var setter = 'set_%s' % [ prop ]
	target.call(setter, instance)


#region Object Properties


static func PropUsageFilter(prop_list: Array, flags: int) -> Array:
	var filtered = [ ]
	for prop in prop_list:
		if (
			not 'usage' in prop
			or typeof(prop['usage']) != TYPE_INT
			or (prop['usage'] & flags) == 0
		):
			filtered.push_back(prop)

	return filtered


static func PropFilterNonRegion(prop_list: Array) -> Array:
	return PropUsageFilter(prop_list, PROPERTY_USED_REGION_FLAGS)


static func CollectProp(dict_arr: Array, prop: String, filter_str := "") -> PoolStringArray:
	var pool := PoolStringArray()

	if filter_str.length() > 0:
		var filter := PropFilter.new(filter_str)
		for item in dict_arr:
			if prop in item and filter.test(item[prop]):
				pool.push_back(item[prop])
	else:
		for item in dict_arr:
			if item[prop]:
				pool.push_back(item[prop])

	return pool


static func HasItemWithProp(list: Array, prop_name: String, value) -> bool:
	for item in list:
		if prop_name in item and item[prop_name] == value:
			return true

	return false


#endregion Object Properties


#region Strings


# Non-regex method for naively stripping enclosing parens
static func StripParens(string: String) -> String:
	return string.strip_edges(true, true).trim_prefix('(').trim_suffix(')')
	#return string.strip_edges(true, true).right(1).rstrip(')')


# Check if string needs to be quoted (e.g. for property names in object literal-likes)
static func NeedsQuot(string: String) -> bool:
	return string.find(' ') >= 0 or string.strip_escapes().length() < string.length()


static func TypeStringOf(value) -> String:
	return TYPE_ENUMS_UI[typeof(value)]


static func TypeStringOfRaw(value) -> String:
	return TYPE_ENUMS_RAW[typeof(value)]


const TYPE_ENUMS_RAW := [
	"TYPE_NIL",
	"TYPE_BOOL",
	"TYPE_INT",
	"TYPE_REAL",
	"TYPE_STRING",
	"TYPE_VECTOR2",
	"TYPE_RECT2",
	"TYPE_VECTOR3",
	"TYPE_TRANSFORM2D",
	"TYPE_PLANE",
	"TYPE_QUAT",
	"TYPE_AABB",
	"TYPE_BASIS",
	"TYPE_TRANSFORM",
	"TYPE_COLOR",
	"TYPE_NODE_PATH",
	"TYPE_RID",
	"TYPE_OBJECT",
	"TYPE_DICTIONARY",
	"TYPE_ARRAY",
	"TYPE_RAW_ARRAY",
	"TYPE_INT_ARRAY",
	"TYPE_REAL_ARRAY",
	"TYPE_STRING_ARRAY",
	"TYPE_VECTOR2_ARRAY",
	"TYPE_VECTOR3_ARRAY",
	"TYPE_COLOR_ARRAY",
	"TYPE_MAX"
]

const TYPE_ENUMS_UI := [
	"Nil",
	"Bool",
	"Int",
	"Real",
	"String",
	"Vector2",
	"Rect2",
	"Vector3",
	"Transform2D",
	"Plane",
	"Quat",
	"Aabb",
	"Basis",
	"Transform",
	"Color",
	"NodePath",
	"Rid",
	"Object",
	"Dictionary",
	"Array",
	"PoolRawArray",
	"PoolIntArray",
	"PoolRealArray",
	"PoolStringArray",
	"PoolVector2Array",
	"PoolVector3Array",
	"PoolColorArray",
]


# "1000" => 8
static func bin2int(bin_str: String) -> int:
	var prefix := bin_str.rfindn('b')
	if prefix != -1:
		bin_str = bin_str.substr(prefix + 1)

	var out := 0
	for c in bin_str:
		out = (out << 1) + int(c == "1")
	return out


static func int2bin(value: int, bit_count: int = -1) -> String:
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
