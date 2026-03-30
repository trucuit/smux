import SwiftUI
import SwiftTerm

struct SearchOverlay: View {
    @Binding var isPresented: Bool
    let terminalView: TerminalView?

    @State private var searchText: String = ""

    var body: some View {
        if isPresented {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        findNext()
                    }

                if !searchText.isEmpty {
                    Button(action: findPrevious) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Find previous")

                    Button(action: findNext) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Find next")
                }

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Close search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .padding(8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func findNext() {
        guard let tv = terminalView, !searchText.isEmpty else { return }
        _ = tv.findNext(searchText)
    }

    private func findPrevious() {
        guard let tv = terminalView, !searchText.isEmpty else { return }
        _ = tv.findPrevious(searchText)
    }

    private func dismiss() {
        terminalView?.clearSearch()
        searchText = ""
        isPresented = false
    }
}
