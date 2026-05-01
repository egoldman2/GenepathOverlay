//
//  ImmersiveView.swift
//  GenepathOverlay
//
//  Created by Ethan on 17/3/2026.
//

import RealityKit
import RealityKitContent
import Foundation
import SwiftUI

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
            }

            appModel.overlayRenderer.installIfNeeded(
                content: &content,
                mapper: appModel.coordinateMapper,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
            appModel.overlayRenderer.update(
                trackingSnapshot: appModel.trackingSnapshot,
                mapper: appModel.coordinateMapper,
                highlightedCoordinates: appModel.overlayHighlightedCoordinates,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
        } update: { content in
            appModel.overlayRenderer.installIfNeeded(
                content: &content,
                mapper: appModel.coordinateMapper,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
            appModel.overlayRenderer.update(
                trackingSnapshot: appModel.trackingSnapshot,
                mapper: appModel.coordinateMapper,
                highlightedCoordinates: appModel.overlayHighlightedCoordinates,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
        }
        .task {
            appModel.prepareForLaunch()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
