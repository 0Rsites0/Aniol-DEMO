#!/usr/bin/env bash

set -euo pipefail

branch="${1:-main}"
debounce_seconds="${2:-5}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed or not available in PATH."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This folder is not a Git repository."
  exit 1
fi

echo "Watching $repo_root for changes. Auto-pushing to '$branch' after $debounce_seconds seconds of inactivity."
echo "Press Ctrl+C to stop."

last_state="$(git status --porcelain)"
last_change_time="$(date +%s)"
pending_push=0

while true; do
  current_state="$(git status --porcelain)"

  if [[ "$current_state" != "$last_state" ]]; then
    pending_push=1
    last_change_time="$(date +%s)"
    last_state="$current_state"
    echo "Change detected at $(date '+%Y-%m-%d %H:%M:%S')"
  fi

  if [[ "$pending_push" -eq 1 ]]; then
    now="$(date +%s)"
    if (( now - last_change_time >= debounce_seconds )); then
      if [[ -n "$current_state" ]]; then
        echo "Preparing commit and push..."
        git add -A

        if ! git diff --cached --quiet; then
          timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
          git commit -m "Auto update $timestamp"
          git push origin "$branch"
          echo "Push complete at $timestamp"
        fi
      fi

      last_state="$(git status --porcelain)"
      pending_push=0
    fi
  fi

  sleep 1
done
