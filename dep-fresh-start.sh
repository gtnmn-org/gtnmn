#!/bin/bash
set -e  # stop on errors
trap 'echo; read -r -p "✅ Script finished (or exited early). Press Enter to close..." _ < /dev/tty' EXIT
shopt -s nullglob

# Fail if not exactly one .org file exists
ORG_FILES=(*.org)
if [ ${#ORG_FILES[@]} -ne 1 ]; then
    echo "❌ Expected exactly one .org file, found ${#ORG_FILES[@]}"
    exit 1
fi

ORG_FILE="${ORG_FILES[0]}"
BASENAME=$(basename "$ORG_FILE" .org)

# Handle .rep files (same logic as dep-loy.sh)
REP_FILES=(*.rep)
if [ ${#REP_FILES[@]} -eq 0 ]; then
    REPNAME="$BASENAME"
elif [ ${#REP_FILES[@]} -eq 1 ]; then
    REPNAME=$(basename "${REP_FILES[0]}" .rep)
else
    echo "❌ Expected none or one .rep file, found ${#REP_FILES[@]}"
    exit 1
fi

EXPECTED_URL="git@github.com:${BASENAME}-org/${REPNAME}.git"

# Must be run inside an existing git repo
if [ ! -d .git ]; then
    echo "❌ No .git directory found here — nothing to reset"
    exit 1
fi

# Check current remote
CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")
TARGET_URL="${CURRENT_URL:-$EXPECTED_URL}"

if [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "$EXPECTED_URL" ]]; then
    echo "⚠️ Remote mismatch detected"
    echo "Current:  $CURRENT_URL"
    echo "Expected: $EXPECTED_URL"
    read -p "Use expected remote instead? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        TARGET_URL="$EXPECTED_URL"
    fi
fi

# 🔐 Validate GitHub SSH access
echo "🔐 Checking GitHub SSH access..."
SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
if echo "$SSH_OUTPUT" | grep -q "successfully authenticated"; then
    echo "✅ SSH authentication OK"
else
    echo "❌ SSH authentication failed"
    echo "$SSH_OUTPUT"
    exit 1
fi

# Big scary warning before doing anything destructive
echo "⚠️ This will WIPE all local git history and force-push a single fresh commit to:"
echo "   $TARGET_URL"
echo "   Only files in THIS folder are kept. If the remote has files you don't have locally"
echo "   (e.g. an updated CNAME), run dep-pull.sh first or they will be lost."
echo "   Anyone else with a clone of this repo (e.g. a colleague) will need to re-clone afterwards —"
echo "   pulling into their existing clone will fail or create a mess."
read -p "Type WIPE in capitals to confirm: " CONFIRM
if [[ "$CONFIRM" != "WIPE" ]]; then
    echo "❌ Aborting — no changes made"
    exit 1
fi

# Move old .git aside rather than deleting it outright, so there's a way back
BACKUP_DIR=".git.bak-$(date +%Y%m%d-%H%M%S)"
mv .git "$BACKUP_DIR"
echo "📦 Old history backed up to $BACKUP_DIR — delete it manually once you're happy with the result"

git init -b main
echo ".git.bak-*" >> .git/info/exclude
git remote add origin "$TARGET_URL"
git add .
git commit -m "Fresh start"

echo "🔍 Files about to be pushed (check your .sh/.txt/.log files are NOT in this list):"
git ls-files

read -p "Force-push this fresh history to $TARGET_URL? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ Aborting before push — local repo is re-initialised but nothing was pushed yet"
    echo "   Run 'git push -f origin main' manually when ready"
    exit 1
fi

git push -f origin main
echo "✅ Fresh history pushed."
echo "ℹ️ Tell any other clones of this repo (e.g. your Windows colleague) to delete their local copy and re-clone."
