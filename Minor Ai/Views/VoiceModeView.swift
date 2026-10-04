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

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .accessibilityLabel("End Voice Mode")
                    Spacer()
                    Text(model.displayName).font(.system(size: 15, weight: .medium)).foregroundColor(MinorColor.textSecondary)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                Spacer()
                orb
                    .onTapGesture(perform: tapOrb)
                    .accessibilityElement()
                    .accessibilityLabel(statusText)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(phase == .speaking ? L("Stops the answer and listens") : "")
                Text(statusText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MinorColor.textSecondary)
                ScrollView {
                    Text(phase == .speaking || phase == .thinking ? (answer.isEmpty ? heard : Speaker.plain(answer)) : heard)
                        .font(.system(size: 20, weight: .medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                }
                .frame(maxHeight: 200)
                if let problem {
                    Text(problem).font(.system(size: 14)).foregroundColor(MinorColor.dangerText).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                Spacer()
                HStack(spacing: 24) {
                    Button {
                        if phase == .paused { listen() } else { pause() }
                    } label: {
                        Image(systemName: phase == .paused ? "mic.fill" : "pause.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 68, height: 68)
                            .background(Circle().fill(MinorColor.accent))
                    }
                    .accessibilityLabel(phase == .paused ? "Listen" : "Pause")
                }
                .padding(.bottom, 24)
            }
            .foregroundColor(MinorColor.textPrimary)
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

    // MARK: - Orb

    private var orbLevel: CGFloat {
        switch phase {
        case .listening: return recorder.level
        case .speaking: return speaker.level
        case .thinking: return 0.3
        case .paused: return 0
        }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(MinorColor.accent.opacity(0.18))
                .frame(width: 260, height: 260)
                .scaleEffect(1 + orbLevel * 0.25)
                .blur(radius: 20)
            Circle()
                .fill(AngularGradient(colors: [MinorColor.accent, Color(hex: "#7CC4FF"), Color(hex: "#C9A2FF"), MinorColor.accent], center: .center))
                .frame(width: 180, height: 180)
                .scaleEffect(1 + orbLevel * 0.18)
                .rotationEffect(.degrees(phase == .thinking ? 360 : 0))
                .animation(phase == .thinking ? .linear(duration: 2).repeatForever(autoreverses: false) : .easeOut(duration: 0.12), value: phase == .thinking ? 1 : orbLevel)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .opacity(phase == .paused ? 0.5 : 1)
        }
        .frame(width: 280, height: 280)
    }

    private var statusText: String {
        switch phase {
        case .listening: return heard.isEmpty ? L("Listening…") : L("Listening — pause when you’re done")
        case .thinking: return L("Thinking…")
        case .speaking: return L("Speaking — tap to interrupt")
        case .paused: return L("Paused")
        }
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
        case .speaking: listen()
        case .paused: listen()
        case .listening, .thinking: break
        }
    }

    private func close() {
        recorder.cancel()
        speaker.stop()
        onClose()
    }
}
