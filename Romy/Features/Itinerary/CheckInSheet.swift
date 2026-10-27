import SwiftUI

/// 「チェックインできる時間 15:00から」 in a stay's detail (Figma 宿A2); a stay without it asks for it.
struct StayCheckInCard: View {
    let item: ItineraryItem
    @State private var isEditing = false

    var body: some View {
        Button { isEditing = true } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("チェックインできる時間").font(Theme.jp(12, .bold)).foregroundStyle(Theme.secondary)
                    if let from = item.notBeforeMinutes {
                        Text("\(DaySchedule.clock(from))から").font(Theme.latin(17, .bold)).foregroundStyle(Theme.ink)
                    } else {
                        Text("時刻を入れる").font(Theme.jp(15, .bold)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isEditing) {
            CheckInSheet(item: item) { item.notBeforeMinutes = $0 }
                .presentationDetents([.large])
        }
    }
}

/// チェックインの時刻 of a stay (Figma 宿A2 148:148 「チェックインできる時間」): the time the stay can be entered from.
/// Only the start is kept for now (Notion 02 §6-4, 2026-10-22: a stay is its place and when check-in opens).
/// The plan's guessed start waits for it, while a fixed start stays where the person put it.
struct CheckInSheet: View {
    let item: ItineraryItem
    let onSave: (_ notBeforeMinutes: Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    /// 15:00 is only where the wheel starts; nothing is saved until 「保存」.
    private static let firstGuessMinutes = 15 * 60

    init(item: ItineraryItem, onSave: @escaping (Int?) -> Void) {
        self.item = item
        self.onSave = onSave
        let minutes = item.notBeforeMinutes ?? Self.firstGuessMinutes
        _time = State(initialValue: Calendar.current.date(
            bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now
        ) ?? .now)
    }

    private var minutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(item.title).font(Theme.jp(17, .bold)).foregroundStyle(Theme.ink).padding(.top, 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("チェックインできる時間").font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                Text("\(DaySchedule.clock(minutes))から").font(Theme.latin(28, .bold)).foregroundStyle(Theme.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
            if item.notBeforeMinutes != nil {
                Button("時刻を外す") {
                    onSave(nil)
                    dismiss()
                }
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Button {
                onSave(minutes)
                dismiss()
            } label: {
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
}
