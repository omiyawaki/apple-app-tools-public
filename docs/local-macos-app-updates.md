# Local macOS app updates

Local macOS apps use source fingerprints rather than App Store version checks.
During packaging, `MacAppPackager` writes
`Contents/Resources/LocalAppBuild.json` with the app id, project root, blueprint
path, deploy command, bundle path, source fingerprint, git head, dirty flag, and
build time.

At runtime, `LocalAppUpdateController` snapshots that metadata at launch, asks
`apple-app-tools mac fingerprint` for the current source fingerprint, and marks
an update available when the fingerprints differ. It keeps using the launch
snapshot for later checks so an old running process is not fooled by a deploy
that overwrites `LocalAppBuild.json` on disk.

The controller also reads `LocalAppBuild.json` from the configured installed
bundle path. This lets an already-running app notice that another process has
deployed a newer app bundle after it launched. In that stale-running-app case,
the update action relaunches the installed bundle without rebuilding.

Apps should expose updates with `LocalAppUpdateToolbarButton` in the trailing
toolbar. The button is hidden when the app is current, shows an icon-only
circular Liquid Glass button with an orange `arrow.down` when a local update is
available, shows an in-button spinner while updating, and uses a red warning
symbol if the update fails. Orange is intentionally distinct from blue selection
and accent affordances in the host app.

`LocalAppUpdateToolbarButton` runs the shared update monitor while it is mounted,
so apps do not need to create their own polling timers. Calling
`checkForUpdates()` once at launch is still harmless for apps that already do it.
The monitor is owned by `LocalAppUpdateController` after it starts, so temporary
toolbar visibility changes do not cancel future update checks.

The button should remain macOS-only. iOS and other App Store-managed apps do not
use this local update flow.
