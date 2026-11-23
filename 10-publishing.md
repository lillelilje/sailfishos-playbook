# 10 — Publishing

**Read when:** the app is ready for other people.
**Skip when:** it is not.

**VERIFIED 2026-10-10/12**, from shipping to OpenRepos via Storeman.

---

## Pick the channel first

| Channel | Model | Validator | Reach | Fits |
|---|---|---|---|---|
| **OpenRepos + Storeman** | you upload an RPM | no | community, all devices | anything, incl. unsandboxed |
| **SailfishOS:Chum** | OBS builds from source | some | reproducible, all devices | a later step |
| **Jolla Harbour / Store** | you submit, Jolla curates | **yes** (allowed APIs & permissions) | all Jolla devices | sandboxed, conservative apps |
| **Reef** (beta 2026) | store for Keel/Qt 6 | signature checks | Jolla Phone 2026 | Qt 6 ports |

**The sandbox decision in `NEW-PROJECT.md` already decided this for you.** An app that spawns helper
binaries, runs a localhost proxy or manages its own downloads **cannot** pass Harbour; it goes to
OpenRepos. Say so in the listing rather than hoping nobody notices.

## OpenRepos listing: what to prepare

1. An account and project at <https://openrepos.net>.
2. The **`.rpm`** for your arch (aarch64).
3. A **Summary** — one line, no period.
4. A **Description** — long-form, and this is where you earn trust. Include:
   - what it does, in plain words;
   - **what it deliberately does not do** (it manages expectations better than any feature list);
   - **anything a user must do on first run** — an extra download, a permission, a sign-in. If the
     app installs a 40 MB runtime before it can play anything and you do not say so, the first review
     is "it's broken";
   - sandbox / distribution caveats, and any ToS reality (e.g. a third-party client).
5. **Screenshots.** At least one per real screen. **Re-shoot them whenever the UI changes** — stale
   screenshots are the easiest avoidable embarrassment, and they are easy to forget after a UI pass.
6. An **icon** — the store uses the 86x86 PNG you already ship. Do not paste the 1024 master or a
   screenshot of it; `15-icons-and-art.md` covers the sizes and the style.
6. A **changelog**. For a first release, one entry, not your development history.

## Signing (optional, recommended)

OpenRepos accepts unsigned packages, but Storeman warns about untrusted software.

```sh
gpg --gen-key
cat >> ~/.rpmmacros <<EOF
%_signature gpg
%_gpg_name <key id>
EOF
rpm --addsign RPMS/harbour-myapp-*.aarch64.rpm
rpm -K RPMS/harbour-myapp-*.aarch64.rpm        # digests signatures OK
```

Publish the public key so people can verify: `gpg --armor --export <id>`.

## Release checklist

- [ ] version bumped, and the code's own version constant matches the spec (`02-build-and-package.md`)
- [ ] `scripts/build-rpm.sh` clean — **0 rpmlint errors**
- [ ] `scripts/run-tests.sh` green
- [ ] `rpm -qlp` includes everything (binary, `.desktop`, icons, **extra files**)
- [ ] **installed and used on a real phone** — not just launched
- [ ] any runtime downloads verified on a *fresh* install (not one where they were already present)
- [ ] screenshots re-shot to match the current UI
- [ ] launcher icon still looks right on the homescreen, at all four sizes (`15-icons-and-art.md`)
- [ ] description says what is needed on first run
- [ ] (optional) RPM signed, key published
- [ ] OpenRepos project created, RPM + description + screenshots uploaded
- [ ] Storeman install checked end to end
- [ ] `git tag v<version>` and, if you have a public repo, a GitHub release

## Repo hygiene before going public

- [ ] `LICENSE` present (GPL-3.0-or-later is the norm here, and is *required* if you reuse GPL code)
- [ ] `README.md` — what it is, and **how it was built** (see `11-working-method.md` on AI disclosure)
- [ ] **grep the tracked files and the whole history for credentials** and for personal data
  (LAN addresses, tokens, real names). `git log --all --name-only` catches what `.gitignore` missed.
- [ ] replace any real device address in docs/scripts with a placeholder
- [ ] `docs/` is current — the decision log especially

## Two publishing truths worth internalising

1. **The build toolchain will happily ship an incomplete package.** `2-build-and-package.md` repeats
   this because it matters: a file missing from an `INSTALLS` stanza is silently absent. Check
   `rpm -qlp`, and install it on a clean device.
2. **Your testing is not representative.** Everything here was developed against one phone, one
   account and one network. "It worked for me" is the default state of every bug report you are about
   to receive; a fresh-install check and an honest description are the cheap defences.
