import SwiftUI

/// Top-level tab navigation. When a workout is active, a full-screen cover
/// presents the live workout over whichever tab is selected.
struct RootView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            MyWorkoutsView()
                .tabItem { Label("Workouts", systemImage: "square.grid.2x2.fill") }
                .tag(1)

            ExerciseLibraryView()
                .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
                .tag(2)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .fullScreenCover(isPresented: Binding(
            get: { active.isActive },
            set: { if !$0 { } }
        )) {
            ActiveWorkoutView()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(WorkoutStore())
        .environmentObject(ActiveWorkoutManager())
}
