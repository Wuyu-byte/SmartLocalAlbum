import CoreData
import Foundation

@objc(PhotoEmbeddingEntity)
final class PhotoEmbeddingEntity: NSManagedObject {
    @NSManaged var assetLocalIdentifier: String
    @NSManaged var embeddingKind: String
    @NSManaged var embeddingData: Data
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<PhotoEmbeddingEntity> {
        NSFetchRequest<PhotoEmbeddingEntity>(entityName: "PhotoEmbeddingEntity")
    }
}

@objc(SmartCategoryEntity)
final class SmartCategoryEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var centerEmbeddingData: Data
    @NSManaged var sampleEmbeddingsData: Data?
    @NSManaged var threshold: Float
    @NSManaged var sampleAssetIdsData: Data
    @NSManaged var isPortrait: Bool
    @NSManaged var creationMode: String
    @NSManaged var matchingEmbeddingKind: String
    @NSManaged var promptText: String?
    @NSManaged var templateKey: String?
    @NSManaged var referenceMatchingMode: String?
    @NSManaged var isLive: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<SmartCategoryEntity> {
        NSFetchRequest<SmartCategoryEntity>(entityName: "SmartCategoryEntity")
    }
}

@objc(PhotoHashEntity)
final class PhotoHashEntity: NSManagedObject {
    /// 64 位 dHash,big-endian 字节序,8 字节整数。
    @NSManaged var hashNumber: Int64
    @NSManaged var assetLocalIdentifier: String
    @NSManaged var createdAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<PhotoHashEntity> {
        NSFetchRequest<PhotoHashEntity>(entityName: "PhotoHashEntity")
    }
}

@objc(ClassificationResultEntity)
final class ClassificationResultEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var assetLocalIdentifier: String
    @NSManaged var categoryId: UUID
    @NSManaged var similarity: Float
    @NSManaged var isManual: Bool
    @NSManaged var createdAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<ClassificationResultEntity> {
        NSFetchRequest<ClassificationResultEntity>(entityName: "ClassificationResultEntity")
    }
}

@objc(CategoryExclusionEntity)
final class CategoryExclusionEntity: NSManagedObject {
    @NSManaged var assetLocalIdentifier: String
    @NSManaged var categoryId: UUID
    @NSManaged var createdAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<CategoryExclusionEntity> {
        NSFetchRequest<CategoryExclusionEntity>(entityName: "CategoryExclusionEntity")
    }
}

@objc(TrashedPhotoEntity)
final class TrashedPhotoEntity: NSManagedObject {
    @NSManaged var assetLocalIdentifier: String
    @NSManaged var trashedAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<TrashedPhotoEntity> {
        NSFetchRequest<TrashedPhotoEntity>(entityName: "TrashedPhotoEntity")
    }
}
