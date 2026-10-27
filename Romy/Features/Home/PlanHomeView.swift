import PhotosUI
import SwiftData
import SwiftUI

/// What Home's cover and sheet ask of the shell's sheet. That sheet presents everything (a view behind a sheet
/// cannot present another one), so the cover only raises these.
struct HomeActions {
    var showTrips: () -> Void = {}
    var decideDates: () -> Void = {}
    var pickPhoto: () -> Void = {}
    /// 「行きたい」: search for a place to save, ask which day a saved place goes to, take one out.
    var search: () -> Void = {}
    var chooseDay: (WishPlace) -> Void = { _ in }
    var removeWish: (WishPlace) -> Void = { _ in }
    /// Action Home: open a plan's detail in the itinerary, and 「いまどうする？」 for the plan that is 今
    /// (nil where it is not offered).
    var openPlan: (UUID) -> Void = { _ in }
    var proposal: (ItineraryItem) -> (() -> Void)? = { _ in nil }
    /// True when the sheet is pulled to full height and the cover is hidden behind it.
    var isExpanded = false
}

/// Plan Home 「旅の表紙」 (Notion 02 §6-3, Figma page 6 46:147 / 46:217 / 46:502 / 46:574).
/// First version (Notion 05): the photo the person chose + one next action.
/// The cover (photo and headline) is the shell's background, like the map on the itinerary; what slides over it is
/// the shell's sheet (`PlanHomeSheet`).
struct PlanHomeCover: View {
    let trip: Trip
    let actions: HomeActions

    private static let photoHeight: CGFloat = 600
    private let text = DateText(calendar: .current, holidays: .bundled)

    private var countdown: TripCountdown { TripCountdown(dates: trip.dates, today: .now, text: text) }
    private var photo: UIImage? { trip.photo.flatMap(UIImage.init(data:)) }
    /// White text on a photo, ink text on the plain grey.
    private var onPhoto: Color { photo == nil ? Theme.ink : .white }

    var body: some View {
        ZStack(alignment: .top) {
            cover
            headline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cover: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photo {
                // The photo only fills what it is given: laid out as an overlay it cannot widen the screen.
                Color.clear
                    .frame(height: Self.photoHeight)
                    .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                    .clipped()
                    .overlay(LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            } else {
                Theme.fill.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var photoButton: some View {
        Button(action: actions.pickPhoto) {
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
        .buttonStyle(.plain)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(countdown.caption).font(Theme.jp(14, .medium))
            PlanHomeTripName(name: trip.name, size: 18, action: actions.showTrips)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !countdown.lead.isEmpty { Text(countdown.lead).font(Theme.jp(22, .bold)) }
                Text(countdown.value)
                    .font(countdown.value.allSatisfy(\.isNumber) ? Theme.latin(64, .bold) : Theme.jp(56, .bold))
                if !countdown.trail.isEmpty { Text(countdown.trail).font(Theme.jp(22, .bold)) }
            }
            .padding(.top, 22)
            HStack {
                if countdown.offersDateDecision {
                    Button(action: actions.decideDates) {
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
}

/// The trip's name with the arrow that opens the list of all trips.
struct PlanHomeTripName: View {
    let name: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(name).font(Theme.jp(size, .bold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: size * 0.6, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("すべての旅行を開く")
    }
}

/// What slides over the cover: the next action. Pulled to full height it also carries the trip's name, since the
/// cover is hidden behind it then.
struct PlanHomeSheet: View {
    let trip: Trip
    let actions: HomeActions
    let onAddPlans: () -> Void
    /// 「日に入れる」: opens the itinerary's 未定 tab.
    let onOpenUndecided: () -> Void

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var countdown: TripCountdown { TripCountdown(dates: trip.dates, today: .now, text: text) }

    /// Shinkansen moves are not built yet, so the choice is between 未定 plans and adding plans.
    private var nextAction: NextAction {
        NextActionPicker.pick(dates: trip.dates, trainSteps: [], undecidedPlanCount: trip.items(on: nil).count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if actions.isExpanded {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PlanHomeTripName(name: trip.name, size: 22, action: actions.showTrips)
                        .foregroundStyle(Theme.ink)
                    Text(countdown.short).font(Theme.jp(13, .medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                }
                .padding(.top, 8)
            }
            NextActionCard(action: nextAction) {
                switch nextAction {
                case .decideDates: actions.decideDates()
                case .placeUndecided: onOpenUndecided()
                case .addPlans, .trainStep: onAddPlans()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface.ignoresSafeArea())
    }
}

// MARK: - Photo

extension View {
    /// Picks the trip's cover photo from the library. It is attached inside the shell's sheet, which is what can
    /// present it.
    func tripPhotoPicker(isPresented: Binding<Bool>, trip: Trip) -> some View {
        modifier(TripPhotoPicker(isPresented: isPresented, trip: trip))
    }
}

private struct TripPhotoPicker: ViewModifier {
    @Binding var isPresented: Bool
    let trip: Trip
    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                Task { await save(item) }
            }
    }

    private func save(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = PhotoData.jpeg(from: data, longestSide: PhotoData.coverSide) else { return }
        trip.photo = jpeg
        try? modelContext.save()
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
