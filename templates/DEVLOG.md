# Devlog — <App name>

One entry per working session, newest at the **bottom**. This is the highest-value file in the repo:
it is where measurements, dead ends and bugs live, so the next person does not repeat them.

Keep it factual and numeric. A number ends an argument; a sentence without one starts it.

Template:

```markdown
---

## YYYY-MM-DD — <what this session was about>

<One or two sentences on the goal.>

**Measured:** <the numbers. Timings, counts, log lines, with the command used or the log excerpt.>

**Changed:** <what was changed and why.>

**Broke / found:** <bugs, including any the agent introduced, and how they were found. Do not tidy
these away — this is the warning the next person gets.>
```

---

## YYYY-MM-DD — <example entry>

Goal: get the first build onto the device.

**Measured:**
```
$ scripts/build-rpm.sh     → RPMS/harbour-<name>-0.1.0-1.aarch64.rpm, 0 rpmlint errors
$ ssh … 'tail -5 ~/.local/share/harbour-<name>/dev.log'
2016-10-12 11:02:17 [app] page loaded
2016-10-12 11:02:19 [app] fetch ok: 9 items, 1.9s
```

**Changed:** scaffolded the `.pro`, spec, desktop file and the container build script.

**Broke / found:** the app installed but did not launch — the `Exec=` line named the binary without
`harbour-`, so the launcher found nothing. Fixed in the `.desktop`. (First of many "it compiled,
therefore it works" mistakes.)
