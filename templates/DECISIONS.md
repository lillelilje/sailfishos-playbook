# Decisions — <App name>

Why the app is the way it is. New decisions go at the **bottom**, numbered in order. Never edit an
old entry: if a decision is reversed, add a new one that says `supersedes D-0NN`.

Format:

```markdown
### D-0NN — <short title>
- **Date:** YYYY-MM-DD · **Status:** Accepted | Proposed | Rejected (supersedes D-0MM)
- **Context:** what forced a choice. Evidence and numbers where you have them.
- **Decision:** the choice, stated plainly.
- **Consequences:** what it costs, what it rules out, what to revisit.
```

A decision with no downside listed has not been thought through.

---

### D-001 — Platform target
- **Date:** YYYY-MM-DD · **Status:** Accepted
- **Context:** Sailfish OS 5.x is current (Finlayson 5.2.0.x). Older Xperia devices are `armv7hl`;
  10 II+, Jolla C2 and Jolla Phone 2026 are `aarch64`.
- **Decision:** target **Sailfish OS 5.x, aarch64 only**, on the Jolla Phone 2026.
- **Consequences:** no legacy device support; one build target, so the matrix stays small.

### D-002 — UI toolkit
- **Date:** YYYY-MM-DD · **Status:** Accepted
- **Context:** Silica is the only stable native toolkit and is frozen on Qt 5.6. Keel is a beta Qt 6
  reimplementation served through the beta Reef store.
- **Decision:** **Qt 5.6 + QML + Sailfish Silica**. Revisit Keel only as a deliberate port.
- **Consequences:** the Qt 5.6 floor applies (no `Qt.callLater`, no inline `component`, …).

### D-003 — Where the logic lives
- **Date:** YYYY-MM-DD · **Status:** Accepted
- **Context:** QML cannot be unit-tested here, and the build does not even validate it.
- **Decision:** **dumb QML → async bridge (`Backend.qml`) → engine**. The engine is plain
  Python/C++ and is tested offline on the host.
- **Consequences:** a real test suite with no device and no network. Slightly more indirection for
  trivial UI.

### D-004 — <Application language / bridge>
- **Date:** YYYY-MM-DD · **Status:** Accepted
- **Context:** <why Python via PyOtherSide, or why pure C++>
- **Decision:** <…>
- **Consequences:** <…>

### D-00N — AI assistance
- **Date:** YYYY-MM-DD · **Status:** Accepted
- **Context:** <…>
- **Decision:** AI coding assistance is **disclosed in the README**, along with what it means in
  practice — including bugs the AI introduced and how they were caught. Nothing about the platform or
  upstream services is trusted on the AI's word; it is measured.
- **Consequences:** the human maintainer reviews and tests every change on real hardware.
