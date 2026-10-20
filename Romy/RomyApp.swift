//
//  RomyApp.swift
//  Romy
//
//  Created by 北出琉和 on 2026/10/14.
//

import SwiftData
import SwiftUI

@main
struct RomyApp: App {
    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Trip.self, ItineraryItem.self, WishPlace.self])
    }
}

/// Opens the trip opened last; with no trip, the first Home (Notion 02 §6, §6-3).
struct RootView: View {
    @Query(sort: \Trip.lastOpenedAt, order: .reverse) private var trips: [Trip]
    @State private var isCreating = false

    var body: some View {
        Group {
            if let trip = trips.first {
                // The shell's sheet is always up, so it presents trip creation itself.
                AppShell(trip: trip)
                    .id(trip.id)
            } else {
                FirstHomeView { isCreating = true }
                    .sheet(isPresented: $isCreating) {
                        TripCreationView { trip in trip.lastOpenedAt = .now }
                            .presentationDetents([.large])
                    }
            }
        }
    }
}
