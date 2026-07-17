#!/bin/sh
# Fetches the lichess-org/chess-openings dataset (CC0-1.0, public domain) and
# converts the 5 TSVs into a single JSON array of {eco, name, pgn}, written
# to Packages/AnalysisKit/Sources/AnalysisKit/Resources/eco.json.
#
# The committed eco.json is network-free at build time; this script exists
# only for regenerating it (e.g. if the upstream dataset is updated).
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Packages/AnalysisKit/Sources/AnalysisKit/Resources/eco.json"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for letter in a b c d e; do
    echo "fetching $letter.tsv ..."
    curl -sSfL -o "$tmp/$letter.tsv" "https://raw.githubusercontent.com/lichess-org/chess-openings/master/$letter.tsv"
done

python3 - "$tmp" "$out" <<'PY'
import csv
import json
import sys

tmp_dir, out_path = sys.argv[1], sys.argv[2]
entries = []
for letter in "abcde":
    with open(f"{tmp_dir}/{letter}.tsv", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            entries.append({"eco": row["eco"], "name": row["name"], "pgn": row["pgn"]})

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=False, indent=0, separators=(",", ":"))

print(f"wrote {len(entries)} entries to {out_path}")
PY

index_out="$root/Packages/AnalysisKit/Sources/AnalysisKit/Resources/eco-index.json"
echo "precomputing eco-index.json (replays every line through ChessGame) ..."
(cd "$root/Packages/AnalysisKit" && swift run -c release eco-indexer "$out" "$index_out")

