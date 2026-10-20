# Vikunja for Sailfish OS

A native Sailfish OS (Qt 5.6 / QML / Silica) port of the Vikunja mobile app.
It talks to your own Vikunja server (0.24 or newer) over its REST API.

## Install (sideload)

1. On the phone, allow untrusted software: **Settings → Untrusted software**.
2. Copy `harbour-vikunja-<version>.aarch64.rpm` to the phone (the Jolla C2 and
   current Jolla phones are aarch64; use `armv7hl` for older 32-bit devices and
   `i486` for the SDK emulator).
3. Tap the file in the file manager, or over SSH:
   `devel-su pkcon install-local harbour-vikunja-0.1.0-1.aarch64.rpm`
4. Open **Vikunja**, enter your server address and either an API token
   (Vikunja web app → Settings → API Tokens) or your username and password.

## What it does

| Area | Status |
|---|---|
| Server check (version, HTTPS), API-token login, password + TOTP login | Done |
| Upcoming tasks (overdue / today / tomorrow / later), mark done | Done |
| Projects: tree with sub-projects, create, edit, archive, delete | Done |
| Project list view with done/undone toggle and paging | Done |
| Kanban: buckets, move tasks between buckets, add/rename/limit/delete buckets, add task to a bucket | Done |
| Task detail and edit: title, description, done, project, due/start/end dates, reminders, repeat, priority, progress, colour | Done |
| Labels: assign/unassign, create, delete | Done |
| Comments: list, add, edit, delete own | Done |
| Attachments: list and save to Downloads (with confirmation), open | Done |
| Cover: upcoming and overdue count, next tasks, "New task" and "Refresh" actions | Done |
| Reminder and due-date notifications with "Mark done" | While the app runs (also minimised) |
| OAuth browser login (the Android app's method) | Not yet; API token or password login instead |
| Background sync / reminders with the app closed | Not yet (planned as a sideload-only helper) |
| Home-screen widget, quick-settings tile | Not available on Sailfish; the cover replaces them |
| Share text into a new task | Not yet |
| Rich-text editor | Descriptions render formatted, edit as plain text |

## Security model

| Data | Where it lives | Protection |
|---|---|---|
| API token | Sailfish Secrets collection `harbourvikunja` | Encrypted storage plugin, unlocked with the device lock, owner-only access. If Secrets is unavailable the token is kept in memory only and you sign in on each start. |
| Password, TOTP code | Never stored | Used once to create a scoped API token (projects, tasks, labels, comments, attachments, own user), valid one year and revocable in the web app. |
| Tasks, projects, comments | Memory only | No offline cache and no HTTP disk cache. Nothing about your tasks is written to the phone. |
| Server URL, preferences, pinned certificate fingerprints | `~/.config/io.github.manojgudi/harbour-vikunja/` | Private to the app under sailjail; created with mode 0600 (`umask 077`). Not secret. |
| Attachments | `~/Downloads`, only when you confirm | The dialog tells you the file becomes readable by other apps. File names from the server are sanitised (no path traversal). |

Network:

* TLS 1.2+ with normal certificate validation. A self-signed server is only
  accepted after you compare and trust its SHA-256 fingerprint; only that exact
  certificate is accepted for that host and port afterwards (trust on first use).
* Plain `http://` is refused unless the host is loopback or you explicitly allow
  it for that host after a warning.
* Redirects are not followed, so the token is only ever sent to your server.
* Requests time out after 20 seconds.

Other:

* The app runs in the sailjail sandbox with only `Internet`, `Notifications`,
  `Secrets` and `Downloads` permissions.
* The QML engine has no network access, so task descriptions and comments can
  never load remote images or trackers; their HTML is also sanitised.
* Log output is passed through a redaction filter (bearer tokens, `tk_…` API
  tokens, JWTs, password fields), and debug logging is off in release builds.
* The D-Bus entry point used by notification actions only marks a task done
  when the call comes from the notification server.
* No telemetry or crash reporting.

## Build

With the Sailfish SDK (5.x):

```sh
cd sailfish
sfdk config target=SailfishOS-5.2.0.15-aarch64   # or: mb2 -t <target> build
sfdk build
```

`third_party/sailfish-secrets` holds the public headers of libsailfishsecrets
0.2.44 (BSD-3-Clause), because the SDK targets ship the library but not its
`-devel` package.

## Tests

* `tests/` — unit tests for URL normalisation, HTML sanitising, file-name
  sanitising, log redaction and version checks, plus integration tests against a
  live server (full CRUD, kanban moves, attachments, TLS pinning against a
  self-signed server, password login creating a scoped token). Set
  `VIKUNJA_TEST_URL`, `VIKUNJA_TEST_TOKEN` and optionally `VIKUNJA_TEST_USER`,
  `VIKUNJA_TEST_PASSWORD`, `VIKUNJA_TEST_TLS_URL`, `VIKUNJA_TEST_TLS_SHA256`,
  `VIKUNJA_TEST_ATTACHMENT=<taskId>:<attachmentId>`.
* `tests/qmlsmoke/` — loads the real QML with the real C++ backend on the
  `minimal` Qt platform and walks through every page against a live server,
  failing on any QML warning or JavaScript error. Nothing is rendered, so it
  does not replace checking the layout on a device.
