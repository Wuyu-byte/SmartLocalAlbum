<div align="center">

# 📸 SmartLocalAlbum

一个我自己用来整理混乱相册的 iOS 小工具。

[English](./README.md) | [简体中文](./README.zh-CN.md)

</div>

---

## 为什么做这个

我自己的相册越来越乱 —— 几千张截图、相似照片、一激动就连拍 5 张一样的。想找某张照片只能一直往下翻，体验很差。所以想要：

- 一个能直接用自然语言搜照片的方式
- 一个能自动找重复照片的途径，不用自己一张张看
- 当我大致记得拍照的时间 / 地点 / 大小时，能用元数据筛一下

我懒得为这种事把照片传到云上，也不想再开订阅。所以就自己写了一个，顺便开源出来，万一别人也觉得有用呢。

所有处理都在本机完成，没有服务器，没有账号，没有埋点。

---

## 功能

- 🔍 **智能搜索** —— 用自然语言描述照片（"海边日落"、"沙发上的猫"、"白咖啡杯"），在本地 embedding 里查。需要 MobileCLIP-S2 模型，没模型时会用 mock，效果不准但 UI 流程能跑。
- 🧬 **去重** —— 感知哈希（dHash）+ 并查集，把相似的照片归到一组。可以选严格度（精确 / 较近 / 相似），然后挑要留哪张。
- 🏷️ **智能分类** —— 选几张参考照片建一个分类，App 自动把匹配的照片归进去。
- ♻️ **回收站** —— 删除先进回收站，永久删除才会触发 iOS 系统确认框，避免误删。

---

## 技术栈

没什么花哨的，都是我熟悉的东西：

- **SwiftUI** 写 UI
- **CoreData**（程序化建模，不用跟 `.xcdatamodeld` 打架）
- **CoreML + MobileCLIP-S2** 算 embedding（带 mock fallback）
- **Vision** 做人脸特征
- **Photos** framework 访问相册
- **WidgetKit** 做桌面小组件

iOS 16+，主要在真机上自测。

---

## 目录结构

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

## 怎么跑起来

1. 用 Xcode 15+ 打开 `SmartLocalAlbum.xcodeproj`
2. 选 `SmartLocalAlbum` scheme 和一个 iPhone 模拟器或真机
3. Run。没装模型文件也能跑，去重、分类、回收站这些都能用，只是搜索效果不准

想要真实可用的搜索 / 分类效果，需要把模型文件加到 target：

- `mobileclip_s2_image.mlpackage`
- `mobileclip_s2_text.mlpackage`
- `clip-vocab.json`
- `clip-merges.txt`

`Scripts/` 里有 Python 脚本可以从 MobileCLIP checkpoint 生成 text 包。

---

## 打包 IPA

我自己测的时候导出的是 development IPA，仓库里带了 `ExportOptions.development.plist`，里面配好了 team / bundle id。

大致流程：

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

产物在 `build/ipa/SmartAlbum.ipa`，用 Xcode 的 Devices 窗口或 Apple Configurator 装。

---

## 一些说明

- 模型文件没有放进仓库，需要自己生成或下载
- iOS 14+ 的 Limited Photos Access 可以用，但只能看到你授权的那部分
- 回收站是软删除 —— 真正调 `PHAssetChangeRequest.deleteAssets` 的只有"永久删除"
- 这是我自己用的项目，UI 偏功能型，没做太多打磨

---

## 协议

MIT。详见 [LICENSE](./LICENSE)。
