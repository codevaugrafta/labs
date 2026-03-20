import SwiftUI

/// Lets **Settings** (and other auxiliary windows) adjust live playback volume.
private enum AdhanPlayerEnvironmentKey: EnvironmentKey {
    static let defaultValue: AdhanPlayer? = nil
}

extension EnvironmentValues {
    var adhanPlayer: AdhanPlayer? {
        get { self[AdhanPlayerEnvironmentKey.self] }
        set { self[AdhanPlayerEnvironmentKey.self] = newValue }
    }
}
