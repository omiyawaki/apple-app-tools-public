# Mac app packager

`MacAppPackager` packages SwiftPM GUI executables into local `.app` bundles.
It copies the built executable, Info.plist, declared resources, and build
metadata into the bundle, then signs ad hoc and refreshes LaunchServices.

Apps can keep small app-specific deploy steps, such as generating icons or
ensuring data files exist. The final bundle assembly should go through
`apple-app-tools mac package` so metadata and signing stay consistent.
