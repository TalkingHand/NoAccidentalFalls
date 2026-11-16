#!/bin/bash
# `pzt live` plus real keyboard input: starts tests/tools/keys.ps1 next to the test game. The game
# window comes to the front and gets W/A/S/D/Shift/Alt/E presses during the movement scenarios.
# The game stays open: `pzt stop` at the end.
cd "$(dirname "$0")/../.." || exit 1
ENV_WIN=$(cygpath -w "$PWD/pzt-env")
powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tests/tools/keys.ps1)" -EnvDir "$ENV_WIN" > keys.log 2>&1 &
KEYS=$!
bash ../PZTestHarness/pzt live "$@"
RESULT=$?
kill $KEYS 2>/dev/null
echo "--- keys ---"
cat keys.log
exit $RESULT
