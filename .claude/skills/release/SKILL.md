---
name: release
description: Cut a release of this iOS repo the same way every time — an SPM package (a vX.Y.Z tag consumers pin) or an app (a TestFlight/App Store build) — reconcile the tracker, write the changelog, meet the gate, tag, publish the GitHub Release, mirror to LuxPM. Follow it end to end; never skip a step.
---

<!-- luxios:release-skill asset v1 - DO NOT edit this marker line; it is how luxios's wiring check knows your copy is current. Re-install with `bash $LUXIOS/scripts/install.sh`. -->

# iOS release ritual

The one runnable checklist for cutting a release of THIS repo. Installed from luxios (`bash $LUXIOS/scripts/install.sh`); re-install, never hand-edit. The rationale for each step lives in `$LUXIOS/docs/fleet/FLEET-RELEASE-PROCESS.md`; this is the iOS steps. Do them in order.

## Non-negotiables

- **Commit and tag as the fleet identity** (global git config: name `luxardolabs`, the GitHub noreply email). Never `-c user.email=…`. **No AI attribution** in any message.
- **The git tag is `vX.Y.Z`**, annotated (`git tag -a`). Everything else is bare: the `VERSION` file, `MARKETING_VERSION`, the LuxPM release.
- **`VERSION` at the repo root is the version source of truth.**
  - A **package** uses SemVer: SwiftPM resolves `from:` and `exact:` against tags, so MAJOR breaks the public API, MINOR adds to it, PATCH fixes.
  - An **app** uses the fleet's CalVer `YYYY.0M.MICRO`, and its `MARKETING_VERSION` matches `VERSION`. `CURRENT_PROJECT_VERSION`, the build number, goes up on every upload.
- **Released tags are immutable.** Never move or delete one; cut the next version.
- **Publishing is the owner's call.** Pushing the tag, the GitHub Release, and an App Store submission all publish outward. Ask before the first push of a repo, and before any push of a public one.

## Steps — do every one, in order

1. **Preconditions.** Clean working tree, on the release branch, `git tag -l "v$(cat VERSION)"` prints the previous release (an unreleased version is never bumped past).
1. **Decide the version** per the rule above and bump `VERSION` (and `MARKETING_VERSION` for an app). Record the previous tag.
1. **Gather the window.** `git fetch --tags`, then `git log --no-merges <last-tag>..HEAD --pretty=format:'%h %s'` and `git diff --stat <last-tag>..HEAD`. Note the issue IDs, public API changes (a package), wire-contract changes, and new permissions or entitlements (an app).
1. **Reconcile the tracker (LuxPM).** `luxpm_list_issues` for open issues; close the ones that shipped in this window (`luxpm_update_issue state=done` + a `close_summary`), leave the rest open, and check every commit's issue ID resolves to a closed issue.
1. **Write the changelog now, from the complete window.** A `## X.Y.Z — <one line>` entry at the top of `CHANGELOG.md`: what changed for whoever consumes this (an app's users or a package's adopting apps), breaking changes first, and the steps an adopter must take. For an app, also the App Store "What's New" text, written to the user.
1. **Meet the gate.** `make ios-check` green, or every remaining red escalated (an open issue), approved by the owner to ship red, and listed under `## Known reds` in the entry. An unexamined red blocks the release.
1. **Commit** the bump and the changelog together.
1. **Tag:** `git tag -a "v$(cat VERSION)" -m "v$(cat VERSION)"`.
1. **Ship the artifact. Do not skip this step.**
   - **Package:** the tag IS the artifact; SwiftPM consumers resolve it. Confirm it from a scratch consumer, e.g. `swift package resolve` with `.package(url: …, exact: "X.Y.Z")`.
   - **App:** archive and upload the build with this repo's Mac-native release target. If the repo has none, archive in Xcode (Product › Archive) and upload it with Organizer or Transporter. Confirm the build appears in App Store Connect with this version and its build number.
1. **Push** the commit and the tag (`git push && git push origin "v$(cat VERSION)"`), once the owner has cleared pushing this repo.
1. **Publish the GitHub Release.** `gh release create "v$(cat VERSION)" --title "$(cat VERSION)" --notes-file <this version's CHANGELOG section>`, then confirm it with `gh release view`. A tag is not a Release; skipping this leaves `/releases` empty.
1. **Re-issue the LuxPM sync receipt** (`luxpm_issue_sync_receipt`), written verbatim to `.luxpm-receipt`, then commit and push it. If it says `last_known_commit: none`, drain the commits with `luxpm_link_commits` (each with its `committed_at`) and re-issue.
1. **Close the issues this release fixes** with a `close_summary`. A comment is not a close.
1. **Mirror to LuxPM:** `luxpm_create_release(project_id=<this repo's>, version="X.Y.Z", status="released", release_date=<today>, changelog_md=<the entry>)`.

## Done when

`VERSION` is bumped and the changelog entry is written from the full window. The gate is met. The annotated `vX.Y.Z` tag is pushed. The artifact exists: the tag resolves for a package, and the build is in App Store Connect for an app. The GitHub Release exists, and LuxPM mirrors it with every shipped issue closed. A tag with no artifact or no Release is not a release.
