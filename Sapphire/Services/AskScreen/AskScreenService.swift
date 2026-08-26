//
//  AskScreenService.swift
//  Sapphire
//
//  Ask Screen: capture the display under the cursor, ask an LLM about it via
//  OpenRouter, and stream the answer back into the notch.
//  Read-only — it never types into, or otherwise drives, another app.
//

import AppKit
import Combine
import Foundation
import ScreenCaptureKit

// MARK: - Ask Screen Service

@MainActor
final class AskScreenService: ObservableObject {
    static let shared = AskScreenService()

    // MARK: - Published State

    @Published var question: String = ""
    @Published private(set) var answer: String = ""
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var errorMessage: String?
    /// Downscaled screenshot, for an optional preview thumbnail in the notch.
    @Published private(set) var capturedImage: NSImage?

    private var capturedJPEG: Data?
    private var streamTask: Task<Void, Never>?
    /// Bumped on every ask()/cancel(); a stream only writes state while it owns the current value.
    private var generation: Int = 0

    private init() {}

    // MARK: - Tuning

    // nonisolated: read from the detached credential-resolution task, and immutable anyway.
    nonisolated static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    nonisolated static let defaultModel = "anthropic/claude-opus-5"
    /// Long edge cap for the capture. A raw Retina grab is megabytes of base64, and that costs real money per request.
    nonisolated static let maxLongEdge: CGFloat = 1568
    nonisolated static let jpegQuality: CGFloat = 0.7

    // MARK: - Capture

    /// Captures the display that currently contains the mouse cursor.
    func captureScreen() async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        guard let (displayID, scale) = Self.displayUnderCursor() else {
            errorMessage = "Couldn't work out which display to capture."
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                errorMessage = "No capturable display found."
                return
            }

            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            configuration.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

            guard let jpeg = Self.downscaledJPEG(from: image) else {
                errorMessage = "Couldn't encode the screenshot."
                return
            }
            capturedJPEG = jpeg
            capturedImage = NSImage(data: jpeg)
        } catch {
            errorMessage = "Screen capture failed — check Screen Recording permission in System Settings. (\(error.localizedDescription))"
        }
    }

    private static func displayUnderCursor() -> (CGDirectDisplayID, CGFloat)? {
        let mouse = NSEvent.mouseLocation
        guard let screen = CursorPosition.screen(containing: mouse)
                ?? CursorPosition.targetNotchScreen()
                ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return (displayID, screen.backingScaleFactor)
    }

    /// CoreGraphics downscale to `maxLongEdge`, then JPEG at `jpegQuality`.
    private static func downscaledJPEG(from image: CGImage) -> Data? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let ratio = min(1, maxLongEdge / max(width, height))

        var source = image
        if ratio < 1 {
            let targetWidth = max(1, Int((width * ratio).rounded()))
            let targetHeight = max(1, Int((height * ratio).rounded()))
            guard let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            guard let scaled = context.makeImage() else { return nil }
            source = scaled
        }

        return NSBitmapImageRep(cgImage: source)
            .representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
    }

    // MARK: - Ask

    /// Starts a streamed answer. A second call while streaming cancels the first cleanly.
    func ask(question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let previous = streamTask
        previous?.cancel()

        generation += 1
        let currentGeneration = generation
        self.question = trimmed
        answer = ""
        errorMessage = nil
        isStreaming = true

        streamTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.stream(question: trimmed, generation: currentGeneration)
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        generation += 1
        isStreaming = false
    }

    private func stream(question: String, generation currentGeneration: Int) async {
        // Credential lookup touches the filesystem and the Keychain. Either can block for a long
        // time — a .env under a TCC-gated folder (~/Documents, ~/Desktop) stalls on a permission
        // prompt until the user answers it. On the main actor that freezes the whole notch,
        // including the stop button, so resolve off it.
        let resolved = await Task.detached(priority: .userInitiated) {
            (key: Self.resolvedAPIKey(),
             model: Self.resolvedModel(),
             reasoning: Self.resolvedReasoningEffort(),
             system: Self.resolvedSystemPrompt())
        }.value

        guard let key = resolved.key else {
            finish(generation: currentGeneration, error: "No OpenRouter API key found. Set OPENROUTER_API_KEY in your environment, in ~/Library/Application Support/Sapphire/.env, or in Sapphire's API key settings.")
            return
        }

        let model = resolved.model
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("https://github.com/cshariq/Sapphire", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Sapphire", forHTTPHeaderField: "X-OpenRouter-Title")

        let body = Self.makeRequestBody(
            model: model,
            question: question,
            imageBase64: capturedJPEG?.base64EncodedString(),
            reasoningEffort: resolved.reasoning,
            systemPrompt: resolved.system
        )
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            finish(generation: currentGeneration, error: "Couldn't build the request.")
            return
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let detail = await Self.errorDetail(from: bytes)
                finish(generation: currentGeneration, error: Self.userFacingError(
                    status: http.statusCode,
                    model: model,
                    detail: detail,
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                ))
                return
            }

            var receivedAnything = false
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                switch Self.streamEvent(from: line) {
                case .delta(let text):
                    guard currentGeneration == generation else { return }
                    receivedAnything = true
                    answer += text
                case .failure(let message):
                    finish(generation: currentGeneration, error: message)
                    return
                case .done:
                    finish(generation: currentGeneration, error: nil)
                    return
                case .ignore:
                    continue
                }
            }
            finish(generation: currentGeneration, error: receivedAnything ? nil : "No answer came back from OpenRouter.")
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            finish(generation: currentGeneration, error: "Network error: \(error.localizedDescription)")
        }
    }

    private func finish(generation currentGeneration: Int, error: String?) {
        guard currentGeneration == generation else { return }
        if let error { errorMessage = error }
        isStreaming = false
        streamTask = nil
    }

    // MARK: - Stream Parsing

    enum StreamEvent: Equatable {
        case delta(String)
        case failure(String)
        case done
        case ignore
    }

    nonisolated static func streamEvent(from line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Blank lines and ": OPENROUTER PROCESSING" keepalive comments.
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":"), trimmed.hasPrefix("data:") else { return .ignore }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }

        // A malformed chunk is skipped rather than treated as an error.
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .ignore }

        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return .failure("OpenRouter error: \(message)")
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else { return .ignore }
        return .delta(content)
    }

    private static func errorDetail(from bytes: URLSession.AsyncBytes) async -> String? {
        var raw = ""
        if let lines = try? await bytes.lines.reduce(into: [String](), { $0.append($1) }) {
            raw = lines.joined()
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return String(message.prefix(300))
    }

    nonisolated static func userFacingError(status: Int, model: String, detail: String?, retryAfter: String?) -> String {
        let base: String
        switch status {
        case 401:
            base = "OpenRouter rejected the API key (401). Check the key and try again."
        case 402:
            base = "OpenRouter account is out of credit (402)."
        case 403:
            base = "OpenRouter refused the request (403)."
        case 404:
            base = "OpenRouter couldn't find the model \"\(model)\" (404)."
        case 413:
            base = "The screenshot was too large for OpenRouter (413)."
        case 429:
            if let retryAfter {
                base = "Rate limited by OpenRouter (429). Try again in \(retryAfter)s."
            } else {
                base = "Rate limited by OpenRouter (429). Try again in a moment."
            }
        case 500...599:
            base = "OpenRouter or the model is unavailable right now (\(status))."
        default:
            base = "OpenRouter returned an error (\(status))."
        }
        guard let detail, !detail.isEmpty else { return base }
        return "\(base) \(detail)"
    }

    // MARK: - Request Body

    nonisolated static func makeRequestBody(
        model: String,
        question: String,
        imageBase64: String?,
        reasoningEffort: String? = nil,
        systemPrompt: String? = nil
    ) -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": question]]
        if let imageBase64, !imageBase64.isEmpty {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]
            ])
        }
        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": content])

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages
        ]
        // Some endpoints reject "none" outright ("Reasoning is mandatory for this endpoint"),
        // so this is configurable and omitted entirely when unset rather than hardcoded.
        if let reasoningEffort, !reasoningEffort.isEmpty {
            body["reasoning"] = ["effort": reasoningEffort]
        }
        return body
    }

    // MARK: - Credentials

    // Never logged, never printed, never put into an error message.
    nonisolated static func resolvedAPIKey() -> String? {
        if let value = resolvedValue(for: "OPENROUTER_API_KEY") { return value }
        let stored = APIKeyManager.shared.openRouterAPIKey
        return stored.isEmpty ? nil : stored
    }

    nonisolated static func resolvedModel() -> String {
        resolvedValue(for: "OPENROUTER_MODEL") ?? defaultModel
    }

    /// OPENROUTER_REASONING: an OpenRouter effort level ("low", "medium", "high"), or one of
    /// "none"/"off"/"omit" to send no reasoning parameter at all — some endpoints reject the
    /// parameter rather than ignoring it. Defaults to "low".
    nonisolated static func resolvedReasoningEffort() -> String? {
        resolvedReasoningEffortValue(from: resolvedValue(for: "OPENROUTER_REASONING") ?? "low")
    }

    /// Personal context ("what I do, how I write") prepended as a system message. Edit
    /// ~/Library/Application Support/Sapphire/askscreen-context.md; absent means no system message.
    nonisolated static func resolvedSystemPrompt() -> String? {
        for url in contextFileURLs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return baseInstruction + "\n\n" + trimmed }
        }
        return baseInstruction
    }

    nonisolated static let baseInstruction = """
    You are answering a question about a screenshot of the user's Mac screen, inside a small \
    notch-sized panel. Be concise and concrete — no preamble, no restating the question, no \
    offers to help further. When asked to write something (an email, a comment, a form field), \
    reply with only the text to paste, in the user's own voice. Use light markdown at most.
    """

    nonisolated static var contextFileURLs: [URL] {
        var urls: [URL] = []
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(support.appendingPathComponent("Sapphire", isDirectory: true).appendingPathComponent("askscreen-context.md"))
        }
        urls.append(repoRootEnvURL.deletingLastPathComponent().appendingPathComponent("askscreen-context.md"))
        return urls
    }

    /// Pure normalisation, split out so the self-check can exercise it without touching disk.
    nonisolated static func resolvedReasoningEffortValue(from raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return ["off", "omit", "none", ""].contains(value) ? nil : value
    }

    /// Environment first (Xcode runs), then .env files — a .app launched from Finder or as a
    /// login item inherits no shell environment, so the app has to read the file itself.
    nonisolated static func resolvedValue(for key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { return value }
        for url in envFileURLs {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let value = parseEnv(contents)[key], !value.isEmpty { return value }
        }
        return nil
    }

    nonisolated static var envFileURLs: [URL] {
        var urls: [URL] = []
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(support.appendingPathComponent("Sapphire", isDirectory: true).appendingPathComponent(".env"))
        }
        urls.append(repoRootEnvURL)
        return urls
    }

    // #filePath is <repo>/Sapphire/Services/AskScreen/AskScreenService.swift — four levels up is the repo root.
    // ponytail: dev convenience only; it simply doesn't exist on an installed .app.
    nonisolated static let repoRootEnvURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".env")

    /// Minimal .env parser: `KEY=value` lines, ignoring blanks and `#` comments, tolerating an
    /// `export ` prefix, whitespace around `=`, and matching single or double quotes around the value.
    nonisolated static func parseEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}
