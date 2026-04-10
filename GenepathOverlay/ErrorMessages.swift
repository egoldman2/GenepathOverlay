//
//  ErrorMessages.swift
//  GenepathOverlay
//
//  Created by Melissa Lyon on 9/4/2026.
//


//
//  ErrorMessages.swift
//  GenepathOverlay
//
//  Created by Melissa Lyon on 7/4/2026.
//

import SwiftUI

struct ErrorMessages: View {
    let volume = 78.0 // Pass the volume from your AppModel
    

    var body: some View {
        VStack(spacing: 24) {
         
            //Icon
            Image(systemName: "exclamationmark.triangle.fill")
                
                .foregroundStyle(.yellow)
                .font(.system(size: 60))
            
            // Title
            Text("Wrong Target Detected")
                .font(.title)
                .fontWeight(.bold)
                
            // Description
            Text("STOP. A mistake has been identitified in the target tray. Please select how you will proceed.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
           
            Button(action: {
                //add button integration
            }) {
                Label("Restart the plate", systemImage: "arrow.counterclockwise")
                    .padding(.horizontal, 10)
                    .font(.headline)
                    .foregroundColor(.black)
            }
            .tint(.white)
            
            
            Button(action: {
                //add button integration
            }) {
                Label("Continue anyway", systemImage: "exclamationmark.triangle")
                    
                    .padding(.horizontal, 10)
            }
            
            
        }
        .padding(40)
        .background {

        // 1. We put the tint behind the glass

        Color.red.opacity(0.4)


        }
        
        
        
        .glassBackgroundEffect()
        
    }
}

#Preview(windowStyle: .plain) {
    ErrorMessages()
}
