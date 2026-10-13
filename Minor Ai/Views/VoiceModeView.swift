//
//  VoiceModeView.swift
//  Minor Ai
//
//  Talking with the assistant: Minor listens, sends what you said when you pause, reads the
//  answer aloud in its language, then listens again. Tap the orb to interrupt. Speech is
//  recognized and spoken on the iPhone; only the text goes to the AI, as in the chat.
//

import AVFoundation
import NaturalLanguage
import SwiftUI

// Reads text aloud with the best installed voice for its language.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var speakingID: UUID?
    @Published private(set) var level: CGFloat = 0     // a gentle pulse while speaking

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    private var pulse: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { speakingID != nil }

    func speak(_ text: String, id: UUID = UUID(), then: (() -> Void)? = nil) {
        stop()
        let clean = Self.plain(text)
        guard !clean.isEmpty else { then?(); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.voice(for: clean)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.pitchMultiplier = 1.0
        onFinish = then
        speakingID = id
        synthesizer.speak(utterance)
        pulse = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.level = CGFloat.random(in: 0.25...0.9) }
        }
    }

    func stop() {
        onFinish = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finish(callBack: false)
    }

    private func finish(callBack: Bool) {
        pulse?.invalidate()
        pulse = nil
        level = 0
        speakingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let action = onFinish
        onFinish = nil
        if callBack { action?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(callBack: true) }
    }

    // The voice for the text's language, the best quality installed.
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue ?? AppLanguage.current.code
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }

    // Markdown and links read badly; keep the words.
    static func plain(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[*_`#>|]+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*[-•]\s+"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct VoiceModeView: View {
    @ObservedObject var viewModel: ChatViewModel
    let model: AIModelOption
    let theme: AppTheme
    var onClose: () -> Void

    enum Phase { case listening, thinking, speaking, paused }

    @StateObject private var recorder = VoiceRecorder()
    @ObservedObject private var speaker = Speaker.shared
    @State private var phase: Phase = .paused
    @State private var heard = ""
    @State private var answer = ""
    @State private var lastChange = Date()
    @State private var awaitingReply = false
    @State private var messageCount = 0
    @State private var problem: String?
    private let silence = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    @State private var showTranscript = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("End Voice Mode")
                    Spacer()
                    Text(verbatim: "Minor AI")
                        .minorFont(17, .semibold, maxScale: 1.2)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { showTranscript = true } label: {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 19))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Conversation So Far")
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 12)
                mark
                    .onTapGesture(perform: tapOrb)
                    .accessibilityElement()
                    .accessibilityLabel(statusText)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(phase == .speaking ? L("Stops the answer and listens") : "")
                LevelBars(level: orbLevel, active: phase == .listening || phase == .speaking, reduceMotion: reduceMotion)
                    .frame(height: 40)
                    .padding(.top, 34)
                    .accessibilityHidden(true)
                Text(statusText)
                    .minorFont(30, .bold, style: .title1, maxScale: 1.3)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.updatesFrequently)
                VStack(spacing: 8) {
                    Text(captionText)
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                    ScrollView {
                        Text(spokenText)
                            .minorFont(21, maxScale: 1.4)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxHeight: 150)
                }
                .padding(.top, 34)
                if let problem {
                    Text(problem)
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.dangerText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 8)
                }
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    Button {
                        if phase == .paused { listen() } else { pause() }
                    } label: {
                        Image(systemName: phase == .paused ? "mic.fill" : "pause.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 76, height: 76)
                            .background(Circle().fill(Color.white))
                            .shadow(color: .white.opacity(0.18), radius: 18)
                    }
                    .accessibilityLabel(phase == .paused ? L("Continue") : L("Pause"))
                    Text(phase == .paused ? L("Continue") : L("Pause"))
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .accessibilityHidden(true)
                }
                Button(action: close) {
                    HStack(spacing: 6) {
                        Text("Go to Chat")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .minorFont(15, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(minHeight: 44)
                }
                .padding(.top, 28)
                .padding(.bottom, 12)
            }
            .foregroundColor(MinorColor.textPrimary)
        }
        .sheet(isPresented: $showTranscript) {
            VoiceTranscript(messages: viewModel.messages, theme: theme)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            messageCount = viewModel.messages.count
            listen()
        }
        .onDisappear {
            recorder.cancel()
            speaker.stop()
        }
        .onChange(of: recorder.transcript) { text in
            guard phase == .listening else { return }
            heard = text
            lastChange = Date()
        }
        .onReceive(silence) { _ in checkPause() }
        .onChange(of: viewModel.messages.count) { _ in checkReply() }
        .onChange(of: viewModel.isSending) { sending in if !sending { checkReply() } }
    }

    // MARK: - Mark

    private var orbLevel: CGFloat {
        switch phase {
        case .listening: return recorder.level
        case .speaking: return speaker.level
        case .thinking: return 0.3
        case .paused: return 0
        }
    }

    // The real Minor mark, with a glow that breathes with the voice.
    private var mark: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [MinorColor.accent.opacity(phase == .paused ? 0.12 : 0.34), MinorColor.accent.opacity(0)], center: .center, startRadius: 10, endRadius: 150))
                .frame(width: 300, height: 300)
                .scaleEffect(reduceMotion ? 1 : 1 + orbLevel * 0.22)
                .animation(.easeOut(duration: 0.15), value: orbLevel)
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .scaleEffect(reduceMotion ? 1 : 1 + orbLevel * 0.06)
                .opacity(phase == .paused ? 0.55 : 1)
                .rotationEffect(.degrees(phase == .thinking && !reduceMotion ? 360 : 0))
                .animation(phase == .thinking && !reduceMotion ? .linear(duration: 3).repeatForever(autoreverses: false) : .easeOut(duration: 0.2), value: phase == .thinking)
        }
        .frame(width: 300, height: 260)
    }

    private var statusText: String {
        switch phase {
        case .listening: return L("Listening")
        case .thinking: return L("Thinking")
        case .speaking: return L("Answering")
        case .paused: return L("Paused")
        }
    }

    private var captionText: String {
        switch phase {
        case .speaking: return L("Minor’s answer")
        case .listening where heard.isEmpty: return L("Speak; Minor answers when you pause")
        case .paused where heard.isEmpty: return L("Tap Continue to talk")
        default: return L("Your words")
        }
    }

    private var spokenText: String {
        phase == .speaking ? Speaker.plain(answer) : heard
    }

    // MARK: - Flow

    private func listen() {
        speaker.stop()
        heard = ""
        // The consent screen can't show above Voice Mode, so a question would wait forever.
        guard AIConsent.isGiven else {
            problem = L("Allow AI in Settings → AI Data Sharing to talk with Minor.")
            phase = .paused
            return
        }
        problem = nil
        phase = .listening
        lastChange = Date()
        Task {
            await recorder.start()
            switch recorder.state {
            case .denied:
                problem = L("Allow microphone and speech recognition for Minor in Settings to talk.")
                phase = .paused
            case .failed:
                problem = L("Voice isn’t available right now. Check that no other app is using the microphone.")
                phase = .paused
            default: break
            }
        }
    }

    private func pause() {
        recorder.cancel()
        speaker.stop()
        phase = .paused
    }

    // A pause of a moment and a half after some words sends them.
    private func checkPause() {
        guard phase == .listening, !heard.trimmingCharacters(in: .whitespaces).isEmpty,
              Date().timeIntervalSince(lastChange) > 1.5 else { return }
        Task {
            let text = await recorder.finish()
            guard !text.isEmpty else { return listen() }
            // An earlier answer (a picture, say) is still coming: the question would be dropped.
            guard !viewModel.isSending else {
                heard = text
                problem = L("Minor is still answering. Ask again in a moment.")
                phase = .paused
                return
            }
            heard = text
            answer = ""
            phase = .thinking
            messageCount = viewModel.messages.count
            awaitingReply = true
            viewModel.send(text, model: model)
        }
    }

    private func checkReply() {
        guard awaitingReply, !viewModel.isSending else { return }
        awaitingReply = false
        let newMessages = viewModel.messages.dropFirst(messageCount)
        guard let reply = newMessages.last(where: { $0.role == .assistant && !$0.isHidden }) else {
            problem = viewModel.errorMessage
            phase = .paused
            return
        }
        // Pictures, maps and other cards are shown in the chat; the voice says so briefly.
        answer = reply.text.isEmpty ? L("Done. It’s in the chat.") : reply.text
        phase = .speaking
        speaker.speak(answer) {
            if phase == .speaking { listen() }
        }
    }

    private func tapOrb() {
        switch phase {
        case .speaking, .paused: listen()
        case .listening, .thinking: break
        }
    }

    private func close() {
        recorder.cancel()
        speaker.stop()
        onClose()
    }
}

// Bars under the mark that rise with the voice; flat dots when nothing is heard.
private struct LevelBars: View {
    let level: CGFloat
    let active: Bool
    let reduceMotion: Bool

    private let count = 17

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { i in
                    let distance = abs(Double(i) - Double(count - 1) / 2) / (Double(count) / 2)
                    let wave = active && !reduceMotion ? (sin(t * 7 + Double(i) * 0.9) + 1) / 2 : 0
                    let height = 4 + (active ? CGFloat((1 - distance) * (0.35 + 0.65 * wave)) * max(level, 0.15) * 36 : 0)
                    Capsule()
                        .fill(MinorColor.accent.opacity(0.35 + 0.65 * (1 - distance)))
                        .frame(width: 4, height: height)
                }
            }
            .frame(height: 40)
        }
    }
}

// What was said so far in this conversation, from Voice Mode.
private struct VoiceTranscript: View {
    let messages: [ChatMessage]
    let theme: AppTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages.filter { !$0.isHidden && !$0.text.isEmpty }) { message in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(message.role == .user ? L("You") : "Minor")
                                .minorFont(12, .semibold, style: .caption1, maxScale: 1.3)
                                .foregroundColor(MinorColor.textTertiary)
                            Text(Speaker.plain(message.text)).minorFont(16, maxScale: 1.4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(Text("Conversation So Far"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundColor(MinorColor.accent) } }
        }
        .preferredColorScheme(.dark)
    }
}

