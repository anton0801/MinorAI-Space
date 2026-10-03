//
//  IconPickerView.swift
//  Minor Ai
//
//  Pick an emoji for an idea: a grid of common ones, or any emoji typed from the keyboard.
//

import SwiftUI

struct IconPickerView: View {
    let current: String?
    var onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    static let icons = [
        "💡", "🎯", "🚀", "⭐️", "🔥", "✅", "❗️", "❓", "📌", "🧠",
        "📚", "✏️", "🧪", "📊", "📈", "💰", "🛒", "💼", "🏆", "⏰",
        "📅", "🗺️", "🌍", "🏠", "❤️", "😊", "🤝", "👥", "🎨", "🎵",
        "🎬", "📷", "💻", "📱", "⚙️", "🔒", "🔑", "🧩", "🌱", "🍎",
        "☕️", "✈️", "🚗", "⚡️", "🌟", "⚠️", "🔍", "💬",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(MinorColor.fillThumb).frame(width: 36, height: 5).padding(.top, 8)
            ZStack {
                Text("Icon").font(.system(size: 18, weight: .bold))
                HStack {
                    if current != nil {
                        Button("Remove") { onPick(nil) }
                            .foregroundColor(MinorColor.dangerText)
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(MinorColor.closeFill))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(Self.icons, id: \.self) { icon in
                        Button { onPick(icon) } label: {
                            Text(icon)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 12).fill(icon == current ? MinorColor.row : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    TextField("", text: $typed)
                        .placeholder(when: typed.isEmpty) { Text("Or type any emoji").foregroundColor(MinorColor.textTertiary) }
                        .font(.system(size: 17))
                        .onChange(of: typed) { value in
                            if let icon = value.last.map(String.init).flatMap(MindNode.cleanIcon) { onPick(icon) }
                        }
                        .accessibilityLabel("Emoji")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.row))
                .padding(16)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
