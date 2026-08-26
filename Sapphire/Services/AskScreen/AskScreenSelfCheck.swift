//
//  AskScreenSelfCheck.swift
//  Sapphire
//
//  Assert-based self-check for the pure Ask Screen logic: the .env parser, the
//  OpenRouter request body, and SSE line parsing. No test framework, no fixtures.
//  Call `AskScreenSelfCheck.run()` from a debug menu or a test. Asserts are
//  compiled out in release builds.
//

import Foundation

// MARK: - Self Check

enum AskScreenSelfCheck {
    static func run() {
        checkEnvParser()
        checkRequestBody()
        checkStreamEvents()
        checkMarkdown()
    }

    // MARK: - Markdown

    private static func checkMarkdown() {
        let source = """
        Here's what I see:

        ## Main Focus
        You're viewing **Z.ai: GLM 5.3 Flash** (`z-ai/glm-5.3-flash`), which includes:

        - **Description**: a multimodal model
        - **Key specs**:
          - Modalities: text, image
        1. first
        ```
        let x = 1
        ```
        """
        let blocks = MarkdownBlock.parse(source)

        assert(blocks.contains(.heading(level: 2, text: "Main Focus")), "'## ' should become a level-2 heading")
        assert(blocks.contains(.listItem(depth: 0, marker: "•", text: "**Description**: a multimodal model")), "'- ' should become a bullet")
        assert(blocks.contains(.listItem(depth: 1, marker: "•", text: "Modalities: text, image")), "two-space indent should nest one level")
        assert(blocks.contains(.listItem(depth: 0, marker: "1.", text: "first")), "ordered items keep their marker")
        assert(blocks.contains(.code("let x = 1")), "fenced code should become a code block")
        assert(blocks.contains(.paragraph("Here's what I see:")), "plain lines should become paragraphs")

        // A heading marker with no space is not a heading (e.g. a '#hashtag').
        assert(MarkdownBlock.parse("#nothashtag") == [.paragraph("#nothashtag")], "'#' without a space is not a heading")

        // Streaming ends mid-fence constantly; the partial block must still render.
        assert(MarkdownBlock.parse("```\nhalf").contains(.code("half")), "an unterminated fence should still render")

        // Inline emphasis is stripped into attributes, not left as literal asterisks.
        let inline = MarkdownBlock.inline("a **bold** word")
        assert(!String(inline.characters).contains("*"), "inline markdown should consume the asterisks")

        // The copy button pastes into forms and email bodies, so it must carry no markdown syntax.
        let plain = MarkdownBlock.plainText(source)
        assert(!plain.contains("**"), "copied text should not contain bold markers")
        assert(!plain.contains("## "), "copied text should not contain heading markers")
        assert(!plain.contains("```"), "copied text should not contain code fences")
        assert(plain.contains("Main Focus"), "copied text should keep the heading's words")
        assert(plain.contains("let x = 1"), "copied text should keep code contents")
        assert(plain.contains("• Description: a multimodal model"), "bullets keep their marker, without the markdown")
    }

    // MARK: - .env Parser

    private static func checkEnvParser() {
        let sample = """
        # a comment line
        OPENROUTER_API_KEY=plain-value

          export OPENROUTER_MODEL = "anthropic/claude-opus-5"
        SINGLE='single quoted'
        #EMPTY=should-be-ignored
        NOT_A_PAIR
        """
        let env = AskScreenService.parseEnv(sample)

        assert(env["OPENROUTER_API_KEY"] == "plain-value", "plain KEY=value should parse")
        assert(env["OPENROUTER_MODEL"] == "anthropic/claude-opus-5", "'export ' prefix, spaces around '=', and double quotes should all be stripped")
        assert(env["SINGLE"] == "single quoted", "single quotes should be stripped")
        assert(env["EMPTY"] == nil, "commented-out lines should be ignored")
        assert(env["NOT_A_PAIR"] == nil, "lines without '=' should be ignored")
        assert(env["MISSING_KEY"] == nil, "an absent key should be nil, not empty string")
        assert(AskScreenService.parseEnv("").isEmpty, "empty input should parse to no keys")
    }

    // MARK: - Request Body

    private static func checkRequestBody() {
        let model = "anthropic/claude-opus-5"
        let body = AskScreenService.makeRequestBody(model: model, question: "What is on screen?", imageBase64: "QUJD")

        assert(body["model"] as? String == model, "body should carry the model")
        assert(body["stream"] as? Bool == true, "body should request streaming")
        // Omitted entirely when unset — some endpoints reject the parameter rather than ignore it.
        assert(body["reasoning"] == nil, "no reasoning parameter should be sent when none is configured")

        let lowEffort = AskScreenService.makeRequestBody(model: model, question: "q", imageBase64: nil, reasoningEffort: "low")
        assert((lowEffort["reasoning"] as? [String: Any])?["effort"] as? String == "low", "a configured effort should be sent through")

        // "off"/"none"/"omit" must map to no parameter at all, not to effort "none" —
        // OpenRouter answers that with 400 "Reasoning is mandatory for this endpoint".
        for disabling in ["off", "none", "omit", "", "  NONE  "] {
            assert(AskScreenService.resolvedReasoningEffortValue(from: disabling) == nil, "\"\(disabling)\" should omit the reasoning parameter")
        }
        assert(AskScreenService.resolvedReasoningEffortValue(from: "High") == "high", "an effort level should normalise to lowercase")

        guard let messages = body["messages"] as? [[String: Any]],
              let first = messages.first,
              first["role"] as? String == "user",
              let content = first["content"] as? [[String: Any]] else {
            assertionFailure("body should be messages[0].content = [parts] with role 'user'")
            return
        }
        assert(content.count == 2, "an image ask should produce a text part and an image part")
        assert(content[0]["type"] as? String == "text", "first part should be text")
        assert(content[0]["text"] as? String == "What is on screen?", "text part should carry the question")
        assert(content[1]["type"] as? String == "image_url", "second part should be image_url")

        // OpenRouter nests the URL: messages[].content[].image_url.url — an object, not a string.
        let imageURL = (content[1]["image_url"] as? [String: Any])?["url"] as? String
        assert(imageURL == "data:image/jpeg;base64,QUJD", "image part should be a jpeg data URI wrapping the base64")

        let noImage = AskScreenService.makeRequestBody(model: model, question: "Hi", imageBase64: nil)
        let noImageContent = (noImage["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        assert(noImageContent?.count == 1, "without a capture the body should carry only the text part")

        // Personal context rides as a leading system message; absent when there is none.
        assert(messages.count == 1, "no system message when no context is configured")
        let withContext = AskScreenService.makeRequestBody(model: model, question: "q", imageBase64: nil, systemPrompt: "I write tersely.")
        let ctxMessages = withContext["messages"] as? [[String: Any]]
        assert(ctxMessages?.count == 2, "context should add exactly one message")
        assert(ctxMessages?.first?["role"] as? String == "system", "context must come first, as a system message")
        assert(ctxMessages?.first?["content"] as? String == "I write tersely.", "context should be sent verbatim")
        assert(ctxMessages?.last?["role"] as? String == "user", "the question stays the last message")
        let blankContext = AskScreenService.makeRequestBody(model: model, question: "q", imageBase64: nil, systemPrompt: "")
        assert((blankContext["messages"] as? [[String: Any]])?.count == 1, "an empty context should not add a system message")

        // The whole thing must survive JSON serialization.
        assert((try? JSONSerialization.data(withJSONObject: body)) != nil, "body should be JSON-serializable")
    }

    // MARK: - SSE Lines

    private static func checkStreamEvents() {
        assert(AskScreenService.streamEvent(from: ": OPENROUTER PROCESSING") == .ignore, "keepalive comments should be skipped")
        assert(AskScreenService.streamEvent(from: "") == .ignore, "blank lines should be skipped")
        assert(AskScreenService.streamEvent(from: "data: [DONE]") == .done, "[DONE] should terminate the stream")
        assert(AskScreenService.streamEvent(from: "data: {not json") == .ignore, "a malformed chunk should be skipped, not fatal")
        assert(AskScreenService.streamEvent(from: #"data: {"choices":[{"delta":{"content":"hi"}}]}"#) == .delta("hi"), "delta content should be extracted")
        if case .failure = AskScreenService.streamEvent(from: #"data: {"error":{"code":429,"message":"slow down"}}"#) {} else {
            assertionFailure("an in-stream error object should surface as a failure")
        }
    }
}
