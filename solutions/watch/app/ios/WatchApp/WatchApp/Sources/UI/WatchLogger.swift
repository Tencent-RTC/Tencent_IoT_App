import OSLog

enum WatchLogger {
    static let ui = Logger(subsystem: "com.tencent.iot.watchapp", category: "ui")
    static let im = Logger(subsystem: "com.tencent.iot.watchapp", category: "im")
}
