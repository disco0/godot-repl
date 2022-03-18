class_name BBCodeText

const ZWSP := '\u200B'


static func ColorTag(color) -> String:
	return '[color=#%s]' % [
			(color as Color).to_html() if color is Color else color.trim_prefix('#') ]


# Original escape function, keeping it in case this version w/ both delimiters is needed
static func Escape(text: String) -> String:
	# Keeping it simple here
	return text.replacen('[', '[\u200B').replacen(']', '\u200B]')


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
