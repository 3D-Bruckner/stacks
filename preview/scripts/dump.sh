#!/usr/bin/env bash
# One copy of preview's data into ../data/dumps, and the old copies of the same kind removed.
#
#   dump.sh <kind> <days to keep>      e.g.  dump.sh hourly 1
#
# Each run makes a folder <kind>-<time>/ with preview.sqlite (customers, their links, models, versions), auth.sqlite (sign-in,
# sessions, API tokens, connected clients) and files/ (each version's model.3mf, preview.png and drawings). The databases are
# consistent `sqlite3 .backup` copies taken while preview writes (needs sqlite3 on the host, and to run as the user the container
# runs as, 1000), checked with PRAGMA integrity_check. The files are hard links: preview writes a version's files into a new folder
# of their own and never changes one afterwards, so a link keeps the file as it is and costs no space. The files are linked first:
# preview writes a version's files before its row, so every row in the copy has its files. The folder gets its real name only once
# all of it is whole; old folders of the kind are removed only after a new one succeeded. The secret is not in a dump: on the
# server it is PREVIEW_SECRET in the deployment's vault. The logo (brand/) is not either: the deployment writes it.
#
# To restore, with preview stopped (docker compose stop preview; docker compose start preview afterwards):
#   rm -f data/preview.sqlite-wal data/preview.sqlite-shm data/auth.sqlite-wal data/auth.sqlite-shm
#   cp data/dumps/<kind>-<time>/preview.sqlite data/dumps/<kind>-<time>/auth.sqlite data/
#   rm -rf data/files && cp -a data/dumps/<kind>-<time>/files data/files
set -euo pipefail

kind=${1:?the kind of dump, e.g. hourly}
keep_days=${2:?how many days to keep dumps of this kind}
[[ $kind =~ ^[a-z][a-z0-9-]*$ ]] || { echo "dump: the kind may hold only a-z, 0-9 and -" >&2; exit 2; }
[[ $keep_days =~ ^[0-9]+$ ]] || { echo "dump: the days to keep must be a number" >&2; exit 2; }

data=${DUMP_DATA_DIR:-$(cd "$(dirname "$0")/.." && pwd)/data}
dir="$data/dumps"

umask 077
mkdir -p "$dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out="$dir/$kind-$stamp"
tmp="$out.tmp"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp"

# The files: hard links, folder by folder (files/<model>/<version>/…).
mkdir "$tmp/files"
if [[ -d $data/files ]]; then
  (cd "$data/files" && find . -type f ! -name '.*') |
    while IFS= read -r f; do
      mkdir -p "$tmp/files/$(dirname "$f")"
      ln "$data/files/$f" "$tmp/files/$f"
    done
fi

for db in preview auth; do
  [[ -f $data/$db.sqlite ]] || { echo "dump: $data/$db.sqlite is missing" >&2; exit 1; }
  sqlite3 "$data/$db.sqlite" ".backup '$tmp/$db.sqlite'"
  [[ $(sqlite3 "$tmp/$db.sqlite" 'PRAGMA integrity_check;') == ok ]] || { echo "dump: the copy of $db.sqlite is not intact" >&2; exit 1; }
done
mv "$tmp" "$out"

# Older than the days to keep, of this kind only; never the one just made.
find "$dir" -maxdepth 1 -mindepth 1 -type d -name "$kind-*Z" ! -path "$out" -mmin +$((keep_days * 1440)) -exec rm -rf {} +
echo "dump: $(basename "$out")"
