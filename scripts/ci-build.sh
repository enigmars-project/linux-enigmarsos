#!/usr/bin/env bash
# Run inside the Arch Linux container on GitHub Actions.
# Builds, validates, and writes release artefacts to /out.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ci-build.sh must start as root inside the container" >&2
  exit 1
fi

export LANG=C.UTF-8
SRC="${SRC:-/src}"
OUT="${OUT:-/out}"
BUILDROOT="${BUILDROOT:-/build}"

echo "==> Initialising pacman"
pacman-key --init
pacman-key --populate archlinux
pacman -Syu --noconfirm --needed \
  base-devel git curl wget gnupg zstd jq python \
  bc binutils cpio gettext libelf openssl pahole perl \
  rust rust-bindgen rust-src tar xxhash xz zlib \
  kmod mkinitcpio pacman-contrib namcap \
  qemu-system-x86 busybox ccache

# Import vendored kernel/Arch keys used by makepkg source verification.
if [[ -d "$SRC/keys/pgp" ]]; then
  echo "==> Importing vendored PGP keys"
  for key in "$SRC/keys/pgp"/*.asc; do
    [[ -f "$key" ]] || continue
    pacman-key --add "$key" || true
    gpg --import "$key" || true
  done
  # Trust the vendored kernel/Arch keys. Ownertrust needs the full
  # fingerprint (fpr records), not the short key id on pub records.
  gpg --list-keys --with-colons \
    | awk -F: '/^fpr:/{print $10}' \
    | while read -r fpr; do
        [[ ${#fpr} -eq 40 ]] || continue
        echo "${fpr}:6:" | gpg --import-ownertrust || true
      done
fi

useradd -m -U -s /bin/bash builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
chmod 440 /etc/sudoers.d/builder

NPROC="$(nproc)"
cat >>/etc/makepkg.conf <<EOF

MAKEFLAGS="-j${NPROC}"
PACKAGER="EnigmarsOS Kernel CI <ci@enigmarsos.org>"
PKGDEST=${OUT}
SRCDEST=${BUILDROOT}/srcdest
LOGDEST=${OUT}
BUILDDIR=${BUILDROOT}/build
INTEGRITY_CHECK=(b2 sha256)
BUILDENV=(!distcc color !ccache check !sign)
EOF

if [[ "${ENABLE_CCACHE:-1}" == "1" ]]; then
  mkdir -p /cache/ccache
  chown -R builder:builder /cache
  echo 'BUILDENV=(!distcc color ccache check !sign)' >>/etc/makepkg.conf
  echo "CCACHE_DIR=/cache/ccache" >>/etc/makepkg.conf
fi

mkdir -p "$OUT" "$BUILDROOT/srcdest" "$BUILDROOT/build" "$BUILDROOT/pkg"
# Copy the packaging tree so makepkg can write src/pkg without touching the
# checkout ownership.
cp -a "$SRC/." "$BUILDROOT/pkg/"
chown -R builder:builder "$BUILDROOT" "$OUT"

# Reproducible timestamp from the git commit when available.
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  :
elif [[ -d "$SRC/.git" ]]; then
  SOURCE_DATE_EPOCH="$(git -C "$SRC" log -1 --pretty=%ct)"
  export SOURCE_DATE_EPOCH
fi
echo "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-unset}"

sudo -u builder --preserve-env=SOURCE_DATE_EPOCH,CCACHE_DIR,ENABLE_CCACHE \
  bash -lc "
    set -euo pipefail
    cd '$BUILDROOT/pkg'
    ./scripts/prepare-build.sh
    ./scripts/status.sh || true
    makepkg -sf --noconfirm --needed
    ./scripts/verify-build.sh '$OUT'
  "

# Install the just-built kernel into the container so mkinitcpio can run.
echo "==> Generating initramfs with mkinitcpio"
shopt -s nullglob
KERNEL_PKG=("$OUT"/linux-enigmarsos-[0-9]*.pkg.tar.zst)
HEADERS_PKG=("$OUT"/linux-enigmarsos-headers-*.pkg.tar.zst)
shopt -u nullglob
[[ -f "${KERNEL_PKG[0]:-}" ]] || { echo "kernel package missing in $OUT" >&2; exit 1; }

pacman -U --noconfirm "${KERNEL_PKG[0]}" "${HEADERS_PKG[0]:-}"
KREL="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -name '*enigmarsos*' -printf '%f\n' | head -n1)"
[[ -n "$KREL" ]] || { echo "installed kernel release not found" >&2; exit 1; }
echo "Installed kernel release: $KREL"
if ! mkinitcpio -k "$KREL" -g "$OUT/initramfs-linux-enigmarsos.img"; then
  echo "==> mkinitcpio with default hooks failed; retrying without autodetect"
  mkinitcpio -k "$KREL" -g "$OUT/initramfs-linux-enigmarsos.img" -S autodetect
fi
[[ -s "$OUT/initramfs-linux-enigmarsos.img" ]] || { echo "mkinitcpio produced an empty image" >&2; exit 1; }
echo "==> mkinitcpio: OK"

sudo -u builder bash -lc "'$BUILDROOT/pkg/scripts/qemu-smoke.sh' '$OUT'"

echo "==> Checksums"
(
  cd "$OUT"
  sha256sum linux-enigmarsos-*.pkg.tar.zst initramfs-linux-enigmarsos.img > SHA256SUMS
  if command -v b2sum >/dev/null 2>&1; then
    b2sum linux-enigmarsos-*.pkg.tar.zst initramfs-linux-enigmarsos.img > B2SUMS
  fi
)

if command -v namcap >/dev/null 2>&1; then
  echo "==> namcap (informational; warnings are expected for kernel packages)"
  namcap "${KERNEL_PKG[0]}" | tee "$OUT/namcap-linux-enigmarsos.txt" || true
  if [[ -f "${HEADERS_PKG[0]:-}" ]]; then
    namcap "${HEADERS_PKG[0]}" | tee "$OUT/namcap-linux-enigmarsos-headers.txt" || true
  fi
fi

# Build metadata consumed by the release step.
# shellcheck source=/dev/null
source "$BUILDROOT/pkg/scripts/lib.sh"
# lib.sh sets REPO_ROOT from BASH_SOURCE, which is wrong after source from here.
REPO_ROOT="$BUILDROOT/pkg"
PKGBUILD_PATH="$REPO_ROOT/PKGBUILD"
BORE_META="$REPO_ROOT/patches/bore.meta"
# shellcheck disable=SC1090
source "$BORE_META"

cat >"$OUT/BUILD-METADATA.txt" <<EOF
package_name=linux-enigmarsos
package_version=$(package_version)
upstream_linux=$(upstream_kernel)
arch_pkgver=$(pkgbuild_var pkgver)
arch_pkgrel_tracked=$(pkgbuild_var _arch_pkgrel)
enigmarsos_pkgrel=$(pkgbuild_var pkgrel)
expected_kernel_release=$(expected_kernel_release)
installed_kernel_release=$KREL
bore_version=$BORE_VERSION
bore_commit=$BORE_COMMIT
bore_designed_for=$BORE_DESIGNED_FOR_KERNEL
bore_channel=$BORE_CHANNEL
bore_sha256=$BORE_SHA256
git_commit=${GITHUB_SHA:-$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)}
git_ref=${GITHUB_REF:-unknown}
build_event=${GITHUB_EVENT_NAME:-local}
build_trigger=${BUILD_TRIGGER:-${GITHUB_EVENT_NAME:-local}}
github_run_id=${GITHUB_RUN_ID:-}
github_run_number=${GITHUB_RUN_NUMBER:-}
source_date_epoch=${SOURCE_DATE_EPOCH:-}
image_digest=${ARCH_IMAGE_DIGEST:-}
ccache=${ENABLE_CCACHE:-1}
EOF

cat >"$OUT/RELEASE-NOTES.md" <<EOF
# linux-enigmarsos $(package_version)

Custom EnigmarsOS kernel: current Arch Linux kernel + EnigmarsOS configuration + BORE scheduler.

| Field | Value |
| --- | --- |
| Package | \`linux-enigmarsos $(package_version)\` |
| Kernel release | \`$KREL\` |
| Upstream Linux | $(upstream_kernel) |
| Tracked Arch \`linux\` | $(pkgbuild_var pkgver)-$(pkgbuild_var _arch_pkgrel) |
| EnigmarsOS pkgrel | $(pkgbuild_var pkgrel) |
| BORE | $BORE_VERSION (\`$BORE_COMMIT\`, $BORE_CHANNEL) |
| BORE designed for | Linux $BORE_DESIGNED_FOR_KERNEL |
| Git commit | \`${GITHUB_SHA:-unknown}\` |
| Trigger | ${BUILD_TRIGGER:-${GITHUB_EVENT_NAME:-local}} |
| Run | ${GITHUB_RUN_ID:-n/a} |

## Validation

- BORE patch applied with \`--fuzz=0\`
- \`CONFIG_SCHED_BORE=y\`
- Kernel release identifies EnigmarsOS
- Package and headers metadata validated
- \`mkinitcpio\` produced an initramfs
- QEMU TCG smoke test booted the kernel and read \`/proc/sys/kernel/sched_bore=1\`

## Install (pacman repo — GitHub Releases mirror)

\`\`\`ini
[linux-enigmarsos]
SigLevel = Optional TrustAll
Server = https://github.com/enigmars-project/linux-enigmarsos/releases/latest/download
\`\`\`

\`\`\`bash
sudo pacman -Sy linux-enigmarsos linux-enigmarsos-headers
\`\`\`

Or install the release assets directly:

\`\`\`bash
sudo pacman -U linux-enigmarsos-$(package_version)-x86_64.pkg.tar.zst \\
              linux-enigmarsos-headers-$(package_version)-x86_64.pkg.tar.zst
\`\`\`

Keep the official Arch \`linux\` package installed as the fallback kernel.
EOF

echo "==> Building pacman repo metadata (db/files, in-container: repo-add lives here)"
# $OUT, not /build/output: PKGDEST=${OUT}, so the packages live in $OUT.
sudo -u builder bash -lc "cd /build/pkg && ./scripts/publish-repo.sh \"$OUT\" \"$OUT\""

echo "==> ci-build: OK"
# Everything root wrote above (initramfs is mode 600, checksums, metadata)
# must be readable by the host runner user or upload-artifact fails EACCES.
chmod -R a+rX "$OUT"
ls -lh "$OUT"
cat "$OUT/BUILD-METADATA.txt"
