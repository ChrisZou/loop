#!/bin/bash
# Exercises loop review --detach / loop wait without LaunchServices.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$ROOT/bin/loop"
STATE="$(mktemp -d "${TMPDIR:-/tmp}/loop-cli-test.XXXXXX")"
trap 'rm -rf "$STATE"' EXIT
export XDG_STATE_HOME="$STATE/xdg"
export HOME="$STATE/home"
mkdir -p "$HOME" "$XDG_STATE_HOME"

fake_open_submit() {
  # argv after -- : plan out
  local plan="$2" out="$3"
  sleep 1
  printf 'feedback-ok\n' > "$out"
}
fake_open_close() {
  sleep 1
  : > "$3"
}

export -f fake_open_submit fake_open_close

# --- detach + wait success ---
export LOOP_OPEN_CMD='fake_open_submit'
plan="$STATE/plan.md"
printf '# hello\n' > "$plan"
json="$("$LOOP" review --detach "$plan")"
id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$json")"
out="$("$LOOP" wait "$id" --timeout 10)"
[[ "$out" == "feedback-ok" ]] || { echo "fail: expected feedback-ok got: $out" >&2; exit 1; }

# --- detach + wait closed ---
export LOOP_OPEN_CMD='fake_open_close'
json="$("$LOOP" review --detach "$plan")"
id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$json")"
set +e
err="$("$LOOP" wait "$id" --timeout 10 2>&1 >/dev/null)"
code=$?
set -e
[[ $code -eq 1 ]] || { echo "fail: expected exit 1 got $code ($err)" >&2; exit 1; }
[[ "$err" == *未提交* ]] || { echo "fail: stderr: $err" >&2; exit 1; }

# --- wait timeout ---
export LOOP_OPEN_CMD='bash -c "sleep 30"'
# can't use LOOP_OPEN_CMD with bash -c easily for long sleep — use a no-op that never writes
fake_open_hang() { sleep 30; }
export -f fake_open_hang
export LOOP_OPEN_CMD='fake_open_hang'
json="$("$LOOP" review --detach "$plan")"
id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$json")"
set +e
err="$("$LOOP" wait "$id" --timeout 2 2>&1 >/dev/null)"
code=$?
set -e
[[ $code -eq 2 ]] || { echo "fail: expected exit 2 got $code ($err)" >&2; exit 1; }

# --- stdin detach ---
export LOOP_OPEN_CMD='fake_open_submit'
json="$(printf '# from stdin\n' | "$LOOP" review --detach -)"
id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$json")"
out="$("$LOOP" wait "$id" --timeout 10)"
[[ "$out" == "feedback-ok" ]] || { echo "fail stdin: $out" >&2; exit 1; }

echo "loop-cli.test.sh: ok"
