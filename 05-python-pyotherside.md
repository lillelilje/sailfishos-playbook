# 05 — Python from QML (PyOtherSide)

**Read when:** the app needs real logic — parsing, networking, file formats, anything stateful.
**Skip when:** the app is pure C++/QML.

This is the pattern all four sibling projects use. It has one big payoff: **the engine runs under
plain `python3` on your host**, so you get a real unit test suite with no device and no network.

---

## The shape

```
qml/Backend.qml      the async facade — properties in, callbacks out. No logic.
python/<engine>.py   the engine — pure stdlib, importable, testable
python/test_<engine>.py
```

`Backend.qml` is an `Item` (not a `Page`) so it can be reached from anywhere as `app.backend`.

```qml
import io.thp.pyotherside 1.5

Item {
    id: backend
    property bool pyReady: false
    property string someValue: ""

    readonly property string _pyPath:
        Qt.resolvedUrl("../python").toString().replace("file://", "")

    Python {
        id: py
        Component.onCompleted: {
            addImportPath(backend._pyPath)
            importModule("myengine", function() {
                backend.pyReady = true
                backend.refresh()
            })
        }
        onError: console.log("python error: " + traceback)
    }
}
```

`../python` resolves to `/usr/share/harbour-<name>/python` on device, because `sailfishapp.prf`
installs the `qml/` tree and your `.pro` installs the engine next to it. Ship it with:

```qmake
python.files = python/myengine.py
python.path = /usr/share/$${TARGET}/python
INSTALLS += python
```

---

## The rules

**1. Nothing returns a value. Everything is a callback.**

```qml
py.call("myengine.get_settings", [], function(s) { backend.quality = s.quality || 1080 })
```

**2. A blocking call is fine — on a worker thread.** `py.call` runs on PyOtherSide's worker thread,
so a slow `subprocess.run` will not freeze the UI. It *will* block that whole lane, though, which is
rule 3.

**3. Give slow work its own lane, because each `Python` element is a separate worker thread.**
This is the most valuable trick here. Kibble runs four:

| element | purpose |
|---|---|
| `py` | control: health, settings, session, feed, likes |
| `pyResolve` | playback resolves (seconds long) |
| `pyPreload` | speculative preloading |
| `pyPreload2` | a *second* preload lane, so two can run in parallel |

Without separate lanes, a 7-second resolve queues behind the feed refresh and the UI feels broken.
With them, work genuinely runs concurrently — PyOtherSide gives each element its own thread, and the
interpreter (and therefore module globals) is shared.

**VERIFIED 2026-10-12:** two preload lanes cut the "preparing the next item" stalls to nearly zero
once a single lane could not keep up with the user.

**4. Never let a *whole lane* be occupied by something the UI needs now.** Serialise the slow lane
with a flag and let callers get `{ok: false, error: "busy"}` immediately, rather than queueing:

```qml
function prefetch(query, callback) {
    if (backend._prefetchBusy) { callback({ok: false, error: "busy"}); return }
    backend._prefetchBusy = true
    …lane.call(…, function(s) { backend._prefetchBusy = false; callback(s || {}) })
}
```

**5. Module globals are shared across lanes.** That is how a token created on the resolve lane is
served by a proxy thread. It also means shared mutable state needs a lock (`threading.Lock`).

**6. Keep PyOtherSide out of the engine's import path.** Import it *inside* the function that needs
it, never at module top level, or you cannot import the engine from the host for tests:

```python
def install_something():
    import pyotherside                       # only here
    pyotherside.send("install_progress", 42)
```

The same goes for anything else device-only.

**7. Push progress with `pyotherside.send`, not a blocking loop.** A long download reports with
`pyotherside.send("install_progress", pct)`; QML receives it as a signal on the element.

**8. Surface errors.** `onError: console.log(traceback)` on every `Python` element, mirrored into the
app's log (`03-device.md`). A Python traceback is invisible otherwise.

**9. A `Future` from `run_coroutine_threadsafe` hides its exception unless you ask.** This is the
quiet version of rule 8. `future.result()` only happens when you pass `result_required=True`; the
fire-and-forget path keeps a `concurrent.futures.Future` whose exception nobody reads. The feature
just does nothing, with no traceback:

```python
from concurrent.futures import CancelledError

# A network fetch scheduled on the loop from the worker thread
future = asyncio.run_coroutine_threadsafe(coro(), self.loop)
future.add_done_callback(self._log_future_error)

def _log_future_error(self, future):
    try:
        error = future.exception()
    except CancelledError:
        return                              # cancellation is not a bug
    if error is not None:
        logging.error("background task failed", exc_info=error)
```

Attach the callback in the one shared helper (the `result_required=False` branch), not at every call
site. This is the failure mode to suspect when a scheduled feature “does nothing” and there is no
traceback anywhere.

**10. Log the error, not just the notification.** `pyotherside.send("error", ...)` becomes a banner
that disappears; the user cannot copy it and the next run is blind. Mirror the same call into the
log:

```python
def show_error(name, info="", other=None):
    logging.error("show_error %s: %s %s", name, info, other or "")
    qsend("error", name, str(info), other)
```

A notification is a UI affordance, not a record. Mirror the same call into the log in every app.

---

## Engine conventions that pay off

- **Pure stdlib where possible.** Every project's `test_<engine>.py` runs on plain host `python3`
  with no venv, no device, no network — because the engine imports nothing exotic.
- **Tolerant parsing.** Walk the JSON defensively and degrade instead of raising; upstream shapes
  change without warning. A helper that yields every `(key, value)` pair in a nested tree makes
  this much less painful.
- **Small pure functions for policy.** Format selection, date formatting, ranking, dedup — keep them
  as functions taking data and returning data, so they are trivially testable.
- **Never trust a plausible theory about an external service.** Write the measurement down.

## The test suite is the safety net

```sh
scripts/run-tests.sh        # → python3 python/test_<engine>.py
```

It costs minutes to set up and it catches the class of bug you cannot see otherwise. Tests worth
having on day one, learned by shipping bugs:

- **Version sync:** the engine's version constant equals the RPM spec's `Version:` (this drifted and
  shipped twice).
- **QML name collisions:** no `function foo()` shares a name with `property … foo` in any `.qml`
  file — the shadowing is silent and breaks the UI at runtime. A ten-line regex test would have saved
  an entire debugging cycle (see `12-pitfalls.md`).
- **Error mapping:** raw upstream errors map to text a user can act on.
- **Pure helpers:** the parsers and pickers, with realistic fixtures copied from real responses.

Run it before every build. It is the only automated check that exists — the build compiler will not
look at QML, and nothing here tests C++ or the real network.
