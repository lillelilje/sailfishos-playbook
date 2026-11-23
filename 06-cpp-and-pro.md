# 06 — C++, the `.pro`, and native QML types

**Read when:** you need something QML cannot do — a native sink, a background thread, a file format
QML has no binding for — or you are changing the build.
**Skip when:** QML + Python covers it. It usually does; reach for C++ deliberately, not by habit.

---

## What C++ is actually used for in these projects

Only two things:

1. **A GStreamer video player exposed as a QML type** (`VideoPlayer`) — see `08-media-playback.md`.
2. **`main()` overrides** that must happen before the QML scene loads: installing a disk cache,
   demoting a GStreamer rank, redirecting a temp path off tmpfs.

Everything else is QML + Python. Keep it that way.

## `main()` — when to write your own instead of `SailfishApp::main`

`SailfishApp::main()` is fine for a plain app. You need a manual `QQuickView` setup when you want to
inject something into the QML engine first, e.g.:

- a persistent **`QNetworkDiskCache`** so QML `Image` thumbnails are not re-downloaded every launch;
- **environment tweaks that must run before anything reads them** — for example `qputenv("TMPDIR", …)`
  to steer GStreamer's `downloadbuffer` off `/tmp`, which is tmpfs on Sailfish and will otherwise
  grow a media buffer until the phone OOMs. `g_get_tmp_dir()` caches on first use, so this only works
  early.

Do it with `QQmlNetworkAccessManagerFactory` + `QQuickView`, then `qmlRegisterType` for your own
types, before `view.setSource(...)`.

## Exposing a C++ type to QML

```cpp
qmlRegisterType<VideoPlayer>("MyApp 1.0", 1, 0, "VideoPlayer");
```

```qml
import MyApp 1.0
VideoPlayer { id: player }
```

Properties and methods follow the usual Qt rules:

```cpp
Q_PROPERTY(QString videoUrl READ videoUrl WRITE setVideoUrl NOTIFY videoUrlChanged)
Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)
Q_INVOKABLE void play();
Q_INVOKABLE void seek(qint64 positionMs);
```

**Useful property set** (all of these existed in the player and every one earned its place):
`playing`, `position`, `duration`, `hasFrame`, plus setters for the two URLs and their *extensions*.

**`hasFrame` is not decoration.** It is what lets QML keep a poster image visible until the first
frame actually arrives. Without it you cannot tell "buffering" from "broken".

## The `.pro` essentials

```qmake
TARGET = harbour-myapp
CONFIG += sailfishapp link_pkgconfig
QT += opengl network
PKGCONFIG += gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 \
             egl nemo-gstreamer-interfaces-1.0

# load-bearing: adding PKGCONFIG can drop these from the link line
LIBS += -lsailfishapp -lmdeclarativecache5
QMAKE_LFLAGS += -pie -rdynamic

SOURCES += src/harbour-myapp.cpp src/videoplayer.cpp
HEADERS += src/videoplayer.h

# keep qmake's intermediates out of the source root
OBJECTS_DIR = .build/obj
MOC_DIR     = .build/moc
RCC_DIR     = .build/rcc
```

Notes:

- `sailfishapp.prf` installs `qml/` and the `.desktop`. **Anything else needs its own `INSTALLS`**
  (the Python engine, data files, extra QML subdirectories) — and if you forget, the file is simply
  missing from the RPM. It will not fail the build. Check `rpm -qlp`.
- `DISTFILES` is for the source tarball/IDE; it does not control installation.
- The final binary and Makefile must stay at the source root for `%qmake5_install`.
- Icons are installed by four `INSTALLS` stanzas, one per density — see any sibling `.pro` — or
  let `sailfishapp.prf` do it with `SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172` and files at
  `icons/<W>x<H>/$$TARGET.png` (`15-icons-and-art.md`).

## Threading and native objects

The hardware video sink in FinTube is a two-thread object (render thread + control): GL/EGL calls are
allowed **only** in the paint path on the render thread, everything else under a mutex. If you write
anything similar, keep the same discipline — the failure mode is rare, ugly corruption rather than a
clean crash.

**Lock discipline matters in the proxy too.** A stream registry with a mutex plus per-stream
condition variables has a lock *order*; pick one, write it down in a comment, and never block on a
subprocess while holding a lock.

## Things that only fail at runtime

The build compiler does **not** check:

- QML at all (see `04-qml-and-silica.md`),
- whether a `PKGCONFIG` package exists on device,
- whether a plugin you import is installed (wrap optional imports in a `Loader`),
- link line order.

So: build, install, and watch the log. Every one of these has bitten at least once.
