const COMMIT_INPUT := '\u001B'

var inputs := PoolStringArray([
	'root',
	COMMIT_INPUT,
	'root.get_children()',
	COMMIT_INPUT
])

func run(harness: ReplTestHarness, interval := 80) -> void:
	for input in inputs:
		if input == COMMIT_INPUT:
			harness.commit_input()
		else:
			harness.add_text(input)
		yield()
