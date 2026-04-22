// AddressSearchScreen — Full-screen address search overlay.
// Presented when the user taps the start or end field in ManualTripSheet.
// Streams completions from MKLocalSearchCompleter as the user types.

import SwiftUI
import MapKit

struct AddressSearchScreen: View {
    let placeholder: String
    let onSelect: (MKLocalSearchCompletion) -> Void

    @State private var searcher = AddressSearcher()
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: MTSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.mtTextSub)
                    TextField(placeholder, text: $searcher.query)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !searcher.query.isEmpty {
                        Button {
                            searcher.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.mtTextSub)
                        }
                    }
                }
                .padding(MTSpacing.sm + 2)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
                .padding(.horizontal, MTSpacing.md)
                .padding(.vertical, MTSpacing.sm)

                Divider()

                if searcher.query.isEmpty {
                    // Empty state — prompt
                    VStack(spacing: MTSpacing.md) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.mtBorder)
                        Text("Start typing an address or place name")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mtTextSub)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(MTSpacing.xl)
                } else if searcher.completions.isEmpty {
                    VStack(spacing: MTSpacing.md) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.mtBorder)
                        Text("No results for "\(searcher.query)"")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mtTextSub)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(MTSpacing.xl)
                } else {
                    List(searcher.completions, id: \.self) { completion in
                        Button {
                            onSelect(completion)
                            dismiss()
                        } label: {
                            CompletionRow(completion: completion)
                        }
                        .listRowBackground(Color.mtBackground)
                        .listRowSeparatorTint(Color.mtBorder)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.mtBackground)
            .navigationTitle(placeholder)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { fieldFocused = true }
    }
}

// MARK: - CompletionRow

private struct CompletionRow: View {
    let completion: MKLocalSearchCompletion

    var body: some View {
        HStack(spacing: MTSpacing.md) {
            Image(systemName: "mappin")
                .foregroundStyle(Color.mtGreen)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                highlightedText(completion.title, ranges: completion.titleHighlightRanges)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.mtTextPrimary)

                if !completion.subtitle.isEmpty {
                    highlightedText(completion.subtitle, ranges: completion.subtitleHighlightRanges)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Renders text with the matched ranges bolded — same pattern as Maps/Contacts.
    private func highlightedText(_ text: String, ranges: [NSValue]) -> Text {
        guard !ranges.isEmpty else { return Text(text) }
        let nsText = text as NSString
        var result = Text("")
        var cursor = 0

        for value in ranges {
            let range = value.rangeValue
            // Normal portion before match
            if range.location > cursor {
                let plain = nsText.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result = result + Text(plain)
            }
            // Highlighted (bold) match
            let matched = nsText.substring(with: range)
            result = result + Text(matched).bold()
            cursor = range.location + range.length
        }
        // Remaining tail
        if cursor < nsText.length {
            result = result + Text(nsText.substring(from: cursor))
        }
        return result
    }
}
