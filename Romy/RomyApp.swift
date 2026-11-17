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
            #if DEBUG
            if FenrirCapture.screen != nil {
                FenrirCaptureHost()
                    .modelContainer(FenrirCapture.container)
            } else {
                RootView()
                    .modelContainer(for: [Trip.self, ItineraryItem.self, WishPlace.self])
            }
            #else
            RootView()
                .modelContainer(for: [Trip.self, ItineraryItem.self, WishPlace.self])
            #endif
        }
    }
}

/// Opens the trip opened last; with no trip, the first Home (Notion 02 §6, §6-3).
struct RootView: View {
    @Query(sort: \Trip.lastOpenedAt, order: .reverse) private var trips: [Trip]
    @State private var isCreating = false
    @Environment(\.scenePhase) private var scenePhase

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
        // The stays of today and tomorrow are checked ahead, so Romy Now does not wait (Notion 02 §6-4 事実の確認⑤).
        .task(id: scenePhase) {
            if scenePhase == .active { await LuggagePrefetch.run(trips: trips) }
        }
    }
}
