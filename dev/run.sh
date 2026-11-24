#!/usr/bin/env bash
# Try dired.nvim in a fully isolated nvim (own config/data/state dirs via NVIM_APPNAME).
#
#   dev/run.sh              -> opens a fresh throwaway sandbox tree
#   dev/run.sh /some/dir    -> opens that directory (careful: ops are real!)
#   dev/run.sh --keep       -> sandbox is not deleted afterwards
#
# Inside: :DiredReload reloads the plugin code, `-` = dired-jump, <space>d = dired cwd.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keep=0
target=""
for a in "$@"; do
  case "$a" in
    --keep) keep=1 ;;
    *) target="$a" ;;
  esac
done

cleanup=""
if [ -z "$target" ]; then
  target="$("$root/dev/sandbox.sh")"
  [ "$keep" = 1 ] || cleanup="$target"
  echo "sandbox: $target" >&2
fi

export NVIM_APPNAME=dired-dev
cd "$target"
nvim -u "$root/dev/init.lua" -i NONE "$target" || true
[ -n "$cleanup" ] && rm -rf "$cleanup"
exit 0
