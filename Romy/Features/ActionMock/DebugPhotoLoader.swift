#if DEBUG
import Foundation
import SwiftData

/// DEBUG only (poster screenshots): puts the photos of a folder on the opened trip, by file name. Launch with
/// ROMY_PHOTOS_DIR=<folder>: 「カバー」 becomes the trip's cover, any other name is the title of the plans it goes to.
enum DebugPhotoLoader {
    @MainActor
    static func run(trips: [Trip], context: ModelContext) {
        guard let path = ProcessInfo.processInfo.environment["ROMY_PHOTOS_DIR"], let trip = trips.first,
              let files = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
        for file in files where file.lowercased().hasSuffix(".jpg") {
            let name = (file as NSString).deletingPathExtension.precomposedStringWithCanonicalMapping
            guard let data = FileManager.default.contents(atPath: (path as NSString).appendingPathComponent(file))
            else { continue }
            if name == "カバー" {
                trip.photo = PhotoData.jpeg(from: data, longestSide: PhotoData.coverSide)
            } else if let jpeg = PhotoData.jpeg(from: data, longestSide: PhotoData.planSide) {
                for item in trip.items where item.title.precomposedStringWithCanonicalMapping == name {
                    item.photo = jpeg
                }
            }
        }
        try? context.save()
    }
}
#endif
