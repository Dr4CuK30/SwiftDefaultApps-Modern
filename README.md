# SwiftDefaultApps (modern)

View and change the **default applications** on macOS for any URL scheme (`http`, `mailto`, `ssh`…) or file type (`.md`, `public.plain-text`…), from a graphical app or the command line.

This is a from-scratch reimplementation, for modern macOS, of [SwiftDefaultApps](https://github.com/Lord-Kamina/SwiftDefaultApps) by Gregorio Litenstein. The original (v2.0.1, 2019) no longer works on current Macs:

- its binaries are Intel-only (`x86_64`) and fail with `bad CPU type in executable` on Apple Silicon without Rosetta;
- it was a `.prefPane`, and System Settings (macOS 13+) no longer properly supports third-party preference panes.

This version runs natively on **Apple Silicon and Intel** (universal binary), uses the current `NSWorkspace`/`UniformTypeIdentifiers` APIs, and ships as a **standalone app** instead of a preference pane.

## Requirements

- macOS 13 Ventura or later.
- To build: Xcode 15+ (Swift 5.9+).

## Installation

### From the release

1. Download `SwiftDefaultApps-<version>.zip` from [Releases](../../releases).
2. Unzip it and drag `SwiftDefaultApps.app` to `/Applications`.
3. The app is ad-hoc signed (not notarized): the first time, open it with **right-click → Open**, or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/SwiftDefaultApps.app
   ```

The CLI is bundled inside the app and is also available as a separate download (`swda-<version>.zip`). To put it on your `PATH`:

```bash
sudo ln -sf /Applications/SwiftDefaultApps.app/Contents/Resources/swda /usr/local/bin/swda
```

### From source

```bash
git clone https://github.com/Dr4CuK30/SwiftDefaultApps-Modern.git
cd SwiftDefaultApps-Modern
./build-app.sh
```

This produces `build/SwiftDefaultApps.app`, `./swda`, and the release zips in `dist/`.

## The app

Three sections in the sidebar:

| Section | What it does |
| --- | --- |
| **URL Schemes** | Lists every scheme known to LaunchServices along with its current app. Pick another one under "Open with" or via "Other Application…". |
| **File Types** | The same for UTIs, with their description and extension. Lets you choose the role (Viewer, Editor, Shell, or All). |
| **Applications** | For each installed app, shows which schemes and types it declares, which ones it already opens, and a "Use This App" button for the rest. |

Every list is searchable. The **Reload** button re-reads LaunchServices.

> When you change the browser (`http`/`https`), macOS shows its own confirmation dialog. This is a system restriction.

## The CLI: `swda`

Compatible with the commands of the original `swda`:

```text
swda getSchemes                        List URL schemes and their default app
swda getUTIs                           List UTIs and their default app
swda getApps                           List apps registered with LaunchServices
swda getHandler <type> [--role R] [--all]
swda setHandler <type> --app <app> [--role R]
```

`<type>` can be `--URL <scheme>`, `--UTI <uti>`, `--ext <extension>`, or a shortcut: `--browser`, `--mail`, `--ftp`, `--rss`, `--news`.
`<app>` can be a name, a bundle ID, or a path to a `.app`.

Examples:

```bash
swda getHandler --browser
swda getHandler --ext md --all
swda setHandler --ext md --app "Visual Studio Code"
swda setHandler --mail --app com.apple.mail
swda setHandler --UTI public.plain-text --role Editor --app TextEdit
```

### Differences from the original

- New `--ext` option to pass a file extension instead of a UTI.
- `--app` accepts a name, bundle ID, or path.
- `--app None` is no longer supported: modern macOS removes associations to "empty" apps, so the original's *ThisAppDoesNothing* helper has no equivalent.

## Project layout

```text
Sources/
  DefaultAppsCore/   Shared LaunchServices logic
  swda/              CLI
  SwiftDefaultApps/  SwiftUI app
Resources/           App icon (AppIcon.icns and its 1024 px source PNG)
Scripts/make-icon.swift  Redraws the icon: swift Scripts/make-icon.swift
build-app.sh         Builds both as universal binaries, assembles the .app and the release zips
```

## Credits and license

Concept and command design based on [SwiftDefaultApps](https://github.com/Lord-Kamina/SwiftDefaultApps) by Gregorio Litenstein, itself inspired by Carl Lindberg's RCDefaultApp. The code in this repository is new.

Licensed under the [MIT License](LICENSE).
