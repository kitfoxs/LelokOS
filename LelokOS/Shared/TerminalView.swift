import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var shell: ShellManager
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shell.outputLines) { line in
                            TerminalLine(line: line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onChange(of: shell.outputLines.count) {
                    if let last = shell.outputLines.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input line
            HStack(spacing: 0) {
                Text(shell.prompt)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.green)
                
                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .onSubmit {
                        executeCommand()
                    }
                    .onKeyPress(.upArrow) {
                        inputText = shell.historyBack() ?? inputText
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        inputText = shell.historyForward() ?? inputText
                        return .handled
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .onAppear {
            inputFocused = true
            shell.printWelcome()
        }
    }
    
    private func executeCommand() {
        let command = inputText.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        
        shell.addOutput(.input(shell.prompt + command))
        inputText = ""
        
        Task {
            await shell.execute(command)
        }
    }
}

struct TerminalLine: View {
    let line: OutputLine
    
    var body: some View {
        Text(line.text)
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(line.color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TerminalView()
        .environmentObject(ShellManager())
        .frame(width: 800, height: 500)
}
