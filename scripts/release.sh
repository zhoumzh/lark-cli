#!/usr/bin/env bash
# Build linux-amd64 binary, create a GitHub release on origin (zhoumzh/lark-cli),
# and upload the archive via curl (no gh CLI required).
#
# Usage:
#   GITHUB_TOKEN=<token> ./scripts/release.sh            # uses package.json version
#   GITHUB_TOKEN=<token> ./scripts/release.sh v1.0.12    # explicit version tag

set -euo pipefail

REPO="zhoumzh/lark-cli"
NAME="lark-cli"
MODULE="github.com/larksuite/cli"

# Default to package.json version so it matches what install.js expects
PKG_VERSION=$(node -p "require('./package.json').version")
VERSION="${1:-v${PKG_VERSION}}"
TAG="${VERSION}"
[[ "$TAG" != v* ]] && TAG="v${TAG}"
BARE="${TAG#v}"   # without leading 'v', used in archive filename

DATE="$(date +%Y-%m-%d)"
LDFLAGS="-s -w -X ${MODULE}/internal/build.Version=${TAG} -X ${MODULE}/internal/build.Date=${DATE}"

DIST="dist"
rm -rf "$DIST" && mkdir -p "$DIST"

ARCHIVE_FILE="${NAME}-${BARE}-linux-amd64.tar.gz"

echo "==> Building ${TAG} (linux/amd64)"
python3 scripts/fetch_meta.py

GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "$LDFLAGS" -o "${DIST}/${NAME}" .
(cd "$DIST" && tar -czf "${ARCHIVE_FILE}" "${NAME}" && rm "${NAME}")
echo "  => dist/${ARCHIVE_FILE}"

# GitHub token required for release API
TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN is not set}"

echo ""
echo "==> Creating release ${TAG} on ${REPO}"

# Delete existing release + tag if present (idempotent re-run)
RELEASE_ID=$(curl -sf \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://api.github.com/repos/${REPO}/releases/tags/${TAG}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])" 2>/dev/null || true)

if [[ -n "$RELEASE_ID" ]]; then
  echo "  existing release found (id=${RELEASE_ID}), deleting..."
  curl -sf -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://api.github.com/repos/${REPO}/releases/${RELEASE_ID}"
  curl -sf -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://api.github.com/repos/${REPO}/git/refs/tags/${TAG}" || true
fi

# Create release
RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/${REPO}/releases" \
  -d "{\"tag_name\":\"${TAG}\",\"name\":\"${TAG}\",\"body\":\"Built from $(git rev-parse --short HEAD)\"}")

UPLOAD_URL=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['upload_url'])" | sed 's/{.*//')

echo "  uploading ${ARCHIVE_FILE} ..."
curl -sf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/gzip" \
  "${UPLOAD_URL}?name=${ARCHIVE_FILE}" \
  --data-binary "@${DIST}/${ARCHIVE_FILE}" > /dev/null

echo ""
echo "==> Done. Install with:"
echo "    npm install -g https://github.com/zhoumzh/lark-cli"
echo "    npx skills add https://github.com/zhoumzh/lark-cli -y -g"
