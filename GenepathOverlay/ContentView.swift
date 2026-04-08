//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 17/3/2026.
//

import RealityKit
import RealityKitContent
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    private let primaryTextColor = Color(red: 0.09, green: 0.13, blue: 0.21)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.89, green: 0.94, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    workflowCard
                    trackingCard

                    if !appModel.previewSteps.isEmpty {
                        stepQueueCard
                    }

                    if let summary = appModel.uiState.summary {
                        completionCard(summary)
                    }
                }
                .padding(28)
            }
        }
        .foregroundStyle(primaryTextColor)
        .preferredColorScheme(.light)
        .task {
            appModel.prepareForLaunch()
        }
        .fileImporter(
            isPresented: Binding(
                get: { appModel.uiState.isShowingImporter },
                set: { appModel.uiState.isShowingImporter = $0 }
            ),
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if needsAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    await appModel.importCSV(from: url)
                case .failure(let error):
                    appModel.uiState.setError(error.localizedDescription)
                }
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { appModel.uiState.isShowingExporter },
                set: { appModel.uiState.isShowingExporter = $0 }
            ),
            document: appModel.uiState.logDocument,
            contentType: .plainText,
            defaultFilename: "genepath-session-log"
        ) { result in
            if case .failure(let error) = result {
                appModel.uiState.setError(error.localizedDescription)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spatial Pipetting Workflow")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Import a transfer CSV, generate an ordered step queue, and validate each aspiration and dispense target against the mixed reality plate overlay workflow.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Model3D(named: "Scene", bundle: realityKitContentBundle)
                    .frame(width: 180, height: 130)
            }

            HStack(spacing: 12) {
                Button("Import CSV") {
                    appModel.showImporter()
                }
                .buttonStyle(.borderedProminent)

                ToggleImmersiveSpaceButton()
                    .buttonStyle(.bordered)
            }

            if let fileName = appModel.uiState.importedFileName {
                Text("Loaded file: \(fileName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(cardBackground)
    }

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(appModel.progressLabel)
                    .font(.headline.weight(.semibold))

                Spacer(minLength: 0)

                stateBadge(appModel.uiState.appState.title, color: feedbackColor(for: appModel.uiState.validationFeedback.tone))
            }

            if case .loadingCSV = appModel.uiState.appState {
                ProgressView()
                    .progressViewStyle(.linear)
            } else if case .mapping = appModel.uiState.appState {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(appModel.currentInstructionTitle)
                    .font(.title3.weight(.semibold))

                Text(appModel.currentInstructionDetail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let step = appModel.currentStep {
                HStack(spacing: 14) {
                    detailItem("Source", value: step.source.well)
                    detailItem("Destination", value: step.destination.well)
                    detailItem("Volume", value: formattedVolume(step.volume))
                }
            }

            validationCard

            if let errorMessage = appModel.uiState.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            actionRow
        }
        .padding(24)
        .background(cardBackground)
    }

    private var validationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appModel.uiState.validationFeedback.title)
                .font(.headline)

            Text(appModel.uiState.validationFeedback.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(feedbackColor(for: appModel.uiState.validationFeedback.tone).opacity(0.12))
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        if appModel.currentStep == nil {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                switch appModel.uiState.validationResult {
                case .none:
                    if appModel.isPreviewTracking {
                        Button("Preview Correct") {
                            appModel.validateCurrentPhase()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Preview Wrong") {
                            appModel.validateCurrentPhase(simulatingMismatch: true)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(appModel.currentPhase.actionTitle) {
                            appModel.validateCurrentPhase()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case .some(.correct):
                    Button(appModel.currentPhase.confirmationTitle) {
                        appModel.confirmValidationAndAdvance()
                    }
                    .buttonStyle(.borderedProminent)
                case .some(.incorrect):
                    Button("Retry") {
                        appModel.retryValidation()
                    }
                    .buttonStyle(.bordered)

                    Button("Continue Anyway") {
                        appModel.continueAnyway()
                    }
                    .buttonStyle(.borderedProminent)
                case .some(.blocked):
                    Button("Retry Validation") {
                        appModel.retryValidation()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracking Manager")
                .font(.headline)

            Text(appModel.trackingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            detailItem("Reference Objects", value: appModel.bundledReferenceObjectsLabel)
            detailItem("Tracked Plates", value: appModel.trackedPlatesLabel)
            detailItem("Test Plate Model", value: appModel.testWellPlateModelName)

            Toggle("Show Test Well Plate Model", isOn: Binding(
                get: { appModel.isShowingTestWellPlate },
                set: { appModel.isShowingTestWellPlate = $0 }
            ))
            .disabled(!appModel.isTestWellPlateModelAvailable)

            Text(
                appModel.isTestWellPlateModelAvailable
                    ? "Displays the bundled USDZ on a simulated source-plate anchor so you can test alignment without depending on live object tracking."
                    : "Add a well plate `.usdz` file to `ReferenceObjects/` to enable the simulated tracked-plate test toggle."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if appModel.isPreviewTracking {
                Text("Preview mode keeps the mixed reality workflow testable until trained reference objects and live pipette tracking are bundled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var stepQueueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queued Steps")
                .font(.headline)

            ForEach(appModel.previewSteps) { step in
                HStack {
                    Text("Step \(step.sequenceNumber)")
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Text("\(step.source.well) -> \(step.destination.well)")
                        .foregroundStyle(.secondary)
                    Text(formattedVolume(step.volume))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func completionCard(_ summary: WorkflowSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Summary")
                .font(.headline)

            HStack(spacing: 14) {
                detailItem("Total", value: "\(summary.totalSteps)")
                detailItem("Aspiration Warnings", value: "\(summary.aspirationWarnings)")
                detailItem("Dispense Warnings", value: "\(summary.dispenseWarnings)")
            }

            Text("Completed at \(summary.completedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Export Log") {
                appModel.exportLog()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(cardBackground)
    }

    private func detailItem(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
    }

    private func stateBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func feedbackColor(for tone: ValidationTone) -> Color {
        switch tone {
        case .neutral:
            return Color(red: 0.14, green: 0.31, blue: 0.60)
        case .success:
            return Color(red: 0.10, green: 0.60, blue: 0.32)
        case .failure:
            return Color(red: 0.82, green: 0.24, blue: 0.18)
        case .warning:
            return Color(red: 0.84, green: 0.57, blue: 0.12)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.92))
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private func formattedVolume(_ volume: Double) -> String {
        if volume.rounded() == volume {
            return "\(Int(volume)) uL"
        }

        return String(format: "%.1f uL", volume)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
