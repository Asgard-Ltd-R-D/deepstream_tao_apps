#!/usr/bin/env bash
set -euo pipefail

# ── CONFIG ────────────────────────────────────────────────────────────────────
DIR="/home/swish/swish_computer_vision/deepstream_tao_apps"

# Optional: open parent dirs so other users can traverse into your home path.
# Comment these if you DON’T want to open your home.
chmod o+rx /home/swish || true
chmod o+rx /home/swish/swish_computer_vision || true

echo "[1/7] Remove immutable flags (if any)…"
sudo chattr -R -i "$DIR" 2>/dev/null || true

echo "[2/7] Make you the owner (not strictly required for world-writable, but tidy)…"
sudo chown -R "$(id -un):$(id -gn)" "$DIR"

echo "[3/7] Open directory perms for EVERYONE (setgid + rwx) …"
# 2 = setgid so new files inherit the directory's group; 777 = rwx for all
find "$DIR" -type d -print0 | xargs -0 sudo chmod 2777

echo "[4/7] Open file perms for EVERYONE (rw for all; keep +x on executables) …"
# Add rw to all files
find "$DIR" -type f -print0 | xargs -0 sudo chmod a+rw
# Re-add +x to files that were already executable by someone (heuristic: scripts/binaries)
# (If you need stricter detection, use git or 'file' — this is enough for most repos.)
find "$DIR" -type f -perm -u=x -print0 | xargs -0 sudo chmod a+x || true
find "$DIR" -type f -perm -g=x -print0 | xargs -0 sudo chmod a+x || true
find "$DIR" -type f -perm -o=x -print0 | xargs -0 sudo chmod a+x || true

echo "[5/7] Create/prepare ALL engine output folders from configs (world-writable)…"
# Parse model-engine-file paths, mkdir parents, 2777 so anyone can write engines there
grep -R --include='*.txt' --include='*.cfg' -n "model-engine-file" "$DIR" \
  | awk -F '=' '{print $2}' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | xargs -I{} dirname "{}" \
  | sort -u \
  | while read -r p; do
      [ -z "$p" ] && continue
      sudo mkdir -p "$p"
      sudo chmod 2777 "$p"
    done

echo "[6/7] Add default ACLs so NEW files/dirs are also open for everyone…"
# Requires ACL support (most ext4/xfs have it). If not available, this step is skipped.
if command -v setfacl >/dev/null 2>&1; then
  sudo setfacl -R -m u::rwx,g::rwx,o::rwx "$DIR" || true
  # Default ACLs on directories so newly created content inherits world rwx
  find "$DIR" -type d -print0 | xargs -0 sudo setfacl -m d:u::rwx,d:g::rwx,d:o::rwx || true
else
  echo "(!) 'setfacl' not found — skipping ACL defaults (chmod 2777 still applied)."
fi

echo "[7/7] Quick write test to each engine directory (as current user)…"
grep -R --include='*.txt' --include='*.cfg' -n "model-engine-file" "$DIR" \
  | awk -F '=' '{print $2}' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | xargs -I{} dirname "{}" \
  | sort -u \
  | while read -r p; do
      tf="$p/.perm_test_$$.tmp"
      ( echo "ok" > "$tf" ) && echo "✓ writable: $p" || echo "✗ not writable: $p"
      rm -f "$tf" 2>/dev/null || true
    done

echo "Done. Any user should now be able to run DeepStream and write engine files under:"
echo "  $DIR"
