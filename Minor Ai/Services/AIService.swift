//
//  AIService.swift
//  Minor Ai
//
//  Chat replies come from the `ai` edge function. Provider keys live only on the server.
//

import Foundation

final class AIService {
    static let shared = AIService()

    struct NodeContext: Encodable {
        let mapTitle: String
        let path: [String]
    }

    struct Answer {
        let text: String
        let model: String?   // the model the server actually used
        var intent: Intent?  // set instead of text when the person asked for a picture or a map
    }

    // The model decides, from any wording, that the person wants a picture or a map (see the
    // server's _shared/intent.ts); the app then makes it.
    struct Intent: Decodable, Equatable {
        enum Kind: String, Decodable { case image, map, deck, read, edit, editdeck, open, tasks }
        let kind: Kind
        let prompt: String
        var maps: [String]?     // read, edit, open: map references (Workspace.ref)
        var command: String?    // edit: what to change
        // "MAP: ^" asks for a map of the conversation itself.
        var mapsConversation: Bool { prompt == "^" }
    }

    func reply(to messages: [ChatMessage], model: AIModelOption, context: NodeContext? = nil) async throws -> String {
        try await answer(to: messages, model: model, context: context).text
    }

    func answer(to messages: [ChatMessage], model: AIModelOption, context: NodeContext? = nil, intents: Bool = false, workspace: [Workspace.Entry]? = nil) async throws -> Answer {
        struct Message: Encodable { let role: String; let content: String; let images: [String]? }
        struct Body: Encodable {
            let action = "chat"
            let messages: [Message]
            let context: NodeContext?
            let model: String
            let intents: Bool?
            let workspace: [Workspace.Entry]?
            let today: String?
        }
        struct Reply: Decodable {
            let reply: String
            let model: String?
            let intent: Intent?

            enum CodingKeys: String, CodingKey { case reply, model, intent }

            // An action this version doesn't know (added on the server later) leaves just the text
            // instead of failing the whole answer.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                reply = try c.decode(String.self, forKey: .reply)
                model = try c.decodeIfPresent(String.self, forKey: .model)
                intent = try? c.decodeIfPresent(Intent.self, forKey: .intent)
            }
        }

        // The server reads at most the last 30 messages; photos travel only with the last few.
        let messages = Array(messages.suffix(30))
        let withImages = Set(messages.suffix(3).map(\.id))
        let body = Body(
            messages: messages.map { message in
                Message(
                    role: message.role.rawValue,
                    content: message.contentForModel,
                    // Only the person's photos go to the model; created images stay on the device.
                    images: message.role == .user && withImages.contains(message.id) ? message.images?.map { $0.base64EncodedString() } : nil
                )
            },
            context: context,
            model: model.apiModelID,
            intents: intents ? true : nil,
            workspace: workspace,
            today: workspace == nil ? nil : await Workspace.today
        )
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: body)
        let intent = reply.intent.flatMap { intent -> Intent? in
            switch intent.kind {
            case .image, .map: return intent.prompt.isEmpty ? nil : intent
            case .deck: return intent.prompt.isEmpty && intent.maps?.isEmpty != false ? nil : intent
            case .read, .open: return intent.maps?.isEmpty == false ? intent : nil
            case .edit, .editdeck: return intent.maps?.isEmpty == false && intent.command?.isEmpty == false ? intent : nil
            case .tasks: return intent
            }
        }
        return Answer(text: reply.reply.trimmingCharacters(in: .whitespacesAndNewlines), model: reply.model, intent: intent)
    }

    // An AI image (JPEG) from a description, or for an idea of a map when `context` is given.
    // `quality` "high" is honored for PRO; the server picks the plan's quality otherwise.
    func generateImage(prompt: String, context: NodeContext? = nil, quality: String? = nil) async throws -> Data {
        struct Body: Encodable {
            let action = "image"
            let prompt: String
            let context: NodeContext?
            let quality: String?
        }
        struct Reply: Decodable { let image: String }
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(prompt: prompt, context: context, quality: quality))
        guard let data = Data(base64Encoded: reply.image), !data.isEmpty else { throw BackendError.aiFailed }
        return data
    }

    // Reports an AI image or answer someone found offensive or wrong.
    func report(kind: String, content: String, reason: String? = nil) async throws {
        struct Body: Encodable {
            let action = "report"
            let kind: String
            let content: String
            let reason: String?
        }
        struct Reply: Decodable { let reported: Bool }
        let _: Reply = try await BackendClient.shared.invoke("ai", body: Body(kind: kind, content: content, reason: reason))
    }

}
