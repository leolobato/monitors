# Monitors

A macOS menu bar app that lists the connected displays and turns each one on or off.

It uses the private SkyLight `SLSConfigureDisplayEnabled` call, the same soft disconnect that Playden uses. When the app quits, it
turns on again all the displays that it disabled. A crash or a force quit (`kill -9`) does not do this. In that case, open the app
and use **Enable All Displays**. If the app does not show the display
(for example, after a reboot changed the display IDs), disconnect and connect the monitor again, or restart the Mac.

- The app never disables the last enabled display.
- The app does not disable displays while mirroring is on.
- The app lists an offline display only if the app disabled it. SkyLight also reports empty display slots.

## Build

```sh
cp Configuration/LocalSigning.xcconfig.example Configuration/LocalSigning.xcconfig  # set your team
xcodegen generate
xcodebuild -project Monitors.xcodeproj -scheme Monitors -destination 'platform=macOS' build
```
