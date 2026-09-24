#!/usr/bin/env bash
# Boot the built kernel in QEMU/TCG with a tiny initramfs and prove BORE.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: qemu-smoke.sh [package-dir]

Extracts vmlinuz from the built linux-enigmarsos package, builds a
busybox initramfs, and boots it under qemu-system-x86_64 (TCG).

The guest must print ENIGMARSOS_QEMU_PASS and show:
  - uname -r contains enigmarsos
  - /proc/sys/kernel/sched_bore == 1
  - /proc/config.gz contains CONFIG_SCHED_BORE=y
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

need_cmd qemu-system-x86_64
need_cmd bsdtar
need_cmd cpio
need_cmd gzip
need_cmd find

if command -v busybox >/dev/null 2>&1; then
  BUSYBOX="$(command -v busybox)"
else
  die "busybox is required for the QEMU smoke test"
fi

PKGDIR="${1:-}"
if [[ -z "$PKGDIR" ]]; then
  mapfile -t ALL_PKGS < <(find_built_packages || true)
else
  shopt -s nullglob
  ALL_PKGS=("$PKGDIR"/linux-enigmarsos-[0-9]*.pkg.tar.zst)
  shopt -u nullglob
fi

KERNEL_PKG=""
for p in "${ALL_PKGS[@]:-}"; do
  base="$(basename "$p")"
  if [[ "$base" == linux-enigmarsos-* && "$base" != linux-enigmarsos-headers-* ]]; then
    KERNEL_PKG="$p"
  fi
done
[[ -n "$KERNEL_PKG" ]] || die "linux-enigmarsos package not found"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/enigmarsos-qemu.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

info "Extracting vmlinuz from $KERNEL_PKG"
# libarchive bsdtar has no GNU tar --wildcards: match a member list instead.
bsdtar -tf "$KERNEL_PKG" > "$WORKDIR/members.list"
extract_matching "$KERNEL_PKG" "$WORKDIR/members.list" "$WORKDIR" \
  'usr/lib/modules/.*/vmlinuz'
VMLINUZ="$(find "$WORKDIR/usr/lib/modules" -name vmlinuz -print -quit)"
[[ -n "$VMLINUZ" ]] || die "vmlinuz missing from package"

info "Building tiny initramfs"
INITDIR="$WORKDIR/initramfs"
mkdir -p "$INITDIR"/{bin,proc,sys,dev,root}
cp "$BUSYBOX" "$INITDIR/bin/busybox"
chmod 755 "$INITDIR/bin/busybox"
ln -s busybox "$INITDIR/bin/sh"

cat > "$INITDIR/init" <<'EOF'
#!/bin/busybox sh
/bin/busybox mkdir -p /proc /sys /dev
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev 2>/dev/null || true

echo "=== ENIGMARSOS QEMU SMOKE ==="
/bin/busybox uname -a
echo -n "Kernel release: "
/bin/busybox uname -r

fail=0
krel="$(/bin/busybox uname -r)"
case "$krel" in
  *enigmarsos*) echo "EnigmarsOS kernel: enabled" ;;
  *) echo "EnigmarsOS kernel: MISSING"; fail=1 ;;
esac

if [ -f /proc/sys/kernel/sched_bore ]; then
  val="$(/bin/busybox cat /proc/sys/kernel/sched_bore)"
  echo "BORE sysctl: $val"
  if [ "$val" = "1" ]; then
    echo "BORE: enabled"
  else
    echo "BORE: disabled ($val)"
    fail=1
  fi
else
  echo "BORE: /proc/sys/kernel/sched_bore missing"
  fail=1
fi

if [ -f /proc/config.gz ]; then
  if /bin/busybox zcat /proc/config.gz | /bin/busybox grep -q '^CONFIG_SCHED_BORE=y'; then
    echo "Configuration validation: PASS"
  else
    echo "Configuration validation: FAIL (CONFIG_SCHED_BORE not y)"
    fail=1
  fi
else
  echo "Configuration validation: FAIL (/proc/config.gz missing)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "ENIGMARSOS_QEMU_PASS"
else
  echo "ENIGMARSOS_QEMU_FAIL"
fi

# Prefer a clean shutdown so QEMU exits.
if [ -w /proc/sysrq-trigger ]; then
  echo o > /proc/sysrq-trigger
fi
/bin/busybox poweroff -f 2>/dev/null || /bin/busybox halt -f
EOF
chmod 755 "$INITDIR/init"

(
  cd "$INITDIR"
  find . | cpio -o -H newc
) | gzip -9 > "$WORKDIR/initramfs.img"

LOG="$WORKDIR/qemu.log"
info "Booting QEMU (TCG, 120s timeout)"
set +e
timeout 120 qemu-system-x86_64 \
  -machine q35 \
  -cpu qemu64 \
  -m 512 \
  -nographic \
  -no-reboot \
  -kernel "$VMLINUZ" \
  -initrd "$WORKDIR/initramfs.img" \
  -append "console=ttyS0,115200 earlyprintk=serial,ttyS0,115200 panic=1" \
  >"$LOG" 2>&1
rc=$?
set -e

echo "----- QEMU serial output -----"
cat "$LOG"
echo "----- end QEMU output -----"

if grep -q 'ENIGMARSOS_QEMU_PASS' "$LOG"; then
  echo
  echo "Kernel: $(grep -m1 'Kernel release:' "$LOG" | awk '{print $3}')"
  echo "EnigmarsOS kernel: enabled"
  echo "BORE: enabled"
  echo "Configuration validation: PASS"
  info "qemu-smoke: OK"
  exit 0
fi

die "QEMU smoke test failed (qemu exit $rc). Refusing to publish."
