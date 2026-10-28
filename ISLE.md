# Isle additions (fork of TheBoredTeam/boring.notch)

GPL-3.0, like upstream. All new code lives in `boringNotch/Isle/` (a folder
synced into the Xcode target); a handful of existing files got small hooks.

## Features

| Area | What | Where |
| --- | --- | --- |
| Liquid Glass | Open island uses `glassEffect(.regular.tint(.black.opacity(t)), in: notchShape)` on macOS 26+ (t = "Glass darkness", default 0.72), with a black band (solid at notch height, fading out 34 pt below). Closed island stays black. Header/timer buttons use `.regular.interactive()`. Black fallback before macOS 26 or when built with Xcode < 26. | `IsleGlass.swift`, `ContentView.swift`, `BoringHeader.swift` |
| Menu bar shield | In full screen, a HID-level `CGEventTap` clamps the y of mouse-moved/dragged events above the island to `clearance` pt below the edge, so the auto-hidden menu bar does not slide down. Never warps or detaches the pointer. Bypass: hold ⌘/⌥/fn, or push upward for ~1 s. Tap is only enabled while a full-screen space is visible, and is torn down on sleep, lock and quit. Needs Accessibility. | `MenuBarShield.swift` |
| Calendar alerts | N min (default 10) before start and at start, using the calendars selected under Calendar. | `IsleMonitors.swift` |
| Timer | Ring and remaining time around the closed notch, plus a Timer tab with presets, ±1 min, pause and cancel. | `IsleTimer.swift` |
| Bluetooth | "Connected" activity for AirPods and other devices, with battery level (AirPods via IOBluetooth, Apple keyboards/mice via IORegistry). | `BluetoothActivityMonitor.swift` |
| Low battery | One alert each at 20, 10 and 5 % while not charging. | `IsleMonitors.swift` |
| Brightness HUD | Shows the HUD for brightness changes made outside the app, but ignores auto-brightness (only jumps of at least 0.03 between 0.4 s samples). | `IsleMonitors.swift` |
| Hover peek | The closed island grows ~16×4 pt while hovered. A click opens it at once, and the delay is adjustable. | `ContentView.swift`, `IsleSettingsView.swift` |
| Polish | Glow in the album color, and a blur/scale transition on open. Marquee titles and the draggable scrubber already existed upstream. | `IsleGlass.swift` |

All of these can be toggled under **Settings → Island**.

## CI

`.github/workflows/isle-build.yml` runs two unsigned builds: one on
`macos-latest` with the newest stable Xcode (Liquid Glass path), and one on
`macos-15` with Xcode 16 (fallback path).
