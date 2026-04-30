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
        VStack(spacing:20){
            //Icon
            /*
            ZStack {
                Image(systemName: "apps.ipad.landscape")
                    .scaleEffect(x: -1, y: 1)
                Image(systemName: "apps.ipad.landscape")
                Image(systemName: "apps.ipad.landscape")
                    .rotationEffect(.degrees(180))
                Image(systemName: "apps.ipad.landscape")
                    .rotationEffect(.degrees(180))
                    .scaleEffect(x: -1, y: 1)
            } .font(.system(size: 48, weight: .regular))
            
             */
            // Title
            Text("Well Transferring")
                .font(.title2.weight(.semibold))
            
            // Description
            
            Text("Refer to this window or the overlay shown above the plates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            //Coordinates
            HStack(spacing: 20) {
                Text(aspirationPos)
                    .font(.system(size: !isAspirationConfirmed ? 35 : 24))
                    .foregroundColor(!isAspirationConfirmed ? .white : .secondary)
                    .fontWeight(!isAspirationConfirmed ? .bold : .regular)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            // Background: Blue when active, faint gray when not
                            .fill(!isAspirationConfirmed ? Color.blue : Color.secondary.opacity(0.1))
                    )
                
                Image(systemName: "arrow.right")
                    .font(.title)
                    .foregroundColor(.secondary)
                
                Text(depositPos)
                    .font(.system(size: isAspirationConfirmed && !isDepositConfirmed ? 35 : 24))
                    .foregroundColor(isAspirationConfirmed && !isDepositConfirmed ? .white : .secondary)
                    .fontWeight(isAspirationConfirmed && !isDepositConfirmed ? .bold : .regular)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            // Background: Blue when active, faint gray when not
                            .fill(isAspirationConfirmed && !isDepositConfirmed ? Color.blue : Color.secondary.opacity(0.1))
                    )
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAspirationConfirmed)
            
            // Buttons
            if !isAspirationConfirmed {
                Button(action: {
                    withAnimation { isAspirationConfirmed = true }
                }) {
                    Label("Confirm Aspiration", systemImage: "checkmark")
                        .padding(.horizontal, 10)
                        .padding()
                        
                }
                .buttonStyle(.plain)
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hoverEffect(.highlight)
            } else {
                Button(action: {
                    withAnimation { isDepositConfirmed = true }
                }) {
                    Label("Confirm Deposit", systemImage: "checkmark")
                        .padding(.horizontal, 10)
                        .font(.headline)
                        .padding()
                }
                .buttonStyle(.plain)
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hoverEffect(.highlight)
                
            }
            
            Button(action: {
                isAspirationConfirmed = false
                isDepositConfirmed = false
            }) {
                Label("Skip", systemImage: "xmark")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
            
        }
        .padding(40)
        .glassBackgroundEffect()
        
    }
    
    /*
    var body: some View {
        VStack(spacing: 20) {
            //Icon
            ZStack {
                Image(systemName: "apps.ipad.landscape")
                    .scaleEffect(x: -1, y: 1)
                Image(systemName: "apps.ipad.landscape")
                Image(systemName: "apps.ipad.landscape")
                    .rotationEffect(.degrees(180))
                Image(systemName: "apps.ipad.landscape")
                    .rotationEffect(.degrees(180))
                    .scaleEffect(x: -1, y: 1)
            } .font(.system(size: 48, weight: .regular))
            
            // Title
            Text("Well Transferring")
                .font(.title2.weight(.semibold))
            
            // Description
            Text("Refer to this window or the overlay shown above the plates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            // Coordinates
            VStack(spacing: 40) {
                Text(aspirationPos)
                    .foregroundColor(!isAspirationConfirmed ? .blue : .white)
                
                Image(systemName: "arrow.down")
                    .foregroundColor(.secondary)
                
                Text(depositPos)
                    .foregroundColor(isAspirationConfirmed && !isDepositConfirmed ? .blue : .white)
                    
            }
            .font(.title.monospaced()) // Monospaced keeps the spacing consistent
            
                // Buttons
                if !isAspirationConfirmed {
                    Button(action: {
                        withAnimation { isAspirationConfirmed = true }
                    }) {
                        Label("Confirm Aspiration", systemImage: "checkmark")
                            .padding(.horizontal, 10)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        withAnimation { isDepositConfirmed = true }
                    }) {
                        Label("Confirm Deposit", systemImage: "checkmark")
                            .padding(.horizontal, 10)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button(action: {
                    isAspirationConfirmed = false
                    isDepositConfirmed = false
                }) {
                    Label("Skip", systemImage: "xmark")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            
        }
        .padding(40)
        .glassBackgroundEffect()
    }
     */
}

#Preview {
    WellTransferingView()
}
