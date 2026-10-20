#if DEBUG
import SwiftData
import SwiftUI

/// DUMMY for the poster (Figma page 6 「Action D 観光の時間」): the Home of a trip in progress, showing the plan that is
/// 今, what is left today and tonight's stay. It reads the opened trip's real plans but is only a picture: nothing on it
/// works, and the app's own Home does not switch to it yet. Debug builds only: launch with ROMY_MOCK_ACTIONHOME=1
/// (and ROMY_FAKE_NOW to be on a day of the trip).
struct ActionHomeMockView: View {
    static var isLaunched: Bool {
        ProcessInfo.processInfo.environment["ROMY_MOCK_ACTIONHOME"] == "1"
    }

    @Query(sort: \Trip.lastOpenedAt, order: .reverse) private var trips: [Trip]
    private let text = DateText(calendar: .current, holidays: .bundled)

    var body: some View {
        if let trip = trips.first {
            content(for: trip)
        }
    }

    // MARK: - Data from the trip

    private struct Snapshot {
        let dayCaption: String
        let color: Color
        let now: ItineraryItem?
        let nowTime: String
        let rest: [(time: String, title: String)]
        let stay: ItineraryItem?
    }

    private func snapshot(of trip: Trip) -> Snapshot {
        let dayCount = ItineraryDays.count(of: trip.dates)
        let day = min(max(trip.dates.dayNumber(on: AppClock.now, calendar: text.calendar) ?? 1, 1), max(dayCount, 1))
        let days = ItineraryDays(dates: trip.dates, text: text)
        let plans = trip.items(on: day)
        let schedule = trip.schedule(of: plans, on: days.date(of: day), calendar: text.calendar)
        let stay = plans.first { $0.kind == .stay }
        let visits = plans.filter { $0.kind != .stay }
        let now = visits.first { $0.doneAt == nil }
        let nowTime = now.flatMap { schedule.slot(for: $0.id) }
            .map { "\(DaySchedule.clock($0.startMinutes)) – \(DaySchedule.clock($0.endMinutes))" } ?? ""
        let later = now.flatMap { current in visits.firstIndex { $0.id == current.id } }
            .map { Array(visits.dropFirst($0 + 1)) } ?? []
        let rest = later.prefix(2).map { plan in
            (time: schedule.slot(for: plan.id).map { DaySchedule.clock($0.startMinutes) } ?? "", title: plan.title)
        }
        return Snapshot(
            dayCaption: days.caption(for: .day(day), hasDestination: true), color: Theme.dayColor(day),
            now: now, nowTime: nowTime, rest: rest, stay: stay
        )
    }

    // MARK: - Screen

    private func content(for trip: Trip) -> some View {
        let data = snapshot(of: trip)
        return ZStack(alignment: .top) {
            Color.white
            header(trip: trip, data: data)
            VStack(alignment: .leading, spacing: 0) {
                nowCard(data).padding(.top, 262)
                Text("今日の残り")
                    .font(Theme.jp(13, .bold)).foregroundStyle(Theme.secondary)
                    .padding(.top, 20)
                VStack(spacing: 10) {
                    ForEach(Array(data.rest.enumerated()), id: \.offset) { _, row in restRow(row, color: data.color) }
                }
                .padding(.top, 10)
                if let stay = data.stay { stayCard(stay).padding(.top, 14) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            ShellBar(
                tab: .constant(.home), isShowingAddMenu: .constant(false), sheet: .constant(nil), note: .constant(nil),
                trip: trip, dayForNewPlan: nil, onAdded: { _ in }, onUndo: { _ in }
            )
        }
        .ignoresSafeArea()
    }

    private func header(trip: Trip, data: Snapshot) -> some View {
        ZStack(alignment: .topLeading) {
            if let photo = trip.photo.flatMap(UIImage.init(data:)) {
                Color.clear.frame(height: 330)
                    .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.05)], startPoint: .top, endPoint: .bottom
                )
                .frame(height: 330)
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x7DB4E8), Color(hex: 0xEDB48F)], startPoint: .top, endPoint: .bottom
                )
                .frame(height: 330)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(data.dayCaption)
                    .font(Theme.jp(13, .medium))
                HStack(spacing: 6) {
                    Text(trip.name).font(Theme.jp(19, .bold))
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8))
                }
                Text(ward(of: data.now))
                    .font(Theme.jp(72, .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.top, 14)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 6)
            .padding(.horizontal, 20)
            .padding(.top, 78)
            Image(systemName: "person.fill")
                .font(.system(size: 17)).foregroundStyle(Theme.secondary)
                .frame(width: 46, height: 46).background(Circle().fill(.white))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20).padding(.top, 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 「京都市下京区」 → 「下京区」: the big word is the ward the plan is in.
    private func ward(of item: ItineraryItem?) -> String {
        guard let area = item?.area, !area.isEmpty else { return item?.title ?? "" }
        return area.replacingOccurrences(of: "京都市", with: "")
    }

    private func nowCard(_ data: Snapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(data.nowTime)
                    .font(Theme.latin(15, .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(data.now?.title ?? "")
                    .font(Theme.jp(26, .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 36, height: 36)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36).background(Circle().fill(.white))
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 30).fill(Theme.ink))
    }

    private func restRow(_ row: (time: String, title: String), color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(row.time).font(Theme.latin(15, .semibold)).foregroundStyle(Theme.secondary)
            Text(row.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func stayCard(_ stay: ItineraryItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("今夜の宿").font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                Text(stay.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 16).frame(height: 68)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.fill))
    }
}
#endif
