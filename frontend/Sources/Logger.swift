import Foundation

private let logFile = "/tmp/umi-dev.log"
private let logQueue = DispatchQueue(label: "app.umi.logger", qos: .utility)
private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

private func writeToFile(_ line: String) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    logQueue.async {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

func log(_ message: String) {
    let ts = dateFormatter.string(from: Date())
    let line = "[\(ts)] [app] \(message)"
    print(line)
    fflush(stdout)
    writeToFile(line)
}

func logSync(_ message: String) { log(message) }

func logError(_ message: String, error: Error? = nil) {
    let ts = dateFormatter.string(from: Date())
    let desc = error.map { ": \($0.localizedDescription)" } ?? ""
    let line = "[\(ts)] [error] \(message)\(desc)"
    print(line)
    fflush(stdout)
    writeToFile(line)
}

func logPerf(_ message: String, duration: Double? = nil, cpu: Bool = false) {
    var parts = [message]
    if let d = duration { parts.append(String(format: "(%.1fms)", d * 1000)) }
    log("[perf] " + parts.joined(separator: " "))
}

class PerfTimer {
    private let name: String
    private let start = CFAbsoluteTimeGetCurrent()
    init(_ name: String, logCPU: Bool = false) { self.name = name }
    func stop() { logPerf(name, duration: CFAbsoluteTimeGetCurrent() - start) }
    func checkpoint(_ label: String) { logPerf("\(name) → \(label)", duration: CFAbsoluteTimeGetCurrent() - start) }
}

func measurePerf<T>(_ name: String, logCPU: Bool = false, _ block: () -> T) -> T {
    let t = PerfTimer(name)
    let r = block()
    t.stop()
    return r
}

func measurePerfAsync<T>(_ name: String, logCPU: Bool = false, _ block: () async -> T) async -> T {
    let t = PerfTimer(name)
    let r = await block()
    t.stop()
    return r
}
