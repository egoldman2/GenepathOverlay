import SwiftUI
import RealityKit

struct UploadCSVFileView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Upload Icon - uses material to pop against the glass
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .padding()
                .background(.ultraThinMaterial, in: Circle())

            // Title
            Text("Upload CSV File")
                .font(.title2.weight(.semibold))
            
            // Description
            Text("Select a CSV file from your device to begin plate mapping and move sequencing.\n")
                .font(.body)
                .foregroundStyle(.secondary) // Use secondary for a cleaner "Apple" look
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // THE COLORED BUTTON
            HStack {
                Button(action: {
                    
                }) {
                    Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .padding(.horizontal, 10)
                }
                .buttonBorderShape(.roundedRectangle)
                .tint(.gray)
                .controlSize(.large)
                
                Button(action: {
                    
                }) {
                    Label("Select CSV File", systemImage: "tablecells")
                        .padding(.horizontal, 10)
                }
                .buttonBorderShape(.roundedRectangle)
                .tint(.blue)
                .controlSize(.large)
            }
            
        }
        .padding(40)
        // This is what blurs the real world/simulator environment
        .glassBackgroundEffect()
    }
}

#Preview(windowStyle: .plain) {
    UploadCSVFileView()
}
