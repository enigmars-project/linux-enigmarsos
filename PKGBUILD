# Maintainer: EnigmarsOS
# Contributor: Jan Alexander Steffens (heftig) <heftig@archlinux.org>
#
# Derived from the official Arch Linux `linux-lts` PKGBUILD (0BSD).
# Tracked Arch package: linux-lts 6.18.53-1
#
# This is not a kernel fork. The tree is:
#   vanilla Linux 6.18.51 + Arch linux-lts patches + BORE 6.8.0
#   + EnigmarsOS config fragment + x86-64-v2 ISA floor
#
# Live ISO default kernel. Rolling v3 stays on branch main
# (linux-enigmarsos) and is installed by Calamares.

pkgbase=linux-enigmarsos-lts
pkgver=6.18.53
pkgrel=3
pkgdesc='EnigmarsOS Linux LTS'
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

# Arch linux-lts package this PKGBUILD was last synchronized against.
_arch_pkgrel=1
_srcname=linux-$pkgver
_srctag=v$pkgver

# Compiler ISA floor. Vanilla 6.18 hardcodes -march=x86-64. Rewrite to
# v2 so the live ISO (and GitHub Actions DKMS) runs on x86-64-v2 CPUs.
# Minimum CPU: SSE4.2 (Nehalem 2008+, Silvermont, Bulldozer+).
_x86_64_march=x86-64-v2

# BORE pin. Keep in sync with patches/bore.meta.
_bore_version=7.0.0
_bore_commit=d429c0226fb5d25d51e6869a4bf7d8256e1122ff
_bore_designed_for=6.18.48

source=(
  https://cdn.kernel.org/pub/linux/kernel/v${pkgver%%.*}.x/${_srcname}.tar.{xz,sign}
  0001-add-sysctl-to-allow-disabling-unprivileged-CLONE_NEW.patch
  0002-drm-amdgpu-avoid-memory-allocation-in-the-critical-c.patch
  0003-drm-amdgpu-use-GFP_ATOMIC-instead-of-NOWAIT-in-the-c.patch
  bore.patch
  enigmarsos.config
)
source_x86_64=(
  config.x86_64
)
validpgpkeys=(
  ABAF11C65A2970B130ABE3C479BE3E4300411886  # Linus Torvalds
  647F28654894E3BD457199BE38DBBDC86092693E  # Greg Kroah-Hartman
)
b2sums=('cf369f9069895e57801f9427b65a7e7b5db5054c4ecd3ad5976bd94f6f88b5c5e01c8ac0b36aa331cbe5c8e84c8c858257c542b47487ae63aeeabdb6cd9f0024'
        'SKIP'
        'f98f4a2e714f7c9e05740caaad2bf014065ec950c096df74a3dee8b2ce6549f034adf6f87a76168f513aa68eb738edbdb6fe1a3f1b3a5104201c65199b5b931e'
        '6ca246df80fa85f9c21d090f87ee31e33acb02f3c1147944750e0896ebf199bc0cf427a164dacbdd9baa26dbdbce2fabd89ebdb6a8ce5dae83fc455b27a56cc8'
        'a612d5ea58485eeaa5cce0b30074ab3188f4321c4759448780de2f3f656821356d640df433e31bd4e8f2c9719c8e275374ddea29b9504335ed0981be5ac7bf7b'
        'ed0839b759e6a63aa7e349b4aa6b5cc6d3c169c11be8ed19265a03fd5e0a1ddd8576290e5ba179921ab73a3d301e958fe28109bc404e6855a8e4dd21459a0266'
        '8d90f477415b6cb19e5c2a906ad88fb42f27e6beabdfb405ea80b47b3b5f32c5f1903535375b19b69d6189f7020139fe55c66c05d51cd7bec305df76ee72499f')
b2sums_x86_64=('d801aa851700faaa5410b99ede568d6b5d2f4f98d047c3b2b8f26259437011e0c1dfe036a74fb37268540e0e6d54e4a562aab873727573736cad82016c242cb9')

# https://www.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
sha256sums=('4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0'
            'SKIP'
            '0bb3b4cda53db35c10e0a34defb5f52f3c91895d7b4a9f93b3f40f5401a71e02'
            '70d54dfde13e52ea1109c4222a987a29ada68feec35dca9ce4afd6f7977e8740'
            '44caa7c6a79055539f16ab118bece58934cdf93557643a50017634366c864b91'
        '529ac503052e2ea09d9c54cbf536ffaac842ba436ff368c4a595585f46e7b709'
        '39b41963f4925b6ef1391ca41869d7d76335af36d242eb85bbbc06d4a7d5a527')

export KBUILD_BUILD_HOST=enigmarsos
export KBUILD_BUILD_USER=$pkgbase
export KBUILD_BUILD_TIMESTAMP="$(date -Ru${SOURCE_DATE_EPOCH:+d @$SOURCE_DATE_EPOCH})"

# Kernel Makefile assigns HOSTCFLAGS with `=`, which ignores the environment.
# Pass these on every `make` command line. gcc on a v3 packager still emits
# v3 host binaries (fixdep) unless -march is explicit — those then abort on
# GitHub Actions (v2) with "CPU ISA level is lower than required".
_hostcflags="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu11 -march=${_x86_64_march}"
_hostcxxflags="-O2 -march=${_x86_64_march}"
_host_make() {
  make HOSTCFLAGS="${_hostcflags}" HOSTCXXFLAGS="${_hostcxxflags}" "$@"
}

# CachyOS glibc crt (Scrt1.o) stamps every linked ELF as
# "x86 ISA needed: … v3, v4" even when compiled with -march=x86-64-v2.
# glibc on GitHub Actions then aborts: CPU ISA level is lower than required.
# The actual code is baseline; drop the note so DKMS can run fixdep.
_sanitize_host_isa() {
  local f
  while IFS= read -r -d '' f; do
    case "$(file -Sib "$f" 2>/dev/null || true)" in
      application/x-executable\;*|application/x-pie-executable\;*|application/x-sharedlib\;*) ;;
      *) continue ;;
    esac
    if readelf -n "$f" 2>/dev/null | grep -qE 'x86-64-v[34]'; then
      echo "    removing inflated ISA note from ${f#"$PWD"/}"
      objcopy --remove-section=.note.gnu.property "$f" \
        || _die "objcopy failed on $f"
    fi
    if readelf -n "$f" 2>/dev/null | grep -qE 'x86-64-v[34]'; then
      _die "$f still tagged x86-64-v3/v4 after objcopy"
    fi
  done < <(find scripts tools/objtool tools/bpf/resolve_btfids -type f -print0 2>/dev/null)
}

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
  echo "-$pkgrel" > localversion.10-pkgrel
  echo "-enigmarsos-lts" > localversion.20-pkgname

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

  echo "Setting x86-64 ISA level to $_x86_64_march..."
  # Same position as vanilla -march=x86-64, after -mno-avx/-mno-sse.
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

  _host_make olddefconfig
  diff -u ../config.$CARCH .config || :

  echo "Validating EnigmarsOS configuration..."
  _require_config SCHED_BORE y
  _require_config MIN_BASE_SLICE_NS 2000000
  _require_config IKCONFIG y
  _require_config IKCONFIG_PROC y
  # scripts/config -s prints 'n' for unset bools that have a default of n
  _require_config X86_NATIVE_CPU n

  _host_make -s kernelrelease > version
  local krel
  krel=$(<version)
  echo "Prepared $pkgbase version $krel"
  [[ $krel == *enigmarsos-lts* ]] \
    || _die "kernel release '$krel' does not identify EnigmarsOS LTS"
}

build() {
  cd $_srcname
  _host_make all
  _host_make -C tools/bpf/bpftool vmlinux.h feature-clang-bpf-co-re=1
  echo "Sanitizing host-tool ISA notes for GitHub Actions (CachyOS crt is v4)..."
  _sanitize_host_isa
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
    'linux: official Arch kernel used as an extra fallback'
    'linux-enigmarsos: rolling EnigmarsOS kernel (installed by Calamares)'
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
  _sanitize_host_isa
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
