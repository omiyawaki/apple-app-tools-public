# Icon Composer build

`IconComposerBuild` builds Apple app icons from Icon Composer `.icon`
documents. It compiles `Assets.car`, exports compatibility PNG and `.icns`
assets, writes rendition previews, creates a small-size review sheet, and can
verify that an app plist uses `CFBundleIconName`.

The old `~/tools/icon-composer-build` repo remains as a compatibility wrapper.
New scripts should prefer `~/tools/apple-app-tools`.
