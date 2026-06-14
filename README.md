# SmartLocalAlbum

iOS 16+ SwiftUI project for local-only photo grouping and lightweight camera-roll cleanup.

## Directory

```text
SmartLocalAlbum/
  SmartLocalAlbum.xcodeproj/
  SmartLocalAlbum/
    SmartLocalAlbumApp.swift
    Models/
      DomainModels.swift
      CoreDataEntities.swift
    Managers/
      PhotoLibraryManager.swift
      CoreDataManager.swift
      SmartCategoryManager.swift
      ScanManager.swift
      BackgroundScanManager.swift
      SearchManager.swift
      DuplicateDetectionManager.swift
      ExportManager.swift
    Services/
      ImageEmbeddingExtracting.swift
      TextEmbeddingExtracting.swift
      ImageEmbeddingExtractor.swift
      MobileCLIPTextEmbeddingExtractor.swift
      LazyEmbeddingExtractors.swift
      MockImageEmbeddingExtractor.swift
      SimilarityClassifier.swift
      PerceptualHashExtractor.swift
      WidgetSharedData.swift
      WidgetSyncService.swift
      FaceEmbeddingExtractor.swift
    Utils/
      VectorUtils.swift
    Views/
      HomeView.swift
      CreateCategoryView.swift
      CategoryDetailView.swift
      PhotoGridItemView.swift
      PhotoPreviewView.swift
      EmptyStateView.swift
      ShareSheetView.swift
      RecycleBinView.swift
      OnboardingView.swift
      SearchView.swift
      DuplicateGroupsView.swift
      ExportSheetView.swift
      LiveAlbumsView.swift
      MetadataFilterView.swift
    Resources/
      Info.plist
      Models/
        mobileclip_s2_image.mlpackage
        mobileclip_s2_text.mlpackage
        clip-vocab.json
        clip-merges.txt
```

## Core Data model

The first version builds the model programmatically in `CoreDataManager.swift`, so there is no `.xcdatamodeld` file to keep in sync.

- `PhotoEmbeddingEntity`
  - `assetLocalIdentifier`: String, indexed
  - `embeddingData`: Binary Data, allows external storage
  - `createdAt`: Date
  - `updatedAt`: Date

- `SmartCategoryEntity`
  - `id`: UUID, indexed
  - `name`: String
  - `centerEmbeddingData`: Binary Data, allows external storage
  - `threshold`: Float
  - `creationMode`: String
  - `matchingEmbeddingKind`: String
  - `promptText`: String?
  - `templateKey`: String?
  - `referenceMatchingMode`: String?
  - `sampleAssetIdsData`: Binary Data, JSON-encoded `[String]`
  - `createdAt`: Date
  - `updatedAt`: Date

- `ClassificationResultEntity`
  - `id`: UUID, indexed
  - `assetLocalIdentifier`: String, indexed
  - `categoryId`: UUID, indexed
  - `similarity`: Float
  - `createdAt`: Date

The app stores only identifiers, embeddings, thresholds, similarities, and result metadata. It does not save original images and does not copy Photo Library assets into the sandbox. If the user deletes a photo, iOS shows the system confirmation first; after deletion succeeds, the app removes cached embeddings and classification results for that asset.

## Photo privacy permission

`Resources/Info.plist` includes:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>SmartAlbum 只在本机读取照片用于整理和分类，不上传照片。</string>
```

## Model hookup

The project falls back to mock extractors when optional Core ML packages are missing, so the UI and storage flows remain testable. Real on-device classification requires the bundled MobileCLIP image and text models.

Expected model resources:

- `mobileclip_s2_image.mlpackage`: MobileCLIP image encoder, already included.
- `mobileclip_s2_text.mlpackage`: MobileCLIP text encoder for natural-language categories.
- `clip-vocab.json` and `clip-merges.txt`: CLIP BPE tokenizer resources used by the Swift text extractor.

Generate the optional text package from local checkouts/weights:

```bash
python Scripts/convert_mobileclip_text.py \
  --mobileclip-repo ../ml-mobileclip \
  --checkpoint checkpoints/mobileclip_s2.pt \
  --output-dir SmartLocalAlbum/Resources/Models
```

After generating the packages, add `mobileclip_s2_image.mlpackage`, `mobileclip_s2_text.mlpackage`, `clip-vocab.json`, and `clip-merges.txt` to the `SmartLocalAlbum` target in Xcode. `SmartLocalAlbumApp.swift` lazily loads the real MobileCLIP extractors when the compiled resources are first needed.

MobileCLIP-S2 is used for both natural-language categories and reference-image categories. The old MobileCLIP2-L/14 package may remain on disk for reference, but it is not part of the app target and is not bundled into builds.

## Build and run

1. Open `SmartLocalAlbum.xcodeproj` in Xcode.
2. Select the `SmartLocalAlbum` scheme.
3. Choose an iPhone simulator or a physical iPhone running iOS 16+.
4. For a physical device, set your signing team and bundle identifier.
5. Run. The mock extractors let you test permissions, category creation, scanning, matching strictness adjustment, cleanup, deletion, and grid preview without the optional models.

## IPA packaging

This project can be exported as a development IPA for installation on devices that are covered by the selected Apple Developer Team. The current project signing values are:

- Team ID: `5J56V9S9H8`
- Bundle ID: `com.loyuk.SmartLocalAlbum`
- Product name: `SmartAlbum`
- Export options file: `ExportOptions.development.plist`

### Prerequisites

1. Install Xcode and open it at least once.
2. Sign in to your Apple Developer account in Xcode: `Xcode > Settings > Accounts`.
3. Make sure the Bundle ID is available in your Apple Developer account.
4. For a development IPA, register the target iPhone in the developer account or connect the device once and let Xcode manage signing automatically.
5. Confirm the Core ML resources are included in the app target if you want real classification in the packaged app:
   - `mobileclip_s2_image.mlpackage`
   - `mobileclip_s2_text.mlpackage`
   - `clip-vocab.json`
   - `clip-merges.txt`

### Package with Xcode

1. Open `SmartLocalAlbum.xcodeproj`.
2. Select the `SmartLocalAlbum` scheme.
3. Select `Any iOS Device (arm64)` as the destination.
4. Open `Product > Archive`.
5. After the archive finishes, Xcode opens the Organizer window.
6. Select the new archive, then click `Distribute App`.
7. Choose `Debugging` or `Development` export, depending on the Xcode version.
8. Keep automatic signing enabled and use Team ID `5J56V9S9H8`.
9. Finish the wizard and choose an output folder. The exported `.ipa` can be installed on eligible devices.

### Package from the command line

Run the following commands from the repository root:

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

After export succeeds, the IPA should be in:

```text
build/ipa/SmartAlbum.ipa
```

### Install the IPA

For a development IPA, install it on a device included in the provisioning profile:

- Xcode: open `Window > Devices and Simulators`, select the device, then drag the `.ipa` into the installed apps list.
- Apple Configurator: add the `.ipa` to the connected device.

### Export method notes

`ExportOptions.development.plist` is configured for development export:

```xml
<key>method</key>
<string>development</string>
<key>signingStyle</key>
<string>automatic</string>
<key>teamID</key>
<string>5J56V9S9H8</string>
```

Use a different export method only when the signing setup matches that distribution path:

- `development`: local development devices.
- `ad-hoc`: registered external test devices.
- `app-store-connect`: TestFlight or App Store upload.

If you change the export method, update or create a matching export options plist before running `xcodebuild -exportArchive`.

### Troubleshooting

- `No profiles for 'com.loyuk.SmartLocalAlbum' were found`: sign in to Xcode, select the correct team, and rerun with `-allowProvisioningUpdates`.
- `Automatic signing is disabled`: enable automatic signing in Xcode or keep `signingStyle` as `automatic` in the export options plist.
- `Provisioning profile doesn't include the selected device`: register the device in the Apple Developer account, then regenerate the profile.
- `CoreMLModelCompile failed`: verify the `.mlpackage` files are present and included in the `SmartLocalAlbum` target.
- IPA installs but cannot open photos: grant photo library access in iOS Settings for `SmartAlbum`.
