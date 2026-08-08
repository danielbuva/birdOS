#!/bin/bash
# Host-only coverage for the PortMaster installation/readiness checkpoints.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
SOURCE=$ROOT/kernel/rocknix/stock-root/prepare-ports.sh
FIXED_STORAGE_SOURCE=$ROOT/kernel/rocknix/stock-root/fixed-storage.sh
MANIFEST_SOURCE=$ROOT/kernel/rocknix/stock-root/portmaster-provider.manifest.tsv
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bird-prepare-ports.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

grep -Fq 'FIXED_STORAGE=/flash/bird/fixed-storage.sh' "$SOURCE"
grep -Fq 'PROVIDER_MANIFEST=/flash/bird/portmaster-provider.manifest.tsv' \
	"$SOURCE"
grep -Fq 'PROVIDER_VERIFIER=/flash/bird/verify-portmaster-provider.sh' \
	"$SOURCE"

# fixed-storage.sh is independently replaceable by the fast workflow. Assert
# its complete fixed-device bind contract directly; the prepare-ports runtime
# cases below intentionally substitute a failing helper to test checkpoint
# ordering and therefore cannot stand in for coverage of these source bytes.
bash -n "$FIXED_STORAGE_SOURCE"
grep -Fqx 'ROM_SOURCE=/storage/bird-data/ROMS' "$FIXED_STORAGE_SOURCE"
grep -Fqx 'MEDIA_SOURCE=/storage/bird-data/MEDIA' "$FIXED_STORAGE_SOURCE"
grep -Fqx 'ROM_TARGET=/storage/roms' "$FIXED_STORAGE_SOURCE"
grep -Fqx 'MEDIA_TARGET=/storage/media' "$FIXED_STORAGE_SOURCE"
grep -Fq 'mount --bind "$ROM_SOURCE" "$ROM_TARGET" || exit 1' \
	"$FIXED_STORAGE_SOURCE"
grep -Fq 'mount -o remount,bind,rw,exec "$ROM_TARGET" || exit 1' \
	"$FIXED_STORAGE_SOURCE"
grep -Fq 'mount --bind "$MEDIA_SOURCE" "$MEDIA_TARGET" || exit 1' \
	"$FIXED_STORAGE_SOURCE"
grep -Fq '[ "$ROM_TARGET" -ef "$ROM_SOURCE" ] || exit 1' \
	"$FIXED_STORAGE_SOURCE"
grep -Fq '[ "$MEDIA_TARGET" -ef "$MEDIA_SOURCE" ] || exit 1' \
	"$FIXED_STORAGE_SOURCE"
if grep -Eq 'lsblk|blkid|findmnt|/dev/(sd|mmc|nvme)' "$FIXED_STORAGE_SOURCE"; then
	printf '%s\n' 'fixed storage regained generic block-device discovery' >&2
	exit 1
fi

PORT_ROOT=$TMP/ports
PROVIDER=$PORT_ROOT/PortMaster
CONFIG=$TMP/config
LEGACY=$TMP/legacy
MARKER=$TMP/run/ports-ready
FIXED_STORAGE=$TMP/fixed-storage
MANIFEST=$TMP/provider.manifest.tsv
VERIFIER=$TMP/provider-verifier
UNDER_TEST=$TMP/prepare-ports.sh
VERIFY_CALLED=$TMP/verifier-called

/bin/mkdir -p "$PROVIDER" "$CONFIG" "$LEGACY" "${MARKER%/*}"
cp "$MANIFEST_SOURCE" "$MANIFEST"
cat >"$FIXED_STORAGE" <<'EOF'
#!/bin/sh
exit 99
EOF
cat >"$VERIFIER" <<'EOF'
#!/bin/sh
printf '%s\n' called >>"$VERIFY_CALLED"
exit 1
EOF
/bin/chmod 0755 "$FIXED_STORAGE" "$VERIFIER"
export VERIFY_CALLED

sed \
	-e "s#^PORT_ROOT=.*#PORT_ROOT=$PORT_ROOT#" \
	-e "s#^PORTMASTER=.*#PORTMASTER=$PROVIDER#" \
	-e "s#^CONFIG=.*#CONFIG=$CONFIG#" \
	-e "s#^LEGACY=.*#LEGACY=$LEGACY#" \
	-e "s#^MARKER=.*#MARKER=$MARKER#" \
	-e "s#^FIXED_PORT_ROOT=.*#FIXED_PORT_ROOT=$PORT_ROOT#" \
	-e "s#^FIXED_STORAGE=.*#FIXED_STORAGE=$FIXED_STORAGE#" \
	-e "s#^PROVIDER_MANIFEST=.*#PROVIDER_MANIFEST=$MANIFEST#" \
	-e "s#^PROVIDER_VERIFIER=.*#PROVIDER_VERIFIER=$VERIFIER#" \
	-e "s#mkdir -p \"\$PORT_ROOT\" /run/bird#mkdir -p \"\$PORT_ROOT\" \"${MARKER%/*}\"#" \
	"$SOURCE" >"$UNDER_TEST"
/bin/chmod 0755 "$UNDER_TEST"
bash -n "$UNDER_TEST"

REVISION=$(awk -F '\t' '$1 == "revision" {print $2}' "$MANIFEST")
DIGEST=$(sha256sum "$MANIFEST" | awk '{print $1}')
CHECKPOINT=bird-portmaster-v3:$REVISION:$DIGEST
printf '%s\n' "$CHECKPOINT" >"$PROVIDER/.bird-release-complete"
printf '%s\n' "$CHECKPOINT" >"$MARKER"

# A same-boot checkpoint must exit before invoking the installation verifier.
"$UNDER_TEST" >"$TMP/cached.out" 2>"$TMP/cached.err"
grep -Fq 'Bird Ports cached ready uptime=' "$TMP/cached.out"
[ ! -e "$VERIFY_CALLED" ]

# A stale per-boot checkpoint is removed. The persistent installation
# checkpoint permits preparation without hashing the provider tree.
printf '%s\n' stale >"$MARKER"
set +e
"$UNDER_TEST" >"$TMP/stale.out" 2>"$TMP/stale.err"
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
[ ! -e "$VERIFY_CALLED" ]
[ ! -e "$MARKER" ]
grep -Fq 'Bird Ports prepare start uptime=' "$TMP/stale.out"

# A special-node checkpoint fails closed before the verifier is trusted.
rm -f "$VERIFY_CALLED"
ln -s "$TMP/missing" "$MARKER"
set +e
"$UNDER_TEST" >"$TMP/unsafe.out" 2>"$TMP/unsafe.err"
STATUS=$?
set -e
[ "$STATUS" -eq 1 ]
[ ! -e "$VERIFY_CALLED" ]
grep -Fq 'per-boot marker is unsafe' "$TMP/unsafe.err"

printf '%s\n' 'stock-root prepare-ports checkpoint tests: PASS'
