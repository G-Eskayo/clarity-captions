import Foundation

public enum InterruptionEvent: Sendable, Equatable {
    case began(reason: String)
    case ended
}
