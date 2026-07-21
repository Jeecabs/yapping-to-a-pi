import Testing
@testable import YappingToAPiHelper

@Suite("StopSignal")
struct StopSignalTests {
    @Test("work cannot begin after stop")
    func preventsLateWork() async {
        let signal = StopSignal()
        signal.stop()
        var ran = false

        let value: Int? = signal.performUnlessStopped {
            ran = true
            return 42
        }

        #expect(value == nil)
        #expect(ran == false)
        #expect(await signal.wait() == true)
    }

    @Test("work that wins the gate runs once")
    func permitsCurrentWork() {
        let signal = StopSignal()
        var runs = 0

        let value: Int? = signal.performUnlessStopped {
            runs += 1
            return 42
        }

        #expect(value == 42)
        #expect(runs == 1)
    }
}
