import XCTest
@testable import OpenWisprLib

final class PracticeTurnGateTests: XCTestCase {
    func testSilenceAndClickDoNotStartTurn() {
        var gate = PracticeTurnGate()
        for _ in 0..<200 { XCTAssertEqual(gate.ingest(db: -65, duration: 0.1, playback: false), .none) }
        XCTAssertEqual(gate.ingest(db: -18, duration: 0.05, playback: false), .none)
        XCTAssertEqual(gate.ingest(db: -65, duration: 0.1, playback: false), .none)
        XCTAssertFalse(gate.speaking)
    }
    func testShortPauseKeepsQuestionTogether() {
        var gate = PracticeTurnGate()
        XCTAssertEqual(gate.ingest(db: -24, duration: 0.1, playback: false), .none)
        XCTAssertEqual(gate.ingest(db: -24, duration: 0.1, playback: false), .began)
        for _ in 0..<9 { XCTAssertEqual(gate.ingest(db: -65, duration: 0.1, playback: false), .none) }
        XCTAssertEqual(gate.ingest(db: -24, duration: 0.1, playback: false), .none)
        for _ in 0..<12 { XCTAssertEqual(gate.ingest(db: -65, duration: 0.1, playback: false), .none) }
        XCTAssertEqual(gate.ingest(db: -65, duration: 0.1, playback: false), .ended)
        XCTAssertFalse(gate.speaking)
    }
    func testPlaybackResidualDoesNotInterruptButSustainedVoiceDoes() {
        var gate = PracticeTurnGate()
        for _ in 0..<20 { XCTAssertEqual(gate.ingest(db: -60, duration: 0.1, playback: true), .none) }
        for _ in 0..<3 { XCTAssertEqual(gate.ingest(db: -20, duration: 0.1, playback: true), .none) }
        XCTAssertEqual(gate.ingest(db: -20, duration: 0.1, playback: true), .began)
    }
    func testMaximumTurnAndReset() {
        var gate = PracticeTurnGate()
        _ = gate.ingest(db: -20, duration: 0.2, playback: false)
        var finished = false
        for _ in 0..<305 { if gate.ingest(db: -20, duration: 0.2, playback: false) == .ended { finished = true; break } }
        XCTAssertTrue(finished)
        gate.reset()
        XCTAssertFalse(gate.speaking)
        XCTAssertEqual(gate.ingest(db: -65, duration: 0.2, playback: false), .none)
    }
    func testQuietSpeechWithSyllableGaps() {
        var gate = PracticeTurnGate()
        var began = false
        for _ in 0..<6 {
            for _ in 0..<4 { if gate.ingest(db: -52, duration: 0.02, playback: false) == .began { began = true } }
            for _ in 0..<3 { _ = gate.ingest(db: -80, duration: 0.02, playback: false) }
        }
        XCTAssertTrue(began)
    }
    func testInvalidMeterValuesCannotCreateSpeech() {
        var gate = PracticeTurnGate()
        for level in [Double.nan, Double.infinity, -Double.infinity] { XCTAssertEqual(gate.ingest(db: level, duration: 0.1, playback: false), .none) }
        XCTAssertEqual(gate.ingest(db: -20, duration: -1, playback: false), .none)
        XCTAssertFalse(gate.speaking)
    }
}
