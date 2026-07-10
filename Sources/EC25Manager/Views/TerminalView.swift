import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var modem: Modem
    @State private var command = ""
    private let quick = ["ATI", "AT+CSQ", "AT+QNWINFO", "AT+QTEMP", "AT+CGDCONT?", "AT+QENG=\"servingcell\""]

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(modem.terminalLines.joined(separator: "\n"))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Palette.goodC)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).id("end")
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.30)))
                .onChange(of: modem.terminalLines.count) { proxy.scrollTo("end", anchor: .bottom) }
            }

            HStack(spacing: 8) {
                TextField("AT+QNWINFO", text: $command)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                    .onSubmit(submit)
                Button("发送", action: submit).buttonStyle(.borderedProminent)
            }

            FlowChips(items: quick) { command = $0; submit() }
        }
        .padding(16)
    }

    private func submit() {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        command = ""; modem.runTerminalCommand(c)
    }
}

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { c in
                        Button { onTap(c) } label: {
                            Text(c).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }
}
