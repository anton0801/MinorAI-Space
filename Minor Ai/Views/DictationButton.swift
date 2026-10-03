//
//  DictationButton.swift
//  Minor Ai
//
//  Dictation in a message field, like ChatGPT: tap the microphone and speak; the words appear in
//  the field as you talk; tap again to stop, then check and send. Recognition runs on the device
//  (VoiceRecorder), so it is free on every plan and nothing is sent until you send the message.
//

import SwiftUI

struct DictationButton: View {
    @Binding var text: String
    var tint: Color = .white
    var stroke: Color = Color.white.opacity(0.2)
    var onError: (String) -> Void = { _ in }
    var onListeningChange: (Bool) -> Void = { _ in }

    @StateObject private var recorder = VoiceRecorder()
    @State private var base = ""

    private var isListening: Bool { recorder.state == .listening || recorder.state == .starting }

    var body: some View {
        Button(action: toggle) {
            ZStack {
                if isListening {
                    // The ring breathes with the voice.
                    Circle()
                        .fill(MinorColor.danger.opacity(0.25 + 0.5 * recorder.level))
                        .scaleEffect(1 + 0.35 * recorder.level)
                        .animation(.easeOut(duration: 0.12), value: recorder.level)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else if recorder.state == .finishing {
                    ProgressView().tint(tint).scaleEffect(0.7)
                } else {
                    Circle().stroke(stroke, lineWidth: 1)
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
            }
            .frame(width: 32, height: 32)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Stop Dictation" : "Dictate")
        .onChange(of: recorder.transcript) { heard in
            guard isListening || recorder.state == .finishing else { return }
            text = Self.join(base, heard)
        }
        .onChange(of: isListening) { onListeningChange($0) }
        .onAppear {
            recorder.onAutoFinish = { heard in text = Self.join(base, heard) }
        }
        .onDisappear { recorder.cancel() }
    }

    private func toggle() {
        Haptics.selection()
        if isListening {
            Task {
                let heard = await recorder.finish()
                text = Self.join(base, heard)
            }
            return
        }
        base = text
        Task {
            await recorder.start()
            switch recorder.state {
            case .denied: onError(L("Allow microphone and speech recognition for Minor in Settings to dictate."))
            case .failed: onError(L("Dictation isn’t available right now. Check that no other app is using the microphone."))
            default: break
            }
        }
    }

    // What was typed before, then what was said.
    static func join(_ base: String, _ heard: String) -> String {
        let typed = base.trimmingCharacters(in: .whitespaces)
        guard !heard.isEmpty else { return base }
        return typed.isEmpty ? heard : typed + " " + heard
    }
}
