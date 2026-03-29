#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

echo "Branch: $(git branch --show-current)"
echo
echo "Worktrees:"
git worktree list
echo
echo "Grouped status:"

status_output=$(git status --short)
if [[ -z "$status_output" ]]; then
  echo "  clean"
  exit 0
fi

printf '%s\n' "$status_output" | while IFS= read -r line; do
  path=${line#?? }
  path=${path##* -> }
  top=${path%%/*}
  if [[ "$path" != */* ]]; then
    top="(root)"
  fi
  printf '%s\t%s\n' "$top" "$line"
done | sort | awk -F '\t' '
  {
    count[$1]++
    lines[$1] = lines[$1] "  " $2 "\n"
  }
  END {
    for (group in count) {
      printf "- %s (%d)\n%s", group, count[group], lines[group]
    }
  }
'
