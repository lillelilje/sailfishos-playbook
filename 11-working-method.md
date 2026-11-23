# 11 — Working method

**Read when:** you are starting or resuming a project, or working with an LLM on one.
**Skip when:** never, honestly. This is the file that makes the rest usable.

The technical facts elsewhere in this folder are cheap to re-derive. **This** is the part that turned
several messy projects into ones a different agent could pick up.

---

## The docs set

```
AGENTS.md            instructions for whoever edits the repo next (human or AI)
docs/PLAN.md         scope, phases, risks, non-goals
docs/DECISIONS.md    numbered decision log — the "why"
docs/PLATFORM.md     facts about THIS platform, dated
docs/BUILD.md        build + install steps
docs/PUBLISH.md      channel, signing, listing text, release checklist
docs/TODO.md         ordered tasks, one "Now" section at the top
docs/DEVLOG.md       dated log of measurements and bugs
```

Keep `AGENTS.md` honest about the shape of the code, the invariants that must not be broken, and
where the risky parts are. FinTube's is the model: it says what each layer is, lists ten invariants
with the reason for each, and then a "gotchas that will bite you" list. An agent that reads only that
file can already work safely.

---

## The decision log

Numbered (`D-001`, `D-002`, …), append-only, one short entry each:

```markdown
### D-014 — Stream through a localhost proxy
- **Date:** 2026-10-12 · **Status:** Accepted (supersedes D-009)
- **Context:** what forced a choice, and the evidence. Numbers if you have them.
- **Decision:** the choice, stated plainly.
- **Consequences:** what it costs, what it rules out, what to revisit.
```

Rules that make it useful rather than ceremonial:

- **Never edit history.** When a decision is reversed, add a new entry that says
  `supersedes D-009`. The wrong turns are the most valuable entries in the file — they stop someone
  (or something) from confidently re-making the same mistake.
- **Record the measurement, not the theory.** "QoS drops lined up with the pre-warm, not with decode"
  beats "we fixed stutter".
- **Include the cost.** A decision with no downside listed has not been thought about.

## The devlog

One entry per working session, dated, short:

- what was measured, with numbers;
- what was changed and why;
- **what was broken and how it was found** — including bugs the *agent* introduced. Leaving those in
  is not self-flagellation; it is the only warning the next person gets.

The good entries read like lab notes:

```
13:36:30 resolve x
13:36:39 resolve y        ← 8 s apart: one lane cannot keep up
11:15:35 swipe blocked / released  (1 s)
```

A number in the devlog ends an argument. A sentence without one starts it.

---

## Verification discipline

**Everything important gets measured on real hardware, and the marker goes in the doc.**

- `VERIFIED <date>` — measured, or read out of the device's own files. Trust over theory.
- `unverified` — believed, derived, or copied from docs. Say so explicitly.
- `date-sensitive` — platform or upstream changes; re-verify.

Three habits that follow:

1. **Prefer a measurement to an explanation.** Several entries in this folder exist because a
   confident, plausible theory was wrong: the decoder was blamed for a bandwidth problem; "no
   formats" was blamed on cookies when it was a missing JS runtime; a track index was read as a
   language code.
2. **Change one lever at a time, with a measurement between.** Two simultaneous changes tell you
   nothing about which one worked — and this was learned by doing it wrong, twice.
3. **If you find yourself reasoning about what the code probably did, add a log line instead.**
   Especially: which *path* was taken, and how long it took.

## Reproducing beats guessing

Before "fixing" a failure, reproduce it. The most expensive mistakes in this project came from acting
on the first plausible cause. Instrument, re-run on the device, *then* change code. If you cannot
reproduce it, say so and log the uncertainty instead of shipping a speculative fix.

---

## Working with an LLM (what actually worked)

This is the disclosure section, and it is not optional. Say plainly in the README that the project
was built with AI assistance, and then say **what that means in practice**:

- most code was AI-drafted and human-verified on a device;
- the AI wrote much of the docs and tests too — the judgements are the human's, the prose is not;
- **list bugs the AI introduced and how they were caught.** Kibble's README does. It is the most
  useful part of the file for anyone evaluating trust;
- state that upstream behaviour is never trusted on the AI's word.

### What works well

- **A narrow task with a clear success test** ("make this log line appear", "why did this fail").
- **Instrumenting before fixing** — asking for the log line instead of the fix.
- **Mechanical work with a check**: renaming, porting a known-good pattern from a sibling project,
  writing a test for a bug that just happened.
- **Reading its own past decisions.** An agent pointed at `DECISIONS.md` + `DEVLOG.md` +
  `AGENTS.md` behaves very differently from one guessing.

### What goes wrong

- **Confident, plausible, wrong** theories about an external service. Mitigation: require a
  measurement before a fix.
- **Silent runtime breakage in QML**, because the toolchain does not validate it. Mitigation: the
  component-existence check and the name-collision test in `04-qml-and-silica.md`.
- **Fixing the symptom.** A client-side dedupe "fixed" repeating videos by hiding them, while the
  real cause (the wrong continuation token) starved the feed. Ask "why is this happening" before
  "how do I hide it".
- **Several changes at once**, and then not knowing which one broke it.
- **Declaring victory from a build passing.** The build passing means it compiled. On this platform
  that is a low bar.

### The standing instructions worth putting in `AGENTS.md`

- Read the surrounding code and the relevant doc before editing.
- One change at a time; verify on device between changes.
- Add a log line rather than theorising.
- Never state a Sailfish/YouTube fact without marking it verified or unverified.
- When a measurement contradicts a prior claim in the docs, **update the doc** — the folder is only
  worth anything if it is true.
