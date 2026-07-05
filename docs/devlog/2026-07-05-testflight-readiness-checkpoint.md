# 2026-07-05 — TestFlight readiness checkpoint

## Goal

Execute the first implementation phases from `2026-07-03-testflight-pipeline-plan.md`: clear upload blockers, prove the generated Xcode project and test plans are mechanically sound, and create a committed checkpoint before App Store Connect archive/upload work.

## Completed

### Upload blockers

- Replaced the generated app icon set with a clean local bitmap icon and regenerated all referenced sizes:
  - `icon_1024.png`
  - `icon_512.png`
  - `icon_256.png`
  - `icon_128.png`
  - `icon_64.png`
  - `icon_32.png`
  - `icon_16.png`
- Verified every icon reports `hasAlpha: no` with `sips`.
- Kept `project.yml` as the source of truth and regenerated `Listsurf.xcodeproj` with XcodeGen.
- Verified `App/PrivacyInfo.xcprivacy` is included in both app targets; the macOS debug build copied it into `Listsurf.app/Contents/Resources/PrivacyInfo.xcprivacy`.
- Confirmed bundle/signing/version metadata remains:
  - Bundle ID: `net.vorwaller.listsurf`
  - Development team: `BH65T3A7FT`
  - Signing style: Automatic
  - Marketing version: `1.0.0`
  - Build: `1`

### Xcode project and tests

- Rechecked `xcodebuild -list -project Listsurf.xcodeproj`.
- Confirmed the expected targets remain present:
  - `Listsurf_iOS`
  - `Listsurf_iOSLogicTests`
  - `Listsurf_iOSUITests`
  - `Listsurf_macOS`
  - `Listsurf_macOSLogicTests`
  - `Listsurf_macOSUITests`
- Validated `Listsurf_iOS.xctestplan` and `Listsurf_macOS.xctestplan` with `python3 -m json.tool`.
- Validated `App/PrivacyInfo.xcprivacy` and `App/Info.plist` with `plutil -lint`.

### macOS UI-test stability

The first macOS Xcode test run exposed a harness issue in `testCoreActionsAreVisible`: XCTest attempted to scroll/click while other desktop windows were treated as interrupting elements and raised `NSInvalidArgumentException` while checking a non-string accessibility value.

The app was launching and UI tests were executing, so this was not the old "Timed out while enabling automation mode" host gate. I fixed the harness by activating the Listsurf app after launch/relaunch and immediately before the shared create-list click helper.

## Verification

Commands run from `/Users/gaylonvorwaller/listsurf`:

```sh
xcodegen generate
xcodebuild -list -project Listsurf.xcodeproj
python3 -m json.tool Listsurf_iOS.xctestplan >/dev/null
python3 -m json.tool Listsurf_macOS.xctestplan >/dev/null
plutil -lint App/PrivacyInfo.xcprivacy App/Info.plist
sips -g hasAlpha App/Assets.xcassets/AppIcon.appiconset/icon_*.png
swift test --quiet
xcodebuild test -project Listsurf.xcodeproj -scheme Listsurf_iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/listsurf-dd-ios -resultBundlePath /tmp/listsurf-ios.xcresult
xcodebuild build -project Listsurf.xcodeproj -scheme Listsurf_macOS -destination 'platform=macOS' -derivedDataPath /tmp/listsurf-dd-macos-build -resultBundlePath /tmp/listsurf-macos-build.xcresult
xcodebuild test -project Listsurf.xcodeproj -scheme Listsurf_macOS -destination 'platform=macOS' -derivedDataPath /tmp/listsurf-dd-macos-test -resultBundlePath /tmp/listsurf-macos-test.xcresult
```

Results:

- `swift test --quiet`: 95 tests passed.
- iOS Xcode test plan on iPhone 17 iOS 26.5 Simulator:
  - Logic tests: 95 passed.
  - UI tests: 4 passed.
  - Result bundle: `/tmp/listsurf-ios.xcresult`.
- macOS debug build: succeeded.
  - Result bundle: `/tmp/listsurf-macos-build.xcresult`.
- macOS Xcode test plan:
  - Logic tests: 95 passed.
  - UI tests: 6 passed after the harness activation fix.
  - Result bundle: `/tmp/listsurf-macos-test.xcresult`.

## Archive attempts

### iOS

Attempted:

```sh
xcodebuild archive -project Listsurf.xcodeproj -scheme Listsurf_iOS -destination 'generic/platform=iOS' -archivePath /tmp/listsurf-ios.xcarchive -derivedDataPath /tmp/listsurf-dd-ios-archive -allowProvisioningUpdates
```

Result: blocked before compilation by Apple signing/provisioning state.

Exact xcodebuild errors from `/tmp/listsurf-ios-archive.log`:

- `Communication with Apple failed: Your team has no devices from which to generate a provisioning profile. Connect a device to use or manually add device IDs in Certificates, Identifiers & Profiles.`
- `No profiles for 'net.vorwaller.listsurf' were found: Xcode couldn't find any iOS App Development provisioning profiles matching 'net.vorwaller.listsurf'.`

I also checked the installed signing identities and confirmed both are present:

- `Apple Distribution: GAYLON BLAINE VORWALLER (BH65T3A7FT)`
- `Apple Development: GAYLON BLAINE VORWALLER (94NK4MZHHR)`

I briefly tested forcing `CODE_SIGN_IDENTITY = Apple Distribution` for Release. Xcode rejected that because the target is still automatically signed for development:

`Listsurf_iOS has conflicting provisioning settings. Listsurf_iOS is automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified.`

That override was not kept. The next action is Apple/Xcode workflow setup rather than a repo code change: register an iOS device or use Xcode Organizer/App Store Connect to create the distribution profile path for upload.

Follow-up after connecting a physical iPhone:

- Xcode Devices and Simulators saw the device as `00008130-000869591A13803A`.
- Device build with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` succeeded.
- Xcode created `iOS Team Provisioning Profile: net.vorwaller.listsurf`.
- Re-ran iOS archive successfully at `/tmp/listsurf-ios.xcarchive`.
- Fixed two iOS validation warnings by adding `UILaunchScreen`, `UISupportedInterfaceOrientations`, and `UISupportedInterfaceOrientations~ipad` to `App/Info.plist`.
- Re-ran iOS archive after the plist fix; archive succeeded and no longer emitted the orientation/launch-screen validation warnings.

Export attempt:

```sh
xcodebuild -exportArchive -archivePath /tmp/listsurf-ios.xcarchive -exportPath /tmp/listsurf-ios-export -exportOptionsPlist /tmp/listsurf-export-app-store-connect.plist -allowProvisioningUpdates
```

Result:

- `xcodebuild -exportArchive`: succeeded.
- Export path: `/tmp/listsurf-ios-export`.
- Upload package: `/tmp/listsurf-ios-export/Listsurf.ipa`.
- The exported IPA is signed by `Apple Distribution: GAYLON BLAINE VORWALLER (BH65T3A7FT)`.
- Embedded profile: `iOS Team Store Provisioning Profile: net.vorwaller.listsurf`.

Upload attempt:

```sh
xcodebuild -exportArchive -archivePath /tmp/listsurf-ios.xcarchive -exportPath /tmp/listsurf-ios-upload-export -exportOptionsPlist /tmp/listsurf-upload-app-store-connect.plist -allowProvisioningUpdates
```

Result: blocked by missing App Store Connect app record. Xcode authenticated to App Store Connect and queried apps for `net.vorwaller.listsurf`, but App Store Connect returned `data: []`.

Specific log evidence:

- Distribution log: `IDEDistribution.DistributionAppRecordProviderError.missingApp(bundleId: "net.vorwaller.listsurf")`.
- Request log: `GET .../v1/apps?...filter[bundleId]=net.vorwaller.listsurf...`
- Response: `200 success`, `fetched 0 items`.

### macOS

Attempted:

```sh
xcodebuild archive -project Listsurf.xcodeproj -scheme Listsurf_macOS -destination 'generic/platform=macOS' -archivePath /tmp/listsurf-macos.xcarchive -derivedDataPath /tmp/listsurf-dd-macos-archive -allowProvisioningUpdates
```

Initial result: archive succeeded, but validation warned that no app category was set.

Fix:

- Added `LSApplicationCategoryType = public.app-category.productivity` to `App/Info.plist`.

Final result:

- `plutil -lint App/Info.plist`: OK.
- `xcodebuild archive` for `Listsurf_macOS`: succeeded.
- Archive path: `/tmp/listsurf-macos.xcarchive`.
- Log path: `/tmp/listsurf-macos-archive.log`.

Export attempt:

```sh
xcodebuild -exportArchive -archivePath /tmp/listsurf-macos.xcarchive -exportPath /tmp/listsurf-macos-export -exportOptionsPlist /tmp/listsurf-export-app-store-connect.plist -allowProvisioningUpdates
```

Result:

- `xcodebuild -exportArchive`: succeeded.
- Export path: `/tmp/listsurf-macos-export`.
- Upload package: `/tmp/listsurf-macos-export/Listsurf.pkg`.
- `pkgutil --check-signature`: package is signed by `3rd Party Mac Developer Installer: GAYLON BLAINE VORWALLER (BH65T3A7FT)`.
- Upload still requires App Store Connect app/authentication state.

## Remaining phases

### App Store Connect setup

This still needs an interactive Apple session:

- Create the App Store Connect app record for `net.vorwaller.listsurf`.
- Category: Productivity.
- Pricing: free.
- TestFlight information: minimum internal testing details.
- Privacy answers: no tracking and no data collection, matching the local-only app behavior and `PrivacyInfo.xcprivacy`.

### Archive and upload

Both iOS and macOS now have local App Store Connect export artifacts. Upload is blocked until the App Store Connect app record exists for `net.vorwaller.listsurf`.

Preferred path remains Xcode Organizer:

1. Open `Listsurf.xcodeproj`.
2. Archive `Listsurf_iOS` for generic iOS.
3. Validate and upload to App Store Connect.
4. Archive `Listsurf_macOS`.
5. Validate and upload to App Store Connect.
6. Record exact App Store Connect, signing, entitlement, sandbox, or upload errors if Apple rejects either build.

### Dogfood

Once App Store Connect processes builds:

- Add the builds to an internal TestFlight group.
- Install on owned iOS/macOS devices.
- Exercise create/edit hierarchy, check mode, archive/restore, export/import backup, quit/relaunch, and persistence.
- File follow-up `td` items for product friction discovered through the TestFlight build.
