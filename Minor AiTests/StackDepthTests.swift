//
//  StackDepthTests.swift
//  Minor AiTests
//
//  3.0.0 crashed on every iPhone when a presentation opened: the editor's body was one ~26 KB
//  value (a chain of ~45 modifiers), SwiftUI walks such values level by level on the main
//  thread, and the iPhone's main thread has 1 MB of stack (the simulator's has 8 MB, so tests
//  never saw it). The big screens now keep their parts behind AnyView; this keeps them that way.
//  The full check is a UI run on a build whose main stack is cut to 640 KB (see the memory notes).
//

import SwiftUI
import Testing
@testable import Minor_Ai

struct StackDepthTests {
    // Bytes of each screen's `body` value.
    static let bodySizes: [String: Int] = [
        "AIConsentView": MemoryLayout<AIConsentView.Body>.size,
        "ActionCard": MemoryLayout<ActionCard.Body>.size,
        "AddMaterialSheet": MemoryLayout<AddMaterialSheet.Body>.size,
        "AllowanceBar": MemoryLayout<AllowanceBar.Body>.size,
        "AudioSourceView": MemoryLayout<AudioSourceView.Body>.size,
        "BackgroundEditor": MemoryLayout<BackgroundEditor.Body>.size,
        "BranchPulse": MemoryLayout<BranchPulse.Body>.size,
        "BrandSheet": MemoryLayout<BrandSheet.Body>.size,
        "BuildingCardView": MemoryLayout<BuildingCardView.Body>.size,
        "ChartView": MemoryLayout<ChartView.Body>.size,
        "ChatPickerView": MemoryLayout<ChatPickerView.Body>.size,
        "ChatView": MemoryLayout<ChatView.Body>.size,
        "CollabSheet": MemoryLayout<CollabSheet.Body>.size,
        "ColorChoices": MemoryLayout<ColorChoices.Body>.size,
        "ContentView": MemoryLayout<ContentView.Body>.size,
        "CreateMapView": MemoryLayout<CreateMapView.Body>.size,
        "DeckEditorView": MemoryLayout<DeckEditorView.Body>.size,
        "DeckExportSheet": MemoryLayout<DeckExportSheet.Body>.size,
        "DeckOrganizerView": MemoryLayout<DeckOrganizerView.Body>.size,
        "DeckPresenterView": MemoryLayout<DeckPresenterView.Body>.size,
        "DeckTemplateChooser": MemoryLayout<DeckTemplateChooser.Body>.size,
        "DeckThumbnail": MemoryLayout<DeckThumbnail.Body>.size,
        "DesignPromptSheet": MemoryLayout<DesignPromptSheet.Body>.size,
        "DiagramPanel": MemoryLayout<DiagramPanel.Body>.size,
        "DiagramStage": MemoryLayout<DiagramStage.Body>.size,
        "DiagramView": MemoryLayout<DiagramView.Body>.size,
        "DictationButton": MemoryLayout<DictationButton.Body>.size,
        "DueDateSheet": MemoryLayout<DueDateSheet.Body>.size,
        "DueLabel": MemoryLayout<DueLabel.Body>.size,
        "EditorSheetHeader": MemoryLayout<EditorSheetHeader.Body>.size,
        "ElementInspector": MemoryLayout<ElementInspector.Body>.size,
        "ExportSheetView": MemoryLayout<ExportSheetView.Body>.size,
        "ExternalSlideView": MemoryLayout<ExternalSlideView.Body>.size,
        "GeneratingView": MemoryLayout<GeneratingView.Body>.size,
        "GhostNode": MemoryLayout<GhostNode.Body>.size,
        "IconPicker": MemoryLayout<IconPicker.Body>.size,
        "IconPickerView": MemoryLayout<IconPickerView.Body>.size,
        "ImageViewer": MemoryLayout<ImageViewer.Body>.size,
        "InviteView": MemoryLayout<InviteView.Body>.size,
        "JoinInviteView": MemoryLayout<JoinInviteView.Body>.size,
        "LabelChip": MemoryLayout<LabelChip.Body>.size,
        "LaserDot": MemoryLayout<LaserDot.Body>.size,
        "LaunchReveal": MemoryLayout<LaunchReveal.Body>.size,
        "LaunchSplashView": MemoryLayout<LaunchSplashView.Body>.size,
        "LayoutPicker": MemoryLayout<LayoutPicker.Body>.size,
        "LibraryMapThumbnail": MemoryLayout<LibraryMapThumbnail.Body>.size,
        "LibraryView": MemoryLayout<LibraryView.Body>.size,
        "LookEditor": MemoryLayout<LookEditor.Body>.size,
        "MapCanvasView": MemoryLayout<MapCanvasView.Body>.size,
        "MapCardView": MemoryLayout<MapCardView.Body>.size,
        "MapDesignSheet": MemoryLayout<MapDesignSheet.Body>.size,
        "MapEditProposalPanel": MemoryLayout<MapEditProposalPanel.Body>.size,
        "MapEditorView": MemoryLayout<MapEditorView.Body>.size,
        "MapGroupsLayer": MemoryLayout<MapGroupsLayer.Body>.size,
        "MapLayoutCards": MemoryLayout<MapLayoutCards.Body>.size,
        "MapLinesPicker": MemoryLayout<MapLinesPicker.Body>.size,
        "MapLinkSheet": MemoryLayout<MapLinkSheet.Body>.size,
        "MapLinksLayer": MemoryLayout<MapLinksLayer.Body>.size,
        "MapMergeSheet": MemoryLayout<MapMergeSheet.Body>.size,
        "MapMiniPreview": MemoryLayout<MapMiniPreview.Body>.size,
        "MapOptionsSheet": MemoryLayout<MapOptionsSheet.Body>.size,
        "MapOutlineView": MemoryLayout<MapOutlineView.Body>.size,
        "MapResultCard": MemoryLayout<MapResultCard.Body>.size,
        "MapSnapshotView": MemoryLayout<MapSnapshotView.Body>.size,
        "MapThemePreview": MemoryLayout<MapThemePreview.Body>.size,
        "MapThumbnail": MemoryLayout<MapThumbnail.Body>.size,
        "MapViewPreview": MemoryLayout<MapViewPreview.Body>.size,
        "MapViewSheet": MemoryLayout<MapViewSheet.Body>.size,
        "MarkdownText": MemoryLayout<MarkdownText.Body>.size,
        "MentionSuggestions": MemoryLayout<MentionSuggestions.Body>.size,
        "MindNodeView": MemoryLayout<MindNodeView.Body>.size,
        "MinorFont": MemoryLayout<MinorFont.Body>.size,
        "MinorSurface": MemoryLayout<MinorSurface.Body>.size,
        "MoveTargetPicker": MemoryLayout<MoveTargetPicker.Body>.size,
        "NewDeckView": MemoryLayout<NewDeckView.Body>.size,
        "NextStepsSheet": MemoryLayout<NextStepsSheet.Body>.size,
        "NodeActionsSheet": MemoryLayout<NodeActionsSheet.Body>.size,
        "NodeCardView": MemoryLayout<NodeCardView.Body>.size,
        "NodeChatView": MemoryLayout<NodeChatView.Body>.size,
        "NodeLabelsLine": MemoryLayout<NodeLabelsLine.Body>.size,
        "NodeMarksSheet": MemoryLayout<NodeMarksSheet.Body>.size,
        "NodePicture": MemoryLayout<NodePicture.Body>.size,
        "NodeStyleSheet": MemoryLayout<NodeStyleSheet.Body>.size,
        "NotesSheet": MemoryLayout<NotesSheet.Body>.size,
        "OnboardingView": MemoryLayout<OnboardingView.Body>.size,
        "PDFSourceView": MemoryLayout<PDFSourceView.Body>.size,
        "PaywallView": MemoryLayout<PaywallView.Body>.size,
        "PlanComparisonView": MemoryLayout<PlanComparisonView.Body>.size,
        "PlusBadge": MemoryLayout<PlusBadge.Body>.size,
        "ProjectChatView": MemoryLayout<ProjectChatView.Body>.size,
        "ProjectMemorySheet": MemoryLayout<ProjectMemorySheet.Body>.size,
        "ProjectSlidesStart": MemoryLayout<ProjectSlidesStart.Body>.size,
        "ProjectView": MemoryLayout<ProjectView.Body>.size,
        "QRImage": MemoryLayout<QRImage.Body>.size,
        "Reveal": MemoryLayout<Reveal.Body>.size,
        "RewriteSheet": MemoryLayout<RewriteSheet.Body>.size,
        "SettingsView": MemoryLayout<SettingsView.Body>.size,
        "SharedItemSheet": MemoryLayout<SharedItemSheet.Body>.size,
        "SignInView": MemoryLayout<SignInView.Body>.size,
        "SlideBackdrop": MemoryLayout<SlideBackdrop.Body>.size,
        "SlideCanvas": MemoryLayout<SlideCanvas.Body>.size,
        "SlideDesignSheet": MemoryLayout<SlideDesignSheet.Body>.size,
        "SlideElementEditor": MemoryLayout<SlideElementEditor.Body>.size,
        "SlideElementView": MemoryLayout<SlideElementView.Body>.size,
        "SlideGallery": MemoryLayout<SlideGallery.Body>.size,
        "SlideInspector": MemoryLayout<SlideInspector.Body>.size,
        "SlideTextSheet": MemoryLayout<SlideTextSheet.Body>.size,
        "SlideView": MemoryLayout<SlideView.Body>.size,
        "SourceViewer": MemoryLayout<SourceViewer.Body>.size,
        "SourcesSheet": MemoryLayout<SourcesSheet.Body>.size,
        "StageStaysUsable": MemoryLayout<StageStaysUsable.Body>.size,
        "StructurePreview": MemoryLayout<StructurePreview.Body>.size,
        "StudyView": MemoryLayout<StudyView.Body>.size,
        "Sweep": MemoryLayout<Sweep.Body>.size,
        "TaskDetailSheet": MemoryLayout<TaskDetailSheet.Body>.size,
        "TemplateLibraryView": MemoryLayout<TemplateLibraryView.Body>.size,
        "TemplatesView": MemoryLayout<TemplatesView.Body>.size,
        "TextSourceView": MemoryLayout<TextSourceView.Body>.size,
        "ThemePicker": MemoryLayout<ThemePicker.Body>.size,
        "TodayView": MemoryLayout<TodayView.Body>.size,
        "TypingDots": MemoryLayout<TypingDots.Body>.size,
        "UpdateFromMapSheet": MemoryLayout<UpdateFromMapSheet.Body>.size,
        "UsageMeterView": MemoryLayout<UsageMeterView.Body>.size,
        "UsageView": MemoryLayout<UsageView.Body>.size,
        "VersionHistoryView": MemoryLayout<VersionHistoryView.Body>.size,
        "VoiceModeView": MemoryLayout<VoiceModeView.Body>.size,
        "WritingSlidesView": MemoryLayout<WritingSlidesView.Body>.size,
    ]

    @Test func editorsKeepTheirBodiesSmall() {
        #expect(MemoryLayout<DeckEditorView.Body>.size <= 4096, "The presentation editor's parts belong behind AnyView")
        #expect(MemoryLayout<MapEditorView.Body>.size <= 4096, "The map editor's parts belong behind AnyView")
    }

    // No screen grows back to the size that crashed: the largest left are sheets of about 19 KB.
    @Test func noScreenBodyIsHuge() {
        let huge = Self.bodySizes.filter { $0.value > 20 * 1024 }
        #expect(huge.isEmpty, "Split these screens: \(huge.keys.sorted())")
        if let out = ProcessInfo.processInfo.environment["STACK_OUT"] {
            let lines = Self.bodySizes.sorted { $0.value > $1.value }.map { "SIZE|\($0.key)|\($0.value)" }
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
    }
}
