# Icon Composer build

`IconComposerBuild` builds Apple app icons from Icon Composer `.icon`
documents. It compiles `Assets.car`, exports compatibility PNG and `.icns`
assets, writes rendition previews, creates a small-size review sheet, and can
verify that an app plist uses `CFBundleIconName`.

Pass `--design-generation 27` with Icon Composer 2 to render both appearance
previews and the small-size review sheet with the current generation. The
review sheet is exported directly with the selected `ictool`; compatibility
`.icns` and `Assets.car` files still come from `actool` for the configured
deployment target.

Build icons with the `apple-app-tools icon build` command.
