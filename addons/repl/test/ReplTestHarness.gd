class_name ReplTestHarness

# For programmatic repl interaction

var repl: ReplControl

func _init(repl_control: ReplControl):
	repl = repl_control

func add_text(text: String, join := ' ') -> void:
	repl.input.text += join + text

func commit_input() -> void:
	repl._on_eval_pressed()

func clear_repl() -> void:
	repl.clear_repl_input()
