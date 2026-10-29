import Foundation
import CoreData

public final class UsageRepository {
    private let container: NSPersistentContainer
    private var usageObjects: [UUID: NSManagedObject] = [:]
    private var breakObjects: [UUID: NSManagedObject] = [:]

    public init(directory: URL? = nil, inMemory: Bool = false) throws {
        let model = NSManagedObjectModel()
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let result = NSAttributeDescription(); result.name = name; result.attributeType = type; result.isOptional = optional
            return result
        }
        let usage = NSEntityDescription(); usage.name = "UsageSegment"; usage.managedObjectClassName = "NSManagedObject"
        usage.properties = [attribute("id", .UUIDAttributeType), attribute("roundID", .UUIDAttributeType),
                            attribute("startedAt", .dateAttributeType), attribute("endedAt", .dateAttributeType),
                            attribute("seconds", .doubleAttributeType), attribute("mode", .stringAttributeType)]
        usage.uniquenessConstraints = [["id"]]
        let rest = NSEntityDescription(); rest.name = "BreakRecord"; rest.managedObjectClassName = "NSManagedObject"
        rest.properties = [attribute("id", .UUIDAttributeType), attribute("startedAt", .dateAttributeType),
                           attribute("endedAt", .dateAttributeType, optional: true), attribute("targetSeconds", .doubleAttributeType),
                           attribute("outcome", .stringAttributeType), attribute("source", .stringAttributeType)]
        rest.uniquenessConstraints = [["id"]]
        model.entities = [usage, rest]
        container = NSPersistentContainer(name: "Still", managedObjectModel: model)
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription(); description.type = NSInMemoryStoreType
        } else {
            let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Still", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: folder.appendingPathComponent("usage.sqlite"))
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    public func load() throws -> (segments: [UsageSegment], breaks: [BreakRecord]) {
        var result: (segments: [UsageSegment], breaks: [BreakRecord]) = ([], [])
        var failure: Error?
        container.viewContext.performAndWait {
            do {
                let context = container.viewContext
                let usage = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "UsageSegment"))
                result.segments = usage.compactMap { item in
                    guard let id = item.value(forKey: "id") as? UUID,
                          let round = item.value(forKey: "roundID") as? UUID,
                          let start = item.value(forKey: "startedAt") as? Date,
                          let end = item.value(forKey: "endedAt") as? Date,
                          let mode = TrackingMode(rawValue: item.value(forKey: "mode") as? String ?? "") else { return nil }
                    usageObjects[id] = item
                    return UsageSegment(id: id, roundID: round, startedAt: start, endedAt: end,
                                        seconds: item.value(forKey: "seconds") as? Double ?? 0, mode: mode)
                }.sorted { $0.startedAt < $1.startedAt }
                let rests = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "BreakRecord"))
                result.breaks = rests.compactMap { item in
                    guard let id = item.value(forKey: "id") as? UUID,
                          let start = item.value(forKey: "startedAt") as? Date,
                          let outcome = BreakOutcome(rawValue: item.value(forKey: "outcome") as? String ?? ""),
                          let source = BreakSource(rawValue: item.value(forKey: "source") as? String ?? "") else { return nil }
                    breakObjects[id] = item
                    var record = BreakRecord(startedAt: start, endedAt: item.value(forKey: "endedAt") as? Date,
                                             targetSeconds: item.value(forKey: "targetSeconds") as? Double ?? 0,
                                             outcome: outcome, source: source)
                    record.id = id; return record
                }.sorted { $0.startedAt < $1.startedAt }
            } catch { failure = error }
        }
        if let failure { throw failure }
        return result
    }

    public func save(segments: [UsageSegment], breaks: [BreakRecord]) throws {
        var failure: Error?
        container.viewContext.performAndWait {
            let context = container.viewContext
            for segment in segments {
                let item = usageObjects[segment.id] ?? NSEntityDescription.insertNewObject(forEntityName: "UsageSegment", into: context)
                item.setValue(segment.id, forKey: "id"); item.setValue(segment.roundID, forKey: "roundID")
                item.setValue(segment.startedAt, forKey: "startedAt"); item.setValue(segment.endedAt, forKey: "endedAt")
                item.setValue(segment.seconds, forKey: "seconds"); item.setValue(segment.mode.rawValue, forKey: "mode")
                usageObjects[segment.id] = item
            }
            for record in breaks {
                let item = breakObjects[record.id] ?? NSEntityDescription.insertNewObject(forEntityName: "BreakRecord", into: context)
                item.setValue(record.id, forKey: "id"); item.setValue(record.startedAt, forKey: "startedAt")
                item.setValue(record.endedAt, forKey: "endedAt"); item.setValue(record.targetSeconds, forKey: "targetSeconds")
                item.setValue(record.outcome.rawValue, forKey: "outcome"); item.setValue(record.source.rawValue, forKey: "source")
                breakObjects[record.id] = item
            }
            if context.hasChanges { do { try context.save() } catch { failure = error } }
        }
        if let failure { throw failure }
    }
}
