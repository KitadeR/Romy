import SwiftUI
import Testing
import UIKit
@testable import Romy

struct PlanPhotoTests {
    private func jpegData(width: CGFloat, height: CGFloat) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 1)!
    }

    @Test func aLargePhotoIsCutToTheLongestSideAndKeepsItsShape() throws {
        let stored = try #require(PhotoData.jpeg(from: jpegData(width: 3000, height: 2000), longestSide: 1000))
        let image = try #require(UIImage(data: stored))
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #expect(max(pixels.width, pixels.height) <= 1000)
        #expect(abs(pixels.width / pixels.height - 1.5) < 0.01)
    }

    @Test func aSmallPhotoIsNotEnlarged() throws {
        let stored = try #require(PhotoData.jpeg(from: jpegData(width: 400, height: 300), longestSide: 1000))
        let image = try #require(UIImage(data: stored))
        #expect(image.size.width * image.scale <= 400)
    }

    @Test func notAPhotoGivesNothing() {
        #expect(PhotoData.jpeg(from: Data([1, 2, 3]), longestSide: 1000) == nil)
    }

    @Test func aDeletedPlanComesBackWithItsPhoto() {
        let item = ItineraryItem(title: "清水寺", day: 2, order: 0, kind: .sight)
        item.photo = Data([9, 8, 7])
        let restored = ItineraryItem.restored(from: item.snapshot())
        #expect(restored.photo == Data([9, 8, 7]))
    }
}
