#!/bin/sh
# Produces an unsigned Release build of Chessanto and prints its path.
#
# This script never signs or notarizes anything - see README.md's "Release
# builds, signing, and notarization" section for those steps, which use
# your own Developer ID and are meant to be run by hand.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "fetching NNUE networks (no-op if already present) ..."
scripts/fetch-nnue.sh

echo "regenerating Xcode project ..."
xcodegen generate

echo "building Chessanto (Release) ..."
xcodebuild -scheme Chessanto -project Chessanto.xcodeproj -configuration Release build

app_path=$(
    xcodebuild -scheme Chessanto -project Chessanto.xcodeproj -configuration Release \
        -showBuildSettings 2>/dev/null \
        | awk -F'= ' '/ BUILT_PRODUCTS_DIR/ { print $2; exit }'
)

echo ""
echo "Unsigned Release build ready:"
echo "  $app_path/Chessanto.app"
echo ""
echo "This build runs locally as-is. To distribute it to other people, sign"
echo "and notarize it with your own Developer ID - see README.md."
