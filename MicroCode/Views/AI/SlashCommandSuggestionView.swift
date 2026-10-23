import SwiftUI

struct SlashCommandSuggestionView: View {
    @EnvironmentObject var appState: AppState
    let suggestions: [SlashCommandType]
    let selectedIndex: Int
    let onSelect: (SlashCommandType) -> Void
    
    private let rowHeight: CGFloat = 34
    private let maxVisibleRows: Int = 6
    
    @ViewBuilder
    private var rowsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, command in
                Button(action: {
                    onSelect(command)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: command.icon)
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 18, alignment: .center)
                            .foregroundColor(index == selectedIndex ? .accentColor : .secondary)
                        
                        Text("/\(command.rawValue)")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Text(command.description)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if command.requiresArgument {
                            Text("arg")
                                .font(.system(size: 9.5, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(4)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: rowHeight)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.14) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                if index < suggestions.count - 1 {
                    Divider().background(Color.primary.opacity(0.08))
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if suggestions.count <= maxVisibleRows {
                rowsList
            } else {
                ScrollView {
                    rowsList
                }
                .frame(height: CGFloat(maxVisibleRows) * rowHeight)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: appState.appTheme.panelBackground))
                .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
