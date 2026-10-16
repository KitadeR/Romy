import SwiftUI

/// 時刻のシート (Notion 02 §6-5, Figma 125:2 / 125:202): switch between 「長さ」 and 「時刻を決める」.
/// 長さ: a big number with − ＋ and quick buttons; the start and end shown are guesses (目安).
/// 時刻を決める: the start is fixed with a lock, and the plans after it follow.
struct TimeSheet: View {
    let item: ItineraryItem
    let slot: DaySchedule.Slot
    let onSave: (_ durationMinutes: Int, _ fixedStartMinutes: Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var duration: Int
    @State private var start: Date

    enum Mode: Hashable { case length, exact }

    private static let quick: [(label: String, minutes: Int)] = [
        ("30m", 30), ("1h", 60), ("2h", 120), ("3h", 180), ("4h", 240), ("半日", 240), ("1日", 480)
    ]

    init(item: ItineraryItem, slot: DaySchedule.Slot, onSave: @escaping (Int, Int?) -> Void) {
        self.item = item
        self.slot = slot
        self.onSave = onSave
        _mode = State(initialValue: slot.isFixed ? .exact : .length)
        _duration = State(initialValue: item.durationMinutes)
        _start = State(initialValue: Self.date(minutes: slot.startMinutes))
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private var startMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(item.title).font(Theme.jp(17, .bold)).foregroundStyle(Theme.ink).padding(.top, 24)

            Picker("", selection: $mode.animation(.snappy)) {
                Text("長さ").tag(Mode.length)
                Text("時刻を決める").tag(Mode.exact)
            }
            .pickerStyle(.segmented)

            switch mode {
            case .length: lengthBody
            case .exact: exactBody
            }

            Spacer(minLength: 0)

            Button(action: save) {
                Text("保存")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(Theme.surface.ignoresSafeArea())
    }

    // MARK: - 長さ

    private var lengthBody: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                stepButton("minus") { duration = max(15, duration - 15) }
                let parts = DaySchedule.lengthParts(duration)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(parts.hours)").font(Theme.latin(48, .bold))
                    Text("h").font(Theme.latin(16, .medium)).foregroundStyle(Theme.secondary)
                    Text(String(format: "%02d", parts.minutes)).font(Theme.latin(48, .bold))
                    Text("m").font(Theme.latin(16, .medium)).foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line))
                stepButton("plus") { duration = min(24 * 60, duration + 15) }
            }
            HStack(spacing: 10) {
                timeBox("始まり（目安）", DaySchedule.clock(slot.startMinutes))
                timeBox("終わり（目安）", DaySchedule.clock(slot.startMinutes + duration))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.quick, id: \.label) { option in
                        Button { duration = option.minutes } label: {
                            Text(option.label)
                                .font(Theme.jp(13, .bold))
                                .foregroundStyle(duration == option.minutes ? Theme.surface : Theme.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Capsule().fill(duration == option.minutes ? Theme.ink : Theme.fill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(Circle().strokeBorder(Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "15分長く" : "15分短く")
    }

    private func timeBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.latin(20, .bold)).foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
    }

    // MARK: - 時刻を決める

    private var exactBody: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("始まり").font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                    HStack {
                        Text(DaySchedule.clock(startMinutes)).font(Theme.latin(20, .bold))
                        Spacer()
                        Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(Theme.ink)
                    }
                    .foregroundStyle(Theme.ink)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink, lineWidth: 1.5))
                timeBox("終わり", DaySchedule.clock(startMinutes + duration))
            }
            DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
            if slot.isFixed {
                Button("固定を外す") {
                    onSave(duration, nil)
                    dismiss()
                }
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func save() {
        onSave(duration, mode == .exact ? startMinutes : (slot.isFixed ? slot.startMinutes : nil))
        dismiss()
    }
}
