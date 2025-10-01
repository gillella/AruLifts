//
//  RestTimerView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI

struct RestTimerView: View {
    let restTime: Int
    @Binding var isPresented: Bool
    @State private var timeRemaining: Int
    @State private var isPaused = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(restTime: Int, isPresented: Binding<Bool>) {
        self.restTime = restTime
        self._isPresented = isPresented
        self._timeRemaining = State(initialValue: restTime)
    }
    
    var progress: Double {
        Double(timeRemaining) / Double(restTime)
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Timer circle
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 20)
                    .frame(width: 250, height: 250)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: progress > 0.5 ? [.orange, .red] : [.green, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)
                
                VStack(spacing: 8) {
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    Text("Rest Time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Controls
            HStack(spacing: 24) {
                Button(action: {
                    isPaused.toggle()
                }) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.orange)
                        .clipShape(Circle())
                }
                
                Button(action: {
                    timeRemaining = restTime
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            
            Spacer()
            
            // Quick add buttons
            VStack(spacing: 12) {
                Text("Add Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    ForEach([15, 30, 60], id: \.self) { seconds in
                        Button(action: {
                            timeRemaining += seconds
                        }) {
                            Text("+\(seconds)s")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                                .frame(width: 70)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .padding()
        .onReceive(timer) { _ in
            if !isPaused && timeRemaining > 0 {
                timeRemaining -= 1
                
                // Haptic feedback at specific intervals
                if timeRemaining == 10 || timeRemaining == 5 || timeRemaining == 0 {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
                
                // Auto-dismiss when timer reaches 0
                if timeRemaining == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    RestTimerView(restTime: 180, isPresented: .constant(true))
}

