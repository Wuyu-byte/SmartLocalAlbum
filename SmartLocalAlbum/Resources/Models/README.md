# Models

Place Core ML model packages here.

Expected resource names:

```text
mobileclip_s2_image.mlpackage
mobileclip_s2_text.mlpackage
clip-vocab.json
clip-merges.txt
```

Xcode compiles `.mlpackage` files into bundled `.mlmodelc` resources. Runtime loaders look for these compiled names:

```text
mobileclip_s2_image.mlmodelc
mobileclip_s2_text.mlmodelc
```

Use the conversion scripts in `Scripts/` to generate the optional MobileCLIP text package. Add `mobileclip_s2_image.mlpackage`, `mobileclip_s2_text.mlpackage`, `clip-vocab.json`, and `clip-merges.txt` to the SmartLocalAlbum target in Xcode.

`mobileclip2_l14_image.mlpackage` is intentionally not part of the app target, so it will not be bundled into builds.
