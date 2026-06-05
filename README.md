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
    Services/
      ImageEmbeddingExtracting.swift
      TextEmbeddingExtracting.swift
      ImageEmbeddingExtractor.swift
      MobileCLIPTextEmbeddingExtractor.swift
      LazyEmbeddingExtractors.swift
      MockImageEmbeddingExtractor.swift
      SimilarityClassifier.swift
    Utils/
      VectorUtils.swift
    Views/
      HomeView.swift
      CreateCategoryView.swift
      CategoryDetailView.swift
      PhotoGridItemView.swift
      PhotoPreviewView.swift
      EmptyStateView.swift
    Resources/
      Info.plist
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
