# Vikunja for Sailfish OS

A native Sailfish OS (Qt 5.6 / QML / Silica) port of the Vikunja mobile app.
It talks to your own Vikunja server (0.24 or newer) over its REST API.

## Install (sideload)

1. On the phone, allow untrusted software: **Settings → Untrusted software**.
2. Copy `harbour-vikunja-<version>.aarch64.rpm` to the phone (the Jolla C2 and
   current Jolla phones are aarch64; use `armv7hl` for older 32-bit devices and
   `i486` for the SDK emulator).
3. Tap the file in the file manager, or over SSH:
   `devel-su pkcon install-local harbour-vikunja-0.2.5-1.aarch64.rpm`
4. Open **Vikunja**, enter your server address, username and password. If
   your account uses two-factor authentication, the app asks for the code next.

## What it does

| Area | Status |
|---|---|
| Server check (version, HTTPS); username + password login, then a two-factor step when the account needs it | Done |
| Stays signed in; signs out after 30 days without opening the app | Done |
| Upcoming tasks (overdue / today / tomorrow / later), mark done | Done |
| Projects: tree with sub-projects, create, edit, archive, delete | Done |
| Projects open as a kanban board (Trello-style columns); list view one pull-down away, remembered per project | Done |
| Kanban: move tasks between buckets, add/rename/limit/delete buckets, add task to a bucket | Done |
| Task detail and edit: title, description, done, project, due/start/end dates, reminders, repeat, priority, progress, colour | Done |
| Date and time in one dialog; quick presets (today, tomorrow, next Monday, ...) stay editable | Done |
| Labels: assign/unassign, create, delete | Done |
| Comments: list, add, edit, delete own | Done |
| Attachments: attach photos or files from the phone, view images in the app, save to Downloads, delete | Done |
| Cover: upcoming and overdue count, next tasks, "New task" and "Refresh" actions | Done |
| Reminder and due-date notifications with "Open" and "Mark done" | Done, also with the app closed (scheduled with timed) |
| Light / dark / ambience theme | Done |
| OAuth browser login | Not yet |
| Home-screen widget, quick-settings tile | Not available on Sailfish; the cover replaces them |
| Share text into a new task | Not yet |
| Rich-text editor | Descriptions render formatted, edit as plain text |

### Reminders with the app closed

When tasks change, the app hands every upcoming due date and reminder (up to
64) to timed, the Sailfish system alarm service, plus a wake-up every six
hours to pick up tasks added elsewhere. When one is due, timed runs
`dbus-send` to call the app's D-Bus service; the session bus starts the app
through sailjail (`ExecDBus=... -prestart` in the desktop file) without a
window, the app fetches the task, checks it really is due, shows the
notification and exits. Only the task id, kind and time are given to timed;
titles are fetched from your server when the reminder fires. If the server
cannot be reached (or the phone was just rebooted and not unlocked yet), a
reminder without details is shown.

This uses libtimed and D-Bus activation, which the Jolla Store does not
allow, so it is part of the sideload/OpenRepos build only.

## Security model

| Data | Where it lives | Protection |
|---|---|---|
| Access token | Sailfish Secrets collection `harbourvikunjasession` | Encrypted storage plugin, unlocked with the device lock, owner-only access. Every save is read back. If Secrets refuses it, the app asks once whether the token may be kept in `~/.local/share/io.github.manojgudi/harbour-vikunja/api-token.secret` instead (mode 0600, folder 0700, hidden from other sandboxed apps by sailjail but not encrypted; unsandboxed apps and root can read it). If you say no, it stays in memory and you sign in on each start. Settings shows where it is kept and lets you change the choice. Wiped on sign-out and after 30 days without opening the app. |
| Password, two-factor code | Never stored | Used once to create a scoped API token (projects, tasks, labels, comments, attachments, own user), valid one year and revocable in the web app. |
| Tasks, projects, comments | Memory only | No offline cache and no HTTP disk cache. Nothing about your tasks is written to the phone. |
| Image previews | Memory only | Shown from an in-memory image provider (max 40 MB), cleared on sign-out. Never written to storage. |
| Scheduled reminders | timed's event store | Task id, kind and time only, no titles. Cancelled on sign-out. |
| Server URL, preferences, pinned certificate fingerprints, last-used time | `~/.config/io.github.manojgudi/harbour-vikunja/settings.conf` (inside the folder sailjail keeps; the QSettings default next to it would be lost on every exit) | Private to the app under sailjail; created with mode 0600 (`umask 077`). Not secret. Preferences reset on sign-out. |
| Downloaded attachments | `~/Downloads`, only when you choose "Save" | The dialog tells you the file becomes readable by other apps. File names from the server are sanitised (no path traversal). |
| Uploads | Read from your Pictures/Documents/Videos/Music/Downloads | Only regular files in your own folders; the app's private data, hidden files and system files are refused. Max 20 MB. |

Network:

* TLS 1.2+ with normal certificate validation. A self-signed server is only
  accepted after you compare and trust its SHA-256 fingerprint; only that exact
  certificate is accepted for that host and port afterwards (trust on first use).
* Plain `http://` is refused unless the host is loopback or you explicitly allow
  it for that host after a warning.
* Redirects are not followed, so the token is only ever sent to your server.
* Requests time out after 20 seconds.

Other:

* The desktop file uses `X-Nemo-Application-Type=generic`, not a booster
  type. A booster loads the app into a booster process, so Sailfish Secrets
  would see the booster, shared with other apps, as the owner of the token
  instead of `/usr/bin/harbour-vikunja`.
* The app runs in the sailjail sandbox with `Internet`, `Notifications`,
  `Secrets`, `Downloads`, plus `Pictures`, `Documents`, `Videos`, `Music` and
  `MediaIndexing` so you can pick files to attach.
* The QML engine has no network access, so task descriptions and comments can
  never load remote images or trackers; their HTML is also sanitised.
* Log output is passed through a redaction filter (bearer tokens, `tk_…` API
  tokens, JWTs, password fields), and debug logging is off in release builds.
* The D-Bus entry point used by notification actions only marks a task done
  when the call comes from the notification server. A reminder call from
  anyone else can at most make the app re-check a task on your server: it only
  notifies if that task really has a due date or reminder at that time.
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
* `tests/e2e/` — end-to-end reminder test: private system and session buses,
  the real `timed` daemon from the SDK target, a stand-in notification server,
  and the installed app started by D-Bus activation. Checks that a reminder
  fires while the app runs and that a due date fires after it was closed.
* `tests/qmlsmoke/` — loads the real QML with the real C++ backend on the
  `minimal` Qt platform and walks through every page against a live server,
  failing on any QML warning or JavaScript error. Nothing is rendered, so it
  does not replace checking the layout on a device. `RestartDriver.qml` runs
  it four times in a row with the real token store (`SMOKE_PERSIST=1`,
  `SMOKE_PHASE=login|reopen|signout|after`) to check that a closed and
  reopened app is still signed in and that signing out leaves nothing behind.
  `run-restart.sh` deletes everything sailjail would not keep between runs.
