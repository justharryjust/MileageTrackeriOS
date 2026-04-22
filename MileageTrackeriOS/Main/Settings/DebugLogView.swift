// DebugLogView — Scrollable view of persisted log entries with export and clear actions

import SwiftUI
import CoreLocation

struct DebugLogView: View {
    @State private var logger = TripLogger.shared
    @State private var isExporting = false
    @State private var filterCategory: LogCategory? = nil
    @State private var searchText = ""

    private var filteredEntries: [LogEntry] {
        logger.entries
            .filter { filterCategory == nil || $0.category == filterCategory }
            .filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText) ||
                      $0.category.rawValue.localizedCaseInsensitiveContains(searchText) }
            .reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MTSpacing.sm) {
                    CategoryChip(label: "All", color: Color.mtGreen, isSelected: filterCategory == nil) {
                        filterCategory = nil
                    }
                    ForEach([LogCategory.trip, .location, .motion, .system, .ui, .error], id: \.self) { cat in
                        CategoryChip(
                            label: cat.emoji + " " + cat.rawValue,
                            color: categoryColor(cat),
                            isSelected: filterCategory == cat
                        ) {
                            filterCategory = filterCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, MTSpacing.md)
                .padding(.vertical, MTSpacing.sm)
            }
            .background(Color.mtSurface)

            Divider()

            if filteredEntries.isEmpty {
                Spacer()
                Text("No log entries").foregroundStyle(Color.mtTextSub)
                Spacer()
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.category.emoji + " " + entry.category.rawValue)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(categoryColor(entry.category))
                                Spacer()
                                Text(TripLogger.timestampFormatter.string(from: entry.date))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color.mtTextSub.opacity(0.6))
                            }
                            Text(entry.message)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(entry.category == .error ? Color.mtRecording : Color.mtTextPrimary)
                        }
                        .listRowBackground(Color.mtBackground)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search logs")
            }
        }
        .navigationTitle("Debug Log (\(logger.entries.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isExporting = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                    logger.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.mtRecording)
                }
            }
        }
        .sheet(isPresented: $isExporting) {
            ShareSheet(items: [logger.exportURL])
        }
    }

    private func categoryColor(_ cat: LogCategory) -> Color {
        switch cat {
        case .trip:     return .mtGreen
        case .location: return .blue
        case .motion:   return .orange
        case .system:   return Color.mtTextSub
        case .ui:       return .purple
        case .error:    return .mtRecording
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, MTSpacing.sm)
                .padding(.vertical, 4)
                .background(isSelected ? color : color.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
