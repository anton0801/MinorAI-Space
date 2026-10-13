//
//  UpdateFromMapSheet.swift
//  Minor Ai
//
//  New slides written from the map as it is now, before anything changes: the slides now and the
//  slides after. Saving them as a separate presentation is the safe default; replacing is possible
//  while the presentation hasn't changed meanwhile, and Undo brings the old slides back.
//

import SwiftUI

struct UpdateFromMapSheet: View {
    let deck: Deck
    let preview: DeckEditorView.UpdatePreview
    let theme: AppTheme
    var onCopy: () -> Void
    var onReplace: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var unchanged: Bool { deck.slides == preview.base }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("New slides are ready from the map as it is now. Choose what to do with them.")
                        .minorFont(15, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 12) {
                        column(L("Now"), deck.slides.map(\.plainText.first).map { $0 ?? "" })
                        column(L("After the update"), preview.slides.map(\.plainText.first).map { $0 ?? "" })
                    }
                    Text("Design, brand and transitions stay as they are. Changes you made by hand to these slides are replaced if you choose Replace.")
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        Button {
                            dismiss()
                            onCopy()
                        } label: {
                            Text("Save as a Separate Presentation")
                                .minorFont(16, .semibold, maxScale: 1.3)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Capsule().fill(MinorColor.sendFill))
                        }
                        .buttonStyle(PressScale())
                        Button {
                            dismiss()
                            onReplace()
                        } label: {
                            Text("Replace These Slides")
                                .minorFont(15, .medium, maxScale: 1.3)
                                .foregroundColor(unchanged ? .white : MinorColor.textTertiary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                        }
                        .buttonStyle(PressScale())
                        .disabled(!unchanged)
                        if !unchanged {
                            Text("The presentation changed while the update was written, so it can only be saved as a copy.")
                                .minorFont(12, style: .caption1, maxScale: 1.4)
                                .foregroundColor(MinorColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .background(MinorColor.sheet.ignoresSafeArea())
            .navigationTitle(Text("Update from Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundColor(.white) }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func column(_ title: String, _ titles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .minorFont(12, .semibold, style: .caption1, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
            ForEach(Array(titles.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1)").minorFont(12, .semibold, style: .caption1, maxScale: 1.3).monospacedDigit().foregroundColor(MinorColor.textTertiary)
                    Text(text.isEmpty ? L("Untitled slide") : text).minorFont(14, maxScale: 1.3).lineLimit(3)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.fillRow))
    }
}
