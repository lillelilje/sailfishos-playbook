# 07 — Storing data

**Read when:** the app has to remember anything.
**Skip when:** it is genuinely stateless.

---

## Where

- **App data:** `~/.local/share/harbour-<name>/`
- **Cache (regenerable):** `~/.cache/harbour-<name>/`
- Both are created on demand (`os.makedirs(..., exist_ok=True)`).

**Sandboxed apps** only see their own data directory by default; anything outside it needs a
permission or a profile. **Unsandboxed apps** see everything. Pick the storage location accordingly
— if you need a shared or external location, that is a sandbox decision, not a detail.

## JSON, not SQLite (for small apps)

Every sibling project uses small JSON files. There is no reason for SQLite until you have real
queries, and JSON is inspectable on the device with `cat`, which matters when you are debugging over
SSH.

- **Settings:** one `settings.json` with a `_DEFAULTS` dict. Read = merge defaults with what is on
  disk, so a new key does not break an old install.
- **Sensitive stores** (anything with a credential in it): write `0600`.

## Write atomically, always

A crash — or a kill from the OS — during a plain `open(path, "w")` truncates the live file and you
lose the user's data. Write to a temp file and rename:

```python
def _atomic_write_json(path, obj):
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)          # atomic on the same filesystem
    except Exception:
        try: os.remove(tmp)
        except OSError: pass
        raise
```

`os.replace` is atomic on the same filesystem — which is why the temp file must live in the **same
directory** as the target, not `/tmp`.

## Read defensively

```python
def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default                       # missing, truncated, or corrupt → a sane default
```

Never let a corrupt store crash the app on launch. A truncated settings file should reset to
defaults, not white-screen the app.

## Permissions and secrets

- Anything with a cookie, token or session in it: `0600`, and keep it out of the repo
  (`.gitignore` it, and confirm with `git log --all --name-only` before publishing).
- **Prefer not to persist secrets at all.** Kibble writes its session to a fresh `0600` temp file for
  the duration of a single external call and deletes it after, instead of leaving a plaintext cookie
  jar on disk. Do that whenever you can.
- **Before making a repo public, grep the tracked files and the whole history for credentials** and
  for anything personal (LAN addresses, tokens). It takes a minute and it is unrecoverable if you
  miss it.

## Caches

- Cache things that are expensive and regenerable (thumbnails, resolved URLs, parsed feeds).
- **Bound them.** An unbounded cache on a phone is a bug that appears an hour into use. A prune that
  keeps the newest N files is enough.
- Prefer the platform's own cache where it exists. A `QNetworkDiskCache` installed on QML's
  `Image` loader can be set up in `main()` (`06-cpp-and-pro.md`) and saves downloading every
  thumbnail on every launch.

## In-memory session state is real state

State that lives only in QML lasts exactly as long as the app process. If the UI implies a
"session" — remember-what-was-shown, a paging cursor — then **give the user a way to reset it**, or
it is a state they can only escape by force-closing the app. Kibble's reel remembers which shorts it
has shown; there is now a "Start a new session" button for exactly this reason.
