import SwiftUI

struct MemoSlashCommandMenu: View {
    let commands: [MemoSlashCommand]
    let selectedCommand: MemoSlashCommand?
    let onSelect: (MemoSlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands, id: \.self) { command in
                Button {
                    onSelect(command)
                } label: {
                    HStack {
                        Text("/")
                            .foregroundStyle(.secondary)
                        Text(command.rawValue)
                            .fontWeight(selectedCommand == command ? .semibold : .regular)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selectedCommand == command ? Color.secondary.opacity(0.14) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 170)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8, y: 3)
    }
}
