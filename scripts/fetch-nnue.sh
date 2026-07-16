#!/bin/sh
# Fetches the Stockfish 17 NNUE networks into App/Resources/.
#
# chesskit-engine compiles Stockfish with NNUE_EMBEDDING_OFF and Stockfish 17
# has no classical-eval fallback: if a search starts with no network loaded,
# Stockfish exit()s the host process. These files are therefore REQUIRED for
# all engine work (app and engine-smoke alike). They are gitignored because
# of their size; a network's filename is the first 12 hex chars of its
# sha256, which this script verifies after download.
set -eu

dir="$(cd "$(dirname "$0")/.." && pwd)/App/Resources"
mkdir -p "$dir"

for net in nn-1111cefa1111 nn-37f18f62d772; do
    out="$dir/$net.nnue"
    expected="${net#nn-}"
    if [ -f "$out" ] && [ "$(shasum -a 256 "$out" | cut -c1-12)" = "$expected" ]; then
        echo "$net.nnue already present and verified"
        continue
    fi
    echo "fetching $net.nnue ..."
    curl -sSfL -o "$out" "https://data.stockfishchess.org/nn/$net.nnue"
    got="$(shasum -a 256 "$out" | cut -c1-12)"
    if [ "$got" != "$expected" ]; then
        rm -f "$out"
        echo "hash mismatch for $net.nnue (got $got, expected $expected)" >&2
        exit 1
    fi
    echo "$net.nnue fetched and verified"
done
