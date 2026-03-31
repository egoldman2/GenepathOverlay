//
//  GlassyCSVUploadView.swift
//  GenepathOverlay
//
//  Created by Melissa Lyon on 31/3/2026.
//


import SwiftUI
import RealityKit

struct GlassyCSVUploadView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Upload Icon
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .padding()
                .background(.ultraThinMaterial, in: Circle())

            // Title
            Text("Upload CSV File")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            // Description
            Text("Select a CSV file from your device to begin processing and analysing your data within the mixed reality environment.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Button
            Button(action: {
                // Handle file selection
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "tablecells")
                    Text("Select CSV File")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(30)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding()
    }
}



#Preview(windowStyle: .automatic) {
    GlassyCSVUploadView()
        .environment(AppModel())
}
