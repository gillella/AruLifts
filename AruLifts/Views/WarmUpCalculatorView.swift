//
//  WarmUpCalculatorView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI

struct WarmupSet: Identifiable {
    let id = UUID()
    let setNumber: Int
    let percentage: Double
    let weight: Double
    let reps: Int
}

struct WarmUpCalculatorView: View {
    @State private var workingWeight: String = "135"
    @State private var barWeight: Double = 45.0
    @State private var warmupSets: [WarmupSet] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Warm-up Calculator")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Calculate your warm-up sets before lifting heavy")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Input section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Working Weight")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter weight", text: $workingWeight)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                        
                        Text("lbs")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Bar Weight")
                        .font(.headline)
                        .padding(.top)
                    
                    Picker("Bar Weight", selection: $barWeight) {
                        Text("45 lbs (Standard)").tag(45.0)
                        Text("35 lbs (Women's)").tag(35.0)
                        Text("15 lbs (Training)").tag(15.0)
                    }
                    .pickerStyle(.segmented)
                    
                    Button(action: calculateWarmups) {
                        Text("Calculate Warm-ups")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.top)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                .padding(.horizontal)
                
                // Warm-up sets display
                if !warmupSets.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Warm-up Sets")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            ForEach(warmupSets) { set in
                                WarmupSetRow(set: set, barWeight: barWeight)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                
                // Tips section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Warm-up Tips")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(
                            icon: "1.circle.fill",
                            text: "Start with the empty bar for technique practice"
                        )
                        TipRow(
                            icon: "2.circle.fill",
                            text: "Gradually increase weight by 10-20%"
                        )
                        TipRow(
                            icon: "3.circle.fill",
                            text: "Do fewer reps as weight increases"
                        )
                        TipRow(
                            icon: "4.circle.fill",
                            text: "Rest 30-60 seconds between warm-up sets"
                        )
                        TipRow(
                            icon: "5.circle.fill",
                            text: "Don't tire yourself out before working sets"
                        )
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .padding(.top)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.05), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func calculateWarmups() {
        guard let target = Double(workingWeight), target > barWeight else {
            warmupSets = []
            return
        }
        
        var sets: [WarmupSet] = []
        
        // Set 1: Empty bar - 5 reps
        sets.append(WarmupSet(setNumber: 1, percentage: 0, weight: barWeight, reps: 5))
        
        if target > barWeight + 50 {
            // Set 2: 40% - 5 reps
            let weight2 = round((barWeight + (target - barWeight) * 0.4) / 5) * 5
            sets.append(WarmupSet(setNumber: 2, percentage: 40, weight: weight2, reps: 5))
        }
        
        if target > barWeight + 100 {
            // Set 3: 60% - 3 reps
            let weight3 = round((barWeight + (target - barWeight) * 0.6) / 5) * 5
            sets.append(WarmupSet(setNumber: 3, percentage: 60, weight: weight3, reps: 3))
        }
        
        if target > barWeight + 140 {
            // Set 4: 80% - 2 reps
            let weight4 = round((barWeight + (target - barWeight) * 0.8) / 5) * 5
            sets.append(WarmupSet(setNumber: 4, percentage: 80, weight: weight4, reps: 2))
        }
        
        if target > barWeight + 180 {
            // Set 5: 90% - 1 rep
            let weight5 = round((barWeight + (target - barWeight) * 0.9) / 5) * 5
            sets.append(WarmupSet(setNumber: 5, percentage: 90, weight: weight5, reps: 1))
        }
        
        warmupSets = sets
    }
}

struct WarmupSetRow: View {
    let set: WarmupSet
    let barWeight: Double
    
    var platesPerSide: String {
        let weightPerSide = (set.weight - barWeight) / 2
        if weightPerSide <= 0 { return "No plates" }
        
        var plates: [String] = []
        var remaining = weightPerSide
        
        // Calculate plates (45, 25, 10, 5, 2.5)
        let plateSizes: [Double] = [45, 25, 10, 5, 2.5]
        for plateSize in plateSizes {
            let count = Int(remaining / plateSize)
            if count > 0 {
                plates.append("\(count)×\(Int(plateSize))")
                remaining -= Double(count) * plateSize
            }
        }
        
        return plates.isEmpty ? "No plates" : plates.joined(separator: " + ")
    }
    
    var body: some View {
        HStack {
            // Set number
            Text("Set \(set.setNumber)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(set.weight)) lbs")
                        .font(.title3)
                        .fontWeight(.bold)
                    if set.percentage > 0 {
                        Text("(\(Int(set.percentage))%)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(platesPerSide)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(set.reps) reps")
                .font(.headline)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationView {
        WarmUpCalculatorView()
    }
}

