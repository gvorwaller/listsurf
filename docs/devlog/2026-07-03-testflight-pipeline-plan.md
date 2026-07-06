# 2026-07-03 — TestFlight pipeline plan

## Goal

Use Listsurf to learn the real Apple deployment pipeline without optimizing for
public App Store competition. The near-term success condition is a real iOS and
macOS build uploaded to App Store Connect, installable through TestFlight on
owned devices, and documented enough that the next iteration can focus on app
changes instead of distribution unknowns.

This plan deliberately stops short of public App Review unless we explicitly
choose to exercise that final step later.

## Task Structure

- `td-e1fd6f` — TestFlight pipeline proof for Listsurf
- `td-07c9ed` — Fix App Store upload blockers
- `td-47ab6b` — Verify Xcode project and test-plan readiness
- `td-e3a1c5` — Archive and upload iOS TestFlight build
- `td-9cccf4` — Archive and upload macOS TestFlight build
- `td-18ab4b` — Exercise Listsurf through TestFlight
- `td-e151b9` — Optional public App Store metadata and screenshots

Existing related task:

- `td-76cfdb` — Restore XcodeGen UI test wiring

## Current Evidence

- The worktree already contains App Store prep changes, including bundle ID,
  signing, version, app icon assets, privacy manifest, README updates, XcodeGen
  project regeneration, test-plan wiring, and one screenshot.
- `project.yml` currently sets:
  - bundle ID: `net.vorwaller.listsurf`
  - team: `BH65T3A7FT`
  - signing: Automatic
  - marketing version: `1.0.0`
  - build: `1`
- `xcodebuild -list -project Listsurf.xcodeproj` shows the expected app, logic
  test, and UI test targets for both iOS and macOS.
- `Listsurf_iOS.xctestplan` and `Listsurf_macOS.xctestplan` parse as JSON.
- App icon files exist and are wired, but current PNGs have an alpha channel and
  the 1024 image still has a visible Gemini sparkle/artifact in the lower-right.
- Only one screenshot exists: `docs/screenshots/iphone-library.jpg`, and it is a
  development/reference screenshot rather than a final public product-page set.

## Phase 1 — Fix Upload Blockers

Task: `td-07c9ed`

Scope:

- Preserve the current dirty App Store prep work.
- Flatten app icon PNGs so they have no alpha channel.
- Clean the current icon artifact if we keep that generated icon.
- Verify `App/PrivacyInfo.xcprivacy` is included in app targets.
- Keep `project.yml` as the source of truth for bundle ID, signing, version, and
  test targets.
- Regenerate `Listsurf.xcodeproj` only from `project.yml` if regeneration is
  required.

Exit criteria:

- Icon assets are valid upload candidates.
- Privacy manifest is bundled.
- Bundle/signing/version settings are still correct.
- No unrelated dirty work is discarded.

## Phase 2 — Verify Project Readiness

Task: `td-47ab6b`

Scope:

- Re-check `xcodebuild -list`.
- Validate `.xctestplan` target references.
- Run SwiftPM tests.
- Run iOS Xcode test plan on an available simulator.
- Run macOS build/tests as far as the host allows.
- If macOS UI tests still fail with `Timed out while enabling automation mode`,
  inspect the `.xcresult` and record it as a host/TCC gate only if tests never
  execute.

Exit criteria:

- The project is mechanically coherent enough to archive.
- Any remaining test limitation is evidence-backed and not silently ignored.

## Phase 3 — Commit App Store Prep Checkpoint

Scope:

- Write a devlog entry for the completed blocker/readiness work.
- Commit the coherent prep state before upload attempts.
- Keep public screenshots/metadata separate unless they become upload blockers.

Rationale:

Archive/upload attempts should happen from a committed source state so failures
can be reproduced and build numbers can be traced.

## Phase 4 — App Store Connect Setup

Scope:

- Create the App Store Connect app record for `net.vorwaller.listsurf`.
- Use Productivity as the likely category.
- Set pricing to free.
- Fill the minimum required TestFlight information.
- Answer privacy questions according to reality: local-only app, no tracking, no
  data collection.

Exit criteria:

- App Store Connect can accept uploaded builds for TestFlight.

## Phase 5 — Archive and Upload iOS

Task: `td-e3a1c5`

Preferred path:

1. Open the project in Xcode.
2. Select the `Listsurf_iOS` scheme.
3. Select a generic iOS destination.
4. Product -> Archive.
5. Validate the archive.
6. Distribute App -> App Store Connect -> Upload.
7. Wait for App Store Connect build processing.
8. Add the processed build to an internal TestFlight group.
9. Install it from TestFlight on an owned iPhone or iPad.

Exit criteria:

- iOS build is processed in App Store Connect and available for internal
  TestFlight testing.

## Phase 6 — Archive and Upload macOS

Task: `td-9cccf4`

Scope:

- Repeat the archive/upload flow for `Listsurf_macOS`.
- Record any macOS-specific signing, sandbox, entitlement, archive, or
  TestFlight differences.

Exit criteria:

- macOS build is processed in App Store Connect and available for internal
  TestFlight testing, or every blocker is documented with exact error text and
  next action.

## Phase 7 — Exercise Through TestFlight

Task: `td-18ab4b`

Scope:

- Install the TestFlight build on owned device(s).
- Create a real list.
- Edit hierarchy.
- Use check mode.
- Archive and restore.
- Export backup.
- Import backup.
- Quit and relaunch.
- Verify persistence.

Exit criteria:

- Distribution pipeline is proven end to end.
- Product friction is captured as follow-up `td` items.
- Decide whether to keep iterating privately, invite a small tester group, or
  stop before public App Review.

## Optional Phase — Public Storefront Prep

Task: `td-e151b9`

Only do this if we decide to exercise public App Review or create a presentable
product page.

Scope:

- Capture App Store-sized screenshots for iPhone library, editor, check mode,
  and macOS views.
- Write subtitle, description, keywords, support URL, and privacy policy URL.
- Complete age rating, pricing, availability, and export compliance.
- Submit for public App Review only if explicitly chosen.

This phase is intentionally not required for the TestFlight pipeline proof.

## Operating Rule

Treat this as deployment education first. Fix upload blockers and record exact
Apple/Xcode/App Store Connect behavior. Do not spend time competing with
existing outliner apps or polishing public marketing assets unless that becomes
the explicit goal.
