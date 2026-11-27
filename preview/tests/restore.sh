#!/usr/bin/env bash
# A dump restores preview whole: runs the image on an empty data folder, makes a customer, a model and a version through the API,
# takes a dump with scripts/dump.sh, restores it into a second data folder the way dump.sh's header says, starts a second container
# on that alone, and checks that the version list, the customer's page and the model's file are the same there.
#
#   preview/tests/restore.sh [image]      (default ghcr.io/3d-bruckner/preview:main; needs docker, sqlite3, curl, python3, root)
#
# The 3MF and the PNG are preview's own test fixtures, fetched from its repository.
set -euo pipefail

image=${1:-ghcr.io/3d-bruckner/preview:main}
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
names=()
cleanup() { for n in "${names[@]}"; do docker rm -f "$n" >/dev/null 2>&1 || true; done; rm -rf "$work"; }
trap cleanup EXIT

fixtures=https://github.com/3D-Bruckner/preview/raw/main/backend/fixtures
curl -fsSL -o "$work/ramp.3mf" "$fixtures/ramp.3mf"
curl -fsSL -o "$work/preview.png" "$fixtures/preview.png"

# A way in must exist for preview to start; this SMTP server is never contacted, nobody signs in here.
cat >"$work/env" <<'ENV'
PUBLIC_URL=https://preview.test
PREVIEW_SECRET=a-test-secret-of-at-least-thirty-two-characters
PREVIEW_ALLOWED_EMAILS=test@example.org
PREVIEW_SMTP_URL=smtps://u:p@smtp.invalid:465
PREVIEW_SMTP_FROM=Test <noreply@example.org>
ENV

# start <name> <data dir> <host port>: runs preview and waits for /health.
start() {
  names+=("$1")
  docker run -d --name "$1" --env-file "$work/env" -v "$2:/data" -p "127.0.0.1:$3:3000" "$image" >/dev/null
  for _ in $(seq 60); do curl -fsS "http://127.0.0.1:$3/health" >/dev/null 2>&1 && return; sleep 1; done
  docker logs "$1" >&2; echo "restore: $1 did not answer" >&2; exit 1
}

mkdir -p "$work/a" "$work/b"
start preview-restore-a "$work/a" 38084
a=http://127.0.0.1:38084

token=$(docker exec -u 1000 preview-restore-a /nodejs/bin/node node_modules/next-app-kit/dist/cli.js token \
  --prefix PREVIEW --token-prefix preview_ --email test@example.org --name restore-test --scope read+write --days 1 | grep -o 'preview_[A-Za-z0-9_-]*')
auth=(-H "Authorization: Bearer $token")
json() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

customer=$(curl -fsS "${auth[@]}" -H 'Content-Type: application/json' -d '{"name":"Restore test"}' $a/api/v1/customers | json "['id']")
model=$(curl -fsS "${auth[@]}" -H 'Content-Type: application/json' -d "{\"customerId\":\"$customer\",\"title\":\"Ramp\"}" $a/api/v1/models | json "['id']")
link=$(curl -fsS "${auth[@]}" -F model=@"$work/ramp.3mf" -F preview=@"$work/preview.png" -F note="2 cm wider" \
  "$a/api/models/$model/versions" | json "['link']")
path=${link#https://preview.test}
version=$(curl -fsS "${auth[@]}" "$a/api/v1/models/$model/versions" | json "['versions'][0]['id']")
token_path=${path%/*}

DUMP_DATA_DIR="$work/a" "$here/scripts/dump.sh" restore-test 1 >/dev/null
dump=$(ls -d "$work/a/dumps/restore-test-"*Z)

# The restore, as dump.sh's header has it.
cp "$dump/preview.sqlite" "$dump/auth.sqlite" "$work/b/"
cp -a "$dump/files" "$work/b/files"
chown -R 1000:1000 "$work/b"
start preview-restore-b "$work/b" 38085
b=http://127.0.0.1:38085

same() { [[ $2 == "$3" ]] || { echo "restore: $1 differs" >&2; exit 1; }; }
versions() { curl -fsS "${auth[@]}" "$1/api/v1/models/$model/versions"; }
same "the version list" "$(versions $a)" "$(versions $b)"
page() { curl -fsS "$1$path" | grep -o '2 cm wider' | head -1; }
[[ -n $(page $a) ]] || { echo "restore: the page before the dump has no note" >&2; exit 1; }
same "the customer's page" "$(page $a)" "$(page $b)"
file() { curl -fsS "$1$token_path/files/$version/model.3mf" | sha256sum; }
same "the model's file" "$(file $a)" "$(cat "$work/ramp.3mf" | sha256sum)"
same "the restored model's file" "$(file $b)" "$(file $a)"
echo "restore: ok"
