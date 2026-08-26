//
//  IntelligenceShims.swift — FORK-ONLY SHIM
//  Stand-in for closed-source upstream modules Sapphire/Services/Intelligence and
//  Sapphire/Widgets/Intelligence (the "Blip" agent), which are gitignored in cshariq/Sapphire and
//  therefore absent from this repo. These definitions exist ONLY so the fork compiles. They are
//  inert. Delete this whole folder before proposing anything upstream.
//

import SwiftUI
import AppKit

// MARK: - Backend / model selection
//
// LLMBackend, GeminiSpeedMode and the *ModelOption enums are stored in the Codable+Equatable
// `Settings` struct, so both conformances are mandatory and each needs the default case the
// declaration in SettingsModel.swift names. Nothing switches over them, so extra cases are safe.

enum LLMBackend: String, Codable, Equatable, CaseIterable {
    case auto, gemini, openAI, anthropic, openRouter, xai, nvidia, hackclub

    // ponytail: permissive — never let the (dead) runner button gate on a key the fork can't check.
    var isKeyConfigured: Bool { true }

    func resolveAPIKey(fallbackGeminiKey: String) -> String { fallbackGeminiKey }
}

enum GeminiSpeedMode: String, Codable, Equatable, CaseIterable {
    case fast, balanced, quality
}

enum GeminiModelOption: String, Codable, Equatable, CaseIterable {
    case flash35Lite = "gemini-3.5-flash-lite"
}

enum OpenAIModelOption: String, Codable, Equatable, CaseIterable {
    case auto
}

enum AnthropicModelOption: String, Codable, Equatable, CaseIterable {
    case auto
}

enum OpenRouterModelPreset: String, Codable, Equatable, CaseIterable {
    case auto
}

enum XAIModelOption: String, Codable, Equatable, CaseIterable {
    case auto
}

enum NVIDIAModelOption: String, Codable, Equatable, CaseIterable {
    case auto
}

/// Write-only from the open-source side: SettingsModel assigns all five, nothing reads them back.
/// Must stay non-isolated — the assignments run on SettingsModel's background persistence queue.
enum BlipModelPreferences {
    static var openAIModel: String = ""
    static var anthropicModel: String = ""
    static var openRouterModelStored: String = ""
    static var xaiModel: String = ""
    static var nvidiaModel: String = ""
}

// MARK: - Agent view model

struct IntelligenceSubtaskProgress {
    var current: Int = 0
    var total: Int = 0
}

struct IntelligenceRunResult {
    var success: Bool
    var subtasksCompleted: Int
    var subtasksTotal: Int
    var actionsTaken: Int
    var duration: Double
}

struct IntelligenceLogEntry: Identifiable {
    let id = UUID()
    var text: String
    var isError: Bool
    var isSubtask: Bool
}

/// Deliberately NOT @MainActor: constructed from `IntelligenceRunnerView.init` (a plain struct init)
/// as well as from AppDelegate, and its publishers are subscribed by LiveActivityManager.
final class IntelligenceNotchViewModel: ObservableObject {
    @Published var taskInput: String = ""
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = ""
    @Published var currentActionLabel: String = ""
    @Published var subtaskProgress = IntelligenceSubtaskProgress()
    @Published var lastResult: IntelligenceRunResult?
    @Published var logEntries: [IntelligenceLogEntry] = []

    var currentStepTitle: String { "" }
    var displayStepIndex: Int { 0 }
    var displayStepTotal: Int { 0 }

    // ponytail: no agent loop. Upstream runs the multi-step LLM/accessibility automation here.
    func run(apiKey: String, backend: LLMBackend, geminiSpeedMode: GeminiSpeedMode) {}
    func stop() {}
}

// MARK: - Screen perception

struct ScreenElement {}

final class ScreenPerception {
    // ponytail: no screen capture, no accessibility tree walk — returns nothing, prompts nothing.
    func captureAnnotatedScreen() async -> (NSImage?, [ScreenElement]) { (nil, []) }
}

// MARK: - Views

struct IntelligenceSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intelligence").font(.largeTitle.bold())
            ShimUnavailableView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct IntelligenceNotchView: View {
    let navigationStack: Binding<[NotchWidgetMode]>

    var body: some View {
        ShimUnavailableView()
            .frame(width: 380, height: 160)
    }
}

struct BlipHubView: View {
    let navigationStack: Binding<[NotchWidgetMode]>

    var body: some View {
        ShimUnavailableView()
            .frame(width: 380, height: 160)
    }
}
