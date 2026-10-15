import SwiftData
import SwiftUI

/// 旅行を作る: 行き先 → 日付 → 旅行名. One card opens at a time; decided cards shrink to one line
/// and reopen when tapped (Notion 02 §1–§4, §6-3; Figma page 6 「1. 旅行を作る」).
struct TripCreationView: View {
    let onCreate: (Trip) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var trips: [Trip]

    @State private var model = TripCreationModel()
    @FocusState private var focusedField: TripCreationModel.Step?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(TripCreationModel.Step.allCases, id: \.self) { step in
                        if step == model.openStep {
                            openCard(step)
                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        } else {
                            collapsedRow(step)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.base.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { primaryButton }
    }

    // MARK: - Header and button

    private var header: some View {
        ZStack {
            Text("旅行を作る")
                .font(Theme.jp(17, .bold))
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("閉じる")
                Spacer()
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var primaryButton: some View {
        Button(action: next) {
            Text(model.openStep == .name ? "旅行を作る" : "次へ")
                .font(Theme.jp(17, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Theme.ink))
        }
        .buttonStyle(.plain)
        .opacity(model.canContinue ? 1 : 0.3)
        .disabled(!model.canContinue)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func next() {
        focusedField = nil
        var finished = false
        withAnimation(.snappy(duration: 0.35)) { finished = model.advance() }
        guard finished else {
            if model.openStep == .name { focusedField = .name }
            return
        }
        let trip = model.makeTrip(existingNames: trips.map(\.name))
        modelContext.insert(trip)
        try? modelContext.save()
        onCreate(trip)
        dismiss()
    }

    private func open(_ step: TripCreationModel.Step) {
        focusedField = nil
        withAnimation(.snappy(duration: 0.35)) { model.openStep = step }
    }

    // MARK: - Collapsed rows

    private func collapsedRow(_ step: TripCreationModel.Step) -> some View {
        let isAhead = step.rawValue > model.openStep.rawValue
        return Button { open(step) } label: {
            HStack {
                Text(title(of: step))
                    .font(Theme.jp(15))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 12)
                summary(of: step, isAhead: isAhead)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
            .opacity(isAhead ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    private func title(of step: TripCreationModel.Step) -> String {
        switch step {
        case .destinations: "行き先"
        case .dates: "日付"
        case .name: "旅行名"
        }
    }

    @ViewBuilder
    private func summary(of step: TripCreationModel.Step, isAhead: Bool) -> some View {
        switch step {
        case .destinations:
            if !model.destinations.isEmpty {
                Text(model.destinations.map(\.name).joined(separator: "・"))
                    .font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            } else if !isAhead {
                Text("あとで決める").font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            }
        case .dates:
            if !isAhead {
                Text(model.dateText.summary(model.dates))
                    .font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            }
        case .name:
            let typed = model.name.trimmingCharacters(in: .whitespaces)
            if typed.isEmpty {
                Text("入れなければ「\(model.autoName(existingNames: trips.map(\.name)))」")
                    .font(Theme.jp(13)).foregroundStyle(Theme.secondary)
            } else {
                Text(typed).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: - Open cards

    private func openCard(_ step: TripCreationModel.Step) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch step {
            case .destinations: DestinationSearchCard(model: model, focusedField: $focusedField)
            case .dates: datesCard
            case .name: nameCard
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
        )
    }

    // MARK: 日付

    @ViewBuilder
    private var datesCard: some View {
        Text("いつ行く？").font(Theme.jp(24, .bold)).foregroundStyle(Theme.ink)

        HStack(spacing: 0) {
            modeButton("あとで", .later)
            modeButton("日数だけ", .days)
            modeButton("日付を指定", .specific)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.fill))

        switch model.dateMode {
        case .later:
            EmptyView()
        case .days:
            DayCountDrum(value: $model.dayCount)
        case .specific:
            specificDates
        }
    }

    private func modeButton(_ title: String, _ mode: TripCreationModel.DateMode) -> some View {
        let isOn = model.dateMode == mode
        return Button { withAnimation(.snappy) { model.dateMode = mode } } label: {
            Text(title)
                .font(Theme.jp(14, .medium))
                .foregroundStyle(isOn ? Theme.ink : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 18).fill(isOn ? Theme.surface : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var specificDates: some View {
        let options = model.quickDates.options(today: model.today)
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                quickChip(
                    title: option.title,
                    subtitle: model.isCalendarOpen ? nil : model.dateText.shortRange(option.start, option.end),
                    isOn: model.selectedQuickDate == option.kind
                ) {
                    withAnimation(.snappy) { model.choose(option) }
                }
            }
            quickChip(title: "カレンダーで選ぶ", subtitle: nil, isOn: model.isCalendarOpen) {
                withAnimation(.snappy) { model.openCalendar() }
            }
        }

        if model.isCalendarOpen {
            RangeCalendarView(
                calendar: model.calendar,
                today: model.today,
                start: model.rangeStart,
                end: model.rangeEnd
            ) { day in
                withAnimation(.snappy) { model.tapCalendarDay(day) }
            }
            .transition(.opacity)
        }

        if let start = model.rangeStart {
            let end = model.rangeEnd ?? start
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.dateText.range(start, end))
                    .font(Theme.jp(18, .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(model.dateText.dayCount(start, end))日間")
                    .font(Theme.jp(14, .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func quickChip(title: String, subtitle: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.jp(14, .bold))
                if let subtitle {
                    Text(subtitle).font(Theme.jp(11)).opacity(0.7)
                }
            }
            .foregroundStyle(isOn ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isOn ? Theme.ink : Theme.surface)
                    .strokeBorder(isOn ? .clear : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: 旅行名

    @ViewBuilder
    private var nameCard: some View {
        Text("旅行の名前は？").font(Theme.jp(24, .bold)).foregroundStyle(Theme.ink)
        TextField(model.autoName(existingNames: trips.map(\.name)), text: $model.name)
            .font(Theme.jp(17, .bold))
            .focused($focusedField, equals: .name)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
    }
}
