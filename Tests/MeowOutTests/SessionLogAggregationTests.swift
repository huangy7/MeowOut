import XCTest
@testable import MeowOut

final class SessionLogAggregationTests: XCTestCase {
    func testEmptyLogs() {
        let logs: [SessionLog] = []
        XCTAssertEqual(logs.aggregated(minDuration: 60), [])
    }
    
    func testOngoingLogKeptRegardlessOfDuration() {
        let now = Date()
        let logs = [
            SessionLog(startTime: now, endTime: nil, phase: .working)
        ]
        let result = logs.aggregated(minDuration: 60)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].phase, .working)
        XCTAssertNil(result[0].endTime)
    }
    
    func testFilterAndBridgeGaps() {
        let base = Date()
        let logs = [
            SessionLog(startTime: base, endTime: base.addingTimeInterval(120), phase: .working),
            SessionLog(startTime: base.addingTimeInterval(120), endTime: base.addingTimeInterval(150), phase: .alerting), // 30s (should be filtered)
            SessionLog(startTime: base.addingTimeInterval(150), endTime: base.addingTimeInterval(300), phase: .resting)  // 150s
        ]
        
        let result = logs.aggregated(minDuration: 60)
        XCTAssertEqual(result.count, 2)
        
        // Gap bridged: working should end at resting start time (base + 150)
        XCTAssertEqual(result[0].phase, .working)
        XCTAssertEqual(result[0].startTime, base)
        XCTAssertEqual(result[0].endTime, base.addingTimeInterval(150))
        
        XCTAssertEqual(result[1].phase, .resting)
        XCTAssertEqual(result[1].startTime, base.addingTimeInterval(150))
        XCTAssertEqual(result[1].endTime, base.addingTimeInterval(300))
    }
    
    func testFirstLogAlignment() {
        let base = Date()
        let logs = [
            SessionLog(startTime: base, endTime: base.addingTimeInterval(30), phase: .alerting), // 30s (filtered)
            SessionLog(startTime: base.addingTimeInterval(30), endTime: base.addingTimeInterval(200), phase: .working)
        ]
        
        let result = logs.aggregated(minDuration: 60)
        XCTAssertEqual(result.count, 1)
        
        // First log aligned to base
        XCTAssertEqual(result[0].phase, .working)
        XCTAssertEqual(result[0].startTime, base)
        XCTAssertEqual(result[0].endTime, base.addingTimeInterval(200))
    }
    
    func testMergeConsecutiveAfterFiltering() {
        let base = Date()
        let logs = [
            SessionLog(startTime: base, endTime: base.addingTimeInterval(120), phase: .working),
            SessionLog(startTime: base.addingTimeInterval(120), endTime: base.addingTimeInterval(150), phase: .alerting), // 30s (filtered)
            SessionLog(startTime: base.addingTimeInterval(150), endTime: base.addingTimeInterval(300), phase: .working)
        ]
        
        let result = logs.aggregated(minDuration: 60)
        XCTAssertEqual(result.count, 1)
        
        XCTAssertEqual(result[0].phase, .working)
        XCTAssertEqual(result[0].startTime, base)
        XCTAssertEqual(result[0].endTime, base.addingTimeInterval(300))
    }
    
    func testFirstLogPreservesIdAfterAlignment() {
        let base = Date()
        let firstLogId = UUID()
        let logs = [
            SessionLog(startTime: base, endTime: base.addingTimeInterval(30), phase: .alerting), // 30s (filtered)
            SessionLog(id: firstLogId, startTime: base.addingTimeInterval(30), endTime: base.addingTimeInterval(200), phase: .working)
        ]
        
        let result = logs.aggregated(minDuration: 60)
        XCTAssertEqual(result.count, 1)
        
        XCTAssertEqual(result[0].id, firstLogId)
        XCTAssertEqual(result[0].phase, .working)
        XCTAssertEqual(result[0].startTime, base)
    }
}
