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
                
                .foregroundStyle(AppUIStyle.feedbackColor(for: .failure))
                .font(.system(size: 60))
            
            // Title
            Text("Wrong Target Detected")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(AppUIStyle.primaryTextColor)
                
            // Description
            Text("STOP. A mistake has been identitified in the target tray. Please select how you will proceed.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .foregroundStyle(.secondary)
            
           
            Button(action: {
                //add button integration
            }) {
                Label("Restart the plate", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SecondaryActionButton())
            
            
            Button(action: {
                //add button integration
            }) {
                Label("Continue anyway", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(PrimaryActionButton())
            
        }
        .padding(40)
        .background(AppCardBackground())
        
    }
}

#Preview(windowStyle: .plain) {
    ErrorMessages()
}
