# SmartLocalAlbum

iOS 16+ SwiftUI sample project for local-only smart photo grouping.

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
<string>SmartAlbum needs photo library access to classify local photos on device. It only deletes system photos after you confirm deletion.</string>
```

## Model hookup

The project falls back to mock extractors when optional Core ML packages are missing, so the UI and storage flows remain testable. Accurate classification requires the real models.

Expected model resources:

- `mobileclip_s2_image.mlpackage`: MobileCLIP image encoder, already included.
- `mobileclip2_l14_image.mlpackage`: MobileCLIP2-L/14 image encoder for accurate reference-image categories.
- `mobileclip_s2_text.mlpackage`: MobileCLIP text encoder for natural-language categories.
- `clip-vocab.json` and `clip-merges.txt`: CLIP BPE tokenizer resources used by the Swift text extractor.

Generate the optional packages from local checkouts/weights:

```bash
python Scripts/convert_mobileclip_text.py \
  --mobileclip-repo ../ml-mobileclip \
  --checkpoint checkpoints/mobileclip_s2.pt \
  --output-dir SmartLocalAlbum/Resources/Models

python Scripts/convert_mobileclip_image.py \
  --checkpoint checkpoints/mobileclip2_l14_hf/mobileclip2_l14.pt \
  --variant MobileCLIP2-L-14 \
  --output-name mobileclip2_l14_image \
  --image-size 224 \
  --output-dir SmartLocalAlbum/Resources/Models
```

After generating the packages, add the new `.mlpackage` files plus `clip-vocab.json` and `clip-merges.txt` to the `SmartLocalAlbum` target in Xcode. `SmartLocalAlbumApp.swift` lazily loads the real MobileCLIP extractors when the compiled resources are first needed.

MobileCLIP is used for both natural-language categories and reference-image categories. Reference-image categories support a precise MobileCLIP2-L/14 mode and a fast MobileCLIP-S2 mode.

## Build and run

1. Open `SmartLocalAlbum.xcodeproj` in Xcode.
2. Select the `SmartLocalAlbum` scheme.
3. Choose an iPhone simulator or a physical iPhone running iOS 16+.
4. For a physical device, set your signing team and bundle identifier.
5. Run. The mock extractors let you test permissions, category creation, scanning, matching strictness adjustment, deletion, and grid preview without the optional models.
