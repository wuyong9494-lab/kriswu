# Lobby artwork

## Imported icons
Icons made by **Lorc** and **Delapouite**, available at https://game-icons.net,
licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
Per-icon source URL, author and pinned upstream revision: `icons/manifest.json`.
Original SVGs and upstream license are retained in `icons/`.

Adaptations: remove the solid black background; render at 40/80/120 px; use
as tinted iOS template images within original enamel button frames. No icon
geometry was redrawn. Attribution is also visible in Arena → 设置 → 美术署名.

Rebuild: `python scripts/assets/build_lobby_icons.py` (requires `cairosvg`).
The app uses only the pre-rendered asset catalog, with no runtime downloads or SVG parsing.

## Original layout and backdrop
`ArenaLobbyArt.swift` draws a static blue arena, distant towers/banners and broad
floor ellipses. No third-party game background, logo, audio or character was extracted.
The lobby arrangement follows the existing recorded video comparison, not an exact
pixel reproduction. Acceptance requires actual iOS captures and a physical-device review.
