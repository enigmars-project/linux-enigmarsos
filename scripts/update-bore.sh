#!/usr/bin/env bash
# Fetch a BORE patch that matches the kernel series in PKGBUILD.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: update-bore.sh [--check] [BORE_VERSION]

Looks at firelzrd/bore-scheduler and selects a patch compatible with
the upstream kernel series in PKGBUILD.

Upstream layout (as of 2026): versioned patches live flat under
patches/stable (older layouts used per-series subdirectories and a
patches/testing directory; both forms are accepted).

Preference order:
  1. patch whose filename contains the exact upstream version
  2. patch for the same major.minor series

The chosen file is copied to patches/bore.patch and patches/bore.meta
is rewritten. The script refuses to invent a patch. If nothing matches,
it exits non-zero and leaves the existing pin in place.

  --check   print the best available match without writing files
EOF
}

CHECK_ONLY=0
REQUESTED=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --check) CHECK_ONLY=1 ;;
    *) REQUESTED="$arg" ;;
  esac
done

need_cmd git
need_cmd python3
need_cmd sha256sum

kernel="$(upstream_kernel)"
series="${kernel%.*}"
[[ "$series" == 7 || "$series" == 6 ]] && series="$kernel"

info "Looking for a BORE patch for Linux $kernel (series $series)"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/enigmarsos-bore.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

bore_repo="https://github.com/firelzrd/bore-scheduler.git"
# Clone (git protocol) rather than query api.github.com: the anonymous REST
# quota is 60 req/hour per IP, and CI runners share egress IPs, which caused
# spurious 403s mid-update. The git protocol is not rate-limited.
clone=0
for attempt in 1 2 3; do
  if GIT_TERMINAL_PROMPT=0 git clone --depth 1 --quiet "$bore_repo" "$WORKDIR/bore"; then
    clone=1
    break
  fi
  warn "bore-scheduler clone failed (attempt $attempt/3)"
  rm -rf "$WORKDIR/bore"
  sleep $((attempt * 5))
done
[[ "$clone" -eq 1 ]] || die "could not clone $bore_repo"
commit_sha="$(git -C "$WORKDIR/bore" rev-parse HEAD)"
commit_date="$(git -C "$WORKDIR/bore" log -1 --format=%cd --date=short)"

python3 - "$WORKDIR" "$kernel" "$series" "${REQUESTED}" "$CHECK_ONLY" \
  "$BORE_PATCH" "$BORE_META" "$commit_sha" "$commit_date" <<'PY'
import os, re, sys, hashlib

(workdir, kernel, series, requested, check_only, dest_patch, dest_meta,
 commit_sha, commit_date) = sys.argv[1:10]
check_only = check_only == "1"
bore_root = os.path.join(workdir, "bore")

candidates = []
def scan(relative_dir, channel):
    root = os.path.join(bore_root, relative_dir)
    if not os.path.isdir(root):
        return
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if not name.endswith(".patch"):
                continue
            local = os.path.join(dirpath, name)
            candidates.append({
                "channel": channel,
                "name": name,
                "path": os.path.relpath(local, bore_root),
                "local": local,
            })

# stable is nowadays a flat file list; older layouts used one directory
# per series (e.g. linux-7.2-bore). os.walk handles both.
scan("patches/stable", "stable")
# testing was removed upstream; keep honouring it if it ever returns.
scan("patches/testing", "testing")

def parse_name(name):
    # 0001-linux7.1.5-bore-6.8.0.patch
    # 0001-linux7.1-rc1-bore-6.6.3.patch
    # 0001-linux6.18.48-bore-7.0.0-rc1.patch (rc-suffixed BORE version)
    m = re.search(r'linux(\d+(?:\.\d+)*(?:-rc\d+)?)-bore-([0-9.]+(?:-rc\d+)?)\.patch$', name)
    if not m:
        return None, None
    return m.group(1), m.group(2)

scored = []
for c in candidates:
    designed, version = parse_name(c["name"])
    if not designed:
        continue
    c["designed"] = designed
    c["version"] = version
    if requested and version != requested:
        continue
    score = 0
    if designed == kernel:
        score += 300
    elif designed.startswith(series):
        score += 200
    # Prefer the numerically newest designed version within a series.
    nums = [int(x) for x in re.findall(r'\d+', designed)]
    score += nums[-1] if nums else 0
    c["score"] = score
    scored.append(c)

scored.sort(key=lambda c: c["score"], reverse=True)
if not scored or scored[0]["score"] < 200:
    print("No BORE patch matches Linux %s." % kernel, file=sys.stderr)
    print("Available patches:", file=sys.stderr)
    for c in candidates:
        designed, version = parse_name(c["name"])
        print(f"  {c['channel']:8} {c['name']}  designed={designed} version={version}", file=sys.stderr)
    print("Refusing to invent a patch.", file=sys.stderr)
    sys.exit(3)

best = scored[0]
print(f"Selected {best['channel']} {best['name']}")
print(f"  BORE version:  {best['version']}")
print(f"  Designed for:  {best['designed']}")
print(f"  Upstream path: {best['path']}")

if check_only:
    sys.exit(0)

print("Reading", best["path"])
data = open(best["local"], "rb").read()

sha256 = hashlib.sha256(data).hexdigest()
try:
    import hashlib as _h
    b2 = _h.blake2b(data).hexdigest()
except Exception:
    b2 = ""

os.makedirs(os.path.dirname(dest_patch), exist_ok=True)
open(dest_patch, "wb").write(data)

# Prefer the file's own Subject version if present.
ver = best["version"]
m = re.search(br'SCHED_BORE_VERSION\s+"([^"]+)"', data)
if m:
    ver = m.group(1).decode()

meta = f"""# Pinned BORE patch metadata.
# patches/bore.patch is the verbatim upstream file. Do not edit the patch
# by hand. Refresh it with ./scripts/update-bore.sh.

BORE_VERSION={ver}
BORE_COMMIT={commit_sha}
BORE_DATE={commit_date}
BORE_CHANNEL={best['channel']}
BORE_DESIGNED_FOR_KERNEL={best['designed']}
BORE_UPSTREAM_REPO=https://github.com/firelzrd/bore-scheduler
BORE_UPSTREAM_PATH={best['path']}
BORE_LICENSE=GPL-2.0-only
BORE_SHA256={sha256}
BORE_B2SUM={b2}
"""
open(dest_meta, "w", encoding="utf-8").write(meta)
print(f"Wrote {dest_patch}")
print(f"Wrote {dest_meta}")
print(f"SHA-256 {sha256}")
print("Update PKGBUILD checksums for patches/bore.patch before committing.")
PY

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  exit 0
fi

# Refresh the bore.patch checksums inside PKGBUILD.
new_sha="$(sha256sum "$BORE_PATCH" | awk '{print $1}')"
new_b2="$(b2sum "$BORE_PATCH" 2>/dev/null | awk '{print $1}' || true)"
if [[ -z "$new_b2" ]]; then
  new_b2="$(python3 - "$BORE_PATCH" <<'PY'
import hashlib, sys
print(hashlib.blake2b(open(sys.argv[1],'rb').read()).hexdigest())
PY
)"
fi

python3 - "$PKGBUILD_PATH" "$new_sha" "$new_b2" <<'PY'
import re, sys
path, sha, b2 = sys.argv[1:4]
text = open(path, encoding="utf-8").read()

def replace_nth_quoted(block, n_from_end, new):
    vals = list(re.finditer(r"'([^']+)'", block))
    if len(vals) < n_from_end:
        raise SystemExit("not enough checksum entries")
    target = vals[-n_from_end]
    return block[:target.start(1)] + new + block[target.end(1):]

# bore.patch is the second-to-last entry in both arrays
# (last is enigmarsos.config).
text2 = text
for name, new, n in (("b2sums", b2, 2), ("sha256sums", sha, 2)):
    m = re.search(rf'^{name}=\((.*?)\)', text2, re.S | re.M)
    if not m:
        raise SystemExit(f"missing {name}")
    updated = replace_nth_quoted(m.group(0), n, new)
    text2 = text2[:m.start()] + updated + text2[m.end():]

m = re.search(r'^_bore_version=.*$', text2, re.M)
# leave _bore_version to be rewritten from bore.meta
text = text2
open(path, "w", encoding="utf-8").write(text)
print("updated PKGBUILD checksums for bore.patch")
PY

load_bore_meta
python3 - "$PKGBUILD_PATH" "$BORE_VERSION" "$BORE_COMMIT" "$BORE_DESIGNED_FOR_KERNEL" <<'PY'
import re, sys
path, ver, commit, designed = sys.argv[1:5]
text = open(path, encoding="utf-8").read()
text = re.sub(r'^_bore_version=.*$', f'_bore_version={ver}', text, count=1, flags=re.M)
text = re.sub(r'^_bore_commit=.*$', f'_bore_commit={commit}', text, count=1, flags=re.M)
text = re.sub(r'^_bore_designed_for=.*$', f'_bore_designed_for={designed}', text, count=1, flags=re.M)
open(path, "w", encoding="utf-8").write(text)
print(f"updated PKGBUILD BORE pin to {ver}")
PY

info "BORE updated. Review patches/bore.patch and try a dry-run before committing."
info "A build MUST fail if the new patch does not apply with --fuzz=0."
