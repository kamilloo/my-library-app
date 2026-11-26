# Moja Biblioteka web release

Production runs at https://mojabiblioteka.app/app/. Follow the laptop and VPS steps in order, using Bash. Keep the laptop shell open so the release variables remain available. Coordinate one release operator at a time and complete device QA on an existing approved HTTPS staging origin before production activation.

## Architecture

| Repository | Release responsibility |
| --- | --- |
| [my-library-app](https://github.com/kamilloo/my-library-app) | Flutter source, browser entry point, offline worker template and web preparation script. The prepared output is `build/web/`. |
| [kamilpietka.github.io](https://github.com/kamilloo/kamilpietka.github.io) | Marketing and legal source in `mojabiblioteka/`. The packager assembles a complete document root. The independent portfolio builds into `public/`. |
| [kamilpietka-devops](https://github.com/kamilloo/kamilpietka-devops) | VPS Compose and Caddy configuration. The production Compose project is operated from `/opt/kamilpietka-devops`. |

Existing Cloudflare DNS and HTTPS deliver traffic through Caddy. The three Moja Biblioteka hostnames share the Caddy file server at `/srv/mojabiblioteka`, backed by the read-only bind mount from `/opt/portfolio/mojabiblioteka`. The portfolio has a separate mount from `/opt/portfolio/site`. Use the checked-in Compose mount and confirm the running mount before activation. The relative paths in the older infrastructure deployment examples differ from the current Compose file. Normal web releases require no DNS, Cloudflare, Caddyfile or database migration changes. [Task 35 hosting notes](https://github.com/kamilloo/kamilpietka.github.io/blob/main/docs/task35-mojabiblioteka.md) · [Compose](https://github.com/kamilloo/kamilpietka-devops/blob/main/compose.yml) · [Caddyfile](https://github.com/kamilloo/kamilpietka-devops/blob/main/Caddyfile)

The worker serves local app assets within `/app/`. SQLite runs in WASM with a browser worker and stores library data in IndexedDB. Keep the original HTTPS origin and browser profile when testing an upgrade. Aliases, staging, private browsing and other profiles can have separate storage. Export a `.mlbak` before moving a library to a different origin.

## 1. Prerequisites

- Laptop with the Flutter SDK and its bundled Dart. Use the versions pinned by the release checkout's CI. The current README lists Flutter 3.47.5 and Dart 3.13.4.
- Node.js 22 or newer, following the existing release baseline. The preparation script uses built-in Fetch and crypto, with no npm install or explicit Node version check. It needs network access to fetch the pinned ZXing distribution and license. Task 33 documented Node.js 20 or newer, while the production packaging notes use 22 or newer.
- Python 3, Git, Bash, OpenSSH, `rsync` and `curl` on the laptop. The VPS uses Bash, `rsync`, GNU coreutils, `mountpoint` and Docker Compose v2. For the origin HTTPS probe, use `curl` on the VPS.
- Obtain the SSH login, host or configured alias, port and host-key fingerprint from the VPS operator or approved infrastructure inventory. Check how an alias expands with `ssh -G "$VPS"` after setting the variable below. The alias `vouchers` depends on local SSH configuration. Public Cloudflare-proxied web hostnames may resolve to Cloudflare instead of the SSH origin. Verify the host key through the operator on first connection.

## 2. Build and prepare on the laptop

```bash
cd ~/projects/my-library-app
git status --short
git switch main
git pull --ff-only origin main
test -z "$(git status --porcelain)"
FLUTTER_COMMIT="$(git rev-parse HEAD)"
printf 'Flutter commit: %s\n' "$FLUTTER_COMMIT"
flutter --version
node --version

flutter pub get
flutter analyze
flutter test
dart run sqflite_common_ffi_web:setup
flutter build web --release \
  --no-web-resources-cdn \
  --base-href /app/
node tool/prepare_web.mjs

git status --short
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$FLUTTER_COMMIT"
git diff --check
```

Stop on a failed command or a dirty checkout. Resolve tracked changes before building or packaging, and keep the full SHA recorded with the release. The build tree and generated SQLite runtime in `web/` are ignored by Git.

The trailing slash in `/app/` makes relative Flutter assets and the service worker resolve inside the application directory. The CDN flag keeps Flutter's renderer resources local for offline startup. [The preparation script](../tool/prepare_web.mjs) downloads pinned ZXing JavaScript, checks its SHA-256, saves the license, and writes a sorted inventory into the worker template. The revision hashes the template plus each inventoried path and its bytes. Dot-prefixed filenames, source maps and the two top-level service worker scripts are excluded from the inventory.

Expect `index.html`, `entry.css`, `entry.js`, `flutter_bootstrap.js`, `main.dart.js`, `offline-worker.js`, `sqlite3.wasm`, `sqflite_sw.js`, `zxing.min.js`, `zxing-LICENSE.txt`, `canvaskit/canvaskit.wasm`, `manifest.webmanifest`, Flutter assets and fonts, `assets/assets/support.json` and the logo icons in `build/web/`. Rebuild and rerun preparation after any change to the build.

## 3. Package on the laptop

```bash
cd ~/projects/kamilpietka.github.io
git status --short
git switch main
git pull --ff-only origin main
test -z "$(git status --porcelain)"
test "$(git -C ../my-library-app rev-parse HEAD)" = "$FLUTTER_COMMIT"
test -z "$(git -C ../my-library-app status --porcelain)"

RELEASE_TAG="web-$(date -u +%Y%m%d-%H%M%S)"
RELEASE_DIR="/tmp/mojabiblioteka-${RELEASE_TAG}"
python3 scripts/package_mojabiblioteka.py \
  --web-build ../my-library-app/build/web \
  --flutter-commit "${FLUTTER_COMMIT:?Run the build section first}" \
  --output "$RELEASE_DIR"
cat "$RELEASE_DIR/release.json"
git rev-parse HEAD
```

Stop if any check fails. Record the website checkout SHA alongside the release tag. The [packager](https://github.com/kamilloo/kamilpietka.github.io/blob/main/scripts/package_mojabiblioteka.py) requires a new output directory so a release cannot overwrite an earlier package or inherit stale files. It copies the marketing site and legal pages, places the complete prepared build under `app/`, then writes root-level `release.json`. The metadata records the full 40-character `flutter_source_commit` supplied by the operator and the computed `offline_revision`. The script checks that the worker inventory matches the eligible files, verifies required paths, recomputes the hash from the template and build bytes, and checks the base href, manifest scope, support URL and legal entry points.

Deploy the complete package so the marketing and legal pages and every resource the worker expects are released together. A lone `main.dart.js` upload leaves other assets and the worker out of sync.

For a local smoke test, serve the assembled root with `python3 -m http.server 8080 --bind 127.0.0.1 --directory "$RELEASE_DIR"`. Open `http://127.0.0.1:8080/app/?app=1` and the legal routes. Use HTTPS staging and the device checklist for Safari, camera and update acceptance.

## 4. Upload a candidate from the laptop

Run each line only after the previous one succeeds. If `mkdir` fails, stop before running `rsync`. The trailing slash on the source uploads the package contents. The dry run checks content and reports extras. Its `--delete` option is used only with `--dry-run`.

```bash
VPS="root@YOUR_VPS_IP_OR_SSH_ALIAS"
CANDIDATE="/opt/portfolio/mojabiblioteka-candidate-${RELEASE_TAG:?Run packaging first}"

ssh "$VPS" "mkdir -m 0755 -- '$CANDIDATE'" &&
rsync -av -- "$RELEASE_DIR/" "$VPS:$CANDIDATE/" &&
rsync -rlcn --delete --itemize-changes -- "$RELEASE_DIR/" "$VPS:$CANDIDATE/" &&
(set -o pipefail; ssh "$VPS" "cat -- '$CANDIDATE/release.json'" | cmp "$RELEASE_DIR/release.json" -)
```

Expect no file changes in the dry run and a successful `cmp`. Keep the expected metadata and tag available for the VPS checks. Uploading a sibling directory leaves the live site unchanged.

## 5. Inspect and activate on the VPS

Connect from the laptop with `ssh "$VPS"`. On the VPS, set the release tag to the exact value printed or used on the laptop, then review the candidate and current tree.

```bash
RELEASE_TAG='web-YYYYMMDD-HHMMSS'
LIVE=/opt/portfolio/mojabiblioteka
CANDIDATE="/opt/portfolio/mojabiblioteka-candidate-$RELEASE_TAG"

cat "$CANDIDATE/release.json"
rsync -rlcn --delete --itemize-changes --exclude='/app/' \
  "$CANDIDATE/" "$LIVE/"
```

In this **dry run**, `*deleting` identifies live root files absent from the package. The checked-in configuration declares no required server-managed files inside this root. Task 35 records a manual preservation procedure, so inspect the live listing before each swap. If the operator confirms a public server-managed file or directory must survive, copy that specific path from live into the candidate with `cp -a`, after checking for conflicts, then verify it. Resolve any ambiguous differences before switching. Use the freshly packaged `app/` as a whole. Preserve the entire former live tree in the rollback directory, including any live-only files. Caddy configuration and certificate state live outside this document root.

Run the following in the same VPS shell. The preflight checks the rendered Compose configuration without printing production environment values. It confirms the existing container's Compose working directory and bind mount, verifies deployment paths, and reserves a unique rollback name using UTC plus a suffix. The empty backup directory serves as a reservation and is replaced by the old live directory. The two renames briefly leave the host path absent. The running container holds the old bind mount until recreated.

```bash
(
  set -euo pipefail
  [[ "$LIVE" = /opt/portfolio/mojabiblioteka ]]
  [[ "$CANDIDATE" = "/opt/portfolio/mojabiblioteka-candidate-$RELEASE_TAG" ]]
  [[ "$RELEASE_TAG" =~ ^web-[0-9]{8}-[0-9]{6}$ ]]
  cd /opt/kamilpietka-devops
  docker compose config --quiet
  docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile

  mount_format='{{range .Mounts}}{{if eq .Destination "/srv/mojabiblioteka"}}{{.Type}} {{.Source}} {{.RW}}{{end}}{{end}}'
  expected_mount="bind $LIVE false"
  check_mount() {
    local container
    container="$(docker compose ps -q caddy)" || return 1
    [[ -n "$container" ]] || return 1
    [[ "$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$container")" = "$PWD" ]] || return 1
    [[ "$(docker inspect --format "$mount_format" "$container")" = "$expected_mount" ]]
  }
  check_mount

  for directory in "$LIVE" "$CANDIDATE"; do
    test -d "$directory"
    test "$(realpath -- "$directory")" = "$directory"
    if mountpoint -q -- "$directory"; then
      printf 'Unexpected mount point: %s\n' "$directory" >&2
      exit 1
    fi
    test "$(stat -c %d -- "$directory")" = "$(stat -c %d -- /opt/portfolio)"
  done
  df -P -- /opt/portfolio "$LIVE" "$CANDIDATE"
  for path in index.html privacy/index.html terms/index.html returns/index.html \
    release.json app/index.html app/offline-worker.js app/main.dart.js \
    app/flutter_bootstrap.js app/sqlite3.wasm app/sqflite_sw.js; do
    test -s "$CANDIDATE/$path"
  done

  stamp="$(date -u +%Y%m%d-%H%M%S)"
  BACKUP="$(mktemp -d "/opt/portfolio/mojabiblioteka-backup-$stamp-XXXXXX")"
  printf 'Record rollback path: %s\n' "$BACKUP"
  mv -T -- "$LIVE" "$BACKUP"
  if ! mv -T -- "$CANDIDATE" "$LIVE"; then
    if ! mv -T -- "$BACKUP" "$LIVE"; then
      printf 'Restore the live path from %s before recreating Caddy.\n' "$BACKUP" >&2
    fi
    exit 1
  fi

  docker compose up -d --no-deps --force-recreate caddy
  docker compose ps caddy
  check_mount
)
```

Recreating only Caddy may briefly interrupt shared HTTPS, including the portfolio and Vouchers routes. Compose currently defines no Caddy healthcheck. Confirm that the container is running, the mount is correct and the HTTP checks pass. If activation fails after renaming, keep both trees and use the rollback procedure. If the session disconnects mid-swap, inspect which directory names exist before retrying. If the live path is missing, restore it from the printed rollback path before recreating Caddy.

Optionally verify the origin from the VPS when Caddy is up. This bypasses Cloudflare while keeping the correct host and TLS SNI. If the origin uses a private certificate authority, use the operator-provided CA with `--cacert`.

```bash
(
  set -euo pipefail
  curl -fsS --retry 3 --resolve mojabiblioteka.app:443:127.0.0.1 \
    https://mojabiblioteka.app/release.json | cmp "$LIVE/release.json" -
)
```

## 6. Verify public HTTP from the laptop

This uses GET, checks for HTTP 200 without following redirects, validates asset MIME types, and checks that missing app resources return 404. Run it in the laptop shell with the packaged release still available.

```bash
(
  set -euo pipefail
  BASE=https://mojabiblioteka.app
  probe() {
    local url="$1" expected="$2" mime="${3:-}" response
    response="$(curl -sS --max-time 30 -o /dev/null \
      -w '%{http_code} %{content_type}' "$url")"
    printf '%s %s\n' "$response" "$url"
    [[ "$response" = "$expected "* ]] || return 1
    [[ -z "$mime" || "${response#* }" =~ $mime ]]
  }
  JS='^(application|text)/(javascript|ecmascript)(;|$)'
  WASM='^application/wasm(;|$)'
  for route in / /app/ /release.json /privacy/ /terms/ /returns/; do
    probe "$BASE$route" 200
  done
  for asset in offline-worker.js main.dart.js flutter_bootstrap.js sqflite_sw.js; do
    probe "$BASE/app/$asset" 200 "$JS"
  done
  probe "$BASE/app/sqlite3.wasm" 200 "$WASM"
  probe "$BASE/app/canvaskit/canvaskit.wasm" 200 "$WASM"
  probe "$BASE/app/nonexistent-release-smoke-test.js" 404
  probe https://kamilpietka.dev/ 200
  curl -fsS "$BASE/release.json" | cmp "$RELEASE_DIR/release.json" -
  curl -fsS "$BASE/app/offline-worker.js" | cmp "$RELEASE_DIR/app/offline-worker.js" -
  curl -fsS "$BASE/app/main.dart.js" | cmp "$RELEASE_DIR/app/main.dart.js" -
)
```

The metadata comparison covers the entire commit and offline revision. A mismatch in an asset at a stable URL can reveal a stale response even when metadata matches. Check the portfolio's project links in a browser too.

## 7. Device QA

Run this on **Android Chrome** and a **physical iPhone in Safari**. Android Chrome cannot substitute for iPhone Safari. Record device, OS and browser versions, origin, commit and offline revision. Open `/app/?app=1` on Android Chrome for web QA. On iPhone Safari, open `/app/`.

- [ ] Open the app online and wait for **Zasoby do pracy offline są gotowe**. With remote developer tools, `await window.mojaBibliotekaOfflineReady()` checks the currently controlling worker's inventory.
- [ ] Search Open Library online and use **Pobierz dane książki** with a known ISBN.
- [ ] Go offline, add a book manually and verify existing books remain visible.
- [ ] Close the app tab and browser, then reopen the same URL and profile while offline. Confirm the added book and existing data persist in IndexedDB. Reconnect after the check.
- [ ] On supported devices, grant camera access and test ISBN barcode and loan QR scanning.
- [ ] Export a `.mlbak` and confirm the file was saved, for example in Files on iPhone. Use test data or safeguard personal backups.
- [ ] Open the marketing page and all three legal routes online.
- [ ] Upgrade a previous release with a test collection on the same origin. Confirm the new worker activates and the collection remains available.

See the [iPhone Safari acceptance notes](task33_iphone_safari.md) for device-specific coverage.

## 8. Worker updates and caching

The app checks for worker updates while online. A new worker precaches the entire revision before it can activate. It waits for clients of the previous worker to close, then removes older app caches and claims clients. Close all app tabs and any standalone instance on that origin, then reopen online. Confirm offline readiness before disconnecting. Cache Storage in browser developer tools shows keys starting with `moja-biblioteka:` and ending with the revision. Compare the active revision with public `release.json`.

If a device stays on an older revision, inspect the worker's installing, waiting and active states and look for failed precache requests. Check the Network panel for missing assets or stale responses. The registration bypasses the browser HTTP cache for worker update checks, but Cloudflare can still serve a cached response. Compare the public worker and asset bytes with the package and with the origin, and inspect `Cache-Control`, `Age` and `CF-Cache-Status` with `curl -sSI URL`. Stable URLs need to revalidate. If the edge serves mixed or stale bytes, use the existing Cloudflare cache operations with the operator for the affected URLs and retest. Routine releases use the existing configuration.

Keep website data intact during diagnosis. Clearing website data may delete the IndexedDB book collection. Export and verify a `.mlbak` before any browser storage reset.

## 9. Roll back on the VPS

Use the rollback directory recorded during activation. List available backups and inspect the chosen metadata before proceeding. An older pre-packaging backup may lack `release.json`. In that case, verify known prior files and routes and expect metadata to be absent.

```bash
ls -ld /opt/portfolio/mojabiblioteka-backup-*
BACKUP='/opt/portfolio/mojabiblioteka-backup-REPLACE_WITH_RECORDED_NAME'
if test -f "$BACKUP/release.json"; then cat "$BACKUP/release.json"; fi
```

After confirming the previous directory, verify its expected app and legal files against the prior release. Then run in the same VPS shell.

```bash
(
  set -euo pipefail
  cd /opt/kamilpietka-devops
  docker compose config --quiet
  LIVE=/opt/portfolio/mojabiblioteka
  [[ "$BACKUP" =~ ^/opt/portfolio/mojabiblioteka-backup-[^/]+$ ]]
  for directory in "$LIVE" "$BACKUP"; do
    test -d "$directory"
    test "$(realpath -- "$directory")" = "$directory"
    if mountpoint -q -- "$directory"; then exit 1; fi
    test "$(stat -c %d -- "$directory")" = "$(stat -c %d -- /opt/portfolio)"
  done
  test -s "$BACKUP/index.html"

  stamp="$(date -u +%Y%m%d-%H%M%S)"
  FAILED="$(mktemp -d "/opt/portfolio/mojabiblioteka-failed-$stamp-XXXXXX")"
  printf 'Failed release retained at: %s\n' "$FAILED"
  mv -T -- "$LIVE" "$FAILED"
  if ! mv -T -- "$BACKUP" "$LIVE"; then
    if ! mv -T -- "$FAILED" "$LIVE"; then
      printf 'Restore the live path from %s before recreating Caddy.\n' "$FAILED" >&2
    fi
    exit 1
  fi
  docker compose up -d --no-deps --force-recreate caddy
  docker compose ps caddy
  container="$(docker compose ps -q caddy)"
  test -n "$container"
  test "$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/srv/mojabiblioteka"}}{{.Type}} {{.Source}} {{.RW}}{{end}}{{end}}' "$container")" = "bind $LIVE false"
  if test -f "$LIVE/release.json"; then cat "$LIVE/release.json"; fi
)
```

From the laptop, repeat the public checks with `RELEASE_DIR` pointing at the previous local package. If its local copy is unavailable, compare the restored VPS metadata directly.

```bash
(
  set -euo pipefail
  restored="$(ssh "$VPS" 'cat /opt/portfolio/mojabiblioteka/release.json')"
  served="$(curl -fsS https://mojabiblioteka.app/release.json)"
  test -n "$restored"
  diff -u <(printf '%s\n' "$restored") <(printf '%s\n' "$served")
)
```

Also check the marketing, app, legal, asset and portfolio routes from section 6. For a pre-packaging backup, adapt the route and asset expectations to that release. Close and reopen app tabs online so the rollback worker can take control. Server rollback restores the static site only. Browser-local book data stays in its existing IndexedDB store.

## 10. Troubleshooting

| Symptom | Diagnostics and recovery |
| --- | --- |
| SSH hostname fails to resolve | Check the expanded hostname with `ssh -G "$VPS"`. Use the operator-confirmed SSH address or a configured alias. Verify the fingerprint if it changes. |
| Upload fails | Check SSH access, `rsync` on both ends, VPS permissions and space with `df -h /opt/portfolio`. If the partial candidate is known to be yours, rerun the same upload and checksum dry run. Otherwise stage with a fresh tag. |
| Candidate or package directory exists | Stop and inspect it. Allocate a fresh tag and matching paths for a new attempt. Leave other candidates in place. |
| Offline inventory validation fails | Confirm the build path and the required files. Rerun SQLite setup if its runtime is missing, rebuild and prepare again. A hash mismatch means build bytes or the worker changed; discard that packaging attempt and package from a fresh build. |
| Wrong Flutter base path | Inspect the HTML's `base` element and the browser's asset URLs. Rebuild with `--base-href /app/` and repackage. |
| JS or WASM returns 404 | Check the named file in the packaged tree, the Caddy mount and origin response. Check the request's path in Network. Restore a complete verified package if the live tree is incomplete. |
| Wrong MIME type | Inspect GET status, content type and body at the edge and origin. A JavaScript or WASM URL returning HTML indicates a wrong path, redirect or error response. Compare bytes and verify the mount before investigating infrastructure changes. |
| Browser shows an older release | Compare metadata and exact worker/asset bytes. Inspect worker state and Cache Storage. Close all old app clients and reopen online. Follow section 8 for stale edge responses. |
| Open Library fails online | Inspect the actual request in the browser's Network panel for DNS, HTTP, CORS, rate limiting or timeout errors. Compare on another network and retry once connectivity or the upstream issue is resolved. Manual entry remains available. |
| Device appears offline on a working network | Check actual app asset and Open Library requests separately. Verify the active worker's readiness, browser network settings, developer tools offline emulation and captive portal status. Reopen online once requests work. |
| Caddy fails after activation | From the Compose directory, run `docker compose ps -a caddy` and `docker compose logs --tail=100 caddy`. Check the bind source exists and inspect startup errors. Restore the recorded backup and recreate only Caddy if service cannot be recovered promptly. |
