import Foundation

extension Array where Element == SessionLog {
    /// Aggregates and filters session logs.
    /// Note: The input logs are assumed to be in chronological order.
    /// 1. Filters out logs with duration < minDuration (unless they are ongoing with `endTime == nil`).
    /// 2. Bridges gaps between filtered logs by extending the previous log's endTime.
    /// 3. Aligns the first log's startTime to the original array's first startTime.
    /// 4. Merges consecutive logs of the same phase.
    public func aggregated(minDuration: TimeInterval) -> [SessionLog] {
        // Assumes that the input array of SessionLog is sorted in chronological order.
        guard !self.isEmpty else { return [] }
        
        func logDuration(_ log: SessionLog) -> TimeInterval {
            let raw = (log.endTime ?? Date()).timeIntervalSince(log.startTime)
            return Swift.max(0.0, raw)
        }
        
        // Step 1: Filter out short sessions (< minDuration), keeping ongoing one (endTime == nil)
        var filtered: [SessionLog] = []
        for log in self {
            let duration = logDuration(log)
            if duration >= minDuration || log.endTime == nil {
                if !filtered.isEmpty {
                    // Bridge the gap between the previous log's end time and this log's start time
                    filtered[filtered.count - 1].endTime = log.startTime
                }
                filtered.append(log)
            }
        }
        
        // Step 2: Ensure the first log starts at the original tracking start time
        if let firstRawStart = self.first?.startTime, !filtered.isEmpty {
            let first = filtered[0]
            filtered[0] = SessionLog(id: first.id, startTime: firstRawStart, endTime: first.endTime, phase: first.phase)
        }
        
        // Step 3: Merge consecutive sessions of the same phase
        var result: [SessionLog] = []
        for log in filtered {
            if let last = result.last, last.phase == log.phase {
                result[result.count - 1].endTime = log.endTime
            } else {
                result.append(log)
            }
        }
        
        return result
    }
}
