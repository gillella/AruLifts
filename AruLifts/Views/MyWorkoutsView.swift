import SwiftUI

struct MyWorkoutsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @State private var editingTemplate: WorkoutTemplate?
    @State private var showingBuilder = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.templates) { template in
                    NavigationLink {
                        TemplateDetailView(template: template, onStart: { startWorkout(template) })
                    } label: {
                        templateRow(template)
                    }
                }
                .onDelete(perform: store.deleteTemplates)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("My Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTemplate = nil
                        showingBuilder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if store.templates.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + to build your first workout.")
                    )
                }
            }
            .sheet(isPresented: $showingBuilder) {
                WorkoutBuilderView(existing: editingTemplate)
            }
        }
    }

    private func templateRow(_ template: WorkoutTemplate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(template.category.color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: template.category.symbol).foregroundStyle(template.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.headline)
                Text("\(template.exerciseCount) exercises · \(template.totalSets) sets")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func startWorkout(_ template: WorkoutTemplate) {
        let session = WorkoutSession.from(template: template, library: store.exerciseIndex)
        active.start(session)
    }
}

/// Read-only template overview with Start and Edit actions.
struct TemplateDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    let template: WorkoutTemplate
    let onStart: () -> Void
    @State private var showingEdit = false

    var body: some View {
        List {
            Section {
                HStack {
                    CategoryBadge(category: template.category)
                    Spacer()
                    Text("~\(template.estimatedMinutes) min")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !template.notes.isEmpty {
                    Text(template.notes).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section("Exercises") {
                ForEach(template.exercises) { ex in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.body.weight(.medium))
                            Text("\(ex.targetSets) × \(ex.targetReps)" + (ex.weight > 0 ? " · \(formatWeight(ex.weight, units: store.settings.units))" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(ex.restSeconds)s rest")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onStart) {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            WorkoutBuilderView(existing: template)
        }
    }
}

#Preview {
    MyWorkoutsView()
        .environmentObject(WorkoutStore())
        .environmentObject(ActiveWorkoutManager())
}
