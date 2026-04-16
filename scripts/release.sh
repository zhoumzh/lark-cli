#!/usr/bin/env bash
# Build binaries for all platforms, create a GitHub release on origin (zhoumzh/lark-cli),
# and upload the archives.
#
# Usage:
#   ./scripts/release.sh            # uses version from git describe
#   ./scripts/release.sh v1.0.12    # explicit version tag

set -euo pipefail

NAME="lark-cli"
MODULE="github.com/larksuite/cli"
VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
DATE="$(date +%Y-%m-%d)"
LDFLAGS="-s -w -X ${MODULE}/internal/build.Version=${VERSION} -X ${MODULE}/internal/build.Date=${DATE}"

PLATFORMS=(
  "darwin   arm64"
  "darwin   amd64"
  "linux    amd64"
  "linux    arm64"
  "windows  amd64"
)

DIST="dist"
rm -rf "$DIST" && mkdir -p "$DIST"

echo "==> Building version ${VERSION}"

python3 scripts/fetch_meta.py

for entry in "${PLATFORMS[@]}"; do
  OS=$(echo "$entry" | awk '{print $1}')
  ARCH=$(echo "$entry" | awk '{print $2}')

  BIN="${NAME}"
  [[ "$OS" == "windows" ]] && BIN="${NAME}.exe"

  ARCHIVE="${NAME}-${VERSION#v}-${OS}-${ARCH}"
  [[ "$OS" == "windows" ]] && ARCHIVE_FILE="${ARCHIVE}.zip" || ARCHIVE_FILE="${ARCHIVE}.tar.gz"

  echo "  building ${OS}/${ARCH} ..."
  GOOS="$OS" GOARCH="$ARCH" go build -trimpath -ldflags "$LDFLAGS" -o "${DIST}/${BIN}" .

  if [[ "$OS" == "windows" ]]; then
    (cd "$DIST" && zip -q "${ARCHIVE_FILE}" "${BIN}" && rm "${BIN}")
  else
    (cd "$DIST" && tar -czf "${ARCHIVE_FILE}" "${BIN}" && rm "${BIN}")
  fi
  echo "  => dist/${ARCHIVE_FILE}"
done

echo ""
echo "==> Creating GitHub release ${VERSION} on origin"

# Strip leading 'v' for tag if not already present
TAG="${VERSION}"
[[ "$TAG" != v* ]] && TAG="v${TAG}"

gh release create "$TAG" \
  --repo zhoumzh/lark-cli \
  --title "$TAG" \
  --notes "Built from local source at $(git rev-parse --short HEAD)" \
  dist/*.tar.gz dist/*.zip 2>/dev/null || true

# If release already exists, just upload assets
gh release upload "$TAG" dist/*.tar.gz dist/*.zip \
  --repo zhoumzh/lark-cli \
  --clobber 2>/dev/null || true

echo ""
echo "==> Done. Install with:"
echo "    npm install -g https://github.com/zhoumzh/lark-cli"
echo "    npx skills add https://github.com/zhoumzh/lark-cli -y -g"
