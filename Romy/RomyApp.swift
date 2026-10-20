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

    #if DEBUG
    @Environment(\.modelContext) private var debugContext
    #endif

    var body: some View {
        #if DEBUG
        // DUMMY for the poster: still mocks of Figma 23案 and the Action Home replace the app, and a folder of
        // photos can be put on the trip (ActionCheckMockView, ActionHomeMockView, DebugPhotoLoader). Debug builds only.
        Group {
            if let phase = ActionCheckMockView.launchPhase {
                ActionCheckMockView(phase: phase)
            } else if ActionHomeMockView.isLaunched {
                ActionHomeMockView()
            } else {
                content
            }
        }
        .task { DebugPhotoLoader.run(trips: trips, context: debugContext) }
        #else
        content
        #endif
    }

    private var content: some View {
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
