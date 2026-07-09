# 2026-07-07 - macOS App Review submission

## Goal

Finish the public App Review path for the macOS side of Listsurf after the iOS app was already submitted, so the Apple deployment cycle has been exercised on both platforms.

## Completed

- Prepared the macOS App Store version metadata in App Store Connect.
- Uploaded a macOS App Store screenshot:
  - `docs/screenshots/app-store/macos-library.png`
  - Dimensions: `1440 x 900`
- Attached the processed macOS build:
  - Version: `1.0.0`
  - Build: `1`
  - Upload date shown in App Store Connect: July 5, 2026 at 7:34 PM
- Reused the established app review contact details:
  - Contact: Gaylon Vorwaller
  - Email: `gaylon@vorwaller.net`
  - Phone: `904-403-9216`
- Confirmed sign-in is not required.
- Set the release option to manual release, matching the iOS submission posture.
- Submitted the macOS app version for App Review.

## App Store Connect evidence

App Store Connect now shows a dedicated macOS submission:

- Platform submission: `macOS Submission`
- Status: `Waiting for Review`
- Item submitted: `macOS App 1.0`
- App version: `1.0.0 (1)`
- Type: `App Version`
- Date submitted: `Jul 7, 2026 at 12:27 PM`
- Submitted by: `Gaylon Vorwaller`
- Submission ID: `d10e0835-d50b-4463-b766-cab529f03299`

The iOS app version was already in `Waiting for Review`, so both public App Review paths are now active.

## Local verification

Commands run from `/Users/gaylonvorwaller/listsurf`:

```sh
sips -g pixelWidth -g pixelHeight docs/screenshots/app-store/macos-library.png
git status --short --branch
td usage -q
```

Results:

- `docs/screenshots/app-store/macos-library.png` is `1440 x 900`.
- Current branch is `main` tracking `origin/main`.
- Current uncommitted files after this entry are expected to include:
  - `docs/screenshots/app-store/macos-library.png`
  - `docs/devlog/2026-07-07-macos-app-review-submission.md`
- `td-e1fd6f` remains the active deployment pipeline epic while review monitoring and TestFlight exercise notes continue.

## Remaining follow-ups

1. Monitor App Review for both iOS and macOS.
   - If either platform is rejected, capture the exact rejection text before changing code or metadata.
   - If approved, release manually only after deciding that the current public listing should go live.

2. Continue exercising the app from TestFlight.
   - Create real lists.
   - Edit hierarchy.
   - Use check mode.
   - Archive and restore.
   - Export and import backups.
   - Quit, relaunch, and verify persistence.
   - Convert friction into concrete `td` tasks.

3. Decide whether the first public release should remain mostly a deployment-learning milestone or receive another product-polish pass before manual release.

4. Commit the new macOS screenshot and this devlog entry when ready.

