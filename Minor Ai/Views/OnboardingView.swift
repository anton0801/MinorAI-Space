//
//  OnboardingView.swift
//  Minor Ai
//
//  Three first-launch pages, then Sign in. Illustrations are built from real map components.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    @State private var showSignIn = false

    private let theme = AppTheme(sphere: UserDefaults.standard.integer(forKey: "SelectedSphere"))

    private var pages: [(title: String, text: String)] {
        [
            (L("Think in Maps"), L("Type a topic and Minor builds a mind map in seconds.")),
            (L("Start From Anything"), L("Drop a PDF, paste a link or a YouTube video, or just talk.")),
            (L("Go Deeper With AI"), L("Tap any idea and Minor expands it into new branches.")),
        ]
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack {
                Spacer()
                Rectangle().fill(theme.blur).frame(height: 120).blur(radius: 50).opacity(0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if showSignIn {
                SignInView(onFinish: onFinish)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Skip") { withAnimation { showSignIn = true } }
                            .font(.system(size: 17))
                            .foregroundColor(MinorColor.textSecondary)
                            .frame(height: 44)
                    }
                    .padding(.horizontal, 20)

                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { index in
                            VStack(spacing: 0) {
                                illustration(index)
                                    .frame(height: 320)
                                Text(pages[index].title)
                                    .font(.system(size: 22, weight: .bold))
                                    .padding(.top, 32)
                                Text(pages[index].text)
                                    .font(.system(size: 15))
                                    .foregroundColor(MinorColor.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 8)
                                    .padding(.horizontal, 40)
                                Spacer()
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    HStack(spacing: 10) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == page ? Color.white : theme.chatStroke)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.bottom, 24)
                    .accessibilityHidden(true)

                    Button {
                        if page < pages.count - 1 {
                            withAnimation(.minorSheet) { page += 1 }
                        } else {
                            withAnimation { showSignIn = true }
                        }
                    } label: {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(MinorColor.sendFill))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .foregroundColor(MinorColor.textPrimary)
    }

    @ViewBuilder
    private func illustration(_ index: Int) -> some View {
        switch index {
        case 0:
            let map = MindMap(root: MindNode(title: L("Mind Map"), children: [
                MindNode(title: L("Audience")), MindNode(title: L("New idea")), MindNode(title: L("Pricing")),
            ]))
            let layout = MapLayout(map: map)
            MapSnapshotView(layout: layout, theme: theme, watermark: false)
                .frame(width: layout.size.width, height: layout.size.height)
        case 1:
            ZStack {
                sourceCard("doc.text", "Document", "PDF, TXT or RTF").rotationEffect(.degrees(-12)).offset(x: -60, y: -10)
                sourceCard("play.rectangle", "YouTube", "Video transcript").rotationEffect(.degrees(10)).offset(x: 60, y: -20)
                sourceCard("mic", "Voice", "Talk it through").offset(y: 30)
            }
        default:
            let node = LayoutNode(id: UUID(), title: L("Pricing"), level: 1, frame: CGRect(x: 0, y: 0, width: 110, height: 41),
                                  color: .lilac, hiddenCount: 0, isAIAdded: true, parentID: nil)
            HStack(spacing: 40) {
                MindNodeView(node: node, theme: theme, isGenerating: true)
                VStack(alignment: .leading, spacing: 12) {
                    GhostNode(width: 96)
                    GhostNode(width: 72)
                    GhostNode(width: 110)
                }
            }
        }
    }

    private func sourceCard(_ icon: String, _ title: LocalizedStringKey, _ caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 20))
            Text(title).font(.system(size: 15, weight: .medium))
            Text(caption).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
        }
        .frame(width: 140, alignment: .leading)
        .padding(14)
        .minorSurface(theme)
    }
}
