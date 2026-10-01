# PropManager (managment-company) — iOS

SwiftUI app; bundle ID `com.nicolascooper.rentfolio`.

Open `managment-company.xcodeproj` in Xcode. Shared scheme: **managment-company** (`xcshareddata/xcschemes`).

GitHub Actions runs simulator build + tests on push/PR to `main`, `master`, `develop`.

## Xcode Cloud → TestFlight

The repo is the primary repository of the Xcode Cloud product `managment-company`, workflow
**Default** on the shared scheme `managment-company`: Archive iOS → TestFlight Internal Testing.

- `managment-company.xcodeproj/xcshareddata/xcodecloud/manifest.json` binds the project to that
  product and target. Xcode writes it when the workflow is set up or the product is loaded in the
  Cloud report navigator; keep it committed, and commit the new one if the workflow is recreated.
- No remote Swift packages and no `ci_scripts`: the project builds from a plain clone. The
  monorepo's `make ios-sync` only mirrors sources, it never touches `xcshareddata`.
- Build numbers are assigned by Xcode Cloud (1, 2, 3…), `CURRENT_PROJECT_VERSION` stays `1`.
  Version 1.0 already has manually uploaded builds up to 58, so cloud builds start at
  **1.0.1**; bump `MARKETING_VERSION` (app and `PropManagerActivities` together) for the next
  version.
