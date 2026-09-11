import CoreGraphics

/// A click held while we distinguish a middle-button press from a drag.
/// Stores values, not a physical CGEvent with stale HID routing information.
struct MiddleClick {
    typealias EventSink = (CGEvent, CGEventTapProxy?) -> Void

    nonisolated static let eventMarker: Int64 = 0x464C4F574D4F44 // "FLOWMOD"

    let flags: CGEventFlags
    let clickState: Int64
    let timestamp: CGEventTimestamp
    let eventNumber: Int64

    nonisolated init(down: CGEvent) {
        flags = down.flags
        clickState = max(1, down.getIntegerValueField(.mouseEventClickState))
        timestamp = down.timestamp
        eventNumber = down.getIntegerValueField(.mouseEventNumber)
    }

    /// After an interruption, only finish a press for which we still observe
    /// the matching release. Zero-number events have no reliable identity, so
    /// allow only a short click in that case. The caller also checks movement.
    nonisolated func matchesReleaseAfterInterruption(_ release: CGEvent) -> Bool {
        guard release.type == .otherMouseUp,
              release.getIntegerValueField(.mouseEventButtonNumber) == 2,
              release.timestamp >= timestamp else { return false }
        let releaseNumber = release.getIntegerValueField(.mouseEventNumber)
        if eventNumber != 0 || releaseNumber != 0 {
            return eventNumber == releaseNumber
        }
        return release.timestamp - timestamp <= 1_000_000_000
    }

    /// Deliver a complete pair synchronously, after the physical release is
    /// known. Never re-enter HID processing or leave a release on another queue.
    /// Both events target the current pointer position: it may have moved within
    /// the gesture dead zone since the down was swallowed.
    @discardableResult
    nonisolated func post(release: CGEvent, proxy: CGEventTapProxy?, sink: EventSink) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        source.localEventsSuppressionInterval = 0
        let allEvents: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source.setLocalEventsFilterDuringSuppressionState(allEvents, state: .eventSuppressionStateSuppressionInterval)
        source.setLocalEventsFilterDuringSuppressionState(allEvents, state: .eventSuppressionStateRemoteMouseDrag)

        // Prepare both before posting either, so allocation failure cannot leave
        // the receiving app with a pressed button and no matching release.
        guard let down = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown,
                                 mouseCursorPosition: release.location, mouseButton: .center),
              let up = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp,
                               mouseCursorPosition: release.location, mouseButton: .center) else { return false }

        for event in [down, up] {
            event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        }
        down.flags = flags
        up.flags = release.flags
        // Preserve the actual pressed interval without delaying delivery.
        down.timestamp = timestamp
        up.timestamp = max(timestamp, release.timestamp)

        sink(down, proxy)
        sink(up, proxy)
        return true
    }

    nonisolated static func postEvent(_ event: CGEvent, proxy: CGEventTapProxy?) {
        if let proxy {
            // Quartz inserts these downstream of our tap, in callback order.
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }
}
