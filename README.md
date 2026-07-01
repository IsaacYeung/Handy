# Handy

A lightweight macOS menu-bar utility that adds the small Finder conveniences macOS leaves out.

## Features

- **Cut & Paste files** in Finder — `⌘X` to mark, `⌘V` in another folder to move (a real move, not a copy)
- **Open with Return** — press `Return` to open the selected item instead of renaming it
- **Right-click extras** — Copy Path, Open in Terminal (iTerm2 if installed), New .txt File Here, and Extract All Here for `.zip` files
- **Bluetooth off on sleep** — optionally turn Bluetooth off when your Mac sleeps and back on when it wakes
- **Keep Awake** — stop the screen and system from sleeping
- **Empty Trash** from the menu bar

## Requirements

- macOS 13 (Ventura) or later
- Accessibility permission (for the keyboard features)
- Automation permission for Finder (for cut/paste/open)

## Building from source

```sh
bash build.sh
```

This type-checks, runs the unit tests, compiles the app and its FinderSync
extension, signs (ad-hoc by default), verifies the bundle, and produces
`Handy.dmg`.

To build a distributable, notarizable copy, sign with a Developer ID:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash build.sh
```

## License

MIT — see [LICENSE](LICENSE).
