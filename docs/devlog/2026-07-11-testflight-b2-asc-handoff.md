# 2026-07-11 — Build 2 upload + App Store Connect session: state and handoff

Handoff doc for completing the build-2 review swap. Written after ~2 hours; the CLI half went cleanly, the ASC-web half is partially complete with two problems left, one of them self-inflicted. Everything verified below is verified; everything not marked verified should be re-checked.

## App identifiers

- App Store Connect app ID: **6787792431** (bundle `net.vorwaller.listsurf`, team `BH65T3A7FT`)
- ASC team path: `/teams/aac569eb-a251-4eb5-8ce3-2ca9eada0260/`
- Version pages: `/apps/6787792431/distribution/{ios|macos}/version/inflight`
- Review submissions: `/apps/6787792431/distribution/reviewsubmissions`
- TestFlight: `/apps/6787792431/testflight/{ios|macos}`

## COMPLETED (verified)

1. **Build number bumped to 2** — `project.yml` `CURRENT_PROJECT_VERSION: "2"`, `xcodegen generate`, committed/pushed (`719aa32`). Marketing version stays 1.0.0.
2. **iOS 1.0.0 (2) archived and uploaded** — archive `/tmp/listsurf-ios-b2.xcarchive`; upload via `xcodebuild -exportArchive` with `/tmp/listsurf-upload-app-store-connect.plist` (method `app-store-connect`, destination `upload`, teamID `BH65T3A7FT`). Processed in ASC ("Complete", 1:27 PM).
3. **macOS 1.0.0 (2) archived and uploaded** — `/tmp/listsurf-macos-b2.xcarchive`, same plist. Processed ("Complete", ~1:34 PM).
4. **iOS 1.0 removed from review** → Developer Rejected (editable).
5. **macOS 1.0 removed from review** → Developer Rejected.
6. **TestFlight iOS build 2**: "What to Test" filled and saved (feature summary of the interchange milestone); groups = Internal Dogfood (auto-attached) + **External Beta** (added); **submitted for Beta App Review**. Verified "Groups (2)" on the build page.
7. **TestFlight macOS build 2**: same — notes saved, groups External Beta + Internal Dogfood ("Groups (2)" verified), submitted for beta review.
8. **Marcus added as external tester**: `marcus@vorwaller.net`, "Marcus Vorwaller", External Beta group — verified "Tester (1)" with his row. His invite becomes actionable when a build is available to the group (beta review). Internal Dogfood (Gaylon) gets build 2 with no review gate.
9. **iOS App Store submission DONE**: version 1.0 build swapped 1→2 (verified "2 / 1.0.0" on the version page), saved, added for review, and **submitted — "Waiting for Review"**, submission ID `92708dfe-ebfd-4121-87bc-a0cfda627ed8`, submitted 2:19 PM, item "iOS App 1.0 / 1.0.0 (2)" (verified on the submission record).

## REMAINING (for Codex)

1. **macOS draft submission has the WRONG BUILD — do not submit it as-is.** The draft (created 2:16 PM) contains "macOS App 1.0 / **1.0.0 (1)**". My Add Build selection didn't take (radio click registered visually as checked, but the attached build ended up (1) — root cause not established; treat every attach as unverified until the version page's Build row is re-read). The macOS version is now **"Ready for Review" = locked**: the Build row shows no delete control while the version sits in a draft submission. Required sequence:
   - App Review page → expand the macOS draft → **remove the item / delete the draft** (unlocks the version), then
   - version page → remove build (1) if still attached → Add Build → select **1.0.0 (2)** → confirm → **re-read the Build row and verify it says (2)** → Save if enabled → Add for Review → open the draft → verify the item says **1.0.0 (2)** → Submit for Review.
2. **macOS screenshot is GONE — I deleted it.** While probing for the build-row delete control I clicked a bare "Delete" button that belonged to the **App Previews and Screenshots** section; the deletion persisted through reload ("0 of 10 Screenshots"). The original file is in the repo: `docs/screenshots/app-store/macos-library.png` (1440×900, the accepted size). **Re-upload it via "Choose File"** on the macOS version page before submitting — a macOS version with zero screenshots may fail submission validation. My attempted scripted upload (Choose File → Cmd+Shift+G → path) did not complete; unverified whether the file sheet even opened.
3. **After Beta App Review approves build 2** for External Beta: confirm Marcus's invite email went out (TestFlight → External Beta → tester status changes from "No Builds Available"/invited).
4. Optional housekeeping flagged by ASC: **Age Ratings social-media questions** due Sept 7, 2026 (banner on version pages).

## Environment/tooling notes (the expensive lessons)

- **Homebrew rsync breaks `xcodebuild -exportArchive`**: `/opt/homebrew/bin/rsync` (3.4.1) shadows Apple's; Xcode's rsync client spawns its server side via PATH and it rejects `--extended-attributes`, failing the IPA copy step with a bare "Copy failed" (detail only in `*.xcdistributionlogs/IDEDistributionPipeline.log`). Fix used for both uploads: prefix `env PATH="/usr/bin:/bin:/usr/sbin:/sbin"`.
- **safaridriver/WebDriver is a dead end for ASC**: automation windows get an ephemeral (logged-out) session per WebDriver session, and the glass-pane overlay disrupts the user. The working channel is **`osascript` → Safari `do JavaScript` into the real, logged-in ASC tab** ("Allow JavaScript from Apple Events" is enabled in Safari Developer settings).
- **The ASC SPA ignores synthetic JS clicks** on most action buttons/menus. Real clicks work: `cliclick c:x,y` (installed at /opt/homebrew/bin/cliclick) or System Events `click at {x,y}`. Screen coords from page geometry: `window.screenX + rect.left + rect.w/2`, `window.screenY + (outerHeight - innerHeight) + rect.top + rect.h/2`.
- Reading page state via `document.body.innerText` slices works well; `[role=dialog]` probes are unreliable for ASC's modals (some don't use the role).
- Some ASC table rows reveal their controls only on real mouse hover; and some "Delete" buttons are icon-only with empty accessible context — **never click a Delete without confirming which section owns it** (see: the screenshot casualty).
- Radio/checkbox selection in ASC dialogs: click the input's own coordinates, then **verify `checked` state via JS AND verify the final effect on the underlying page** — one checked-looking radio still produced a wrong attach.

## Where things were left in the UI

- Safari front tab: macOS version page (`.../distribution/macos/version/inflight`), scrolled to the empty screenshots section.
- Sidebar states at handoff: iOS App "1.0 Waiting for Review" (build 2, submitted); macOS App "1.0 Ready for Review" (build 1 in draft — WRONG, see Remaining #1).
- TestFlight: both platform build 2s carry Internal Dogfood + External Beta, beta review submitted.
