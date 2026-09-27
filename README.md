# SiftRoll

**Sift your moments, keep what matters. 篩揀時光，留存所惜。**

SiftRoll is a Tinder-style camera-roll cleaner for iPhone. Every photo in your
library is shown as a full-screen card: swipe right to keep it, swipe left to move
it to *Recently Deleted*. Photos are read straight from the system photo library
through `PHPhotoLibrary` – nothing is imported, copied or uploaded.

- **Pure SwiftUI + PhotoKit**, iOS 17+, no third-party dependencies.
- **Bilingual**: English and Traditional Chinese (Hong Kong terminology). The
  language is detected from the system on first launch and can be toggled from
  the `EN | 繁中` pill in the navigation bar or from Settings.
- **Safe by design, fast in practice**: swiping left queues a photo instead of
  deleting it on the spot. A bilingual notice explains this once per session; after
  that, swipes are instant and the queue is committed with one tap, producing a
  single iOS confirmation for the whole batch. Deleted photos land in the iOS
  *Recently Deleted* album (30-day recovery), exactly like Apple Photos.

## Requirements

- Xcode 16 or later (the project uses Xcode 16 folder-synchronized groups).
- iOS 17.0+ device or simulator. A real device with photos gives the best test.

## Run it

1. Open `SiftRoll.xcodeproj` in Xcode.
2. Select the `SiftRoll` target → *Signing & Capabilities* → pick your team
   (`DEVELOPMENT_TEAM` is intentionally left blank).
3. Choose a device or simulator and press **Run**.
4. On first launch the system asks for photo access – choose **Allow Full Access**.
   If you pick *Limit Access* or *Don't Allow*, SiftRoll explains why full access
   is needed and offers a shortcut to the Settings app.

> Note: iOS shows its own "Allow SiftRoll to delete N photos?" sheet every time an
> app calls `PHAssetChangeRequest.deleteAssets`. No app can suppress it, so SiftRoll
> batches queued photos into one call: one sheet per batch instead of one per photo.

## Project layout

```
SiftRoll.xcodeproj/            Xcode project (iOS 17+, Swift 5 language mode)
SiftRoll/
  App/
    SiftRollApp.swift          @main entry point, environment wiring
    Theme.swift                Colors (#3478F6 / #34C759 / #FF3B30), layout constants, haptics
  Localization/
    AppLanguage.swift          Supported languages + system language detection
    LocalizationManager.swift  Runtime language switching, `t("key")` lookup, bilingual helper
  Services/
    PhotoLibraryService.swift  PHPhotoLibrary authorization, fetching, image loading, deletion
  ViewModels/
    PhotoDeckViewModel.swift   Deck state, pending-deletion queue + batch commit, library-change reconciliation
  Views/
    RootView.swift             Routes between permission screen and the deck
    PermissionView.swift       Onboarding / permission request / "full access required" alert
    PhotoDeckView.swift        Main swipe screen, one-time deletion notice, pending bar, error alerts
    SettingsView.swift         Language switch, how-it-works, privacy, about
    Components/
      SwipeCardView.swift      Drag (spring back / fly away) + pinch-to-zoom + double-tap reset
      SwipeOverlayView.swift   Green "Keep / 保留" and red "Delete / 刪除" stamps
      PhotoCardView.swift      On-demand image loading with loading / error / retry states
      DeckFinishedView.swift   "All sifted" and empty-library states
      LanguageToggleButton.swift
  Resources/
    en.lproj/                  Localizable.strings, InfoPlist.strings
    zh-HK.lproj/               Localizable.strings, InfoPlist.strings (香港繁體中文)
  Assets.xcassets/             App icon, in-app logo, brand colors
  Info.plist                   NSPhotoLibraryUsageDescription and related keys
Design/
  app-icon-1024.png            App Store icon (1024×1024, no alpha)
  mockups/                     iPhone-frame UI mockups for each screen
```

## How the core flow works

| Gesture / action | Result |
| --- | --- |
| Drag right past the threshold | Card flies off, photo is kept, next card appears |
| Drag left past the threshold (first time in session) | Card holds with the red overlay, one-time bilingual notice appears; *Got It* queues the photo, *Cancel* springs it back |
| Drag left past the threshold (afterwards) | Card flies off immediately, photo joins the pending queue (no prompt) |
| ↶ button in the pending bar | Puts the last queued photo back on top of the deck |
| *Delete N Now* (pending bar or finished screen) | One `deleteAssets` call → single iOS sheet → photos move to *Recently Deleted* |
| iOS sheet declined | Queue is kept so it can be committed later |
| Release before the threshold | Card bounces back with a spring animation |
| Pinch | Zooms the photo (up to 4×); dragging pans while zoomed |
| Double-tap | Resets zoom |
| Round ✕ / ✓ buttons | Same flows as swiping, for one-handed or accessibility use |

Error handling: photos that fail to load (e.g. iCloud originals that haven't
downloaded) show an inline error with **Retry** and **Skip**; failed deletions
surface a localized alert with the PhotoKit error message. If the library changes
outside the app (deleting in Photos, iCloud sync), the deck and the pending queue
reconcile themselves through `PHPhotoLibraryChangeObserver`. The pending queue is
persisted (as asset identifiers) so an uncommitted batch survives a relaunch.

## Localization

All UI strings live in `Localizable.strings` and are looked up through
`LocalizationManager.t(_:)`, which loads the `.lproj` bundle for the selected
language at runtime (SwiftUI's built-in `Text("key")` only follows the system
language). The one-time deletion notice and the permission alert show both
languages at once via `LocalizationManager.bilingual(_:)`.

Hong Kong terminology is used throughout the Chinese strings: 相片, 相簿,
相片圖庫, 取用, 私隱與保安, 最近刪除, 設定.

## Design

The `Design/` folder contains the 1024 px app icon (film roll + soft swipe line on a
blue gradient) and iPhone-frame mockups for the five requested screens: permission
request, main swipe screen (keep and delete states, EN and 繁中), settings, and the
two alerts. They follow the dark iOS 17 style with the brand palette
`#3478F6` / `#34C759` / `#FF3B30` on `#000000`.
