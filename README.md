# SiftRoll

**Sift your moments, keep what matters. 篩揀時光，留存所惜。**

SiftRoll is a Tinder-style camera-roll cleaner for iPhone. Every photo in your
library is shown as a full-screen card: swipe right to keep it, swipe left to move
it to *Recently Deleted*. Photos are read straight from the system photo library
through `PHPhotoLibrary` – nothing is imported, copied or uploaded.

- **Pure SwiftUI + PhotoKit**, iOS 17+, no third-party dependencies.
- **Automatic albums**: the library is grouped by year and month from each photo's
  creation date (no albums are written to Photos). Tap the album pill above the card
  to sift a single month, a whole year, or everything; your place in each album is
  remembered, and counts update live as you swipe or as new photos arrive.
- **Bilingual**: English and Traditional Chinese (Hong Kong terminology). The
  language is detected from the system on first launch and can be toggled from
  the `EN | 繁中` pill in the navigation bar or from Settings.
- **Safe by design, fast in practice**: swiping left queues a photo instead of
  deleting it on the spot. A bilingual notice explains this once per session (or
  never again if *Remember my setting / 記住我的設定* is ticked); after that, swipes
  are instant and the queue is committed with one tap, producing a single iOS
  confirmation for the whole batch. Deleted photos land in the iOS
  *Recently Deleted* album (30-day recovery), exactly like Apple Photos.

## Repository (GitHub as primary)

Use **GitHub** as the source of truth for clones, CI, and day-to-day pushes.
Cursor’s Origin remote (`yuk-yiu-wan/siftroll` on [cursor.com/codebase](https://cursor.com/codebase/yuk-yiu-wan/siftroll))
can stay as a mirror after you sync from GitHub.

### One-time setup

1. **Connect GitHub in Cursor**  
   [Cursor Dashboard → Integrations](https://cursor.com/dashboard?tab=integrations) → connect your GitHub account.

2. **Create an empty GitHub repo** (e.g. `https://github.com/<your-user>/siftroll`) — no README if you are pushing an existing tree.

3. **Push `main` from your Mac** (or any machine that already has this project):

   ```bash
   cd ~/siftroll
   git remote add github https://github.com/<your-user>/siftroll.git   # skip if already added
   git push -u github main
   git push github --tags   # optional
   ```

4. **Point Cursor Codebase at GitHub**  
   [cursor.com/codebase](https://cursor.com/codebase) → **Sync from GitHub** → choose `siftroll`.  
   After this, treat GitHub as canonical; pull agents’ work from GitHub when you work locally.

### Daily workflow (GitHub primary)

```bash
git pull github main
# … edit in Xcode …
git add -A && git commit -m "Describe your change"
git push github main
```

If you still have a Cursor **origin** remote and want both updated:

```bash
git push github main && git push origin main
```

**Clone (GitHub):**

```bash
git clone https://github.com/<your-user>/siftroll.git
cd siftroll
open SiftRoll.xcodeproj
```

## Requirements

- Xcode 16 or later (the project uses Xcode 16 folder-synchronized groups).
- iOS 17.0+ device or simulator. A real device with photos gives the best test.

## Run it

### Open the Xcode project (important: repo **root**)

After clone, the layout must look like this — **`SiftRoll.xcodeproj` and the `SiftRoll/` source folder are siblings**:

```
siftroll/                    ← repository root (cd here)
├── SiftRoll.xcodeproj       ← open THIS (not inside SiftRoll/)
├── SiftRoll/                ← Swift source (App, Views, …)
├── Open SiftRoll in Xcode.command
└── README.md
```

From Terminal:

```bash
cd ~/siftroll          # repo root after clone (GitHub or Cursor mirror)
git pull github main   # or: git pull origin main if you only use Cursor remote
ls                     # you must see: SiftRoll.xcodeproj  and  SiftRoll
open SiftRoll.xcodeproj
```

Or in Finder: open the repo folder and **double-click `Open SiftRoll in Xcode.command`** (or double-click `SiftRoll.xcodeproj`).

**If you see** `The file …/SiftRoll/SiftRoll.xcodeproj does not exist`: you are in a **subfolder**, not the repo root. Run `pwd` and `ls`; go up with `cd ..` until `ls` shows `SiftRoll.xcodeproj` next to `SiftRoll/`.

### Fix “Invalid redeclaration” / “ambiguous for type lookup”

These errors mean Xcode is **compiling the same Swift file twice** (common after a nested clone or an old synchronized-folder project).

```bash
cd ~/siftroll
git pull github main   # or origin main
git checkout github/main -- SiftRoll.xcodeproj   # reset project file (use origin/main if needed)
bash Scripts/verify-xcode-project.sh           # should print: ok: 21 Swift files…
find . -name 'AssetThumbnailView.swift'        # should list ONLY ONE path
```

In Xcode: target **SiftRoll → Build Phases → Compile Sources** — each `.swift` should appear **once**. Remove any duplicate rows or a second **SiftRoll** folder reference. Then **Product → Clean Build Folder** (⇧⌘K) and build again.

1. Open the project in **Xcode 16+** (synchronized `SiftRoll/` folder; shared scheme **SiftRoll**).
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
  Models/
    PhotoAlbum.swift           DateKey, AlbumSelection (all / year / month), YearAlbum, MonthAlbum
  Services/
    PhotoLibraryService.swift  PHPhotoLibrary authorization, fetching, image loading, deletion
    DeletionPreferences.swift  Once-per-session flag + persisted "Remember my setting"
  ViewModels/
    PhotoDeckViewModel.swift   Deck state, year/month albums, pending-deletion queue + batch commit, library-change reconciliation
  Views/
    RootView.swift             Routes between permission screen and the deck
    PermissionView.swift       Onboarding / permission request / "full access required" alert
    PhotoDeckView.swift        Main swipe screen, one-time deletion notice, pending bar, error alerts
    SettingsView.swift         Language switch, how-it-works, privacy, about
    AlbumPickerView.swift      Sheet listing All Photos → years → months with counts and covers
    Components/
      SwipeCardView.swift      Drag (spring back / fly away) + pinch-to-zoom + double-tap reset
      SwipeOverlayView.swift   Green "Keep / 保留" and red "Delete / 刪除" stamps
      DeletionNoticeView.swift Custom alert-style notice with the remember checkbox
      AssetThumbnailView.swift Small on-demand thumbnail used for album covers
      PhotoCardView.swift      On-demand image loading with loading / error / retry states
      DeckFinishedView.swift   "All sifted" and empty-library states
      LanguageToggleButton.swift
  Resources/
    en.lproj/                  Localizable.strings, InfoPlist.strings
    zh-HK.lproj/               Localizable.strings, InfoPlist.strings (香港繁體中文)
  Assets.xcassets/             App icon, in-app logo, brand colors
SupportingFiles/
  Info.plist                   NSPhotoLibraryUsageDescription (not copied into the app bundle; merged at build time)
Design/
  app-icon-1024.png            App Store icon (1024×1024, no alpha)
  mockups/                     iPhone-frame UI mockups for each screen
```

## How the core flow works

| Gesture / action | Result |
| --- | --- |
| Drag right past the threshold | Card flies off, photo is kept, next card appears |
| Drag left past the threshold (first time in session) | Card holds with the red overlay, one-time bilingual notice appears with a *Remember my setting* checkbox; *Got It* queues the photo, *Cancel* springs it back. The remembered choice can be reset in Settings › Deletion |
| Drag left past the threshold (afterwards) | Card flies off immediately, photo joins the pending queue (no prompt) |
| ↶ button in the pending bar | Puts the last queued photo back on top of the deck |
| *Delete N Now* (pending bar or finished screen) | One `deleteAssets` call → single iOS sheet → photos move to *Recently Deleted* |
| iOS sheet declined | Queue is kept so it can be committed later |
| Release before the threshold | Card bounces back with a spring animation |
| Pinch | Zooms the photo (up to 4×); dragging pans while zoomed |
| Double-tap | Resets zoom |
| Round ✕ / ✓ buttons | Same flows as swiping, for one-handed or accessibility use |
| Album pill above the card | Opens the album picker (All Photos, each year, each month); the deck reloads for that album and resumes where you left it |

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
