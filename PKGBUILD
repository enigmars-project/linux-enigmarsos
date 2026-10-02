# Maintainer: EnigmarsOS
# Contributor: Jan Alexander Steffens (heftig) <heftig@archlinux.org>
#
# Derived from the official Arch Linux `linux` PKGBUILD (0BSD).
# Tracked Arch package: linux 7.2.8.arch1-2
#
# This is not a kernel fork. The tree is:
#   vanilla Linux 7.1.8 + Arch patch + BORE 6.8.0 + EnigmarsOS config fragment

pkgbase=linux-enigmarsos
pkgver=7.2.8.arch1
pkgrel=3
pkgdesc='EnigmarsOS Linux'
url='https://github.com/enigmars-project/linux-enigmarsos'
arch=(x86_64)
license=(GPL-2.0-only)
makedepends=(
  bc
  binutils
  cpio
  gettext
  glibc
  libelf
  libgcc
  openssl
  pahole
  perl
  python
  rust
  rust-bindgen
  rust-src
  tar
  xxhash
  xz
  zlib
  zstd
)
options=(
  !debug
  !strip
)

# Arch linux package this PKGBUILD was last synchronized against.
_arch_pkgrel=2
_srcname=linux-${pkgver%.*}
_srctag=v${pkgver%.*}-${pkgver##*.}
_arch_linux_url='https://github.com/archlinux/linux'

# Compiler ISA floor. Vanilla 7.2 has no CONFIG_X86_64_VERSION; the
# kernel Makefile hardcodes -march=x86-64. We rewrite that to v3.
# Minimum CPU: AVX2 (Intel Haswell 2013+, AMD Excavator 2015+ / all Zen).
_x86_64_march=x86-64-v3

# BORE pin. Keep in sync with patches/bore.meta.
_bore_version=7.0.0
_bore_commit=d429c0226fb5d25d51e6869a4bf7d8256e1122ff
_bore_designed_for=7.2-rc1

source=(
  https://cdn.kernel.org/pub/linux/kernel/v${pkgver%%.*}.x/${_srcname}.tar.{xz,sign}
  $_arch_linux_url/releases/download/$_srctag/linux-$_srctag.patch.zst{,.sig}
  bore.patch
  enigmarsos.config
)
source_x86_64=(
  config.x86_64
)
validpgpkeys=(
  ABAF11C65A2970B130ABE3C479BE3E4300411886  # Linus Torvalds
  647F28654894E3BD457199BE38DBBDC86092693E  # Greg Kroah-Hartman
  83BC8889351B5DEBBB68416EB8AC08600F108CDF  # Jan Alexander Steffens (heftig)
)
b2sums=('5326dde778eb945f282740ef0d8765b46fbd198f1209cdfd7b91e5dac1312fc01f8bf0b2bc67b16a76de736edd8ea21b38b6c91e696ec0c4b39746cd21a15214'
        'SKIP'
        '107774838edc0c45c3dd602ee6dddedecade6a0b5b85a02a62500d0af64c2c36ed4bcdd15e8e85df1e1a3dbc3efbe1e514f34af9ab3f251b1dcf496e633bdb2d'
        'SKIP'
        '99a35a06bb9a02ed4ebb481397d3c9abf1f18beb784bb8ff1eead8e053cb83709b6e3d950241e5d638fef835c4f0bb004f0729bfb61aea85e2d6fc762d4ff92a'
        '1ce4482c88ccf6f0f8e59dd550beb6aa41b8e1d908548ed6c5c02d9b2842319c90ba13185a70b0e57dea09fa9137b67e772f7a3660cc829e8c75f4d5ebca2372')
b2sums_x86_64=('6fd8ed7afb16b4aa2e6807c7c056a337d19388e19e1554429658532cc86b04b0105b027642ce8782f5b3a61e6c9e8d9f810e8ec42ea199ad8c3ca6bcd596d22a')

# https://www.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc
sha256sums=('12e8d5a973d1ad7c5a5c69882e4022b131ed715db7003fdcd760ddf8c3e51941'
            'SKIP'
            'fee5e7b494cdb2bb833ff6c3516e9360ffbf645ac3efd473ee52291ebe2d446e'
            'SKIP'
        '948aa495364332596d9f00fba1f90b2da04676a37faaeab9ef2390c44c7fbd83'
        '777a7495ff3ed47dbf5f2ae044d50ac5d298c2c8a7e12ef4f3455d5656d2c93d')

export KBUILD_BUILD_HOST=enigmarsos
export KBUILD_BUILD_USER=$pkgbase
export KBUILD_BUILD_TIMESTAMP="$(date -Ru${SOURCE_DATE_EPOCH:+d @$SOURCE_DATE_EPOCH})"

_die() {
  printf '==> ERROR: %s\n' "$*" >&2
  exit 1
}

_require_config() {
  local opt="$1" expected="$2" got
  got=$(scripts/config --file .config -s "$opt" || true)
  if [[ "$got" != "$expected" ]]; then
    _die "required option $opt is '${got:-<unset>}', expected '$expected'"
  fi
}

prepare() {
  cd $_srcname

  echo "Setting version..."
  # localversion files add -$pkgrel and -enigmarsos to the kernel release.
  # Keep upstream version + pkgrel so /usr/lib/modules/* stays unique.
  echo "-$pkgrel" > localversion.10-pkgrel
  echo "-enigmarsos" > localversion.20-pkgname

  local src
  for src in "${source[@]}"; do
    src="${src%%::*}"
    src="${src##*/}"
    src="${src%.zst}"
    [[ $src = *.patch ]] || continue
    echo "Applying patch $src..."
    # --fuzz=0: a context mismatch is a hard failure. Never skip BORE.
    patch -Np1 --fuzz=0 --forward < "../$src" \
      || _die "patch $src did not apply cleanly; refusing to build an unpatched kernel"
  done

  [[ -f kernel/sched/bore.c ]] \
    || _die "kernel/sched/bore.c missing after patching; BORE did not apply"
  grep -q "SCHED_BORE_VERSION[[:space:]]\\+\"$_bore_version\"" include/linux/sched/bore.h \
    || _die "BORE version string $_bore_version not found in include/linux/sched/bore.h"

  echo "Clearing Arch EXTRAVERSION..."
  # The Arch patch sets EXTRAVERSION=-archN *after* the tree is extracted,
  # so it must be cleared after patching (a pre-patch sed is a no-op).
  # uname -r must look like other distros (7.2.6-3-enigmarsos),
  # not 7.2.6-arch2-3-enigmarsos.
  sed -i 's/^EXTRAVERSION =.*/EXTRAVERSION =/' Makefile
  grep -q '^EXTRAVERSION =$' Makefile \
    || _die "EXTRAVERSION was not cleared; upstream Makefile format may have changed"

  echo "Setting x86-64 ISA level to $_x86_64_march..."
  # Same position as vanilla -march=x86-64, after -mno-avx/-mno-sse, so
  # the kernel still must not emit SIMD. v3 unlocks BMI2/LZCNT/MOVBE.
  grep -q -- '-march=x86-64 -mtune=generic' arch/x86/Makefile \
    || _die "arch/x86/Makefile no longer contains the vanilla -march=x86-64 line"
  sed -i "s/-march=x86-64 -mtune=generic/-march=${_x86_64_march} -mtune=generic/" \
    arch/x86/Makefile
  sed -i "s/-Ctarget-cpu=x86-64 -Ztune-cpu=generic/-Ctarget-cpu=${_x86_64_march} -Ztune-cpu=generic/" \
    arch/x86/Makefile
  grep -q -- "-march=${_x86_64_march}" arch/x86/Makefile \
    || _die "failed to set -march=${_x86_64_march} in arch/x86/Makefile"

  echo "Setting config..."
  cp ../config.$CARCH .config

  echo "Applying EnigmarsOS configuration fragment..."
  scripts/config --file .config --enable SCHED_BORE
  scripts/config --file .config --set-val MIN_BASE_SLICE_NS 2000000
  scripts/config --file .config --disable X86_NATIVE_CPU

  make olddefconfig
  diff -u ../config.$CARCH .config || :

  echo "Validating EnigmarsOS configuration..."
  _require_config SCHED_BORE y
  _require_config MIN_BASE_SLICE_NS 2000000
  _require_config IKCONFIG y
  _require_config IKCONFIG_PROC y
  # scripts/config -s prints 'n' for unset bools that have a default of n
  _require_config X86_NATIVE_CPU n

  make -s kernelrelease > version
  local krel
  krel=$(<version)
  echo "Prepared $pkgbase version $krel"
  [[ $krel == *enigmarsos* ]] \
    || _die "kernel release '$krel' does not identify EnigmarsOS"
}

build() {
  cd $_srcname
  make all
  make -C tools/bpf/bpftool vmlinux.h feature-clang-bpf-co-re=1
}

_package() {
  pkgdesc="The $pkgdesc kernel and modules (BORE scheduler)"
  depends=(
    coreutils
    initramfs
    kmod
  )
  optdepends=(
    "$pkgbase-headers: headers and scripts for building modules"
    'linux-firmware: firmware images needed for some devices'
    'scx-scheds: to use sched-ext schedulers'
    'wireless-regdb: to set the correct wireless channels of your country'
    'linux: official Arch kernel used as the EnigmarsOS fallback'
  )
  provides=(
    KSMBD-MODULE
    NTSYNC-MODULE
    VIRTUALBOX-GUEST-MODULES
    WIREGUARD-MODULE
  )
  # Do not conflict with or replace `linux`. The Arch kernel stays
  # installable as the fallback boot entry.

  cd $_srcname
  local modulesdir="$pkgdir/usr/lib/modules/$(<version)"

  echo "Installing boot image..."
  # systemd expects to find the kernel here to allow hibernation
  # https://github.com/systemd/systemd/commit/edda44605f06a41fb86b7ab8128dcf99161d2344
  install -Dm644 "$(make -s image_name)" "$modulesdir/vmlinuz"

  # Used by mkinitcpio to name the kernel
  echo "$pkgbase" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"

  echo "Installing modules..."
  ZSTD_CLEVEL=19 make INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 \
    DEPMOD=/doesnt/exist modules_install  # Suppress depmod

  # remove build link
  rm "$modulesdir"/build
}

_package-headers() {
  pkgdesc="Headers and scripts for building modules for the $pkgdesc kernel"
  depends=(
    binutils
    glibc
    libelf
    libgcc
    openssl
    pahole
    xxhash
    zlib
    zstd
  )
  provides=(LINUX-HEADERS)

  cd $_srcname
  local builddir="$pkgdir/usr/lib/modules/$(<version)/build"

  local karch
  case $CARCH in
    x86_64) karch=x86 ;;
    *) echo "Unknown CARCH $CARCH"; exit 1 ;;
  esac

  echo "Installing build files..."
  install -Dt "$builddir" -m644 .config Makefile Module.symvers System.map \
    localversion.* version vmlinux tools/bpf/bpftool/vmlinux.h
  install -Dt "$builddir/kernel" -m644 kernel/Makefile
  install -Dt "$builddir/arch/$karch" -m644 arch/$karch/Makefile
  cp -t "$builddir" -a scripts
  ln -srt "$builddir" "$builddir/scripts/gdb/vmlinux-gdb.py"

  if [[ $(scripts/config -s CONFIG_HAVE_STACK_VALIDATION) = y ]]; then
    install -Dt "$builddir/tools/objtool" tools/objtool/objtool
  fi

  if [[ $(scripts/config -s CONFIG_DEBUG_INFO_BTF_MODULES) = y ]]; then
    install -Dt "$builddir/tools/bpf/resolve_btfids" tools/bpf/resolve_btfids/resolve_btfids
  fi

  echo "Installing headers..."
  cp -t "$builddir" -a include
  cp -t "$builddir/arch/$karch" -a arch/$karch/include
  install -Dt "$builddir/arch/$karch/kernel" -m644 arch/$karch/kernel/asm-offsets.s

  install -Dt "$builddir/drivers/md" -m644 drivers/md/*.h
  install -Dt "$builddir/net/mac80211" -m644 net/mac80211/*.h

  # https://bugs.archlinux.org/task/13146
  install -Dt "$builddir/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h

  # https://bugs.archlinux.org/task/20402
  install -Dt "$builddir/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
  install -Dt "$builddir/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
  install -Dt "$builddir/drivers/media/tuners" -m644 drivers/media/tuners/*.h

  # https://bugs.archlinux.org/task/71392
  install -Dt "$builddir/drivers/iio/common/hid-sensors" -m644 drivers/iio/common/hid-sensors/*.h

  echo "Installing KConfig files..."
  find . -name 'Kconfig*' -exec install -Dm644 {} "$builddir/{}" \;

  if [[ $(scripts/config -s CONFIG_RUST) = y ]]; then
    echo "Installing Rust files..."
    install -Dt "$builddir/rust" -m644 rust/*.rmeta
    install -Dt "$builddir/rust" rust/*.so
  fi

  echo "Installing unstripped VDSO..."
  make INSTALL_MOD_PATH="$pkgdir/usr" vdso_install \
    link=  # Suppress build-id symlinks

  echo "Removing unneeded architectures..."
  local arch
  for arch in "$builddir"/arch/*/; do
    [[ $arch = */$karch/ ]] && continue
    echo "Removing $(basename "$arch")"
    rm -r "$arch"
  done

  echo "Removing documentation..."
  rm -r "$builddir/Documentation"

  echo "Removing broken symlinks..."
  find -L "$builddir" -type l -printf 'Removing %P\n' -delete

  echo "Removing loose objects..."
  find "$builddir" -type f -name '*.o' -printf 'Removing %P\n' -delete

  echo "Stripping build tools..."
  local file
  while read -rd '' file; do
    case "$(file -Sib "$file")" in
      application/x-sharedlib\;*)      # Libraries (.so)
        strip -v $STRIP_SHARED "$file" ;;
      application/x-archive\;*)        # Libraries (.a)
        strip -v $STRIP_STATIC "$file" ;;
      application/x-executable\;*)     # Binaries
        strip -v $STRIP_BINARIES "$file" ;;
      application/x-pie-executable\;*) # Relocatable binaries
        strip -v $STRIP_SHARED "$file" ;;
    esac
  done < <(find "$builddir" -type f -perm -u+x ! -name vmlinux -print0)

  echo "Stripping vmlinux..."
  strip -v $STRIP_STATIC "$builddir/vmlinux"

  echo "Adding symlink..."
  mkdir -p "$pkgdir/usr/src"
  ln -sr "$builddir" "$pkgdir/usr/src/$pkgbase"
}

pkgname=(
  "$pkgbase"
  "$pkgbase-headers"
)
for _p in "${pkgname[@]}"; do
  eval "package_$_p() {
    $(declare -f "_package${_p#$pkgbase}")
    _package${_p#$pkgbase}
  }"
done

# vim:set ts=8 sts=2 sw=2 et:
