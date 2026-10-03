//
//  Templates.swift
//  Minor Ai
//
//  Ready structures for common maps, made on the phone without AI: a project plan, SWOT,
//  lecture notes and more. Branches come with icons, guiding ideas and tasks where they fit.
//

import SwiftUI

struct MapTemplate: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let palette: MapPalette
    let branches: [Branch]

    struct Branch {
        let icon: String
        let title: String
        var ideas: [String] = []
        var tasks = false     // ideas become tasks with checkboxes
        var collapsed = false
    }

    func makeMap() -> MindMap {
        let children = branches.map { branch in
            var node = MindNode(title: branch.title, children: branch.ideas.map { MindNode(title: $0, isTask: branch.tasks) })
            node.icon = branch.icon
            node.isCollapsed = branch.collapsed && !branch.ideas.isEmpty
            return node
        }
        var root = MindNode(title: title, children: children)
        root.icon = icon
        var map = MindMap(root: root, source: MapSource(kind: .topic, label: L("Template: \(title)")))
        map.palette = palette == .vivid ? nil : palette.rawValue
        return map
    }

    static var all: [MapTemplate] {
        [
            MapTemplate(id: "project", icon: "🚀", title: L("Project Plan"), summary: L("Goal, scope, milestones, team and risks"), palette: .vivid, branches: [
                Branch(icon: "🎯", title: L("Goal"), ideas: [L("What does success look like?"), L("Deadline")]),
                Branch(icon: "📦", title: L("Scope"), ideas: [L("In scope"), L("Out of scope")]),
                Branch(icon: "🏁", title: L("Milestones"), ideas: [L("Kickoff"), L("First version"), L("Launch")], tasks: true),
                Branch(icon: "👥", title: L("Team"), ideas: [L("Owner"), L("Who helps")]),
                Branch(icon: "⚠️", title: L("Risks"), ideas: [L("What could go wrong?"), L("Plan B")]),
                Branch(icon: "💰", title: L("Budget")),
            ]),
            MapTemplate(id: "swot", icon: "🧭", title: L("SWOT Analysis"), summary: L("Strengths, weaknesses, opportunities, threats"), palette: .forest, branches: [
                Branch(icon: "💪", title: L("Strengths"), ideas: [L("What do we do best?"), L("What do others see as our strengths?")]),
                Branch(icon: "🩹", title: L("Weaknesses"), ideas: [L("What could we improve?"), L("Where do we lack resources?")]),
                Branch(icon: "🌱", title: L("Opportunities"), ideas: [L("Trends we can use"), L("Gaps in the market")]),
                Branch(icon: "🌩️", title: L("Threats"), ideas: [L("What are competitors doing?"), L("What could change against us?")]),
            ]),
            MapTemplate(id: "lecture", icon: "🎓", title: L("Lecture Notes"), summary: L("Key ideas, definitions, examples, questions"), palette: .ocean, branches: [
                Branch(icon: "💡", title: L("Key Ideas")),
                Branch(icon: "📖", title: L("Definitions")),
                Branch(icon: "🧪", title: L("Examples")),
                Branch(icon: "❓", title: L("Questions"), ideas: [L("What is still unclear?")]),
                Branch(icon: "📝", title: L("Summary")),
                Branch(icon: "✅", title: L("To Review"), ideas: [L("Reread the notes"), L("Practice problems")], tasks: true),
            ]),
            MapTemplate(id: "book", icon: "📚", title: L("Book Summary"), summary: L("Main idea, chapters, quotes and takeaways"), palette: .sunset, branches: [
                Branch(icon: "✍️", title: L("About the Author")),
                Branch(icon: "💡", title: L("Main Idea")),
                Branch(icon: "📑", title: L("Key Chapters")),
                Branch(icon: "💬", title: L("Quotes")),
                Branch(icon: "🧠", title: L("Takeaways")),
                Branch(icon: "🛠️", title: L("How I'll Use It"), ideas: [L("First thing to try")], tasks: true),
            ]),
            MapTemplate(id: "week", icon: "🗓️", title: L("Weekly Plan"), summary: L("Goals, work, personal, health and a review"), palette: .vivid, branches: [
                Branch(icon: "🎯", title: L("Goals This Week"), ideas: [L("Most important result")], tasks: true),
                Branch(icon: "💼", title: L("Work"), ideas: [L("Task 1"), L("Task 2")], tasks: true),
                Branch(icon: "🏠", title: L("Personal"), ideas: [L("Errand")], tasks: true),
                Branch(icon: "🏃", title: L("Health"), ideas: [L("Workout"), L("Sleep 8 hours")], tasks: true),
                Branch(icon: "📚", title: L("Learning")),
                Branch(icon: "🔁", title: L("Sunday Review"), ideas: [L("What went well?"), L("What to change?")]),
            ]),
            MapTemplate(id: "okr", icon: "🎯", title: L("Goal Setting"), summary: L("Objective, key results, initiatives"), palette: .neon, branches: [
                Branch(icon: "🏆", title: L("Objective"), ideas: [L("Why it matters")]),
                Branch(icon: "📈", title: L("Key Results"), ideas: [L("Result 1"), L("Result 2"), L("Result 3")], tasks: true),
                Branch(icon: "🛠️", title: L("Initiatives")),
                Branch(icon: "🚧", title: L("Obstacles")),
                Branch(icon: "📅", title: L("Weekly Check-in")),
            ]),
            MapTemplate(id: "decision", icon: "⚖️", title: L("Pros and Cons"), summary: L("Compare two options and decide"), palette: .ocean, branches: [
                Branch(icon: "🅰️", title: L("Option A"), ideas: [L("Pros"), L("Cons")]),
                Branch(icon: "🅱️", title: L("Option B"), ideas: [L("Pros"), L("Cons")]),
                Branch(icon: "📏", title: L("What Matters Most")),
                Branch(icon: "✅", title: L("Decision")),
            ]),
            MapTemplate(id: "meeting", icon: "📝", title: L("Meeting Notes"), summary: L("Agenda, decisions and action items"), palette: .vivid, branches: [
                Branch(icon: "📋", title: L("Agenda")),
                Branch(icon: "💬", title: L("Discussion")),
                Branch(icon: "✅", title: L("Decisions")),
                Branch(icon: "📌", title: L("Action Items"), ideas: [L("Who does what by when")], tasks: true),
                Branch(icon: "📅", title: L("Next Meeting")),
            ]),
            MapTemplate(id: "trip", icon: "✈️", title: L("Trip Plan"), summary: L("Route, stay, places, packing and budget"), palette: .sunset, branches: [
                Branch(icon: "📍", title: L("Destination")),
                Branch(icon: "🚆", title: L("Getting There"), ideas: [L("Book tickets")], tasks: true),
                Branch(icon: "🏨", title: L("Stay"), ideas: [L("Book a place")], tasks: true),
                Branch(icon: "🗺️", title: L("Places to See")),
                Branch(icon: "🎒", title: L("Packing List"), ideas: [L("Passport"), L("Chargers"), L("Medicine")], tasks: true),
                Branch(icon: "💳", title: L("Budget")),
            ]),
            MapTemplate(id: "brainstorm", icon: "💡", title: L("Brainstorm"), summary: L("Problem, wild ideas, best ideas, next steps"), palette: .neon, branches: [
                Branch(icon: "❓", title: L("Problem")),
                Branch(icon: "🌪️", title: L("Wild Ideas")),
                Branch(icon: "⭐", title: L("Best Ideas")),
                Branch(icon: "👣", title: L("Next Steps"), ideas: [L("First step")], tasks: true),
            ]),
        ]
    }
}

struct TemplatesView: View {
    let theme: AppTheme
    var onPick: (MapTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(MapTemplate.all) { template in
                        Button {
                            Haptics.selection()
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onPick(template) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: -4) {
                                    Text(template.icon).font(.system(size: 28))
                                    Spacer()
                                    HStack(spacing: -5) {
                                        ForEach(Array(template.palette.colors.prefix(4).enumerated()), id: \.offset) { _, color in
                                            Circle().fill(color.color).frame(width: 12, height: 12)
                                                .overlay(Circle().stroke(theme.chatRectangle, lineWidth: 1.5))
                                        }
                                    }
                                }
                                Text(template.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MinorColor.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text(template.summary)
                                    .font(.system(size: 13))
                                    .foregroundColor(MinorColor.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(template.title). \(template.summary)")
                    }
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(MinorColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
