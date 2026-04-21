import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct UploadCSVFileView: View {
    // 1. State for the File Picker and Error Handling
    @State private var isImporting: Bool = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // 2. This is where parsed data will go
    // Note: You'll likely want to pass this to a ViewModel or Parent view later
    @State private var parsedSteps: [Step] = []
    
    // Will need an instance of the Mapper here
    // Replace 'DefaultCoordinateMapper()' with your actual initializer
    let parser = CSVParser(coordinateMapper: CoordinateMapper())

    var body: some View {
        VStack(spacing: 30) {
            // Upload Icon
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                

            // Title
            Text("Upload CSV File")
                .font(.title2.weight(.semibold))
            
            // Description
            Text("Select a CSV file from your device to begin plate mapping and move sequencing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Buttons
            HStack(spacing:15) {
                Button(action: {
                    // Logic for history could go here
                }) {
                    Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .padding(.horizontal, 10)
                }
                .buttonBorderShape(.roundedRectangle)
                .tint(.gray)
                .controlSize(.large)
                
                Button(action: {
                    // 3. Trigger the file importer
                    isImporting = true
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
        .glassBackgroundEffect()
        
        // 4. The File Importer Logic
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                
                // VisionOS/iOS requires permission to access files outside the app sandbox
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let steps = try parser.parse(fileAt: url)
                        self.parsedSteps = steps
                        print("Successfully parsed \(steps.count) steps!")
                        // Navigate or update UI here
                    } catch {
                        self.errorMessage = error.localizedDescription
                        self.showingError = true
                    }
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.showingError = true
            }
        }
        // 5. Error Alert
        .alert("Upload Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown Error")
        }
    }
}

#Preview(windowStyle: .plain) {
    UploadCSVFileView()
}
