# Controller presets

Gamepad profiles use portable JSON, so players can export a mapping, upload it to the community preset page, and import a downloaded file without platform-specific data.

In **Controls → Gamepad Setup**, capture actions from the controller, tune the axes and thresholds, and select one of eight slots. **Export** saves the profile to the selected slot and opens a native Save dialog for a portable JSON file; upload that file to the community site. **Import** opens a file picker for a downloaded profile, validates it, applies the mapping, and saves a copy into the selected slot. The current mapping is shared by all connected controllers. On platforms without the native macOS picker, the slot JSON files can be exchanged directly under `saves/controller-presets/`.

An exported file has this shape:

```json
{
  "format": 1,
  "name": "Controller preset 1",
  "vendor": "Controller manufacturer",
  "product": "Product category",
  "mapping": {
    "buttons": [0, 1, 2, 4, 5, 3, 6, 7, 11, 10, 8, 9, 12, 13, 14, 15],
    "axes": [0, 1, 2, 3],
    "invert": [false, false, false, false],
    "deadzone": 0.18,
    "trigger_threshold": 0.15
  }
}
```

`buttons` follows this action order: jump, dodge, interact/mantle, grapple, traversal, camera view, sprint, fire, alternate, stomp, menu/join, respawn, UI up, UI down, UI left, UI right. On Apple's standard profile, button IDs are A/Cross (0), B/Circle (1), X/Square (2), Y/Triangle (3), left/right shoulder (4–5), left/right trigger (6–7), Menu (8), Options (9), left/right stick click (10–11), then D-pad up/down/left/right (12–15). Generic HID devices expose their first 16 numbered buttons and hat-switch directions through the same IDs; button capture is the reliable way to map them. Trigger IDs use the analog threshold setting.

Axis IDs are left stick X/Y (0–1) and right stick X/Y (2–3). The four `axes` entries select the physical source for move X, move Y, look X, and look Y; matching `invert` entries reverse those logical axes. `deadzone` must be in `[0, 0.8)` and `trigger_threshold` in `[0, 1]`. Unknown JSON fields are ignored so compatible site metadata can be added without changing the game format.

The macOS bridge first reads GameController Extended and Micro Gamepad profiles, then discovers generic HID joystick, gamepad and multi-axis devices through IOKit. This lets players remap many third-party devices that do not publish Apple's standard profile, as long as macOS exposes them as supported HID game controllers. Keyboard-only devices, unusual vendor-specific interfaces, and devices hidden by the OS still need a native backend. Windows and Linux gamepad backends are not implemented. The website upload/download experience itself is a separate website integration; exported JSON is ready to host there.
