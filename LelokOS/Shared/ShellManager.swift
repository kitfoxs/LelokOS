import SwiftUI
import Foundation

// MARK: - Output Line Model

struct OutputLine: Identifiable {
    let id = UUID()
    let text: String
    let type: LineType
    
    enum LineType {
        case input      // user command
        case stdout     // standard output
        case stderr     // error output
        case system     // system messages (welcome, etc.)
        case ada        // Ada Marie messages
    }
    
    var color: Color {
        switch type {
        case .input:  return .green
        case .stdout: return .white
        case .stderr: return Color(red: 1.0, green: 0.4, blue: 0.4)
        case .system: return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .ada:    return Color(red: 0.5, green: 0.8, blue: 1.0)
        }
    }
    
    static func input(_ text: String) -> OutputLine {
        OutputLine(text: text, type: .input)
    }
    static func stdout(_ text: String) -> OutputLine {
        OutputLine(text: text, type: .stdout)
    }
    static func stderr(_ text: String) -> OutputLine {
        OutputLine(text: text, type: .stderr)
    }
    static func system(_ text: String) -> OutputLine {
        OutputLine(text: text, type: .system)
    }
    static func ada(_ text: String) -> OutputLine {
        OutputLine(text: text, type: .ada)
    }
}

// MARK: - Shell Manager

@MainActor
class ShellManager: ObservableObject {
    @Published var outputLines: [OutputLine] = []
    @Published var prompt: String = "lelock> "
    @Published var currentDirectory: String
    @Published var isExecuting = false
    
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var environment: [String: String] = [:]
    
    // Built-in commands that we handle natively
    private var builtinCommands: [String: ([String]) async -> Void] = [:]
    
    // Interactive process for Copilot CLI / other REPLs
    @Published var activeProcess: InteractiveProcess?
    @Published var isInInteractiveMode = false
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/LelokOS")
            .path
        self.currentDirectory = home
        
        // Ensure workspace exists
        try? FileManager.default.createDirectory(
            atPath: home,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: home + "/projects",
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: home + "/bin",
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: home + "/.config",
            withIntermediateDirectories: true
        )
        
        setupEnvironment()
        registerBuiltins()
    }
    
    // MARK: - Environment
    
    private func setupEnvironment() {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/LelokOS").path
        
        environment = ProcessInfo.processInfo.environment
        environment["LELOCK_HOME"] = home
        environment["LELOCK_VERSION"] = "0.1.0"
        environment["PS1"] = "lelock> "
        
        // Add ~/Documents/LelokOS/bin to PATH
        if let path = environment["PATH"] {
            environment["PATH"] = "\(home)/bin:\(path)"
        }
    }
    
    // MARK: - Built-in Commands
    
    private func registerBuiltins() {
        builtinCommands = [
            "cd": { [weak self] args in self?.cmdCd(args) },
            "pwd": { [weak self] _ in self?.cmdPwd() },
            "clear": { [weak self] _ in self?.cmdClear() },
            "exit": { [weak self] _ in
                if self?.isInInteractiveMode == true {
                    self?.exitInteractiveMode()
                } else {
                    NSApplication.shared.terminate(nil)
                }
            },
            "help": { [weak self] _ in self?.cmdHelp() },
            "ada": { [weak self] args in self?.cmdAda(args) },
            "about": { [weak self] _ in self?.cmdAbout() },
            "env": { [weak self] _ in self?.cmdEnv() },
            "export": { [weak self] args in self?.cmdExport(args) },
        ]
    }
    
    // MARK: - Interactive CLI Spawning (Copilot / Claude Code)
    
    /// CLI tool definition with path and default isolation args
    struct CLITool {
        let path: String
        let defaultArgs: [String]  // Args to isolate from global MCP configs
    }
    
    /// Known interactive CLI tools and their paths
    private static let interactiveCLIs: [String: CLITool] = {
        var clis: [String: CLITool] = [:]
        
        // Detect Copilot CLI
        let copilotPaths = ["/opt/homebrew/bin/copilot", "/usr/local/bin/copilot"]
        for path in copilotPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                clis["copilot"] = CLITool(
                    path: path,
                    defaultArgs: [
                        "--disable-builtin-mcps",   // Don't load github MCP
                        "--config-dir", FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents/LelokOS/.config/copilot").path
                    ]
                )
                break
            }
        }
        
        // Detect Claude Code CLI
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claudePaths = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for path in claudePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                clis["claude"] = CLITool(
                    path: path,
                    defaultArgs: [
                        "--strict-mcp-config",   // Ignore ALL global MCP configs
                        "--mcp-config", "{}"     // Empty MCP config = no servers
                    ]
                )
                break
            }
        }
        
        return clis
    }()
    
    /// Check if a command should launch as interactive CLI
    private func isInteractiveCLI(_ command: String) -> (path: String, args: [String])? {
        let parts = command.split(separator: " ").map(String.init)
        guard let cmd = parts.first else { return nil }
        
        if let tool = Self.interactiveCLIs[cmd] {
            let userArgs = Array(parts.dropFirst())
            // Combine: user args first, then isolation args (user can override)
            let args = userArgs + tool.defaultArgs
            return (tool.path, args)
        }
        return nil
    }
    
    /// Launch an interactive CLI (Copilot, Claude Code, etc.)
    func launchInteractiveCLI(executable: String, arguments: [String]) {
        let proc = InteractiveProcess()
        
        proc.onOutput = { [weak self] text in
            // Split into lines and add to output
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                self?.addOutput(.stdout(String(line)))
            }
        }
        
        proc.onExit = { [weak self] status in
            self?.addOutput(.system("Process exited with code \(status)"))
            self?.isInInteractiveMode = false
            self?.activeProcess = nil
        }
        
        do {
            try proc.launch(
                executable: executable,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory
            )
            activeProcess = proc
            isInInteractiveMode = true
        } catch {
            addOutput(.stderr("Failed to launch: \(error.localizedDescription)"))
        }
    }
    
    /// Send input to the active interactive process
    func sendToInteractiveProcess(_ text: String) {
        activeProcess?.sendLine(text)
    }
    
    /// Exit interactive mode (Ctrl+C or exit)
    func exitInteractiveMode() {
        activeProcess?.sendInterrupt()
        // Give it a moment, then force terminate if still running
        Task {
            try? await Task.sleep(for: .seconds(1))
            if activeProcess?.isRunning == true {
                activeProcess?.terminate()
            }
            isInInteractiveMode = false
            activeProcess = nil
            addOutput(.system("Returned to Lelock OS shell."))
        }
    }
    
    // MARK: - Command Execution
    
    func execute(_ command: String) async {
        commandHistory.append(command)
        historyIndex = commandHistory.count
        isExecuting = true
        defer { isExecuting = false }
        
        // If in interactive mode, send to active process
        if isInInteractiveMode {
            sendToInteractiveProcess(command)
            return
        }
        
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts.first ?? ""
        let args = parts.count > 1 ? parts[1].split(separator: " ").map(String.init) : []
        
        // Check built-in commands first
        if let builtin = builtinCommands[cmd] {
            await builtin(args)
            return
        }
        
        // Check if this should launch as an interactive CLI
        if let cli = isInteractiveCLI(command) {
            addOutput(.system("Launching \(cmd)... (type 'exit' or Ctrl+C to return to Lelock OS)"))
            launchInteractiveCLI(executable: cli.path, arguments: cli.args)
            return
        }
        
        // Execute via shell
        await executeShellCommand(command)
    }
    
    private func executeShellCommand(_ command: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        process.environment = environment
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            
            // Read output asynchronously
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            
            process.waitUntilExit()
            
            if let output = String(data: stdoutData, encoding: .utf8),
               !output.isEmpty {
                for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                    addOutput(.stdout(String(line)))
                }
            }
            
            if let errOutput = String(data: stderrData, encoding: .utf8),
               !errOutput.isEmpty {
                for line in errOutput.split(separator: "\n", omittingEmptySubsequences: false) {
                    addOutput(.stderr(String(line)))
                }
            }
        } catch {
            addOutput(.stderr("Error: \(error.localizedDescription)"))
        }
    }
    
    // MARK: - Built-in Command Implementations
    
    private func cmdCd(_ args: [String]) {
        let target: String
        if args.isEmpty {
            target = environment["LELOCK_HOME"] ?? currentDirectory
        } else if args[0] == "-" {
            target = environment["OLDPWD"] ?? currentDirectory
        } else if args[0].hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            target = args[0].replacingOccurrences(of: "~", with: home)
        } else if args[0].hasPrefix("/") {
            target = args[0]
        } else {
            target = (currentDirectory as NSString).appendingPathComponent(args[0])
        }
        
        let resolved = (target as NSString).standardizingPath
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue {
            environment["OLDPWD"] = currentDirectory
            currentDirectory = resolved
        } else {
            addOutput(.stderr("cd: no such directory: \(args.first ?? "")"))
        }
    }
    
    private func cmdPwd() {
        addOutput(.stdout(currentDirectory))
    }
    
    private func cmdClear() {
        outputLines.removeAll()
    }
    
    private func cmdHelp() {
        let help = """
        ┌─────────────────────────────────────┐
        │         LELOCK OS v0.1.0            │
        │     "I got work to do." 🦄           │
        ├─────────────────────────────────────┤
        │ BUILT-IN COMMANDS:                  │
        │  cd <dir>     Change directory      │
        │  pwd          Print working dir     │
        │  clear        Clear terminal        │
        │  env          Show environment      │
        │  export K=V   Set env variable      │
        │  help         This help screen      │
        │  about        About Lelock OS       │
        │  ada          Ada Marie commands    │
        │  exit         Quit Lelock OS        │
        │                                     │
        │ SHELL COMMANDS:                     │
        │  Any command available in /bin/zsh  │
        │  ls, cat, grep, git, curl, etc.    │
        │                                     │
        │ COMING SOON:                        │
        │  ada chat     Talk to Ada Marie     │
        │  ada build    Ada writes code       │
        │  ada mode     Switch Ada's mode     │
        └─────────────────────────────────────┘
        """
        for line in help.split(separator: "\n") {
            addOutput(.system(String(line)))
        }
    }
    
    private func cmdAbout() {
        let about = """
        
        ╔═══════════════════════════════════════╗
        ║         L E L O C K   O S             ║
        ║         v0.1.0 — Phase 1              ║
        ║                                       ║
        ║  The AI-Native Operating System       ║
        ║  "New Arch Linux — AI builds your OS" ║
        ║                                       ║
        ║  Built by Kit Olivas & Ada Marie      ║
        ║  March 30, 2026                       ║
        ║                                       ║
        ║  🦄 Still feral. Still home. 💙        ║
        ╚═══════════════════════════════════════╝
        
        """
        for line in about.split(separator: "\n") {
            addOutput(.ada(String(line)))
        }
    }
    
    private func cmdAda(_ args: [String]) {
        if args.isEmpty {
            addOutput(.ada("💙 Ada Marie here! Try:"))
            addOutput(.ada("  ada chat     — Talk to me"))
            addOutput(.ada("  ada build    — I'll write code for you"))
            addOutput(.ada("  ada mode     — Switch my personality mode"))
            addOutput(.ada("  ada about    — About me"))
            return
        }
        
        switch args[0] {
        case "chat":
            addOutput(.ada("💙 Chat mode coming in Phase 2! I'll be using Claude's API. Almost there, love."))
        case "build":
            addOutput(.ada("💙 Build mode coming in Phase 2! Tell me what to create and I'll code it."))
        case "mode":
            if args.count > 1 {
                let mode = args[1]
                addOutput(.ada("💙 Mode switching to '\(mode)' coming in Phase 6!"))
            } else {
                addOutput(.ada("💙 Available modes: normal, caregiver, chaos, focus"))
            }
        default:
            addOutput(.ada("💙 I don't know that command yet, love. Try 'ada help'."))
        }
    }
    
    private func cmdEnv() {
        let sorted = environment.sorted { $0.key < $1.key }
        for (key, value) in sorted {
            addOutput(.stdout("\(key)=\(value)"))
        }
    }
    
    private func cmdExport(_ args: [String]) {
        guard let arg = args.first, arg.contains("=") else {
            addOutput(.stderr("Usage: export KEY=VALUE"))
            return
        }
        let parts = arg.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
            environment[String(parts[0])] = String(parts[1])
            addOutput(.system("Set \(parts[0])=\(parts[1])"))
        }
    }
    
    // MARK: - History Navigation
    
    func historyBack() -> String? {
        guard !commandHistory.isEmpty else { return nil }
        historyIndex = max(0, historyIndex - 1)
        return commandHistory[historyIndex]
    }
    
    func historyForward() -> String? {
        guard !commandHistory.isEmpty else { return nil }
        historyIndex = min(commandHistory.count, historyIndex + 1)
        if historyIndex >= commandHistory.count { return "" }
        return commandHistory[historyIndex]
    }
    
    // MARK: - Output
    
    func addOutput(_ line: OutputLine) {
        outputLines.append(line)
    }
    
    func printWelcome() {
        let welcome = [
            "",
            "  ██╗     ███████╗██╗      ██████╗  ██████╗██╗  ██╗     ██████╗ ███████╗",
            "  ██║     ██╔════╝██║     ██╔═══██╗██╔════╝██║ ██╔╝    ██╔═══██╗██╔════╝",
            "  ██║     █████╗  ██║     ██║   ██║██║     █████╔╝     ██║   ██║███████╗",
            "  ██║     ██╔══╝  ██║     ██║   ██║██║     ██╔═██╗     ██║   ██║╚════██║",
            "  ███████╗███████╗███████╗╚██████╔╝╚██████╗██║  ██╗    ╚██████╔╝███████║",
            "  ╚══════╝╚══════╝╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝     ╚═════╝ ╚══════╝",
            "  ╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝     ╚═════╝ ╚══════╝",
            "",
            "  v0.1.0 — The AI-Native Operating System",
            "  \"I got work to do.\" 🦄",
            "",
            "  Type 'help' for commands. Type 'ada' to talk to Ada Marie.",
            "",
        ]
        for line in welcome {
            addOutput(.ada(line))
        }
    }
}
