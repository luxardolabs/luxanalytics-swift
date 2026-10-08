# CLAUDE.md

<!-- luxios:claude-pointer asset v1 - DO NOT edit this block; it is how luxios's wiring check knows your copy is current. Re-install with `bash $LUXIOS/scripts/install.sh`. -->

## How to work here (fleet conduct — read the standard, not just this block)

This is an iOS repo under **luxios**, the fleet's iOS standard. It runs natively on the Mac, with no Docker. `$LUXIOS` below is the luxios checkout this repo's Makefile points at (`LUXIOS ?= …`), pinned by `LUXIOS_VERSION`.

**`$LUXIOS/docs/fleet/FLEET-AGENT-CONDUCT-STANDARD.md`: read it in full before your first change.** It is the one home for *how* agents work in this fleet. `$LUXIOS/docs/FLEET-IOS-STANDARD.md` is the one home for the iOS rules. This block points at them and restates only the rules broken most often. It does not replace reading them.

**Run `/fleet-start` at the start of every session and after every compact.** It rehydrates from LuxPM and restates the session rules.

**Report the result, not the mountain.** No "heavy", "multi-hour", "the big one", no narrating difficulty. Done + next in one line, with numbers.

**Decide; do not hand back a menu.** Whether to ask the owner is decided by the **class of action**, never by how confident you feel:

- **Ask** — deleting anything; changing scope; a waiver, exemption or declared skip (`VIEW_DIRS=none`, `CONTRACT_FACTS=none`); publishing outward (pushing a repo you were not asked to push, a public repo, a force-push, a history rewrite, an App Store submission); a genuine product fork where the choice is taste, not correctness.
- **Do it** — aligning code to a ratified standard or a gate red; anything you have evidence for that is reversible in one commit. The standard already decided; say what you did.

**Work the gate's reds in `make ios-check` stage order, top down. Never ask which one is next.** An escalation covers ONE site: the rest keep going.

**An owner hold is exactly as wide as the owner said.** "Hold off on X" excludes X and nothing else. Skip X, say so in one line, and keep burning down the rest.

**End every turn that worked gate reds with `reds: N (was M)`**, plus the held items by name. A turn that ends on a question while N > 0, outside an ask-class, is the failure this block exists to stop.

When you do ask: **one decision per message**, the evidence that makes it answerable, your recommendation stated as one, and a question answerable in one word. **A recommendation that ends in a menu is not a recommendation.**

**Use the fleet skills; don't improvise the procedure.** `/fleet-start` to open a session. `/wrap-up` before you call anything done (tests you saw fail before the fix, every red in touched files, docs, gate, LuxPM closed out, all with evidence). `/adversarial` to have an independent agent attack a change touching auth, the Keychain, personal data, payments, the backend contract or a release. `/pin-bump` to upgrade luxios. `/escalate` when the standard is wrong. `/release` to cut a release.

**You touched it, you own it.** Edit a file for any reason and it has a SwiftLint, swift-format, arch-check or Swift concurrency red: fix every one in that file, not just yours. Never spend time proving a red predates you; fix it. Test what you changed first.

**Align or escalate; never route around.** A red is fixed by changing the code, or escalated to the luxios maintainer as genuinely wrong. Never by a `swiftlint:disable` without its reason above it, a skipped test, a config carve-out or a local override. Verification is not authorization: proving something is unreferenced does not license deleting it.

**Escalations go in THIS repo's LuxPM project** — label `fleet-escalation`, title `[luxios ESCALATION] …`, self-contained enough to forward whole. **Search LuxPM for an existing issue first** (and comment on it if found); filing a new one is pre-authorized. **Never a GitHub issue** — there is no fallback.

**A red stays RED while its escalation is open.** A lit red is honest; a silenced one is a lie you will inherit.

**Commit as `luxardolabs`** using the global git config, and never `git -c user.email=…`. No AI attribution in commit messages. The installed git hooks scan every commit and push for secrets and non-fleet identities; never `--no-verify`.

<!-- /luxios:claude-pointer -->
