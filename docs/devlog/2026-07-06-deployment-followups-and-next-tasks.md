# 2026-07-06 — Deployment follow-ups and next tasks

## Current state

Listsurf has now exercised the production-style Apple deployment path far enough to remove the original unknowns:

- The App Store Connect app record exists for `net.vorwaller.listsurf`.
- iOS and macOS archives have uploaded successfully to App Store Connect.
- Internal TestFlight distribution is available.
- The user installed the iOS build from TestFlight.
- iOS public App Review was submitted manually after required metadata, privacy, pricing, review notes, and screenshots were completed.
- Release mode is manual, so an App Review approval should still require an explicit release action before the app goes public.

## Tracker cleanup

Updated `td` state after reconciling the tracker with App Store Connect progress:

- `td-b21f7f` — App Store Connect app record: submitted for review because the app record exists and accepted iOS/macOS uploads.
- `td-e1fd6f` — TestFlight pipeline proof: kept in progress while final validation and App Review monitoring remain.
- `td-e151b9` — Optional public App Store metadata and screenshots: kept in progress because iOS submission is complete, but the task still calls for broader storefront screenshot coverage.
- `td-18ab4b` — Exercise Listsurf through TestFlight: still open as the next practical validation task.
- `td-60c5bc` — Full code review remediation plan: returned to open because only earlier slices are complete and the remediation plan still has real remaining phases.

## Immediate follow-ups

1. Monitor iOS App Review.
   - Watch for status changes from waiting to in review, approved, rejected, or clarification needed.
   - If rejected, capture the exact rejection text before changing code or metadata.
   - If approved, decide whether to manually release or hold the approved version.

2. Exercise the TestFlight builds locally.
   - Install and run the iOS build on the owned phone or iPad.
   - Install and run the macOS TestFlight build if available.
   - Create a real list.
   - Edit hierarchy.
   - Use check mode.
   - Archive and restore a list.
   - Export a backup.
   - Import a backup.
   - Quit and relaunch.
   - Verify persistence after relaunch.
   - Capture friction as follow-up `td` tasks.

3. Decide what to do with macOS public submission.
   - Either finish macOS App Store metadata/screenshots and submit it, or explicitly defer macOS public review until after product changes.

4. Improve storefront screenshots if the public App Store path remains active.
   - Current iOS submission has the minimum required iPhone and iPad screenshots.
   - Better later screenshots should include editor view, check mode, and macOS views.

## Product follow-ups

These are the main app-development tracks still represented in `td` and the planning docs:

- Phase 3 iPhone/check-mode work: compact iPhone flows, last-used mode, larger check targets, progress UI, filters, haptics, reset confirmation, undo, Dynamic Type, and physical-phone validation.
- Phase 4 interchange and hardening: JSON/OPML/Markdown round trips, archive/restore hardening, diagnostics, accessibility audit, malformed import handling, migration fixtures, and performance tests.
- Code review remediation remainder: destructive-action safety, Core Data constraints/indexes/versioning, recovery paths, performance baselines, and import/export reliability.
- OPML import: especially useful for bringing CarbonFin Outliner lists into Listsurf.
- CloudKit sync: defer until the local model, recovery, and migration paths are stable.

## Repo state to remember

Current uncommitted state after App Store screenshot and follow-up documentation work:

- Staged modified: `Listsurf.xcodeproj/xcshareddata/xcschemes/Listsurf_macOS.xcscheme`
- Staged added: `docs/screenshots/app-store/ios-65-library.png`
- Staged added: `docs/screenshots/app-store/ipad-13-library.png`
- Modified docs: this follow-up pass updated plan/devlog wording from the old validation term to "exercise" or "local validation".
- Untracked: `docs/devlog/2026-07-06-deployment-followups-and-next-tasks.md`

Do not discard those without checking whether the screenshot assets, scheme change, and follow-up docs should be committed or intentionally left out.
