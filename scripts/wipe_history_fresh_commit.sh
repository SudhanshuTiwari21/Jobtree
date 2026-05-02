#!/usr/bin/env bash
# Wipes full git history and creates a single fresh commit (e.g. after accidentally pushing secrets).
# Run from repo root. Remote will need force-push after this.
set -e

cd "$(dirname "$0")/.."

if [[ -n $(git status --porcelain) ]]; then
  echo "You have uncommitted changes. Commit or stash them first."
  exit 1
fi


BRANCH="${1:-main}"
# Detect default branch if not main
if ! git show-ref --verify --quiet refs/heads/"$BRANCH"; then
  BRANCH="master"
fi

echo "Current branch: $(git branch --show-current)"
echo "This will:"
echo "  1. Create a new orphan branch with no history"
echo "  2. Add all current files (respecting .gitignore; *.pem excluded)"
echo "  3. Create one initial commit"
echo "  4. Replace $BRANCH with this (destructive)"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[yY]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Orphan branch with no history
git checkout --orphan new_root
git add -A
git commit -m "Initial commit (history reset)"

# Replace target branch
git branch -D "$BRANCH" 2>/dev/null || true
git branch -m "$BRANCH"
git gc --aggressive --prune=all

echo ""
echo "Done. Local history is reset. Next:"
echo "  1. Rotate any exposed secrets (e.g. generate new .pem on EC2 and revoke old key)."
echo "  2. Force-push to remote (overwrites remote history):"
echo "     git push --force origin $BRANCH"
echo ""
echo "Anyone who has cloned the repo should re-clone or run: git fetch origin && git reset --hard origin/$BRANCH"
