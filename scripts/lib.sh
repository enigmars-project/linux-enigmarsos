# Shared helpers for linux-enigmarsos scripts.
# shellcheck shell=bash

if [[ -n "${_ENIGMARSOS_LIB_LOADED:-}" ]]; then
  return 0
fi
_ENIGMARSOS_LIB_LOADED=1

set -euo pipefail

repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "$here"
}

REPO_ROOT="$(repo_root)"
PKGBUILD_PATH="$REPO_ROOT/PKGBUILD"
BORE_META="$REPO_ROOT/patches/bore.meta"
BORE_PATCH="$REPO_ROOT/patches/bore.patch"
ARCH_CONFIG="$REPO_ROOT/config/config.x86_64"
ENIGMARS_CONFIG="$REPO_ROOT/config/enigmarsos.config"

die() {
  printf '==> ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

warn() {
  printf '==> WARNING: %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

pkgbuild_var() {
  local name="$1"
  python3 - "$PKGBUILD_PATH" "$name" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
# Strip comments at end of line only for simple assignments
pat = re.compile(rf'^{re.escape(name)}=([^\n]+)$', re.M)
m = pat.search(text)
if not m:
    sys.exit(1)
val = m.group(1).strip()
if (val.startswith("'") and val.endswith("'")) or (val.startswith('"') and val.endswith('"')):
    val = val[1:-1]
print(val)
PY
}

load_bore_meta() {
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=../patches/bore.meta
  source "$BORE_META"
  set +a
}

package_version() {
  printf '%s-%s\n' "$(pkgbuild_var pkgver)" "$(pkgbuild_var pkgrel)"
}

upstream_kernel() {
  local pkgver
  pkgver="$(pkgbuild_var pkgver)"
  printf '%s\n' "${pkgver%.*}"
}

expected_kernel_release() {
  # EXTRAVERSION is cleared (no -arch1). localversion files add
  # -$pkgrel and -enigmarsos → e.g. 7.1.8-2-enigmarsos
  local pkgver pkgrel
  pkgver="$(pkgbuild_var pkgver)"
  pkgrel="$(pkgbuild_var pkgrel)"
  printf '%s-%s-enigmarsos\n' "${pkgver%.*}" "$pkgrel"
}

find_built_packages() {
  local search_dirs=()
  [[ -n "${PKGDEST:-}" ]] && search_dirs+=("$PKGDEST")
  search_dirs+=("$REPO_ROOT/out" "$REPO_ROOT" "$PWD")
  local dir
  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    shopt -s nullglob
    local found=("$dir"/linux-enigmarsos-*.pkg.tar.zst)
    shopt -u nullglob
    if ((${#found[@]})); then
      printf '%s\n' "${found[@]}"
      return 0
    fi
  done
  return 1
}

require_repo_files() {
  local f
  for f in \
    "$PKGBUILD_PATH" \
    "$BORE_PATCH" \
    "$BORE_META" \
    "$ARCH_CONFIG" \
    "$ENIGMARS_CONFIG"
  do
    [[ -f "$f" ]] || die "required file missing: $f"
  done
}

verify_bore_checksum() {
  load_bore_meta
  local got
  got="$(sha256sum "$BORE_PATCH" | awk '{print $1}')"
  [[ "$got" == "$BORE_SHA256" ]] \
    || die "BORE patch SHA-256 mismatch: got $got expected $BORE_SHA256"
}

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

arch_linux_json() {
  curl -fsSL --retry 3 --retry-delay 2 \
    "https://archlinux.org/packages/core/x86_64/linux/json/"
}

# Print "pkgver pkgrel" of the current official Arch linux package.
current_arch_linux() {
  python3 - <<'PY'
import json, sys, urllib.request
url = "https://archlinux.org/packages/core/x86_64/linux/json/"
with urllib.request.urlopen(url, timeout=30) as resp:
    data = json.load(resp)
print(data["pkgver"], data["pkgrel"])
PY
}

# Extract members of a pacman package matching a path pattern.
# libarchive bsdtar does not support GNU tar --wildcards, so match
# against a precomputed member list instead.
#   $1 = package file, $2 = member list file, $3 = dest dir, $4 = pattern
extract_matching() {
  local pkg="$1" list="$2" dest="$3" pattern="$4" f
  mapfile -t hits < <(grep -E "(^|/)${pattern}$" "$list" || true)
  ((${#hits[@]})) || return 0
  for f in "${hits[@]}"; do
    [[ -n "$f" ]] || continue
    bsdtar -C "$dest" -xf "$pkg" "$f"
  done
}
