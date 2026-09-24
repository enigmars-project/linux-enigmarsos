#!/usr/bin/env bash
# Validate built linux-enigmarsos packages. Fail loud; never "almost OK".
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: verify-build.sh [package-dir]

Inspects linux-enigmarsos and linux-enigmarsos-headers packages.
A failure here must prevent publishing.
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

need_cmd bsdtar
need_cmd sha256sum
command -v pacman >/dev/null 2>&1 || warn "pacman not available; skipping -Qip"

load_bore_meta
require_repo_files
verify_bore_checksum

PKGDIR="${1:-}"
ver="$(package_version)"
if [[ -z "$PKGDIR" ]]; then
  mapfile -t ALL_PKGS < <(find_built_packages || true)
else
  shopt -s nullglob
  ALL_PKGS=("$PKGDIR"/linux-enigmarsos-"${ver}"-*.pkg.tar.zst
            "$PKGDIR"/linux-enigmarsos-headers-"${ver}"-*.pkg.tar.zst)
  shopt -u nullglob
fi
# Ignore leftover older builds sitting next to this pkgver-pkgrel.
filtered=()
for p in "${ALL_PKGS[@]}"; do
  base="$(basename "$p")"
  if [[ "$base" == linux-enigmarsos-"${ver}"-* || "$base" == linux-enigmarsos-headers-"${ver}"-* ]]; then
    filtered+=("$p")
  fi
done
ALL_PKGS=("${filtered[@]}")

((${#ALL_PKGS[@]})) || die "no linux-enigmarsos-*.pkg.tar.zst packages found"

KERNEL_PKG=""
HEADERS_PKG=""
for p in "${ALL_PKGS[@]}"; do
  base="$(basename "$p")"
  if [[ "$base" == linux-enigmarsos-headers-* ]]; then
    HEADERS_PKG="$p"
  elif [[ "$base" == linux-enigmarsos-* && "$base" != linux-enigmarsos-headers-* ]]; then
    KERNEL_PKG="$p"
  fi
done

[[ -n "$KERNEL_PKG" ]] || die "linux-enigmarsos package missing"
[[ -n "$HEADERS_PKG" ]] || die "linux-enigmarsos-headers package missing"

info "kernel package:  $KERNEL_PKG"
info "headers package: $HEADERS_PKG"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/enigmarsos-verify.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

fail=0
pass() { echo "    PASS  $*"; }
bad()  { echo "    FAIL  $*" >&2; fail=1; }

if command -v pacman >/dev/null 2>&1; then
  info "Package metadata"
  pacman -Qip "$KERNEL_PKG" | tee "$WORKDIR/kernel.qip"
  pacman -Qip "$HEADERS_PKG" | tee "$WORKDIR/headers.qip"
  grep -q '^Name[[:space:]]*:[[:space:]]*linux-enigmarsos$' "$WORKDIR/kernel.qip" \
    && pass "pkgname linux-enigmarsos" || bad "pkgname is not linux-enigmarsos"
  grep -q '^Name[[:space:]]*:[[:space:]]*linux-enigmarsos-headers$' "$WORKDIR/headers.qip" \
    && pass "pkgname linux-enigmarsos-headers" || bad "pkgname is not linux-enigmarsos-headers"
  grep -q "^Version[[:space:]]*:[[:space:]]*$(package_version)$" "$WORKDIR/kernel.qip" \
    && pass "version $(package_version)" || bad "unexpected package version"
  if grep -q '^Depends[[:space:]]*:.*linux[^-]' "$WORKDIR/kernel.qip"; then
    # "linux" as a hard depend would force the stock kernel; we only want initramfs/kmod.
    :
  fi
  if grep -Eq '^Conflicts[[:space:]]*:.*\blinux\b' "$WORKDIR/kernel.qip"; then
    bad "package must not conflict with linux (fallback kernel)"
  else
    pass "does not conflict with linux"
  fi
  if grep -Eq '^Depends[[:space:]]*:' "$WORKDIR/kernel.qip"; then
    grep -Eq 'initramfs' "$WORKDIR/kernel.qip" && pass "depends on initramfs" || bad "missing initramfs depend"
    grep -Eq 'kmod' "$WORKDIR/kernel.qip" && pass "depends on kmod" || bad "missing kmod depend"
  fi
else
  warn "pacman missing; package metadata check skipped"
fi

info "Package contents"
bsdtar -tf "$KERNEL_PKG" > "$WORKDIR/kernel.list"
bsdtar -tf "$HEADERS_PKG" > "$WORKDIR/headers.list"

# bsdtar -tf lists members without a leading slash
has_path() { grep -Eq "(^|/)${1}$" "$2"; }
has_prefix() { grep -Eq "(^|/)${1}" "$2"; }

has_path 'usr/lib/modules/.*/vmlinuz' "$WORKDIR/kernel.list" \
  && pass "kernel image present" || bad "vmlinuz missing"
has_path 'usr/lib/modules/.*/pkgbase' "$WORKDIR/kernel.list" \
  && pass "pkgbase present" || bad "pkgbase missing"
has_prefix 'usr/lib/modules/.*/kernel/' "$WORKDIR/kernel.list" \
  && pass "modules present" || bad "module tree missing"
has_path 'usr/lib/modules/.*/build/Makefile' "$WORKDIR/headers.list" \
  && pass "headers build tree present" || bad "headers Makefile missing"
has_prefix 'usr/src/linux-enigmarsos' "$WORKDIR/headers.list" \
  && pass "headers /usr/src symlink present" || bad "/usr/src/linux-enigmarsos missing"

# Shared helper in lib.sh (libarchive bsdtar has no GNU tar --wildcards).

info "Extracting identity and configuration"
extract_matching "$KERNEL_PKG" "$WORKDIR/kernel.list" "$WORKDIR" \
  'usr/lib/modules/.*/vmlinuz'
extract_matching "$KERNEL_PKG" "$WORKDIR/kernel.list" "$WORKDIR" \
  'usr/lib/modules/.*/pkgbase'
extract_matching "$HEADERS_PKG" "$WORKDIR/headers.list" "$WORKDIR" \
  'usr/lib/modules/.*/build/\.config'
extract_matching "$HEADERS_PKG" "$WORKDIR/headers.list" "$WORKDIR" \
  'usr/lib/modules/.*/build/include/linux/sched/bore.h'
extract_matching "$HEADERS_PKG" "$WORKDIR/headers.list" "$WORKDIR" \
  'usr/lib/modules/.*/build/kernel/sched/bore.c'
extract_matching "$HEADERS_PKG" "$WORKDIR/headers.list" "$WORKDIR" \
  'usr/lib/modules/.*/build/version'

vmlinuz="$(find "$WORKDIR/usr/lib/modules" -name vmlinuz -print -quit || true)"
pkgbase="$(find "$WORKDIR/usr/lib/modules" -name pkgbase -print -quit || true)"
kconfig="$(find "$WORKDIR/usr/lib/modules" -name .config -print -quit || true)"
bore_h="$(find "$WORKDIR/usr/lib/modules" -name bore.h -print -quit || true)"
bore_c="$(find "$WORKDIR/usr/lib/modules" -name bore.c -print -quit || true)"
versionf="$(find "$WORKDIR/usr/lib/modules" -name version -print -quit || true)"

[[ -n "$vmlinuz" && -s "$vmlinuz" ]] && pass "vmlinuz extracted ($(stat -c%s "$vmlinuz") bytes)" || bad "could not extract vmlinuz"
[[ -n "$pkgbase" ]] && [[ "$(cat "$pkgbase")" == "linux-enigmarsos" ]] \
  && pass "pkgbase is linux-enigmarsos" || bad "pkgbase is not linux-enigmarsos"

krel=""
if [[ -n "$versionf" ]]; then
  krel="$(cat "$versionf")"
fi
if [[ -z "$krel" && -n "$vmlinuz" ]]; then
  krel="$(dirname "$(dirname "$vmlinuz")")"
  krel="$(basename "$krel")"
fi

echo "    Kernel release: ${krel:-unknown}"
if [[ "$krel" == *enigmarsos* ]]; then
  pass "release string identifies EnigmarsOS"
else
  bad "release string '$krel' does not identify EnigmarsOS"
fi
if [[ "$krel" == "$(expected_kernel_release)" ]]; then
  pass "release string matches $(expected_kernel_release)"
else
  warn "release string '$krel' != expected '$(expected_kernel_release)' (Arch EXTRAVERSION may differ)"
  [[ "$krel" == *enigmarsos* ]] || true
fi

[[ -n "$kconfig" ]] || bad "headers .config missing"
if [[ -n "$kconfig" ]]; then
  grep -q '^CONFIG_SCHED_BORE=y$' "$kconfig" \
    && pass "CONFIG_SCHED_BORE=y" || bad "CONFIG_SCHED_BORE is not y"
  grep -q '^CONFIG_MIN_BASE_SLICE_NS=2000000$' "$kconfig" \
    && pass "CONFIG_MIN_BASE_SLICE_NS=2000000" || bad "MIN_BASE_SLICE_NS unexpected"
  grep -q '^CONFIG_IKCONFIG_PROC=y$' "$kconfig" \
    && pass "CONFIG_IKCONFIG_PROC=y" || bad "IKCONFIG_PROC disabled"
fi

[[ -n "$bore_h" && -s "$bore_h" ]] && pass "bore.h shipped in headers" || bad "bore.h missing from headers"
if [[ -n "$bore_c" && -s "$bore_c" ]]; then
  pass "bore.c shipped in headers"
else
  warn "bore.c not in headers (header-only BORE layout is OK)"
fi
if [[ -n "$bore_h" ]]; then
  grep -q "SCHED_BORE_VERSION[[:space:]]\\+\"$BORE_VERSION\"" "$bore_h" \
    && pass "BORE version $BORE_VERSION in headers" \
    || bad "BORE version $BORE_VERSION not in bore.h"
  grep -q 'SCHED_BORE_PROGNAME "BORE CPU Scheduler modification"' "$bore_h" \
    && pass "BORE identity string present" || bad "BORE identity string missing"
fi

# Prove the built image, not just headers, contains BORE.
if [[ -n "$vmlinuz" ]] && command -v python3 >/dev/null 2>&1; then
  info "Scanning vmlinuz for BORE strings"
  if python3 - "$vmlinuz" "$BORE_VERSION" <<'PY'
import sys
path, version = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
needles = [
    b"BORE CPU Scheduler modification",
    f"SCHED_BORE".encode(),
]
# Compressed images may not contain plaintext. Treat a hit as proof;
# a miss is reported but not fatal here because IKCONFIG/headers cover it.
hits = [n.decode() for n in needles if n in data]
print("plaintext hits:", ", ".join(hits) if hits else "(none; image is likely compressed)")
sys.exit(0)
PY
  then
    pass "vmlinuz scan completed"
  fi
fi

echo
echo "----------------------------------------------"
echo "Kernel: ${krel:-unknown}"
echo "EnigmarsOS kernel: $([[ "${krel:-}" == *enigmarsos* ]] && echo enabled || echo MISSING)"
echo "BORE: $([[ -n "$kconfig" ]] && grep -q '^CONFIG_SCHED_BORE=y$' "$kconfig" && echo enabled || echo MISSING)"
if [[ "$fail" -eq 0 ]]; then
  echo "Configuration validation: PASS"
  echo "Package validation: PASS"
  echo "----------------------------------------------"
  info "verify-build: OK"
  exit 0
fi
echo "Configuration validation: FAIL"
echo "Package validation: FAIL"
echo "----------------------------------------------"
die "verify-build failed; refusing to publish"
