tool
class_name PropFilter


var method_names := PoolStringArray()
var filter := ''


func _init(filter: String):

	if filter.begins_with('*'):
		method_names.push_back('ends_with')
		filter = filter.lstrip('*')

	if filter.ends_with('*'):
		method_names.push_back('begins_with')
		filter = filter.rstrip('*')

	if method_names.size() == 0 or method_names.size() == 2:
		method_names = PoolStringArray(['find'])

	self.filter = filter


func begins_with(prop: String) -> bool:
	return prop.begins_with(filter)


func find(prop: String) -> bool:
	return prop.find(filter) != -1


func ends_with(prop: String) -> bool:
	return prop.ends_with(filter)


func test(prop: String) -> bool:
	for method_name in Array(method_names):
		#print('PropFilter.%s %s' % [ method_name, filter ])
		if self.call(method_name, prop):
			return true
	return false

