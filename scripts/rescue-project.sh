#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app> <branch>"
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
common_git_dir=$(git rev-parse --git-common-dir)
if [[ "$common_git_dir" != /* ]]; then
  common_git_dir=$(cd "${repo_root}/${common_git_dir}" && pwd)
fi
workspace_root=$(cd "${common_git_dir}/.." && pwd)
source_root=$repo_root
app=$1
branch=$2
task_name=${branch##*/}
worktree_path="${workspace_root}/.claude/worktrees/${app}/${task_name}"

if [[ ! -d "${source_root}/${app}" ]]; then
  echo "Missing app directory: ${source_root}/${app}"
  exit 1
fi

mkdir -p "$(dirname "$worktree_path")"

if git show-ref --verify --quiet "refs/heads/${branch}"; then
  if [[ ! -d "$worktree_path" ]]; then
    git worktree add "$worktree_path" "$branch"
  fi
else
  git worktree add -b "$branch" "$worktree_path" HEAD
fi

rsync -a --delete \
  --exclude build \
  --exclude .build \
  --exclude .swiftpm \
  --exclude .DS_Store \
  "${source_root}/${app}/" "${worktree_path}/${app}/"

git -C "$worktree_path" add -A -- "$app"

if git -C "$worktree_path" diff --cached --quiet; then
  echo "No staged changes for ${app}"
  exit 0
fi

today=$(date +%F)
lower_app=$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')
git -C "$worktree_path" commit -m "chore(rescue): snapshot ${lower_app} state on ${today}"

echo "Rescued ${app} into ${branch}"
echo "Worktree: ${worktree_path}"
