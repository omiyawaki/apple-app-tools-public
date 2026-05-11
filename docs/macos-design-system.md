# macOS design system

The design system favors native macOS structures over custom chrome:
NavigationSplitView, standard toolbars, semantic foreground styles, system
materials, compact controls, and icon-leading labels.

Reusable controls belong here when they are useful across multiple local apps.
App-specific views belong in the app repo and should be listed in
`AppleAppBlueprint.yaml` under `localModules`.

The first shared control is `LocalAppUpdateToolbarItem`, which gives local apps
a consistent update affordance.
