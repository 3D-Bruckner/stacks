#!/usr/bin/env bash
# One copy of portfolio's data into ../data/dumps, and the old copies of the same kind removed.
#
#   dump.sh <kind> <days to keep>      e.g.  dump.sh hourly 1
#
# Each run makes a folder <kind>-<time>/ with upload.sqlite (the prints), auth.sqlite (sign-in, sessions, passkeys, tokens,
# connected clients) and photos/ (originals and cutouts; thumbnails are left out, upload makes them again). The databases are
# consistent `sqlite3 .backup` copies taken while upload writes (needs sqlite3 on the host, and to run as the user the container
# runs as, 1000), checked with PRAGMA integrity_check. The photos are hard links: upload writes a photo under a temporary name and
# renames it into place, never changing a file, so a link keeps the photo as it was and costs no space. The photos are copied first:
# upload writes a photo's files before its row, so every row in the copy has its files. The folder gets its real name only once all
# of it is whole; old folders of the kind are removed only after a new one succeeded. The secret is not in a dump: on the server it is
# PORTFOLIO_SECRET in the deployment's vault.
#
# To restore, with upload stopped (docker compose stop portfolio; docker compose start portfolio afterwards):
#   rm -f data/upload.sqlite-wal data/upload.sqlite-shm data/auth.sqlite-wal data/auth.sqlite-shm
#   cp data/dumps/<kind>-<time>/upload.sqlite data/dumps/<kind>-<time>/auth.sqlite data/
#   rm -rf data/photos && cp -a data/dumps/<kind>-<time>/photos data/photos
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

# The photos: hard links of the originals and cutouts, folder by folder; no thumbnails, no half-written temporary files.
mkdir "$tmp/photos"
if [[ -d $data/photos ]]; then
  (cd "$data/photos" && find . -type f -name '*.jpg' ! -name '*.thumb.*' ! -name '.*' -o -type f -name '*.orig.*' ! -name '.*') |
    while IFS= read -r f; do
      mkdir -p "$tmp/photos/$(dirname "$f")"
      ln "$data/photos/$f" "$tmp/photos/$f"
    done
fi

for db in upload auth; do
  [[ -f $data/$db.sqlite ]] || { echo "dump: $data/$db.sqlite is missing" >&2; exit 1; }
  sqlite3 "$data/$db.sqlite" ".backup '$tmp/$db.sqlite'"
  [[ $(sqlite3 "$tmp/$db.sqlite" 'PRAGMA integrity_check;') == ok ]] || { echo "dump: the copy of $db.sqlite is not intact" >&2; exit 1; }
done
mv "$tmp" "$out"

# Older than the days to keep, of this kind only; never the one just made.
find "$dir" -maxdepth 1 -mindepth 1 -type d -name "$kind-*Z" ! -path "$out" -mmin +$((keep_days * 1440)) -exec rm -rf {} +
echo "dump: $(basename "$out")"
