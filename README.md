# GenePathOverlay

GenePathOverlay is a visionOS mixed-reality application for guided 96-well plate transfer workflows on Apple Vision Pro.

The app imports a transfer protocol from CSV, maps each transfer into source and destination well coordinates, tracks the physical plates in space, estimates the pipette tip position from hand-based calibration, and validates each workflow step before progression.

## What The App Does

- Imports CSV transfer protocols with `source`, `destination`, and `volume` columns
- Converts well identifiers into spatial coordinates for source and destination plates
- Guides the operator through aspiration and dispense steps in mixed reality
- Confirms pipette volume before a transfer begins
- Tracks pipette interaction through hand calibration and press detection
- Validates whether the pipette is over the expected well
- Inserts tip-change checkpoints between transfer steps
- Produces a workflow summary and session log at the end of a run

## Operator Workflow

1. Start a session
2. Import a transfer CSV
3. Review the parsed workflow
4. Complete the operator checklist
5. Calibrate the pipette input
6. Open the mixed-reality workflow
7. Confirm the target volume
8. Validate aspiration from the source well
9. Validate dispense into the destination well
10. Change the pipette tip
11. Repeat until all steps are complete
12. Export the session log if needed

## Architecture Overview

The app is organized around a few core runtime components:

- `AppModel`
  - Main coordinator for session state, navigation, validation, workflow progression, and logging
- `SequenceEngine`
  - Owns the ordered step queue and the workflow state machine
- `TrackingManager`
  - Manages ARKit object tracking, hand tracking, pipette calibration, and live detection state
- `ValidationEngine`
  - Checks whether the detected pipette pose matches the expected target well
- `CSVParser`
  - Loads protocol rows into `Step` models
- `CoordinateMapper`
  - Maps wells like `A1` and `H12` into normalized positions on the plate layout
- `OverlayRenderer`
  - Draws plate outlines, highlighted wells, and pipette markers in the immersive scene
- `UIStateManager`
  - Converts runtime state into user-facing workflow, warning, and completion states

## Project Structure

```text
GenepathOverlay/
├── App/            # App entry point and shared app model
├── Input/          # CSV import and parsing
├── Logic/          # Workflow sequencing, validation, UI state
├── Models/         # Shared workflow and tracking models
├── Pipette/        # Pipette calibration, press detection, tip estimation
├── Spatial/        # Plate tracking, coordinate mapping, immersive overlays
├── Views/          # SwiftUI screens and components
└── Assets.xcassets # App artwork and calibration images
```

## Key Screens

- `HomeScreenView`
  - Entry point for starting a workflow session
- `LoadProtocolView`
  - CSV import flow
- `ProtocolReviewView`
  - Review parsed steps before execution
- `OperatorChecklistView`
  - Pre-run checklist
- `PipetteCalibrationSetupView`
  - Hand and pipette calibration flow
- `ActiveWorkflowView`
  - Main workflow panel for live step execution
- `ImmersiveView`
  - Mixed-reality overlay scene
- `StepQueueWindowView`
  - Secondary view for the transfer queue
- `WorkflowSettingsView`
  - Runtime configuration and calibration tools

## Tracking And Validation Model

GenePathOverlay uses two tracking paths that feed the workflow:

- Plate tracking
  - Detects source and destination plates as spatial anchors using bundled reference objects
- Pipette tracking
  - Uses hand tracking, calibration samples, and grip-based tip estimation to infer tool position and button presses

Validation succeeds only when:

- tracking is in a usable state
- a detected pipette pose is available
- pose confidence exceeds the configured minimum
- the detected plate matches the expected plate
- the detected tip position is within well tolerance

If validation fails, the user can retry or continue with a warning recorded in the run summary.

## Current Scope

The current implementation is focused on:

- standard 96-well plate workflows
- CSV-driven transfer protocols
- source-to-destination plate transfers
- mixed-reality well guidance
- pipette volume confirmation
- aspiration and dispense validation
- tip-change confirmation

## Current Limitations

- Plate geometry is currently fixed for the supported 96-well layout
- Protocol import is intentionally simple and expects source, destination, and volume rows
- Validation quality depends on object tracking stability, hand visibility, and calibration quality
- Manual override paths exist for real-world usability, so the app is not fully closed-loop

## Notes

- The project includes preview and fallback paths for development when full live tracking is unavailable
- External pipette button events can also be recorded through app commands for workflow testing
