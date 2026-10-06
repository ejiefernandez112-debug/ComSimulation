#!/usr/bin/env bash
# Claude Code hook (PostToolUse, Edit|Write): after a .gd script is edited, run the project check
# (tests/check_project.gd: compiles every script, data, architecture and performance rules).
# Problems are sent back to Claude (exit 2) so it fixes them right away. Other files: nothing.
input=$(cat)
if ! printf '%s' "$input" | grep -qE '"file_path" *: *"[^"]*\.gd"'; then
	exit 0
fi
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
output=$("/c/Program Files/Godot/Godot.exe.exe" --headless --path . -s tests/check_project.gd 2>&1)
if [ $? -ne 0 ]; then
	{
		echo "tests/check_project.gd found problems after this edit. Fix them (or, for a deliberate exception to a performance rule, add a '# perf-ok: why' comment):"
		printf '%s\n' "$output" | grep -E "^FAIL|ERROR|problems"
	} >&2
	exit 2
fi
exit 0
