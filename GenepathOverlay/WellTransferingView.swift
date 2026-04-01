//
//  WellTransferingView.swift
//  GenepathOverlay
//
//  Created by Melissa Lyon on 31/3/2026.
//

import SwiftUI
import RealityKit

struct WellTransferingView: View {
    var aspirationPos = "A4"
    var depositPos = "C7"
    @State private var isAspirationConfirmed = false
    @State private var isDepositConfirmed = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Title
            Text("Well Transferring")
                .font(.title2.weight(.semibold))
            
            // Description
            Text("Refer to this window or the overlay shown above the plates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            //Image  needed custom well plate icons
            HStack {
                ZStack {
                    Image(systemName: "apps.ipad.landscape")
                        .scaleEffect(x: -1, y: 1)
                    Image(systemName: "apps.ipad.landscape")
                    Image(systemName: "apps.ipad.landscape")
                        .rotationEffect(.degrees(180))
                    Image(systemName: "apps.ipad.landscape")
                        .rotationEffect(.degrees(180))
                        .scaleEffect(x: -1, y: 1)
                }
                .foregroundColor(isAspirationConfirmed ? .white : .blue )
                
                Image (systemName: "arrow.right")
                
                ZStack {
                    Image(systemName: "apps.ipad.landscape")
                        .scaleEffect(x: -1, y: 1)
                    Image(systemName: "apps.ipad.landscape")
                    Image(systemName: "apps.ipad.landscape")
                        .rotationEffect(.degrees(180))
                    Image(systemName: "apps.ipad.landscape")
                        .rotationEffect(.degrees(180))
                        .scaleEffect(x: -1, y: 1)
                }
                .foregroundColor(isDepositConfirmed ? .white : .blue )
                
            } .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
            
            HStack {
                Text(aspirationPos + "                     ")
                    .foregroundColor(isAspirationConfirmed ? .white : .blue )
                Text(depositPos)
                    .foregroundColor(isDepositConfirmed ? .white : .blue )
            } .font(.title2)
            
            
            if !isAspirationConfirmed {
                Button(action: {
                    isAspirationConfirmed.toggle()
                }) {
                    Label(
                        "Confirm Aspiration",
                        systemImage: "checkmark"
                    )
                    .padding(.horizontal, 10)
                    .font(.headline)
                    .foregroundColor(.white)
                }
                .tint(.gray)
            } else {
                Button(action: {
                    isDepositConfirmed.toggle()
                }) {
                    Label(
                        "Confirm Deposit",
                        systemImage: "checkmark"
                    )
                    .padding(.horizontal, 10)
                    .font(.headline)
                    .foregroundColor(.white)
                }
                .tint(.gray)
                
                //continue to next screen
            }
            
                
            

            
           
            Button(action: {
                isAspirationConfirmed = false
                isDepositConfirmed = false
            }) {
                Label("Skip", systemImage: "xmark")
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            
        }
        .padding(40)
        // This is what blurs the real world/simulator environment
        .glassBackgroundEffect()
    }
}

#Preview {
    WellTransferingView()
}
