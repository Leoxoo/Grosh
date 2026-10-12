#if os(iOS)
import UIKit
#endif

extension SoundsAndHaptics.Device {
    /// The device the app is running on. An iPad app running on a Mac counts as an iPad.
    @MainActor static var current: Self {
        #if os(macOS)
        return .mac
        #else
        return UIDevice.current.userInterfaceIdiom == .phone ? .iPhone : .iPad
        #endif
    }
}
