import SwiftUI

struct SlashCommandSuggestionView: View {
    @EnvironmentObject var appState: AppState
    let suggestions: [SlashCommandType]
    let selectedIndex: Int
    let onSelect: (SlashCommandType) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, command in
                        Button(action: {
                            onSelect(command)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: command.icon)
                                    .font(.system(size: 14))
                                    .frame(width: 20, alignment: .center)
                                    .foregroundColor(index == selectedIndex ? .primary : .secondary)
                                
                                Text("/\(command.rawValue)")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text(command.description)
                                    .font(.system(.callout))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if command.requiresArgument {
                                    Text("arg")
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color(white: 0.2).opacity(0.3))
                                        .cornerRadius(4)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(index == selectedIndex ? Color(white: 0.5).opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if index < suggestions.count - 1 {
                            Divider().background(Color(white: 0.5).opacity(0.2))
                        }
                    }
                }
            }
            .frame(maxHeight: 300) // approximately 8 items
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: appState.appTheme.panelBackground))
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.5).opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
