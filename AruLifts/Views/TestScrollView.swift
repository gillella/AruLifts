//
//  TestScrollView.swift
//  AruLifts
//
//  Test view to debug scrolling
//

import SwiftUI

struct TestScrollView: View {
    var body: some View {
        NavigationView {
            List(0..<100) { i in
                Text("Item \(i)")
                    .padding()
            }
            .navigationTitle("Scroll Test")
        }
    }
}

#Preview {
    TestScrollView()
}
