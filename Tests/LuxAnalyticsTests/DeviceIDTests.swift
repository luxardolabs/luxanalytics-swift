import Foundation
import Testing

@testable import LuxAnalytics

extension GlobalStateTests {
    @Suite(.serialized)
    struct DeviceIDTests {
        @Test func resetReplacesTheID() async {
            let before = await AppAnalyticsContext.shared.currentDeviceID()
            await LuxAnalytics.resetDeviceID()
            let after = await AppAnalyticsContext.shared.currentDeviceID()
            #expect(after != before)
        }

        @Test func eachResetGivesADifferentID() async {
            // A reset re-derived from identifierForVendor would return the same ID twice.
            let first = await AppAnalyticsContext.shared.resetDeviceID()
            let second = await AppAnalyticsContext.shared.resetDeviceID()
            #expect(first != second)
        }

        @Test func theIDIsAHexSHA256() async {
            let id = await AppAnalyticsContext.shared.resetDeviceID()
            #expect(id.count == 64)
            #expect(id.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
    }
}
