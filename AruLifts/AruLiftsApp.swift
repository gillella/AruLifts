//
//  AruLiftsApp.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI

@main
struct AruLiftsApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var workoutManager = CustomWorkoutManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(workoutManager)
                .onAppear {
                    // Initialize exercise library on first launch
                    workoutManager.loadExerciseLibrary()
                    workoutManager.loadSavedWorkouts()
                }
        }
    }
}

