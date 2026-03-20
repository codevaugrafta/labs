# App icon (Dock) vs in-app mark

- **Main window** uses the SwiftUI **AdhanBrandMark** (crescent + eight-point star + wordmark). It tracks the active theme automatically.
- **Dock / Finder** uses **`Sources/Resources/AppIcon.icns`**. Updating it:
  1. Produce a **1024×1024** master (PNG or PDF) with safe margins per [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons).
  2. Generate the `.icns` set (e.g. `iconutil` on an `.iconset` folder, or an asset tool).
  3. Replace `AppIcon.icns` and rebuild with `./build-app.sh`.

Align the raster icon with the in-app geometry (crescent + small star, emerald/gold or midnight palette) for a consistent story.
