import SwiftUI

struct SessionsSheet: View {
    let store: SessionStore
    let onLoad: (SavedSession) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Sessions")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(16)

            Divider()

            if store.sessions.isEmpty {
                Text("No saved sessions yet.\nSave a session to pick up where you left off.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.sessions) { session in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.mediaName.isEmpty ? "Untitled" : session.mediaName)
                                .fontWeight(.medium)
                            HStack(spacing: 6) {
                                Text(Self.dateFormatter.string(from: session.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !session.segments.isEmpty {
                                    Text("· \(session.segments.count) segments")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !session.starred.isEmpty {
                                    Label("\(session.starred.count) starred", systemImage: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                        Spacer()
                        Button("Load") {
                            onLoad(session)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        Button(role: .destructive) {
                            store.delete(session)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 520, height: 400)
        .tint(.orange)
    }
}
