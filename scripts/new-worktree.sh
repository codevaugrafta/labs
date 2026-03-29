#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <app> <task> [base]"
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
common_git_dir=$(git rev-parse --git-common-dir)
if [[ "$common_git_dir" != /* ]]; then
  common_git_dir=$(cd "${repo_root}/${common_git_dir}" && pwd)
fi
workspace_root=$(cd "${common_git_dir}/.." && pwd)
app_raw=$1
task_raw=$2
base_ref=${3:-main}
agent_prefix=${CODEX_AGENT_PREFIX:-codex}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

app=$(slugify "$app_raw")
task=$(slugify "$task_raw")

if [[ -z "$app" || -z "$task" ]]; then
  echo "App and task must contain at least one letter or number."
  exit 1
fi

branch="${agent_prefix}/${app}-${task}"
worktree_path="${workspace_root}/.claude/worktrees/${app}/${task}"

mkdir -p "$(dirname "$worktree_path")"

if [[ -d "$worktree_path" ]]; then
  echo "Worktree already exists at $worktree_path"
  exit 0
fi

if git show-ref --verify --quiet "refs/heads/${branch}"; then
  git worktree add "$worktree_path" "$branch"
else
  git worktree add -b "$branch" "$worktree_path" "$base_ref"
fi

worktree_git_dir=$(git -C "$worktree_path" rev-parse --git-dir)
if [[ "$worktree_git_dir" != /* ]]; then
  worktree_git_dir=$(cd "${worktree_path}/${worktree_git_dir}" && pwd)
fi
exclude_file="${worktree_git_dir}/info/exclude"
mkdir -p "$(dirname "$exclude_file")"
touch "$exclude_file"
git -C "$worktree_path" config --worktree core.excludesfile "$exclude_file"
if ! grep -qxF 'SESSION.md' "$exclude_file"; then
  printf '\nSESSION.md\n' >> "$exclude_file"
fi

verify_commands() {
  case "$app" in
    leo)
      echo "cd Leo && swift test && ./build-app.sh && ./scripts/run-ux-tests.sh && ./scripts/ui-smoke.sh"
      ;;
    tiempo)
      echo "cd Tiempo && swift test && ./build-app.sh"
      ;;
    adhan)
      echo "cd Adhan && swift test && ./build-app.sh"
      ;;
    love)
      echo "cd Love && swift test && ./build-app.sh"
      ;;
    voicetutor)
      echo "cd VoiceTutor && swift test && ./build-app.sh"
      ;;
    pomodoro)
      echo "cd pomodoro && npm run verify"
      ;;
    focus-node)
      echo "cd focus-node && npm run verify"
      ;;
    syncreader)
      echo "cd syncreader && run the closest project-local npm checks"
      ;;
    *)
      echo "document the app-local verification commands here"
      ;;
  esac
}

cat > "${worktree_path}/SESSION.md" <<EOF
# Session

- Goal: ${task_raw}
- Branch: ${branch}
- Base: ${base_ref}
- Open issues:
  - Fill in what is currently blocked or risky.
- Verify:
  - $(verify_commands)
EOF

echo "Created ${branch}"
echo "Worktree: ${worktree_path}"
echo "Session note: ${worktree_path}/SESSION.md"
