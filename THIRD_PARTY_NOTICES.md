# Third-party notices

This application adapts UI components from [Licoy/codex-runway](https://github.com/Licoy/codex-runway), revision `411240f4bd758e8d5f788b94e4187ba161374ebb` (retrieved 2026-10-09).

Copyright belongs to the CodexRunway authors and contributors. The upstream repository is licensed under the GNU Affero General Public License v3.0. The full license is included in `LICENSE` and bundled with this application as `Resources/Licenses/CodexRunway-AGPL-3.0.txt`.

`Sources/PanelComponents.swift` adapts `RunwaySurface.swift`, `RunwayCursor.swift`, and the `HeaderActionButton`, `DetailBackButton`, `FooterGhostButton`, and `RunwayHairline` components of `RunwayPopoverView.swift`. Names and visibility have been adjusted for esai. The rest of the application implements esai's interface and daily WeChat scheduler. The combined source is provided under AGPL-3.0. Corresponding source, build scripts, and required icon resources are included in this repository: https://github.com/fitzsmith2000/esai.

`Sources/GlassControls.swift` also adapts the 3 pt `ThinOverlayScroller` drawing from `PolishedScrollView.swift` at the same revision. The project is now named [Quosparr](https://github.com/Licoy/Quosparr). esai retains its existing SwiftUI scroll host and applies this transparent, trackless scroller to it.
