//
//  PipetteConfirmationView.swift
//  GenepathOverlay
//
//  Created by Melissa Lyon on 31/3/2026.
//

import SwiftUI
import RealityKit

struct PipetteConfirmationView: View {
    let volume = 78.0 // Pass the volume from your AppModel
    

    var body: some View {
        VStack(spacing: 20) {
            
//            HStack {
//                Image(systemName: "minus")
//                Image(systemName: "arrow.left.and.right") // replaces digitalcrown.horizontal
//                Image(systemName: "plus")
//            }
//            .padding()
//            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 50))
//            .font(.system(size: 30, weight: .regular))
//            .foregroundStyle(.white.opacity(0.9))
            
            
                
                

            // Title
            Text("Set Pipette Volume")
                .font(.title2.weight(.semibold))
            
            // Description
            Text("Verify your pipette is set to the target volume before proceeding. \nThis is for procedure A4 > C7.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
            HStack(spacing: 0) { // no gaps
                // First yellow rectangle
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 50, height: 150)

                // Black rectangle with 4 vertical numbers
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 60, height: 150)

                    VStack {
                        Text("0").foregroundColor(.gray)
                        Text("0").foregroundColor(.gray)
                        Text("3")
                        Text("4")
                    }
//                    .bold()
                    .font(.system(size: 24, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                }

                // Second yellow rectangle
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 50, height: 150)
            }

                
            Button(action: {
                
            }) {
                Label("Confirm and Proceed", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryActionButton())
           
            Button(action: {
                
            }) {
                Label("Skip", systemImage: "xmark")
            }
            .buttonStyle(SecondaryActionButton())
            
        }
        .padding(40)
        // This is what blurs the real world/simulator environment
        .glassBackgroundEffect()
    }
}

#Preview(windowStyle: .plain) {
    PipetteConfirmationView()
}
