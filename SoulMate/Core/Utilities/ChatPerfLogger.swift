import Foundation
import QuartzCore

enum ChatPerfLogger {
    private static var points: [String: TimeInterval] = [:]
    private static let lock = NSLock()

    static func mark(_ key: String) {
        lock.lock()
        points[key] = CACurrentMediaTime()
        lock.unlock()

        #if DEBUG
        if AppConfiguration.Performance.firstPaintLogEnabled {
            emit(event: "mark", fields: [
                "key": key
            ])
        }
        #endif
    }

    static func logDelta(from startKey: String, to endKey: String, context: String? = nil) {
        lock.lock()
        let start = points[startKey]
        let end = points[endKey]
        lock.unlock()

        guard let start, let end else { return }
        let ms = Int((end - start) * 1000)
        #if DEBUG
        if AppConfiguration.Performance.firstPaintLogEnabled {
            var fields: [String: String] = [
                "from": startKey,
                "to": endKey,
                "ms": String(ms)
            ]
            if let context {
                fields["context"] = context
            }
            emit(event: "delta", fields: fields)
        }
        #endif
    }

    #if DEBUG
    private static func emit(event: String, fields: [String: String]) {
        let sortedPairs = fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            let escapedValue = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(key)\":\"\(escapedValue)\""
        }
        print("PERF_CHAT {\"event\":\"\(event)\",\(sortedPairs.joined(separator: ","))}")
    }
    #endif
}
