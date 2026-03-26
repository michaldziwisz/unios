import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum VoiceOverAnnouncer {
    static func post(_ announcement: String) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        #endif
    }
}

