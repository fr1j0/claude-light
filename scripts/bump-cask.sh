#!/usr/bin/env bash
set -euo pipefail

# Bump the Homebrew cask(s) to a released version. Downloads the release zip,
# computes and VERIFIES its sha256 against the published checksum, then rewrites
# `version` + `sha256` in the source cask (and the tap cask, if --tap is given).
#
# It only edits files — it does not commit, push, or merge. That's deliberate:
# you review and open/merge the PRs (only the owner merges). Phase 1 of #26 —
# kills the hand-editing / sha-copying / style-fixing done manually each release.
#
#   scripts/bump-cask.sh 0.5.0
#   scripts/bump-cask.sh 0.5.0 --tap ~/src/homebrew-claude-light
#
# Requires: gh (authenticated), shasum, python3. Runs after the release exists.

REPO="fr1j0/claude-light"

usage() { echo "usage: $0 <version> [--tap <tap-checkout-dir>]" >&2; exit 2; }

VERSION="${1:-}"; [ -n "$VERSION" ] || usage
shift || true
TAP_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tap) TAP_DIR="${2:-}"; [ -n "$TAP_DIR" ] || usage; shift 2 ;;
    *) usage ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_CASK="$ROOT/Casks/claude-light.rb"
[ -f "$SRC_CASK" ] || { echo "source cask not found: $SRC_CASK" >&2; exit 1; }

TAG="v$VERSION"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "→ downloading $REPO release $TAG ..."
gh release download "$TAG" --repo "$REPO" --pattern 'claude-light.zip' --dir "$tmp"
gh release download "$TAG" --repo "$REPO" --pattern 'claude-light.zip.sha256' --dir "$tmp"

published="$(awk '{print $1}' "$tmp/claude-light.zip.sha256")"
actual="$(shasum -a 256 "$tmp/claude-light.zip" | awk '{print $1}')"
if [ "$published" != "$actual" ]; then
  echo "✗ sha256 mismatch: published=$published actual=$actual" >&2
  exit 1
fi
echo "✓ sha256 verified: $actual"

# Rewrite the `version` and `sha256` string literals in a cask, in place.
bump() {
  local f="$1"
  [ -f "$f" ] || { echo "cask not found: $f" >&2; exit 1; }
  python3 - "$f" "$VERSION" "$actual" <<'PY'
import re, sys
path, version, sha = sys.argv[1:4]
s = open(path).read()
s, nv = re.subn(r'(\n[ \t]*version[ \t]+)"[^"]*"', r'\g<1>"%s"' % version, s, count=1)
s, ns = re.subn(r'(\n[ \t]*sha256[ \t]+)"[^"]*"', r'\g<1>"%s"' % sha, s, count=1)
if nv != 1 or ns != 1:
    sys.exit("could not rewrite version/sha256 in %s (version hits=%d sha256 hits=%d)" % (path, nv, ns))
open(path, "w").write(s)
PY
  echo "✓ bumped ${f#"$ROOT"/}"
}

bump "$SRC_CASK"
[ -n "$TAP_DIR" ] && bump "$TAP_DIR/Casks/claude-light.rb"

# Optional lint if brew is available (the tap's CI enforces this).
if command -v brew >/dev/null 2>&1; then
  if brew style "$SRC_CASK" >/dev/null 2>&1; then
    echo "✓ brew style clean"
  else
    echo "⚠ brew style reported issues — run: brew style $SRC_CASK"
  fi
fi

echo
echo "Done — files edited (nothing committed). Next:"
echo "  cd \"$ROOT\" && git checkout -b chore/cask-$VERSION && git commit -am \"chore: bump cask to $VERSION\" && git push -u origin chore/cask-$VERSION"
echo "  gh pr create --base main --title \"chore: bump cask to $VERSION\""
[ -n "$TAP_DIR" ] && echo "  # repeat the branch/commit/PR in the tap: $TAP_DIR"
