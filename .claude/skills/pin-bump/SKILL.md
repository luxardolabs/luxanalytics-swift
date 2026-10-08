---
name: pin-bump
description: Move this iOS repo to the latest luxios the fleet way — bump LUXIOS_VERSION, check the luxios checkout out at that tag, read what changed, re-install the agent and git wiring, run make ios-check, and leave new reds red. Use whenever the wiring stage or a luxios release says this repo is behind.
---

<!-- luxios:pin-bump-skill asset v1 - DO NOT edit this marker line; it is how luxios's wiring check knows your copy is current. Re-install with `bash $LUXIOS/scripts/install.sh`. -->

# Pin bump

The runnable luxios upgrade for this iOS repo. Installed from luxios (`bash $LUXIOS/scripts/install.sh`); re-install, never hand-edit. luxios is a versioned git repo, not a container: the pin is `LUXIOS_VERSION := X.Y.Z` in this repo's Makefile (`:=`, a committed fact) and `LUXIOS ?= <path>` says where the checkout lives on this machine.

**Every step ends with its evidence.**

## 1. Find the latest and bump the pin

```sh
git -C "$LUXIOS" fetch --tags
git -C "$LUXIOS" tag -l 'v*' --sort=-v:refname | head -1
```

Set `LUXIOS_VERSION := <that version>` in the Makefile (no `v`), then put the checkout on that tag: `git -C "$LUXIOS" checkout v<version>` (or `git submodule update` after moving the submodule, if luxios is one). The wiring stage refuses a checkout whose `VERSION` differs from the pin, so the two move together.

**Evidence:** `old -> new`, and `cat "$LUXIOS/VERSION"`.

## 2. Read what changed, before running anything

Read `$LUXIOS/CHANGELOG.md` from the top down to the version you were on. Note every entry that says **"may newly flag"**, every new declaration (`VIEW_DIRS=none`, `CONTRACT_FACTS=none`, …) and every change to a standard you follow.

**Evidence:** the versions read and the entries that apply to this repo.

## 3. Re-install the wiring

`bash "$LUXIOS/scripts/install.sh"`. It rewrites the fleet skills, the Claude Code hooks, the git hooks and the CLAUDE.md block from the pinned luxios and says what it changed. Never hand-patch an installed file to make the wiring stage pass; if one needs a change, `/escalate` it.

**Evidence:** the installer's summary line.

## 4. Run the gate, and leave new reds red

`make ios-check`. A new check that fires is the point of the bump: another repo was held to a stricter bar and this one now is too.

- Fix what is yours to fix now. **You touched it, you own it** applies to every file you edit.
- Anything genuinely wrong with luxios: `/escalate`. A red stays red while its escalation is open; never waive or skip it to get green.

**Evidence:** the red count before and after, and any escalation keys.

## 5. Commit

Commit the pin change and the re-installed files together, as `luxardolabs`, no AI attribution. Pushing follows this repo's rule (`/wrap-up` step 5).

**Evidence:** the commit SHA.
