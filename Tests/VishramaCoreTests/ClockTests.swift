import Foundation
import Testing
@testable import VishramaCore

@Test func systemClockTracksRealTime() {
    let clock = SystemClock()
    let before = Date()
    let now = clock.now
    let after = Date()
    #expect(now >= before && now <= after)
}
