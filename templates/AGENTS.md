# Working instructions — <App name>

Instructions for anyone (human or AI) changing this repository. Follow these unless a decision in
`docs/DECISIONS.md` says otherwise.

## Project facts

- App / binary / package name: `harbour-<name>`; display name **<App name>**
- Stack: Qt 5.6 QML + Sailfish Silica<, a Python engine over PyOtherSide><, a C++ …>
- Target: Sailfish OS 5.x (aarch64), primary device **Jolla Phone 2026**. No `armv7hl`.
- Distribution: <OpenRepos/Storeman | Jolla Harbour> — <sandboxed / unsandboxed, and why>
- License: <GPL-3.0-or-later>
- Data: <where it lives>

## Golden rules

1. **<The one product rule.>** Every feature that is not that is a non-goal unless a decision says
   otherwise.
2. **<Reuse, do not re-implement.>** <what is reused and from where>
3. **<The invariant that is easy to break.>**

## Layout

```
qml/            UI only — dumb views, no logic
qml/Backend.qml async facade over the engine
python/         the engine (pure stdlib where possible) + its offline tests
src/            C++ only for what QML cannot do
rpm/            the .spec
scripts/        build-rpm.sh, deploy-device.sh, run-tests.sh
docs/           PLAN / DECISIONS / PLATFORM / BUILD / PUBLISH / TODO / DEVLOG
```

## Definition of done

- [ ] `scripts/build-rpm.sh` — 0 rpmlint errors
- [ ] `scripts/run-tests.sh` green
- [ ] installed and used on a real phone, not just launched
- [ ] `rpm -qlp` contains every file you expect
- [ ] decisions / platform notes / devlog updated
- [ ] no hardcoded itags, pixel sizes or theme colours

## Verification discipline

- Prefer a measurement to an explanation; the device log is the source of truth.
- Mark new facts in `docs/PLATFORM.md` as **verified <date>** or **unverified**.
- Change **one lever at a time** and verify between changes.
- If you are reasoning about what the code probably did, add a log line instead.
- Never state a Sailfish or upstream-service fact without marking it verified or unverified.

## Escalation points

- **<Highest-risk area.>** <why, and what to check before building on it>
- **Upstream breakage.** <what changes often and how the app copes>
- **Provenance.** Reused files keep their copyright headers and licence; record the exact upstream
  commit in `docs/DECISIONS.md` when a file is copied.

## Do not

- <the tempting shortcut that is actually a trap>
