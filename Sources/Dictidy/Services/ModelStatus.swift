import Foundation

/// Download and readiness state for the on-device Whisper speech model.
/// Used by its settings and onboarding controls.
enum ModelStatus: Equatable {
    case missing
    case downloading(Double)      // 0…1
    case ready(URL)
    case failed(String)
}
