#!/usr/bin/env bash
# Create a disposable directory tree to play with. Prints its path.
set -euo pipefail
dir="${1:-$(mktemp -d -t dired-sandbox.XXXXXX)}"
mkdir -p "$dir"/{src/lib,docs,empty,"dir with spaces"}
cd "$dir"
printf 'hello\n' > README.md
printf 'int main(void){return 0;}\n' > src/main.c
printf 'void f(void);\n' > src/lib/util.h
printf '#!/bin/sh\necho hi\n' > run.sh && chmod +x run.sh
printf 'notes\nTODO fix\n' > docs/notes.txt
printf 'one\n' > docs/a.txt
printf 'two\n' > docs/b.txt
printf 'old\n' > config.json~
printf 'x\n' > '#scratch#'
printf 'v1\n' > data.~1~; printf 'v2\n' > data.~2~; printf 'v3\n' > data.~3~; printf 'v4\n' > data.~4~
printf 'space\n' > 'file with spaces.txt'
printf 'logging\n' > build.log
printf 'UPPER\n' > SHOUT.TXT
ln -sf README.md link-to-readme
ln -sfn src link-to-src
echo "$dir"
