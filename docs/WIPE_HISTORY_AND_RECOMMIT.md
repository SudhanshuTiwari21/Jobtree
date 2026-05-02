# Wipe Git History and Recommit (e.g. After Pushing a Secret)

Use this if you accidentally pushed a `.pem` or other secret and want to **remove it from all history** and start with a single clean commit.

---

## 1. Rotate the exposed key (important)

The old key (e.g. `JobTree.pem`) is compromised because it was in git history. Even after you wipe history, anyone who cloned or pulled before can still see it.

1. **EC2:** In AWS Console → EC2 → Key Pairs (or when viewing the instance), create a **new** key pair and download it.
2. **Attach the new key** to your instance (e.g. add the new public key to `~/.ssh/authorized_keys` on the server, or replace the key pair if your provider allows).
3. **Stop using the old `.pem`**; use the new key for SSH. Delete the old `.pem` from your machine once you’ve switched.
4. Keep `*.pem` in `.gitignore` (already there) so it’s never committed again.

---

## 2. Wipe history and create one fresh commit

Run from the **repository root** (and make sure you have no uncommitted changes you care about, or stash them).

### Option A: Script (asks for confirmation)

```bash
./scripts/wipe_history_fresh_commit.sh
# Or if your default branch is master:
./scripts/wipe_history_fresh_commit.sh master
```

Then force-push (see step 3 below).

### Option B: Manual commands

```bash
# Use your default branch name (e.g. main or master)
BRANCH=main

# Create orphan branch (no history)
git checkout --orphan new_root

# Add all files; .gitignore excludes *.pem
git add -A
git commit -m "Initial commit (history reset)"

# Replace old branch
git branch -D $BRANCH
git branch -m $BRANCH
git gc --aggressive --prune=all
```

---

## 3. Force-push to remote

This **overwrites** the remote branch history. Anyone who has the old history should re-clone or run `git fetch origin && git reset --hard origin/main` (or your branch name).

```bash
git push --force origin main
```

If the remote is on another default branch (e.g. `master`), use that name instead of `main`.

---

## 4. Afterward

- Confirm the repo no longer contains the PEM in history (e.g. clone into a temp dir and run `git log -p` or search for the key).
- Use the **new** key for EC2 and any other services that had the old key.
- Avoid committing secrets; use env vars and `.env` (with `.env` in `.gitignore`) for local config.
