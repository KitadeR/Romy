import SwiftUI

/// A plan's detail (Notion 02 §6-6 予定の詳細シート, agreed 2026-10-11 and 2026-10-13). It takes the place of the
/// itinerary inside the same Apple sheet; ✕ goes back to the itinerary with the same tab.
/// Top to bottom: the time (tap to change it), the place, and 「この予定」 (move, back to 未定, delete).
/// Two buttons float at the bottom: 経路, and in Action the black 済みにする.
/// Not yet: the booking card, the place's photos and Apple's place card, Google Maps (Notion 05).
struct PlanDetailView: View {
    let item: ItineraryItem
    /// 1-based position in its day (or in 未定): the number on its card and pin.
    let number: Int
    /// 「1日目 ・ 10/18（日）」 or 「未定」.
    let dayCaption: String
    let color: Color
    /// Nil in 未定, which has no times.
    let slot: DaySchedule.Slot?
    /// 済み is marked in Action, on days.
    let canMarkDone: Bool
    let note: AppShell.ShellNote?
    let onUndo: (AppShell.ShellNote) -> Void
    let onClose: () -> Void
    let onEditTime: () -> Void
    let onMove: () -> Void
    let onSendToUndecided: () -> Void
    let onRoute: () -> Void
    let onToggleDone: () -> Void
    let onDelete: () -> Void

    private var hasPlace: Bool {
        item.latitude != nil && item.longitude != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.top, 22)
                ScrollView {
                    VStack(spacing: 12) {
                        timeCard
                        placeCard
                        thisPlanCard
                    }
                    .padding(.bottom, 170)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.base.ignoresSafeArea())
    }

    // MARK: - Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Theme.latin(13, .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(Theme.jp(22, .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text([dayCaption, item.kind.label].compactMap { $0 }.joined(separator: " ・ "))
                    .font(Theme.jp(13, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
    }

    @ViewBuilder
    private var timeCard: some View {
        if let slot {
            Button(action: onEditTime) {
                card {
                    HStack(spacing: 10) {
                        Image(systemName: slot.isFixed ? "lock.fill" : "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(slot.isFixed ? Theme.ink : Theme.secondary)
                        Text("\(DaySchedule.clock(slot.startMinutes)) → \(DaySchedule.clock(slot.endMinutes))")
                            .font(Theme.latin(17, .bold))
                            .foregroundStyle(slot.isFixed ? Theme.ink : Theme.secondary)
                        Text(slot.isFixed ? "固定" : "目安")
                            .font(Theme.jp(12, .medium))
                            .foregroundStyle(Theme.secondary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(DaySchedule.clock(slot.startMinutes))から\(DaySchedule.clock(slot.endMinutes))、時刻を変える")
        } else {
            card {
                Text("日に入れると時刻が付きます")
                    .font(Theme.jp(14, .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var placeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                caption("場所")
                if hasPlace {
                    Text(placeLine)
                        .font(Theme.jp(15, .medium))
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("場所はまだありません（名前だけの予定）")
                        .font(Theme.jp(14, .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    /// 「名所 ・ 京都市東山区」: what Apple calls the place and the ward it was saved with.
    private var placeLine: String {
        let line = [item.category, item.area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ ")
        return line.isEmpty ? "場所あり" : line
    }

    private var thisPlanCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                caption("この予定")
                    .padding(.bottom, 4)
                row("日を移す", symbol: "arrow.left.arrow.right", action: onMove)
                if item.day != nil {
                    Divider()
                    row("未定に戻す", symbol: "tray", action: onSendToUndecided)
                }
                Divider()
                row("予定を削除", symbol: "trash", tint: .red, action: onDelete)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let note {
                ShellNoteView(note: note, onUndo: onUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if hasPlace || canMarkDone {
                HStack(spacing: 12) {
                    if hasPlace {
                        Button(action: onRoute) {
                            Label("経路", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(Theme.jp(16, .bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 24)
                                .frame(maxWidth: canMarkDone ? nil : .infinity, minHeight: 52)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title)への経路")
                    }
                    if canMarkDone {
                        Button(action: onToggleDone) {
                            Text(item.doneAt == nil ? "済みにする" : "済みを取り消す")
                                .font(Theme.jp(17, .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Capsule().fill(Theme.ink))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func caption(_ title: String) -> some View {
        Text(title)
            .font(Theme.jp(12, .bold))
            .foregroundStyle(Theme.secondary)
    }

    private func row(
        _ title: String, symbol: String, tint: Color = Theme.ink, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(Theme.jp(15, .bold))
                Spacer(minLength: 8)
            }
            .foregroundStyle(tint)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
