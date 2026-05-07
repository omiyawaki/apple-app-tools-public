# Local macOS app updates

Local macOS apps use source fingerprints rather than App Store version checks.
During packaging, `MacAppPackager` writes
`Contents/Resources/LocalAppBuild.json` with the app id, project root, blueprint
path, deploy command, bundle path, source fingerprint, git head, dirty flag, and
build time.

At runtime, `LocalAppUpdateController` reads that metadata, asks
`apple-app-tools mac fingerprint` for the current source fingerprint, and marks
an update available when the fingerprints differ.

Apps should expose updates with `LocalAppUpdateToolbarButton` in the trailing
toolbar. The button is hidden when the app is current, shows a compact native
`Update` label with `arrow.down.circle.fill` when a local update is available,
shows an in-button spinner while updating, and keeps a warning affordance if
the update fails.

The button should remain macOS-only. iOS and other App Store-managed apps do not
use this local update flow.
