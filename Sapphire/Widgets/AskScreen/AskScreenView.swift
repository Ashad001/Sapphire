//
//  AskScreenView.swift
//  Sapphire
//
//  Ask Screen: capture the screen, ask a question about it, stream the answer
//  back into the notch. Read-only — it never types into other apps.

import SwiftUI
import AppKit

extension Notification.Name {
    static let sapphireOpenAskScreen = Notification.Name("sapphireOpenAskScreen")
}

struct AskScreenView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedObject private var service = AskScreenService.shared
    @State private var escapeMonitor: Any?

    // ponytail: single point of contact with the service's capture image —
    // if AskScreenService names it differently, this line is the only fix.
    private var capture: NSImage? { service.capturedImage }

    private var statusText: String {
        if service.isCapturing { return "Capturing screen…" }
        if service.isStreaming { return "Thinking…" }
        if service.answer.isEmpty { return "Ask about what's on screen" }
        return "Answer"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            inputBar
            answerArea
        }
        .padding(.top, 10)
        .frame(width: 520, height: 300)
        .clipped()
        .onAppear(perform: installEscapeMonitor)
        .onDisappear(perform: removeEscapeMonitor)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.35), Color.blue.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Screen")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if service.isStreaming {
                NotchCapsuleIconButton(
                    systemName: "stop.fill",
                    isActive: true,
                    activeTint: .red,
                    help: "Stop",
                    action: { service.cancel() }
                )
            }

            if !service.answer.isEmpty {
                NotchCapsuleIconButton(
                    systemName: "doc.on.doc",
                    activeTint: .purple,
                    help: "Copy answer",
                    action: copyAnswer
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            if let capture {
                Image(nsImage: capture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(MaterialChartPalette.outline, lineWidth: 1)
                    )
            } else {
                Image(systemName: service.isCapturing ? "camera.viewfinder" : "rectangle.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 28)
            }

            NotchSearchField(
                placeholder: "Ask about this screen",
                text: $service.question,
                onSubmit: submit,
                autofocus: true
            )
            .font(.system(size: 13))

            if service.isStreaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.surfaceContainer)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: .purple))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.purple.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var answerArea: some View {
        if let error = service.errorMessage, !error.isEmpty {
            messageCard(icon: "exclamationmark.triangle.fill", tint: .red, text: error)
        } else if service.answer.isEmpty && !service.isStreaming {
            emptyState
        } else {
            ScrollView {
                MarkdownText(raw: service.answer)
                    .foregroundStyle(.primary.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.surface)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.cardGradient(for: .purple))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MaterialChartPalette.outline, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func messageCard(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MaterialChartPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.purple.opacity(0.8))
            Text("Ask about your screen")
                .font(.headline)
            Text("Type a question and press Return. Escape closes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 20)
    }

    private func submit() {
        let question = service.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            dismiss()
            return
        }
        service.ask(question: question)
    }

    private func copyAnswer() {
        // Plain text, not the markdown source — this usually gets pasted into an email,
        // a form field, or a comment box, where '**' and '#' are just noise.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MarkdownBlock.plainText(service.answer), forType: .string)
    }

    private func dismiss() {
        service.cancel()
        if navigationStack.count > 1 {
            navigationStack.removeLast()
        } else {
            navigationStack = [.defaultWidgets]
        }
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            dismiss()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}
