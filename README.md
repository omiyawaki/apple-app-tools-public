# apple-app-tools

Reusable local tooling for Apple-platform apps.

This repo is the source of truth for app-building pieces that should not be
rebuilt separately in each app. Apps describe their architecture in
`AppleAppBlueprint.yaml`, import shared SwiftPM modules from this package, and
generate an `APPLE_APP_MAP.md` so anyone can see how the app is put
together before editing it.

## Commands

```bash
swift run apple-app-tools blueprint validate --config AppleAppBlueprint.yaml
swift run apple-app-tools blueprint render-map --config AppleAppBlueprint.yaml --out APPLE_APP_MAP.md
swift run apple-app-tools blueprint lock --config AppleAppBlueprint.yaml --out .apple-app-tools/blueprint.lock.json
swift run apple-app-tools mac fingerprint --config AppleAppBlueprint.yaml
swift run apple-app-tools mac package --config AppleAppBlueprint.yaml --binary .build/debug/App --plist Resources/Info.plist
swift run apple-app-tools icon build --icon Resources/AppIcon.icon --name AppIcon --out Resources
```

## Modules

- `AppleAppBlueprint`: blueprint parser, component registry, map renderer, and
  duplicate guard.
- `AppleAppDesignSystem`: shared SwiftUI visual language.
- `LocalAppUpdateKit`: local update detection and redeploy/reopen support.
- `MacAppPackager`: shared `.app` bundle packaging and metadata writing.
- `IconComposerBuild`: Icon Composer asset pipeline migrated from
  `~/tools/icon-composer-build`.

## Test

```bash
swift test
```
