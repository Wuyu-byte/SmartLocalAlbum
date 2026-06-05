import CoreData
import Foundation

@MainActor
final class CoreDataManager: ObservableObject {
    let persistentContainer: NSPersistentContainer

    private var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    init(inMemory: Bool = false) {
        persistentContainer = NSPersistentContainer(
            name: "SmartLocalAlbum",
            managedObjectModel: Self.makeManagedObjectModel()
        )

        if inMemory {
            persistentContainer.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        persistentContainer.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        persistentContainer.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load Core Data store: \(error.localizedDescription)")
            }
        }

        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
    }

    func fetchCategoryModels() throws -> [SmartCategoryModel] {
        let request = SmartCategoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request).map(Self.categoryModel(from:))
    }

    func fetchCategory(id: UUID) throws -> SmartCategoryEntity? {
        let request = SmartCategoryEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    func fetchCategoryNames(for assetLocalIdentifier: String) throws -> [String] {
        let resultRequest = ClassificationResultEntity.fetchRequest()
        resultRequest.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        let categoryIds = Set(try context.fetch(resultRequest).map(\.categoryId))
        guard !categoryIds.isEmpty else { return [] }

        let catRequest = SmartCategoryEntity.fetchRequest()
        catRequest.predicate = NSPredicate(format: "id IN %@", categoryIds)
        return try context.fetch(catRequest).compactMap(\.name)
    }

    func createCategory(
        name: String,
        centerEmbedding: [Float],
        sampleEmbeddings: [[Float]],
        threshold: Float,
        sampleAssetIds: [String],
        isPortrait: Bool,
        creationMode: CategoryCreationMode = .referenceImages,
        matchingEmbeddingKind: EmbeddingKind = .image,
        promptText: String? = nil,
        templateKey: String? = nil,
        referenceMatchingMode: ReferenceMatchingMode = .fast
    ) throws -> SmartCategoryModel {
        let now = Date()
        let entity = SmartCategoryEntity(context: context)
        entity.id = UUID()
        entity.name = name
        entity.centerEmbeddingData = VectorUtils.floatArrayToData(centerEmbedding)
        entity.sampleEmbeddingsData = try JSONEncoder().encode(sampleEmbeddings)
        entity.threshold = threshold
        entity.sampleAssetIdsData = try JSONEncoder().encode(sampleAssetIds)
        entity.isPortrait = isPortrait
        entity.creationMode = creationMode.rawValue
        entity.matchingEmbeddingKind = matchingEmbeddingKind.rawValue
        entity.promptText = promptText
        entity.templateKey = templateKey
        entity.referenceMatchingMode = referenceMatchingMode.rawValue
        entity.createdAt = now
        entity.updatedAt = now
        try saveContext()
        return Self.categoryModel(from: entity)
    }

    func updateCategoryThreshold(id: UUID, threshold: Float) throws {
        guard let category = try fetchCategory(id: id) else { return }
        category.threshold = threshold
        category.updatedAt = Date()
        try saveContext()
    }

    func deleteCategory(id: UUID) throws {
        if let category = try fetchCategory(id: id) {
            context.delete(category)
        }
        try deleteResults(categoryId: id)
        try deleteExclusions(categoryId: id)
        try saveContext()
    }

    func fetchPhotoEmbedding(
        assetLocalIdentifier: String,
        kind: EmbeddingKind = .image
    ) throws -> PhotoEmbeddingEntity? {
        let request = PhotoEmbeddingEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "assetLocalIdentifier == %@ AND embeddingKind == %@",
            assetLocalIdentifier,
            kind.rawValue
        )
        return try context.fetch(request).first
    }

    func savePhotoEmbedding(
        assetLocalIdentifier: String,
        embedding: [Float],
        kind: EmbeddingKind = .image
    ) throws {
        let now = Date()
        let entity: PhotoEmbeddingEntity
        if let existing = try fetchPhotoEmbedding(assetLocalIdentifier: assetLocalIdentifier, kind: kind) {
            entity = existing
        } else {
            entity = PhotoEmbeddingEntity(context: context)
            entity.assetLocalIdentifier = assetLocalIdentifier
            entity.embeddingKind = kind.rawValue
            entity.createdAt = now
        }

        entity.assetLocalIdentifier = assetLocalIdentifier
        entity.embeddingKind = kind.rawValue
        entity.embeddingData = VectorUtils.floatArrayToData(embedding)
        entity.updatedAt = now
        try saveContext()
    }

    func fetchAllPhotoEmbeddingModels(
        kind: EmbeddingKind? = nil
    ) throws -> [(assetLocalIdentifier: String, embedding: [Float])] {
        let request = PhotoEmbeddingEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        if let kind {
            request.predicate = NSPredicate(format: "embeddingKind == %@", kind.rawValue)
        }
        return try context.fetch(request).map {
            ($0.assetLocalIdentifier, VectorUtils.dataToFloatArray($0.embeddingData))
        }
    }

    func hasCategory(templateKey: String) throws -> Bool {
        let request = SmartCategoryEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "templateKey == %@", templateKey)
        return try context.count(for: request) > 0
    }

    func fetchResults(categoryId: UUID) throws -> [ClassificationResultModel] {
        let request = ClassificationResultEntity.fetchRequest()
        let trashedAssetIds = try fetchTrashedAssetIdSet()
        if trashedAssetIds.isEmpty {
            request.predicate = NSPredicate(format: "categoryId == %@", categoryId as CVarArg)
        } else {
            request.predicate = NSPredicate(
                format: "categoryId == %@ AND NOT (assetLocalIdentifier IN %@)",
                categoryId as CVarArg,
                Array(trashedAssetIds)
            )
        }
        request.sortDescriptors = [NSSortDescriptor(key: "similarity", ascending: false)]
        return try context.fetch(request).map(Self.resultModel(from:))
    }

    func fetchUncategorizedAssetIds() throws -> [String] {
        let embeddingRequest = PhotoEmbeddingEntity.fetchRequest()
        embeddingRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        let embeddedAssetIds = try context.fetch(embeddingRequest).map(\.assetLocalIdentifier)

        let resultRequest = ClassificationResultEntity.fetchRequest()
        let categorizedAssetIds = Set(try context.fetch(resultRequest).map(\.assetLocalIdentifier))
        let trashedAssetIds = try fetchTrashedAssetIdSet()

        var seen = Set<String>()
        return embeddedAssetIds.filter { assetId in
            guard
                !categorizedAssetIds.contains(assetId),
                !trashedAssetIds.contains(assetId),
                !seen.contains(assetId)
            else { return false }
            seen.insert(assetId)
            return true
        }
    }

    func fetchTrashedPhotoModels() throws -> [TrashedPhotoModel] {
        let request = TrashedPhotoEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "trashedAt", ascending: false)]
        return try context.fetch(request).map(Self.trashedPhotoModel(from:))
    }

    func fetchTrashedAssetIdSet() throws -> Set<String> {
        let request = TrashedPhotoEntity.fetchRequest()
        return Set(try context.fetch(request).map(\.assetLocalIdentifier))
    }

    func isPhotoTrashed(assetLocalIdentifier: String) throws -> Bool {
        let request = TrashedPhotoEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        return try context.count(for: request) > 0
    }

    func movePhotoToTrash(assetLocalIdentifier: String) throws {
        let request = TrashedPhotoEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)

        let entity = try context.fetch(request).first ?? TrashedPhotoEntity(context: context)
        entity.assetLocalIdentifier = assetLocalIdentifier
        entity.trashedAt = Date()
        try deleteResults(assetLocalIdentifier: assetLocalIdentifier)
        try saveContext()
    }

    func restorePhotoFromTrash(assetLocalIdentifier: String) throws {
        try deleteTrashRecord(assetLocalIdentifier: assetLocalIdentifier)
    }

    func deleteResults(categoryId: UUID) throws {
        let request = ClassificationResultEntity.fetchRequest()
        request.predicate = NSPredicate(format: "categoryId == %@", categoryId as CVarArg)
        for result in try context.fetch(request) {
            context.delete(result)
        }
    }

    func deleteResults(assetLocalIdentifier: String) throws {
        let request = ClassificationResultEntity.fetchRequest()
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        for result in try context.fetch(request) {
            context.delete(result)
        }
        try saveContext()
    }

    func deleteEmbeddings(assetLocalIdentifier: String) throws {
        let request = PhotoEmbeddingEntity.fetchRequest()
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        for embedding in try context.fetch(request) {
            context.delete(embedding)
        }
        try saveContext()
    }

    func deletePhotoData(assetLocalIdentifier: String) throws {
        try deleteResults(assetLocalIdentifier: assetLocalIdentifier)
        try deleteEmbeddings(assetLocalIdentifier: assetLocalIdentifier)
        try deleteExclusions(assetLocalIdentifier: assetLocalIdentifier)
        try deleteTrashRecord(assetLocalIdentifier: assetLocalIdentifier)
    }

    func resetScanData() throws {
        let resultRequest = ClassificationResultEntity.fetchRequest()
        for result in try context.fetch(resultRequest) {
            context.delete(result)
        }

        let embeddingRequest = PhotoEmbeddingEntity.fetchRequest()
        for embedding in try context.fetch(embeddingRequest) {
            context.delete(embedding)
        }

        let exclusionRequest = CategoryExclusionEntity.fetchRequest()
        for exclusion in try context.fetch(exclusionRequest) {
            context.delete(exclusion)
        }

        try saveContext()
    }

    func upsertClassificationResult(
        assetLocalIdentifier: String,
        categoryId: UUID,
        similarity: Float,
        isManual: Bool = false
    ) throws {
        let request = ClassificationResultEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "assetLocalIdentifier == %@ AND categoryId == %@",
            assetLocalIdentifier,
            categoryId as CVarArg
        )

        let entity: ClassificationResultEntity
        if let existing = try context.fetch(request).first {
            entity = existing
        } else {
            entity = ClassificationResultEntity(context: context)
            entity.id = UUID()
            entity.createdAt = Date()
        }

        entity.assetLocalIdentifier = assetLocalIdentifier
        entity.categoryId = categoryId
        entity.similarity = similarity
        entity.isManual = entity.isManual || isManual
        try saveContext()
    }

    func replaceClassificationResults(
        assetLocalIdentifier: String,
        matches: [ClassificationMatch],
        excludedCategoryIds: Set<UUID>? = nil
    ) throws {
        if try isPhotoTrashed(assetLocalIdentifier: assetLocalIdentifier) {
            try deleteResults(assetLocalIdentifier: assetLocalIdentifier)
            return
        }

        try deleteAutomaticResults(assetLocalIdentifier: assetLocalIdentifier)
        let blockedCategoryIds: Set<UUID>
        if let excludedCategoryIds {
            blockedCategoryIds = excludedCategoryIds
        } else {
            blockedCategoryIds = try fetchExcludedCategoryIds(assetLocalIdentifier: assetLocalIdentifier)
        }
        for match in matches where !blockedCategoryIds.contains(match.categoryId) {
            try upsertClassificationResult(
                assetLocalIdentifier: assetLocalIdentifier,
                categoryId: match.categoryId,
                similarity: match.similarity,
                isManual: false
            )
        }
    }

    func moveClassificationResult(
        assetLocalIdentifier: String,
        from sourceCategoryId: UUID?,
        to targetCategoryId: UUID
    ) throws {
        try restorePhotoFromTrash(assetLocalIdentifier: assetLocalIdentifier)
        if let sourceCategoryId {
            try upsertExclusion(assetLocalIdentifier: assetLocalIdentifier, categoryId: sourceCategoryId)
            try deleteResult(assetLocalIdentifier: assetLocalIdentifier, categoryId: sourceCategoryId)
        }
        try deleteExclusion(assetLocalIdentifier: assetLocalIdentifier, categoryId: targetCategoryId)
        try upsertClassificationResult(
            assetLocalIdentifier: assetLocalIdentifier,
            categoryId: targetCategoryId,
            similarity: 1.0,
            isManual: true
        )
    }

    func moveToUncategorized(assetLocalIdentifier: String) throws {
        try restorePhotoFromTrash(assetLocalIdentifier: assetLocalIdentifier)
        for categoryId in try fetchResultCategoryIds(assetLocalIdentifier: assetLocalIdentifier) {
            try upsertExclusion(assetLocalIdentifier: assetLocalIdentifier, categoryId: categoryId)
        }
        try deleteResults(assetLocalIdentifier: assetLocalIdentifier)
    }

    func excludePhotoFromCategory(
        assetLocalIdentifier: String,
        categoryId: UUID
    ) throws {
        try upsertExclusion(assetLocalIdentifier: assetLocalIdentifier, categoryId: categoryId)
        try deleteResult(assetLocalIdentifier: assetLocalIdentifier, categoryId: categoryId)
    }

    func fetchCategoryExclusionMap() throws -> [String: Set<UUID>] {
        let request = CategoryExclusionEntity.fetchRequest()
        return try context.fetch(request).reduce(into: [String: Set<UUID>]()) { result, exclusion in
            result[exclusion.assetLocalIdentifier, default: []].insert(exclusion.categoryId)
        }
    }

    private func fetchExcludedCategoryIds(assetLocalIdentifier: String) throws -> Set<UUID> {
        let request = CategoryExclusionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        return Set(try context.fetch(request).map(\.categoryId))
    }

    private func fetchResultCategoryIds(assetLocalIdentifier: String) throws -> Set<UUID> {
        let request = ClassificationResultEntity.fetchRequest()
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        return Set(try context.fetch(request).map(\.categoryId))
    }

    private func upsertExclusion(assetLocalIdentifier: String, categoryId: UUID) throws {
        let request = CategoryExclusionEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "assetLocalIdentifier == %@ AND categoryId == %@",
            assetLocalIdentifier,
            categoryId as CVarArg
        )
        let entity = try context.fetch(request).first ?? CategoryExclusionEntity(context: context)
        entity.assetLocalIdentifier = assetLocalIdentifier
        entity.categoryId = categoryId
        entity.createdAt = (entity.primitiveValue(forKey: "createdAt") as? Date) ?? Date()
        try saveContext()
    }

    private func deleteExclusion(assetLocalIdentifier: String, categoryId: UUID) throws {
        let request = CategoryExclusionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "assetLocalIdentifier == %@ AND categoryId == %@",
            assetLocalIdentifier,
            categoryId as CVarArg
        )
        for exclusion in try context.fetch(request) {
            context.delete(exclusion)
        }
        try saveContext()
    }

    private func deleteExclusions(assetLocalIdentifier: String) throws {
        let request = CategoryExclusionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        for exclusion in try context.fetch(request) {
            context.delete(exclusion)
        }
        try saveContext()
    }

    private func deleteExclusions(categoryId: UUID) throws {
        let request = CategoryExclusionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "categoryId == %@", categoryId as CVarArg)
        for exclusion in try context.fetch(request) {
            context.delete(exclusion)
        }
        try saveContext()
    }

    private func deleteTrashRecord(assetLocalIdentifier: String) throws {
        let request = TrashedPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "assetLocalIdentifier == %@", assetLocalIdentifier)
        for trashRecord in try context.fetch(request) {
            context.delete(trashRecord)
        }
        try saveContext()
    }

    private func deleteResult(assetLocalIdentifier: String, categoryId: UUID) throws {
        let request = ClassificationResultEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "assetLocalIdentifier == %@ AND categoryId == %@",
            assetLocalIdentifier,
            categoryId as CVarArg
        )
        for result in try context.fetch(request) {
            context.delete(result)
        }
        try saveContext()
    }

    private func deleteAutomaticResults(assetLocalIdentifier: String) throws {
        let request = ClassificationResultEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "assetLocalIdentifier == %@ AND isManual == NO",
            assetLocalIdentifier
        )
        for result in try context.fetch(request) {
            context.delete(result)
        }
        try saveContext()
    }

    func saveContext() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private static func categoryModel(from entity: SmartCategoryEntity) -> SmartCategoryModel {
        let sampleIds = (try? JSONDecoder().decode([String].self, from: entity.sampleAssetIdsData)) ?? []
        let sampleEmbeddings = entity.sampleEmbeddingsData.flatMap {
            try? JSONDecoder().decode([[Float]].self, from: $0)
        } ?? []
        return SmartCategoryModel(
            id: entity.id,
            name: entity.name,
            centerEmbedding: VectorUtils.dataToFloatArray(entity.centerEmbeddingData),
            sampleEmbeddings: sampleEmbeddings,
            threshold: entity.threshold,
            sampleAssetIds: sampleIds,
            isPortrait: entity.isPortrait,
            creationMode: CategoryCreationMode(rawValue: entity.creationMode)
                ?? (entity.isPortrait ? .portraitReference : .referenceImages),
            matchingEmbeddingKind: EmbeddingKind(rawValue: entity.matchingEmbeddingKind)
                ?? (entity.isPortrait ? .face : .image),
            promptText: entity.promptText,
            templateKey: entity.templateKey,
            referenceMatchingMode: ReferenceMatchingMode(rawValue: entity.referenceMatchingMode ?? "")
                ?? Self.defaultReferenceMatchingMode(
                    creationMode: CategoryCreationMode(rawValue: entity.creationMode)
                        ?? (entity.isPortrait ? .portraitReference : .referenceImages),
                    matchingEmbeddingKind: EmbeddingKind(rawValue: entity.matchingEmbeddingKind)
                        ?? (entity.isPortrait ? .face : .image)
                ),
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private static func defaultReferenceMatchingMode(
        creationMode: CategoryCreationMode,
        matchingEmbeddingKind: EmbeddingKind
    ) -> ReferenceMatchingMode {
        .fast
    }

    private static func resultModel(from entity: ClassificationResultEntity) -> ClassificationResultModel {
        ClassificationResultModel(
            id: entity.id,
            assetLocalIdentifier: entity.assetLocalIdentifier,
            categoryId: entity.categoryId,
            similarity: entity.similarity,
            isManual: entity.isManual,
            createdAt: entity.createdAt
        )
    }

    private static func trashedPhotoModel(from entity: TrashedPhotoEntity) -> TrashedPhotoModel {
        TrashedPhotoModel(
            assetLocalIdentifier: entity.assetLocalIdentifier,
            trashedAt: entity.trashedAt
        )
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let photoEmbedding = NSEntityDescription()
        photoEmbedding.name = "PhotoEmbeddingEntity"
        photoEmbedding.managedObjectClassName = NSStringFromClass(PhotoEmbeddingEntity.self)
        photoEmbedding.properties = [
            attribute("assetLocalIdentifier", .stringAttributeType, indexed: true),
            attribute("embeddingKind", .stringAttributeType, indexed: true, defaultValue: EmbeddingKind.image.rawValue),
            attribute("embeddingData", .binaryDataAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ]

        let smartCategory = NSEntityDescription()
        smartCategory.name = "SmartCategoryEntity"
        smartCategory.managedObjectClassName = NSStringFromClass(SmartCategoryEntity.self)
        smartCategory.properties = [
            attribute("id", .UUIDAttributeType, indexed: true),
            attribute("name", .stringAttributeType),
            attribute("centerEmbeddingData", .binaryDataAttributeType),
            attribute("sampleEmbeddingsData", .binaryDataAttributeType, optional: true),
            attribute("threshold", .floatAttributeType),
            attribute("sampleAssetIdsData", .binaryDataAttributeType),
            attribute("isPortrait", .booleanAttributeType, defaultValue: false),
            attribute("creationMode", .stringAttributeType, defaultValue: CategoryCreationMode.referenceImages.rawValue),
            attribute("matchingEmbeddingKind", .stringAttributeType, indexed: true, defaultValue: EmbeddingKind.image.rawValue),
            attribute("promptText", .stringAttributeType, optional: true),
            attribute("templateKey", .stringAttributeType, indexed: true, optional: true),
            attribute("referenceMatchingMode", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ]

        let classificationResult = NSEntityDescription()
        classificationResult.name = "ClassificationResultEntity"
        classificationResult.managedObjectClassName = NSStringFromClass(ClassificationResultEntity.self)
        classificationResult.properties = [
            attribute("id", .UUIDAttributeType, indexed: true),
            attribute("assetLocalIdentifier", .stringAttributeType, indexed: true),
            attribute("categoryId", .UUIDAttributeType, indexed: true),
            attribute("similarity", .floatAttributeType),
            attribute("isManual", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType)
        ]

        let trashedPhoto = NSEntityDescription()
        trashedPhoto.name = "TrashedPhotoEntity"
        trashedPhoto.managedObjectClassName = NSStringFromClass(TrashedPhotoEntity.self)
        trashedPhoto.properties = [
            attribute("assetLocalIdentifier", .stringAttributeType, indexed: true),
            attribute("trashedAt", .dateAttributeType)
        ]

        let categoryExclusion = NSEntityDescription()
        categoryExclusion.name = "CategoryExclusionEntity"
        categoryExclusion.managedObjectClassName = NSStringFromClass(CategoryExclusionEntity.self)
        categoryExclusion.properties = [
            attribute("assetLocalIdentifier", .stringAttributeType, indexed: true),
            attribute("categoryId", .UUIDAttributeType, indexed: true),
            attribute("createdAt", .dateAttributeType)
        ]

        addIndexes(to: photoEmbedding, attributeNames: ["assetLocalIdentifier", "embeddingKind"])
        addIndexes(to: smartCategory, attributeNames: ["id", "matchingEmbeddingKind", "templateKey"])
        addIndexes(to: classificationResult, attributeNames: ["id", "assetLocalIdentifier", "categoryId"])
        addIndexes(to: trashedPhoto, attributeNames: ["assetLocalIdentifier"])
        addIndexes(to: categoryExclusion, attributeNames: ["assetLocalIdentifier", "categoryId"])

        model.entities = [photoEmbedding, smartCategory, classificationResult, trashedPhoto, categoryExclusion]
        return model
    }

    private static func addIndexes(to entity: NSEntityDescription, attributeNames: [String]) {
        entity.indexes = attributeNames.compactMap { attributeName in
            guard let property = entity.propertiesByName[attributeName] else { return nil }
            let element = NSFetchIndexElementDescription(property: property, collationType: .binary)
            return NSFetchIndexDescription(
                name: "\(entity.name ?? "Entity")_\(attributeName)_index",
                elements: [element]
            )
        }
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        indexed: Bool = false,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = optional
        description.defaultValue = defaultValue
        if type == .binaryDataAttributeType {
            description.allowsExternalBinaryDataStorage = true
        }
        return description
    }
}
