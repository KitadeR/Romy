import UIKit

/// Photos the person picks are stored small: the longer side is cut to `longestSide` and saved as JPEG.
enum PhotoData {
    /// The stored cover of a trip.
    static let coverSide: CGFloat = 1600
    /// The photo of one plan: shown at card size and at the top of the plan's detail.
    static let planSide: CGFloat = 1000

    static func jpeg(from data: Data, longestSide: CGFloat) -> Data? {
        UIImage(data: data).flatMap { jpeg(from: $0, longestSide: longestSide) }
    }

    static func jpeg(from image: UIImage, longestSide: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > longestSide else { return image.jpegData(compressionQuality: 0.8) }
        let scale = longestSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Scale 1: the size is in pixels, not multiplied by the screen's scale.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
