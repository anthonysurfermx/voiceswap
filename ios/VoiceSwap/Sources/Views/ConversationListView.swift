import SwiftUI

private let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)

struct ConversationListView: View {
    @ObservedObject var store: ConversationStore
    let onSelect: (Conversation) -> Void
    let onNewChat: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAllConfirm = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("CONVERSATIONS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(1.5)
                    Spacer()
                    if !store.conversations.isEmpty {
                        Button {
                            showDeleteAllConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.trailing, 12)
                    }
                    Button {
                        onNewChat()
                        dismiss()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(emerald)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

                if store.conversations.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.15))
                        Text("No conversations yet")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.conversations) { conv in
                                conversationRow(conv)
                            }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Delete All Conversations?", isPresented: $showDeleteAllConfirm) {
            Button("Delete All", role: .destructive) {
                store.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all conversation history.")
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        Button {
            onSelect(conv)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // Icon
                RoundedRectangle(cornerRadius: 0)
                    .fill(emerald.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: conv.messages.contains(where: { $0.source == "voice" }) ? "waveform" : "text.bubble")
                            .font(.system(size: 14))
                            .foregroundColor(emerald.opacity(0.6))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(conv.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(formatDate(conv.updatedAt))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    if let last = conv.lastMessageText {
                        Text(last)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.04)), alignment: .bottom)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.delete(conversationId: conv.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: date)
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return fmt.string(from: date)
        }
    }
}
