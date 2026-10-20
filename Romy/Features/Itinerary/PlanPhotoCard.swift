import PhotosUI
import SwiftData
import SwiftUI

/// The photo of a plan, at the top of its detail: tap the photo to change it, 外す takes it off.
/// Without one, a dashed box asks for it. The photo is one the person picks (photos that come by themselves are later).
struct PlanPhotoCard: View {
    let item: ItineraryItem

    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Group {
            if let data = item.photo, let image = UIImage(data: data) {
                photo(image)
            } else {
                emptyBox
            }
        }
        .onChange(of: photoItem) { _, picked in Task { await save(picked) } }
    }

    private func photo(_ image: UIImage) -> some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Color.clear
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("写真を変える")
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Text("外す")
                    .font(Theme.jp(12, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("写真を外す")
        }
    }

    private var emptyBox: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            HStack(spacing: 8) {
                Image(systemName: "photo").font(.system(size: 15, weight: .semibold))
                Text("写真を選ぶ").font(Theme.jp(14, .bold))
            }
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    private func save(_ picked: PhotosPickerItem?) async {
        await PlanPhoto.save(picked, to: item, in: modelContext)
        photoItem = nil
    }

    private func remove() {
        item.photo = nil
        try? modelContext.save()
    }
}

enum PlanPhoto {
    /// Stores the picked photo (cut to `PhotoData.planSide`) on the plan; nothing changes when it cannot be read.
    @MainActor
    static func save(_ picked: PhotosPickerItem?, to item: ItineraryItem, in context: ModelContext) async {
        guard let picked, let data = try? await picked.loadTransferable(type: Data.self),
              let jpeg = PhotoData.jpeg(from: data, longestSide: PhotoData.planSide) else { return }
        item.photo = jpeg
        try? context.save()
    }
}

/// The small dashed box on a plan's card that adds its photo without opening the detail.
struct PlanPhotoAddButton: View {
    let item: ItineraryItem

    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)の写真を選ぶ")
        .onChange(of: photoItem) { _, picked in
            Task {
                await PlanPhoto.save(picked, to: item, in: modelContext)
                photoItem = nil
            }
        }
    }
}
