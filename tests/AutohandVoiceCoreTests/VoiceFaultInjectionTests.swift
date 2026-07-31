import XCTest
@testable import AutohandVoiceCore

final class VoiceFaultInjectionTests: XCTestCase {
    func testNoOpInjectorNeverProducesFailure() async {
        let injector = NoVoiceFaultInjector()

        for point in VoiceFaultPoint.allCases {
            let failure = await injector.failure(at: point)
            XCTAssertNil(failure)
        }
    }

    func testDeterministicInjectorConsumesFailuresInOrder() async {
        let injector = DeterministicVoiceFaultInjector(
            schedule: [
                .recognition: [
                    .recognition(.timedOut),
                    .recognition(.failed),
                ],
            ]
        )

        let first = await injector.failure(at: .recognition)
        let second = await injector.failure(at: .recognition)
        let exhausted = await injector.failure(at: .recognition)
        let unrelated = await injector.failure(at: .insertion)

        XCTAssertEqual(first, .recognition(.timedOut))
        XCTAssertEqual(second, .recognition(.failed))
        XCTAssertNil(exhausted)
        XCTAssertNil(unrelated)
    }

    func testInjectorCanBeResetWithoutGlobalOrEnvironmentState() async {
        let injector = DeterministicVoiceFaultInjector(
            schedule: [.insertion: [.insertion(.rejected)]]
        )
        let initial = await injector.failure(at: .insertion)
        XCTAssertNotNil(initial)

        await injector.reset(
            schedule: [.captureStart: [.capture(.startFailed)]]
        )

        let oldSchedule = await injector.failure(at: .insertion)
        let newSchedule = await injector.failure(at: .captureStart)
        XCTAssertNil(oldSchedule)
        XCTAssertEqual(newSchedule, .capture(.startFailed))
    }
}
