# MoonMenuBar

MoonMenuBar is a lightweight macOS menu bar app that shows the current Moon phase and relative Moon brightness for the user's location.

## Features

- Shows a Moon phase icon in the macOS menu bar.
- Optionally shows relative brightness percentage next to the icon.
- Adjusts icon brightness from the estimated Moon phase brightness.
- Shows current Moon altitude and compass direction for the user's location.
- Supports launch at login.
- Builds a distributable `.app` bundle and `.dmg` installer with `build.sh`.

## Requirements

- macOS with Swift compiler and Xcode Command Line Tools.
- Location permission is required for location-based Moon direction and local time zone handling.

## Build

```bash
./build.sh
```

The script creates:

- `MoonMenuBar.app`
- `MoonMenuBar.dmg`

Generated build artifacts are intentionally ignored by Git.

## Run locally

```bash
open MoonMenuBar.app
```

If you run the app from the DMG volume, launch-at-login may not work reliably. Move `MoonMenuBar.app` to `/Applications` before enabling launch at login.

## Notes on accuracy

MoonMenuBar uses an approximate astronomical model for Moon phase, relative brightness, altitude, and azimuth. The brightness value is relative to a full Moon and does not include local weather, clouds, atmospheric extinction, terrain obstruction, or refraction.

## License

MIT License. See [LICENSE](LICENSE).
