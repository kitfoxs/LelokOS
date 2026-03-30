import Foundation

/// Manages an interactive subprocess with a pseudo-terminal (PTY).
/// Thread-safe — NOT MainActor. Dispatches UI callbacks to main.
class InteractiveProcess: @unchecked Sendable {
    private var process: Process?
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let lock = NSLock()
    
    private(set) var isRunning = false
    
    var onOutput: (@Sendable @MainActor (String) -> Void)?
    var onExit: (@Sendable @MainActor (Int32) -> Void)?
    
    func launch(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws {
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw ProcessError.ptyFailed
        }
        
        lock.lock()
        masterFD = master
        slaveFD = slave
        lock.unlock()
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        
        var env = environment ?? ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "120"
        env["LINES"] = "40"
        proc.environment = env
        
        if let dir = currentDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle
        
        let outputCallback = self.onOutput
        let source = DispatchSource.makeReadSource(
            fileDescriptor: master,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            let bytesRead = read(master, buffer, 4096)
            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                if let str = String(data: data, encoding: .utf8) {
                    let cleaned = InteractiveProcess.stripANSI(str)
                    if let cb = outputCallback {
                        Task { @MainActor in cb(cleaned) }
                    }
                }
            }
        }
        source.setCancelHandler { close(master) }
        source.resume()
        
        lock.lock()
        readSource = source
        lock.unlock()
        
        let exitCallback = self.onExit
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            self?.lock.lock()
            self?.isRunning = false
            self?.lock.unlock()
            if let cb = exitCallback {
                Task { @MainActor in cb(status) }
            }
        }
        
        try proc.run()
        close(slave)
        
        lock.lock()
        slaveFD = -1
        process = proc
        isRunning = true
        lock.unlock()
    }
    
    func send(_ text: String) {
        lock.lock()
        let fd = masterFD
        lock.unlock()
        guard fd >= 0, let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress!, $0.count) }
    }
    
    func sendLine(_ text: String) { send(text + "\n") }
    func sendInterrupt() { send("\u{03}") }
    func sendEOF() { send("\u{04}") }
    
    func terminate() {
        lock.lock()
        process?.terminate()
        readSource?.cancel()
        readSource = nil
        if masterFD >= 0 { close(masterFD); masterFD = -1 }
        if slaveFD >= 0 { close(slaveFD); slaveFD = -1 }
        process = nil
        isRunning = false
        lock.unlock()
    }
    
    nonisolated static func stripANSI(_ str: String) -> String {
        let pattern = "\\x1b\\[[0-9;?]*[A-Za-z]|\\x1b\\][^\\x07]*\\x07|\\x1b\\([A-Za-z]|\\r"
        return (try? NSRegularExpression(pattern: pattern))
            .map { $0.stringByReplacingMatches(in: str, range: NSRange(str.startIndex..., in: str), withTemplate: "") }
            ?? str
    }
    
    deinit {
        readSource?.cancel()
        if masterFD >= 0 { close(masterFD) }
        if slaveFD >= 0 { close(slaveFD) }
        process?.terminate()
    }
    
    enum ProcessError: Error, LocalizedError {
        case ptyFailed
        var errorDescription: String? {
            switch self { case .ptyFailed: return "Failed to open pseudo-terminal" }
        }
    }
}
