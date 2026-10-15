import PhotosUI
import SwiftData
import SwiftUI

/// Plan Home 「旅の表紙」 (Notion 02 §6-3, Figma page 6 46:147 / 46:217 / 46:502 / 46:574).
/// First version (Notion 05): the photo the person chose + one next action.
/// The photo stays put while the content slides over it as a sheet.
struct PlanHomeView: View {
    let trip: Trip
    let onCreateTrip: () -> Void
    let onAddPlans: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingTrips = false
    @State private var isDecidingDates = false
    @State private var scrolled = false
    /// Set by 「新しい旅行を作る」; creation opens once the trip list has closed.
    @State private var createAfterTrips = false

    private static let photoHeight: CGFloat = 300
    private let text = DateText(calendar: .current, holidays: .bundled)

    private var countdown: TripCountdown { TripCountdown(dates: trip.dates, today: .now, text: text) }
    private var photo: UIImage? { trip.photo.flatMap(UIImage.init(data:)) }
    /// White text on a photo, ink text on the plain grey.
    private var onPhoto: Color { photo == nil ? Theme.ink : .white }

    /// The itinerary does not exist yet, so there are no Shinkansen steps or 未定 plans to offer.
    private var nextAction: NextAction {
        NextActionPicker.pick(dates: trip.dates, trainSteps: [], undecidedPlanCount: 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            cover
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline
                    sheet
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 170 } action: { _, isPast in
                withAnimation(.snappy) { scrolled = isPast }
            }
            if scrolled { compactHeader.transition(.opacity) }
        }
        .background(Theme.surface.ignoresSafeArea())
        .sheet(isPresented: $isShowingTrips, onDismiss: openCreationIfAsked) {
            AllTripsSheet(current: trip) { createAfterTrips = true }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isDecidingDates) {
            DecideDatesSheet(trip: trip)
                .presentationDetents([.large])
        }
        .onChange(of: photoItem) { _, item in
            Task { await savePhoto(item) }
        }
    }

    private func openCreationIfAsked() {
        guard createAfterTrips else { return }
        createAfterTrips = false
        onCreateTrip()
    }

    // MARK: - Cover

    private var cover: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.photoHeight)
                    .clipped()
                    .overlay(LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            } else {
                Theme.fill.frame(maxWidth: .infinity).frame(height: Self.photoHeight)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var photoButton: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            if photo == nil {
                Label("写真を選ぶ", systemImage: "photo")
                    .font(Theme.jp(13, .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surface))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surface.opacity(0.9)))
                    .accessibilityLabel("写真を変える")
            }
        }
    }

    // MARK: - Headline over the cover

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(countdown.caption).font(Theme.jp(14, .medium))
            tripNameButton(size: 18)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !countdown.lead.isEmpty { Text(countdown.lead).font(Theme.jp(22, .bold)) }
                Text(countdown.value)
                    .font(countdown.value.allSatisfy(\.isNumber) ? Theme.latin(64, .bold) : Theme.jp(56, .bold))
                if !countdown.trail.isEmpty { Text(countdown.trail).font(Theme.jp(22, .bold)) }
            }
            .padding(.top, 22)
            HStack {
                if countdown.offersDateDecision {
                    Button { isDecidingDates = true } label: {
                        Text("日付を決める")
                            .font(Theme.jp(14, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.surface))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                photoButton
            }
            .padding(.top, 6)
        }
        .foregroundStyle(onPhoto)
        .shadow(color: photo == nil ? .clear : .black.opacity(0.25), radius: 6)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, minHeight: Self.photoHeight - 60, alignment: .topLeading)
    }

    private func tripNameButton(size: CGFloat) -> some View {
        Button { isShowingTrips = true } label: {
            HStack(spacing: 4) {
                Text(trip.name).font(Theme.jp(size, .bold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: size * 0.6, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("すべての旅行を開く")
    }

    private var compactHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            tripNameButton(size: 18)
            Text(countdown.short).font(Theme.jp(13, .medium))
            Spacer()
        }
        .foregroundStyle(onPhoto)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().overlay(Color.black.opacity(0.3))
                } else {
                    Theme.fill
                }
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            NextActionCard(action: nextAction) {
                switch nextAction {
                case .decideDates: isDecidingDates = true
                case .addPlans, .placeUndecided, .trainStep: onAddPlans()
                }
            }
            .offset(y: -20)
            .padding(.bottom, -20)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 140)
        .frame(maxWidth: .infinity, minHeight: 600, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(Theme.surface)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Photo

    private func savePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        trip.photo = Self.downscaled(image).jpegData(compressionQuality: 0.8)
        try? modelContext.save()
    }

    /// Keeps the stored cover small: the longer side at most 1600 px.
    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 1600 else { return image }
        let scale = 1600 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// The white 「次にやること」 card. No heading word; the first line says which plan (Notion 02 §6-3, 2026-10-09).
struct NextActionCard: View {
    let action: NextAction
    let onTap: () -> Void

    private var context: String {
        switch action {
        case .trainStep(let step), .decideDates(let step):
            step.day.map { "\($0)日目 \(step.route)" } ?? "未定 \(step.route)"
        case .placeUndecided(let count): "未定の予定 \(count)件"
        case .addPlans: "旅程"
        }
    }

    private var title: String {
        switch action {
        case .trainStep(let step): step.title
        case .decideDates: "日付を決める"
        case .placeUndecided: "日に入れる"
        case .addPlans: "予定を追加"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                Text(context).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
                HStack {
                    Text(title).font(Theme.jp(22, .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.ink))
                }
                if case .trainStep(let step) = action {
                    StepProgress(number: step.number, total: step.total)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white).shadow(
                color: .black.opacity(0.1),
                radius: 12,
                y: 8
            ))
        }
        .buttonStyle(.plain)
    }
}

/// 「━ ・ ・ ・ ・ ・  1 / 6」
private struct StepProgress: View {
    let number: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= number ? Theme.ink : Theme.fill)
                    .frame(width: index == number ? 28 : 10, height: 8)
            }
            Text("  \(number) / \(total)").font(Theme.latin(12, .medium)).foregroundStyle(Theme.secondary)
        }
    }
}
