# apple-app-tools

A SwiftPM toolkit for building and shipping small macOS and iOS apps without
rewriting the same plumbing in every project.

## Why

I maintain several personal Apple-platform apps. They all need the same things:
a consistent way to package a `.app` bundle and sign it, an icon build step, a
shared SwiftUI look, and a way to tell when the installed app is older than the
source. This package holds those pieces in one place so each app only keeps
what is specific to it.

## What is in it

- `AppleAppBlueprint`: parses an `AppleAppBlueprint.yaml` that describes an
  app's architecture, renders it to an `APPLE_APP_MAP.md`, and guards against
  duplicating shared components.
- `AppleAppDesignSystem`: shared SwiftUI components, including an indexed scroll
  rail and a local-update toolbar button.
- `LocalAppUpdateKit`: detects when an installed app is behind its source (it
  watches the source tree with FSEvents) and supports redeploy and reopen.
- `MacAppPackager`: assembles and signs a `.app` bundle from a SwiftPM
  executable, auto-detecting a code-signing identity.
- `IconComposerBuild`: turns an Icon Composer `.icon` file into the assets Xcode
  expects, plus a small-size review sheet.
- `AutoDeployCore` and the `auto-deploy` command: propagate a verified build to
  other Macs over Tailscale using launchd agents.

## Requirements

- macOS 26 or later
- Swift 6.2 (Xcode 26 or the matching toolchain)
- Tailscale, only for `auto-deploy`

## Build and test

```bash
swift build
swift test
```

## Usage

```bash
swift run apple-app-tools blueprint validate --config AppleAppBlueprint.yaml
swift run apple-app-tools blueprint render-map --config AppleAppBlueprint.yaml --out APPLE_APP_MAP.md
swift run apple-app-tools blueprint lock --config AppleAppBlueprint.yaml --out .apple-app-tools/blueprint.lock.json
swift run apple-app-tools mac fingerprint --config AppleAppBlueprint.yaml
swift run apple-app-tools mac package --config AppleAppBlueprint.yaml --binary .build/debug/App --plist Resources/Info.plist
swift run apple-app-tools icon build --icon Resources/AppIcon.icon --name AppIcon --out Resources
```

Each module has a short page under `docs/`.

## License

MIT. See `LICENSE`.
