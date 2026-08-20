# App Store checklist

- [x] Confirm bundle identifier `com.echocool.Tessalytics` and automatic signing for team `P8FYZDZ6AA`
- [x] Confirm iOS 18 minimum deployment target and iPhone-only device family
- [x] Capture and upload five current 6.9-inch App Store screenshots using sanitized demo data
- [ ] Complete additional dark-mode and large Dynamic Type visual QA
- [ ] Complete VoiceOver walkthrough of onboarding, status, lists, maps, and charts
- [x] Add an app privacy manifest declaring no tracking or data collection and the app-only UserDefaults reason
- [x] Publish a privacy-policy URL based on `PRIVACY.md` at https://tessalytics.echo.cool/privacy/
- [ ] Verify Keychain item accessibility and local data protection on physical hardware
- [ ] Test Bearer, Basic, VPN-only, offline, stale, asleep, and multi-vehicle cases
- [ ] Test against the minimum and current supported Tessalytics Backend versions
- [x] Run unit and UI suites on the release Xcode version
- [x] Review repository and release artifacts for secrets and precise location
- [x] Verify every Owner API command has confirmation plus device-owner authentication and no automatic wake path exists
- [x] Verify Owner API tokens use When Unlocked, This Device Only Keychain protection and are absent from logs/preferences/cache
- [ ] Exercise Owner API refresh rotation and each supported command against a non-production vehicle token
- [ ] Review TeslaMate trademark policy and all screenshots/metadata for unofficial positioning
- [ ] Include the unofficial-project disclaimer in store description/support material
- [x] Declare exempt encryption in the generated Info.plist
- [x] Complete the age-rating declaration with no applicable content descriptors or restricted capabilities
- [x] Add English (U.S.) TestFlight beta description and feedback email
- [x] Prepare App Store description, subtitle, promotional text, keywords, review notes, and questionnaire handoff
- [x] Upload and process five App Store screenshots
- [x] Archive, validate, upload, and confirm TestFlight processing for `1.0.1 (3)`
- [x] Archive, validate, upload, and confirm TestFlight processing for `1.1.0 (4)`
- [x] Confirm TestFlight processing and select `1.1.0 (5)` for the App Store version
- [x] Archive, validate, upload, process, and internally distribute `1.0.3 (202608191804)` with generated Demo Mode
- [x] Archive, validate, upload, and confirm processing for `1.2.1 (202608192006)`
- [x] Write App Review notes that open with demo mode instead of a review-server URL
- [x] Assemble the `release/tessalytics-1.2.1/` submission kit
- [x] Push the 1.2.1 kit review notes, TestFlight notes, and site URLs with `scripts/asc.py`
- [ ] Push `whats_new.txt` once a version record exists that accepts it (not the initial store version)
- [ ] Rename the 1.1.0 version record to 1.2.1 and select build `202608192006` (build 5 has expired)
- [ ] Re-shoot 6.9-inch screenshots if the dashboard or Activity changes are visible in them

## 1.6.0 submission

- [x] Capture a current iPad screenshot set (`TARGETED_DEVICE_FAMILY` is `"1,2"`, so App Store Connect requires one)
- [x] Re-capture the 6.9-inch iPhone set; the uploaded one predated the 1.6.0 home screen
- [x] Teach `scripts/asc.py` to upload screenshots (reserve, PUT, commit) and to create/withdraw a review submission
- [x] Withdraw the 1.2.1 submission so 1.6.0 could hold the editable version record
- [x] Submit 1.6.0 (build `202608201258`) — `WAITING_FOR_REVIEW`

Both sets are captured by `ScreenshotCaptureTests` from demo mode, so they can be
retaken for any device class in one command and never carry the real vehicle's
addresses or VIN:

    TEST_RUNNER_TESSALYTICS_SCREENSHOT_DIR=/tmp/shots xcodebuild test \
      -only-testing:TessalyticsUITests/ScreenshotCaptureTests \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'

`whatsNew` stays locked until the app has a released version, so `push-locale`
reports it as skipped rather than failing the whole push.
