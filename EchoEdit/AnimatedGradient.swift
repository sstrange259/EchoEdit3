//
//  AnimatedGradient.swift
//  TextTune
//
//  Created by Steven Strange on 6/13/25.
//

import SwiftUI

// MARK: - Animated Gradient (blue and purple)
struct AnimatedGradient: View {
    @State private var animate = false

    private let colors: [Color] = [
        Color.blue,
        Color(red: 0.4, green: 0.2, blue: 0.8), // Purple-blue
        Color.purple
    ]

    var body: some View {
        RadialGradient(colors: colors,
                       center: animate ? .bottomTrailing : .topLeading,
                       startRadius: 5,
                       endRadius: 150)
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate.toggle() }
    }
}