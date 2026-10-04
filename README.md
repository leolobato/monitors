# Monitors

A macOS menu bar app that lists your connected displays and lets you turn each one off and on again.

It uses the private SkyLight API (`SLSConfigureDisplayEnabled`) to soft-disconnect a display. When you quit the app, it turns
the displays back on. The app never disables your last active display.

Requires macOS 15 or later. The app uses a private API, so it is not sandboxed and cannot be distributed on the Mac App Store.

## Build

```sh
cp Configuration/LocalSigning.xcconfig.example Configuration/LocalSigning.xcconfig  # set your team ID
make install   # Developer ID signed Release build, installed to /Applications
```

`make build` only builds. `make uninstall` removes the app.

If a display stays off (for example, after a crash), open the app and choose **Enable All Displays**.

## License

MIT
