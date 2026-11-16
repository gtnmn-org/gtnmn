#!/bin/bash
set -e  # stop on errors
# Skip the "Press Enter" prompt when called from dep-loy.sh (it has its own)
if [[ -z "$DEP_CHILD" ]]; then
    trap 'echo; read -r -p "✅ Script finished (or exited early). Press Enter to close..." _ < /dev/tty' EXIT
fi
shopt -s nullglob

# Fail if not exactly one .org file exists
ORG_FILES=(*.org)
if [ ${#ORG_FILES[@]} -ne 1 ]; then
    echo "❌ Expected exactly one .org file, found ${#ORG_FILES[@]}"
    exit 1
fi

# Extract organisation file
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

# Check current remote
CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "$EXPECTED_URL" ]]; then
    echo "⚠️ Remote mismatch detected"
    echo "Current:  $CURRENT_URL"
    echo "Expected: $EXPECTED_URL"
    read -p "Update remote to expected? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        git remote set-url origin "$EXPECTED_URL"
    else
        echo "❌ Aborting to avoid pulling from wrong repo"
        exit 1
    fi
else
    git remote set-url origin "$EXPECTED_URL"
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

# Warn if there are uncommitted local changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️ You have uncommitted local changes"
    read -p "Continue with pull anyway? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "❌ Aborting — commit or stash your changes first"
        exit 1
    fi
fi

# Fetch remote state without merging
echo "🔍 Fetching remote..."
git fetch origin main

# Check for divergence
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
BASE=$(git merge-base HEAD origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "✅ Already up to date"
    exit 0
elif [ "$LOCAL" = "$BASE" ]; then
    # Local is behind — simple fast-forward
    echo "⬇️ Local is behind remote — fast-forward pulling..."
    git merge --ff-only origin/main
    echo "✅ Pull complete"
elif [ "$REMOTE" = "$BASE" ]; then
    # Remote is behind local
    echo "⚠️ Local is ahead of remote — nothing to pull"
    echo "   You may need to run the push script instead"
    exit 0
else
    # Genuinely diverged
    echo "⚠️ Branches have diverged"
    echo "   Local:  $(git log --oneline -1 HEAD)"
    echo "   Remote: $(git log --oneline -1 origin/main)"
    echo ""
    echo "How do you want to resolve this?"
    echo "  1) Merge   — combine both histories (creates a merge commit)"
    echo "  2) Rebase  — replay local commits on top of remote"
    echo "  3) Reset   — discard local commits, take remote version"
    echo "  4) Abort   — do nothing"
    read -p "Choose (1/2/3/4): " CHOICE
    case "$CHOICE" in
        1)
            echo "🔀 Merging..."
            git merge origin/main
            echo "✅ Merge complete"
            ;;
        2)
            echo "🔁 Rebasing..."
            STASHED=0
            if ! git diff --quiet || ! git diff --cached --quiet; then
                git stash push -m "dep-pull auto-stash"
                STASHED=1
            fi
            if ! git rebase origin/main; then
                echo "❌ Rebase hit conflicts. Resolve them, then run: git rebase --continue"
                [[ $STASHED -eq 1 ]] && echo "   After that, run: git stash pop"
                exit 1
            fi
            if [[ $STASHED -eq 1 ]]; then
                git stash pop || echo "⚠️ Stash pop hit conflicts. Resolve them (your stash is kept)"
            fi
            echo "✅ Rebase complete"
            ;;
        3)
            echo "⚠️ This will permanently discard your local commits AND any uncommitted changes"
            read -p "Are you sure? (y/N): " CONFIRM
            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                git reset --hard origin/main
                echo "✅ Reset to remote"
            else
                echo "❌ Aborting"
                exit 1
            fi
            ;;
        *)
            echo "❌ Aborting — no changes made"
            exit 1
            ;;
    esac
fi
