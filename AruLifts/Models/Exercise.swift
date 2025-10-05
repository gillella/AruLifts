//
//  Exercise.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import Foundation

enum ExerciseCategory: String, CaseIterable, Codable {
    case compound = "Compound"
    case isolation = "Isolation"
    case cardio = "Cardio"
}

enum EquipmentType: String, CaseIterable, Codable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case machine = "Machine"
    case cable = "Cable"
    case bodyweight = "Bodyweight"
    case kettlebell = "Kettlebell"
    case band = "Band"
}

enum MuscleGroup: String, CaseIterable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case legs = "Legs"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case core = "Core"
    case abs = "Abs"
    case cardio = "Cardio"
}

struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let category: ExerciseCategory
    let equipment: EquipmentType
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    let instructions: [String]
    let videoURL: String? // For future implementation
    let requiresWeight: Bool // True for weighted exercises
    
    init(id: UUID = UUID(),
         name: String,
         description: String,
         category: ExerciseCategory,
         equipment: EquipmentType,
         primaryMuscles: [MuscleGroup],
         secondaryMuscles: [MuscleGroup] = [],
         instructions: [String],
         videoURL: String? = nil,
         requiresWeight: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
        // Provide a default demo video for all exercises if not specified
        self.videoURL = videoURL ?? "exercise_demo"
        self.requiresWeight = requiresWeight
    }
}


