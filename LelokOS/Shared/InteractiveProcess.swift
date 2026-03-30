import Foundation

/// Manages an interactive subprocess with a pseudo-terminal (PTY).
/// Used for long-running processes like Copilot CLI, Python REPL, etc.
@MainActor
class InteractiveProcess: ObservableObject {
    @Published var isRunning = false
    
    private var process: Process?
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    
    var onOutput: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?
    
    /// Launch an interactive process with a PTY
    func launch(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws {
        // Open a PTY pair
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw ProcessError.ptyFailed
        }
        masterFD = master
        slaveFD = slave
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        
        // Set up environment
        var env = environment ?? ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "120"
        env["LINES"] = "40"
        proc.environment = env
        
        if let dir = currentDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        
        // Connect the slave PTY to the process's stdin/stdout/stderr
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle
        
        // Watch for output on the master side
        let source = DispatchSource.makeReadSource(
            fileDescriptor: master,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            let bytesRead = read(master, buffer, 4096)
            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                if let str = String(data: data, encoding: .utf8) {
                    // Strip ANSI escape codes for clean display
                    let cleaned = self?.stripANSI(str) ?? str
                    Task { @MainActor in
                        self?.onOutput?(cleaned)
                    }
                }
            }
        }
        source.setCancelHandler {
            close(master)
        }
        source.resume()
        readSource = source
        
        // Handle process exit
        proc.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.isRunning = false
                self?.onExit?(process.terminationStatus)
                self?.cleanup()
            }
        }
        
        try proc.run()
        close(slave) // Close slave in parent — child owns it
        slaveFD = -1
        process = proc
        isRunning = true
    }
    
    /// Send input to the running process
    func send(_ text: String) {
        guard masterFD >= 0 else { return }
        if let data = text.data(using: .utf8) {
            data.withUnsafeBytes { bytes in
                _ = write(masterFD, bytes.baseAddress!, bytes.count)
            }
        }
    }
    
    /// Send input followed by a newline
    func sendLine(_ text: String) {
        send(text + "\n")
    }
    
    /// Send Ctrl+C (SIGINT)
    func sendInterrupt() {
        send("\u{03}")
    }
    
    /// Send Ctrl+D (EOF)
    func sendEOF() {
        send("\u{04}")
    }
    
    /// Terminate the process
    func terminate() {
        process?.terminate()
        cleanup()
    }
    
    private func cleanup() {
        readSource?.cancel()
        readSource = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
        process = nil
    }
    
    /// Strip ANSI escape sequences for clean terminal display
    private func stripANSI(_ str: String) -> String {
        // Matches CSI sequences like \e[31m, \e[0m, \e[?25h, etc.
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
            switch self {
            case .ptyFailed: return "Failed to open pseudo-terminal"
            }
        }
    }
}
