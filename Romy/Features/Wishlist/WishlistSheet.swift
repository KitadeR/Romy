import CoreLocation
import SwiftUI

/// 「行きたい」 (Notion 02 §6-6, agreed 2026-10-14): the places saved with ♥ for this trip. Plan groups them by ward;
/// Action lists them from the nearest, with the distance. A place that was added to the itinerary stays, marked
/// 「✓ 2日目に追加済み」 in that day's color. ♥ takes a place out (with 「元に戻す」); ＋ asks which day it goes to.
struct WishlistSheet: View {
    let trip: Trip
    let isAction: Bool
    let location: CLLocation?
    let actions: HomeActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("行きたい").font(Theme.jp(22, .bold)).foregroundStyle(Theme.ink)
                Text("\(trip.wishes.count)").font(Theme.latin(14, .medium)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            searchButton
            if trip.wishes.isEmpty {
                Text("♥で保存した場所がここに並びます。旅程に入れても、ここに残ります。")
                    .font(Theme.jp(13, .medium))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) { content }
                        .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        if isAction, let location {
            ForEach(WishList.nearestFirst(trip.wishes, from: location), id: \.wish.id) { entry in
                row(entry.wish, distance: WishList.distanceText(entry.meters))
            }
        } else {
            ForEach(WishList.groups(trip.wishes)) { group in
                Text(group.title)
                    .font(Theme.jp(12, .bold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 6)
                ForEach(group.wishes) { row($0, distance: nil) }
            }
        }
    }

    private var searchButton: some View {
        Button(action: actions.search) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                Text("行きたい所を探す").font(Theme.jp(15, .medium))
                Spacer()
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("行きたい所を探す")
    }

    private func row(_ wish: WishPlace, distance: String?) -> some View {
        let plan = trip.plan(for: wish)
        let detail = [distance, wish.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ ")
        return HStack(spacing: 12) {
            Image(systemName: wish.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill))
            VStack(alignment: .leading, spacing: 4) {
                Text(wish.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                if let plan { addedBadge(plan) }
            }
            Spacer(minLength: 8)
            Button { actions.removeWish(wish) } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(wish.title)を行きたいから外す")
            trailing(wish, plan: plan)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func addedBadge(_ plan: ItineraryItem) -> some View {
        let color = Theme.dayColor(plan.day)
        return Text("✓ \(plan.day.map { "\($0)日目" } ?? "未定")に追加済み")
            .font(Theme.jp(11, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    @ViewBuilder
    private func trailing(_ wish: WishPlace, plan: ItineraryItem?) -> some View {
        if let plan {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.dayColor(plan.day)))
                .accessibilityLabel("追加済み")
        } else {
            Button { actions.chooseDay(wish) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(wish.title)を旅程に入れる")
        }
    }
}
