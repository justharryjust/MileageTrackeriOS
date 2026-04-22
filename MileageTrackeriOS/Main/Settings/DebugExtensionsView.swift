// DebugExtensionsView — renders DebugPotentialExtensions.md in-app.

import SwiftUI

struct DebugExtensionsView: View {
    @State private var markdown: String = ""

    var body: some View {
        ScrollView {
            if markdown.isEmpty {
                ContentUnavailableView(
                    "File not found",
                    systemImage: "doc.questionmark",
                    description: Text("DebugPotentialExtensions.md could not be loaded.")
                )
                .padding(.top, 60)
            } else {
                Text(attributedMarkdown)
                    .padding(MTSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Potential Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private var attributedMarkdown: AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init()
        )) ?? AttributedString(markdown)
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "DebugPotentialExtensions", withExtension: "md") else {
            markdown = ""
            return
        }
        markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
