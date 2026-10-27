import SwiftUI

extension ItineraryView {
    /// 「この後の過ごし方を提案」, or nil where it is not offered.
    func suggestion(
        for item: ItineraryItem, day: Int?, plans: [ItineraryItem], schedule: DaySchedule?
    ) -> (() -> Void)? {
        schedule.flatMap { proposalOpportunity(for: item, day: day, plans: plans, schedule: $0) }
            .map { opportunity in { proposing = opportunity } }
    }

    /// 「いまどうする？」 on the Action Home: the moment for today's plan that is 今, or nil where it is not offered.
    func homeOpportunity(for item: ItineraryItem) -> ActionOpportunity? {
        guard let day = todayNumber else { return nil }
        let plans = trip.items(on: day)
        let schedule = trip.schedule(
            of: plans, on: .now, calendar: text.calendar, travelMinutes: { travel.minutes(from: $0, to: $1) }
        )
        return proposalOpportunity(for: item, day: day, plans: plans, schedule: schedule)
    }

    /// The proposal is offered on the plan that is 今, today, when a later plan has a place (Notion 02 §6-4).
    private func proposalOpportunity(
        for item: ItineraryItem, day: Int?, plans: [ItineraryItem], schedule: DaySchedule
    ) -> ActionOpportunity? {
        guard isAction, let day, day == todayNumber else { return nil }
        let progress = DayProgress(
            plans: plans.map { DayProgress.Input(id: $0.id, isDone: $0.doneAt != nil) }, isToday: true
        )
        guard progress.state(of: item.id) == .now,
              let nowMinutes = Trip.minutes(of: .now, on: .now, calendar: text.calendar) else { return nil }
        return ActionOpportunity.make(after: item, in: plans, schedule: schedule, nowMinutes: nowMinutes)
    }
}

extension View {
    /// 「候補を比べる」, opened from the plan that is 今 (attached where the other sheets of the itinerary are).
    func actionProposalSheet(_ opportunity: Binding<ActionOpportunity?>) -> some View {
        sheet(item: opportunity) { opportunity in
            ActionProposalPresenter(opportunity: opportunity).presentationDetents([.large])
        }
    }
}

/// Builds the sheet's model with the location the shell shares.
private struct ActionProposalPresenter: View {
    let opportunity: ActionOpportunity
    @Environment(LocationProvider.self) private var location

    var body: some View {
        ActionProposalSheet(model: seeded(), location: location)
    }

    /// The model with the tiles' words already put in as chips.
    private func seeded() -> ActionProposalModel {
        let model = ActionProposalModel(opportunity: opportunity, location: location)
        for word in opportunity.seedWords { _ = model.add(word) }
        return model
    }
}
