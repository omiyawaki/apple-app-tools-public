# Migrating existing apps

1. Add `AppleAppBlueprint.yaml` at the app root.
2. Declare imported universal components under `components`.
3. Add a package dependency on `~/tools/apple-app-tools`.
4. Import `LocalAppUpdateKit` and `AppleAppDesignSystem` in the root SwiftUI
   view.
5. Add `LocalAppUpdateToolbarItem` to the trailing toolbar.
6. Update deploy scripts to use `apple-app-tools mac package`.
7. Generate `APPLE_APP_MAP.md` and `.apple-app-tools/blueprint.lock.json`.
