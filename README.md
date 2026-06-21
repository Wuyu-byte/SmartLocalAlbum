<div align="center">

# 📸 SmartLocalAlbum

A small iOS app I built for myself to wrangle a messy camera roll.

[English](./README.md) | [简体中文](./README.zh-CN.md)

</div>

---

## Why I made this

My own photo library got out of hand — thousands of screenshots, near-duplicates, random bursts of 5 identical shots. I wanted:

- A way to find a specific photo without scrolling forever
- A way to spot duplicates without picking through them one by one

I didn't want to upload anything to the cloud for any of this, and I didn't want a subscription. So I built this for myself, and I'm sharing it in case someone else finds it useful.

Everything runs locally on the device. No server, no account, no analytics.

---

## What it does

- 🔍 **Smart search** — Describe a photo in natural language ("beach sunset", "cat on a sofa", "white coffee cup") and search local embeddings. Uses MobileCLIP-S2 if the model is bundled; falls back to a mock extractor otherwise.
- 🧬 **Duplicate detection** — Perceptual hash (dHash) + union-find groups near-identical photos. Pick a threshold (strict / near / similar) and clean up the ones you don't want.
- 🏷️ **Smart categories** — Create a category with a few reference images, then the app auto-assigns matching photos.
- ♻️ **Recycle bin** — Deletions go to a recycle bin first. Permanent delete still triggers the iOS system confirmation, so nothing is unrecoverable by accident.

---

## Tech stack

Nothing fancy, just what I know:

- **SwiftUI** for the UI
- **CoreData** (programmatic model, no `.xcdatamodeld` file to fight with)
- **CoreML + MobileCLIP-S2** for embeddings (with a mock fallback so the UI works even without the model)
- **Vision** for face features
- **Photos** framework for the actual library access
- **WidgetKit** for the home-screen widget

iOS 16+. Built and tested on a real device.

---

## Project layout

```text
SmartLocalAlbum/
  SmartLocalAlbum.xcodeproj/
  SmartLocalAlbum/
    SmartLocalAlbumApp.swift
    Models/           DomainModels, CoreDataEntities
    Managers/         PhotoLibrary, CoreData, Scan, Search, Duplicate, Export
    Services/         ImageEmbedding, MobileCLIPText, FaceEmbedding,
                      PerceptualHash, SimilarityClassifier, WidgetShared
    Utils/            VectorUtils
    Views/            HomeView, SearchView, DuplicateGroupsView,
                      RecycleBinView, PhotoPreviewView,
                      CategoryDetailView, CreateCategoryView, LiveAlbumsView,
                      ExportSheetView, OnboardingView, etc.
    Resources/        Info.plist, Models/*.mlpackage
  SmartAlbumWidgetExtension/
  Scripts/            convert_mobileclip_image.py, convert_mobileclip_text.py
```

---

## Running it

1. Open `SmartLocalAlbum.xcodeproj` in Xcode 15+.
2. Pick the `SmartLocalAlbum` scheme and an iPhone simulator or device.
3. Run. Without the MobileCLIP model files, search results won't be accurate, but the rest of the UI works (categories, dedup, recycle bin).

If you want the real search/categorization, you need to add the model files to the target:

- `mobileclip_s2_image.mlpackage`
- `mobileclip_s2_text.mlpackage`
- `clip-vocab.json`
- `clip-merges.txt`

The `Scripts/` directory has the Python script to generate the text package from a MobileCLIP checkpoint.

---

## IPA packaging

For my own testing I export a development IPA. The repo includes `ExportOptions.development.plist` with the relevant team/bundle IDs.

Roughly:

```bash
mkdir -p build/ipa

xcodebuild \
  -project SmartLocalAlbum.xcodeproj \
  -scheme SmartLocalAlbum \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$PWD/build/SmartLocalAlbum.xcarchive" \
  clean archive \
  -allowProvisioningUpdates

xcodebuild \
  -exportArchive \
  -archivePath "$PWD/build/SmartLocalAlbum.xcarchive" \
  -exportPath "$PWD/build/ipa" \
  -exportOptionsPlist ExportOptions.development.plist \
  -allowProvisioningUpdates
```

The output lands at `build/ipa/SmartAlbum.ipa`. Install via Xcode's Devices window or Apple Configurator.

---

## Notes / known limitations

- The model files are not in the repo. You'll need to generate or download them separately.
- Limited Photos Access (iOS 14+) works, but the app can only see what you allowed.
- The recycle bin is a soft-delete — permanent delete is the only thing that actually calls `PHAssetChangeRequest.deleteAssets`.
- I wrote this for my own use, so the UI is functional rather than polished.

---

## License

MIT. See [LICENSE](./LICENSE).
