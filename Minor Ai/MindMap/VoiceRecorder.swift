//
//  VoiceRecorder.swift
//  Minor Ai
//
//  On-device dictation for the Voice source: live transcript and input level for the waveform.
//

import AVFoundation
import Speech
import UIKit

@MainActor
final class VoiceRecorder: ObservableObject {
    enum State: Equatable { case idle, starting, listening, finishing, denied, failed }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var level: CGFloat = 0     // 0…1, smoothed input loudness
    @Published private(set) var elapsed: TimeInterval = 0

    static let maxDuration: TimeInterval = 300

    // Called with the transcript when listening ends on its own: the time limit, the end of
    // recognition, or an interruption such as a phone call.
    var onAutoFinish: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?   // kept alive for the whole recognition
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var startedAt = Date()
    private var interruption: NSObjectProtocol?
    private var finalResult: CheckedContinuation<Void, Never>?

    func start() async {
        guard state != .listening, state != .starting, state != .finishing else { return }
        state = .starting
        transcript = ""
        elapsed = 0
        guard await Self.authorize() else {
            state = .denied
            return
        }
        // Cancelled while the permission prompts were up.
        guard state == .starting else { return }
        // The person's own language (the app may be shown in English while they speak Russian).
        let spoken = Locale(identifier: Locale.preferredLanguages.first ?? AppLanguage.current.code)
        let recognizer = SFSpeechRecognizer(locale: spoken) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            state = .failed
            return
        }
        self.recognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // No usable microphone (another app holds it, or none is connected): installing a
            // tap with this format would crash.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                stopAudio()
                state = .failed
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.rms(buffer)
                Task { @MainActor in self?.level = (self?.level ?? 0) * 0.6 + level * 0.4 }
            }
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                Task { @MainActor in
                    guard let self else { return }
                    if let text, self.state == .listening || self.finalResult != nil { self.transcript = text }
                    if (isFinal || error != nil), let waiting = self.finalResult {
                        self.finalResult = nil
                        waiting.resume()
                        return
                    }
                    guard self.state == .listening else { return }
                    guard error != nil || isFinal else { return }
                    // Recognition ended by itself (for example, the one-minute limit of server
                    // recognition). Keep what was heard; fail only when nothing was.
                    if self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.stopAudio()
                        self.state = .failed
                    } else {
                        self.finishAutomatically()
                    }
                }
            }
            interruption = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: session, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state == .listening else { return }
                    self.finishAutomatically()
                }
            }
            startedAt = Date()
            state = .listening
            // Long notes shouldn't end because the screen locked mid-sentence.
            UIApplication.shared.isIdleTimerDisabled = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state == .listening else { return }
                    self.elapsed = Date().timeIntervalSince(self.startedAt)
                    if self.elapsed >= Self.maxDuration { self.finishAutomatically() }
                }
            }
        } catch {
            stopAudio()
            state = .failed
        }
    }

    // Stops listening, waits a moment for the recognizer's last words, and returns everything heard.
    func finish() async -> String {
        guard state == .listening, let request else { return stop() }
        request.endAudio()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        state = .finishing
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finalResult = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, let waiting = self.finalResult else { return }
                self.finalResult = nil
                waiting.resume()
            }
        }
        return stop()
    }

    // Stops listening at once and returns what was heard so far.
    @discardableResult
    func stop() -> String {
        request?.endAudio()
        stopAudio()
        state = .idle
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        task?.cancel()
        stopAudio()
        transcript = ""
        state = .idle
    }

    private func finishAutomatically() {
        let heard = stop()
        if !heard.isEmpty { onAutoFinish?(heard) }
    }

    private func stopAudio() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let waiting = finalResult {
            finalResult = nil
            waiting.resume()
        }
        timer?.invalidate()
        timer = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.finish()
        task = nil
        request = nil
        recognizer = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(count))
        return CGFloat(min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 50)))
    }
}
