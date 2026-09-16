import SwiftUI

/// The assistant, as a screen reached from More.
///
/// A drill-down like the visit detail, closed by the same back control, so the
/// three tabs are untouched. Every reply is rendered as text — there is no path
/// by which a provider's response becomes markup.
struct AssistantScreen: View {
    @Environment(FieldOperationsStore.self) private var store
    @Environment(AssistantConversation.self) private var conversation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft = ""
    @State private var isConfirmingClear = false
    @FocusState private var composerFocused: Bool

    private var isThinking: Bool { conversation.status == .thinking }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
                    disclosure
                    if let source = conversation.latestReplySource {
                        replySource(source)
                    }
                    transcript
                    statusLine
                    suggestions
                }
                .padding(AjaniTheme.Spacing.l)
            }
            .background(AjaniTheme.Palette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier(AccessibilityID.assistantScreen)
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: conversation.status) { _, _ in
                scrollToEnd(proxy)
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(AssistantCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", systemImage: "trash") {
                    isConfirmingClear = true
                }
                .accessibilityIdentifier(AccessibilityID.assistantClearAction)
                .disabled(conversation.isEmpty)
            }
        }
        // An alert rather than an action sheet: it presents reliably from a
        // pushed screen, and clearing is deliberate enough to want the question.
        .alert("Clear this conversation?", isPresented: $isConfirmingClear) {
            Button("Clear conversation", role: .destructive) {
                conversation.clear()
            }
            .accessibilityIdentifier(AccessibilityID.assistantClearConfirm)
            Button("Keep conversation", role: .cancel) {}
        } message: {
            Text("The round itself is not changed.")
        }
    }

    // MARK: - Pieces

    private var disclosure: some View {
        Text(AssistantCopy.disclosure)
            .font(.footnote)
            .foregroundStyle(AjaniTheme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Describes the most recent reply, not provider availability, so a built-in
    /// answer is never presented as model output.
    private func replySource(_ source: AssistantSource) -> some View {
        Label(source.label, systemImage: source == .live ? "sparkles" : "book.closed")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AjaniTheme.Palette.primary)
            .padding(.horizontal, AjaniTheme.Spacing.m)
            .padding(.vertical, AjaniTheme.Spacing.xs + 2)
            .background(Capsule().fill(AjaniTheme.Palette.primarySoft))
            // The identifier must follow the element it names, or it lands on a
            // container that carries no value.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.assistantReplySource)
            .accessibilityLabel("Latest reply source")
            .accessibilityValue(source.label)
    }

    @ViewBuilder
    private var transcript: some View {
        if conversation.isEmpty {
            EmptyStateView(
                symbolName: "bubble.left.and.text.bubble.right",
                title: "Ask about the round",
                message: AssistantCopy.welcome
            )
            .ajaniCard()
            .accessibilityIdentifier(AccessibilityID.assistantWelcome)
        } else {
            VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
                ForEach(conversation.messages) { message in
                    MessageBubble(message: message).id(message.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Assistant conversation")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if conversation.status == .thinking {
            Label("Finding an answer\u{2026}", systemImage: "ellipsis.bubble")
                .font(.footnote)
                .foregroundStyle(AjaniTheme.Palette.textSecondary)
                .accessibilityIdentifier(AccessibilityID.assistantStatus)
                .id(Self.statusAnchor)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(title: "Try asking")

            VStack(spacing: AjaniTheme.Spacing.s) {
                ForEach(AssistantCopy.suggestedQuestions, id: \.self) { question in
                    Button {
                        send(question)
                    } label: {
                        HStack(spacing: AjaniTheme.Spacing.m) {
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(AjaniTheme.Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.forward")
                                .font(.footnote)
                                .foregroundStyle(AjaniTheme.Palette.primary)
                                .accessibilityHidden(true)
                        }
                        .padding(AjaniTheme.Spacing.m)
                        .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)
                        .background(
                            RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                                .fill(AjaniTheme.Palette.surfaceMuted)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isThinking)
                    .accessibilityIdentifier(AccessibilityID.assistantSuggestion(question))
                    .accessibilityHint("Asks this question")
                }
            }
        }
        .ajaniCard()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.s) {
            Text("Ask your own question")
                .font(.footnote)
                .foregroundStyle(AjaniTheme.Palette.textSecondary)

            HStack(alignment: .bottom, spacing: AjaniTheme.Spacing.m) {
                TextField("Ask about the round", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(AjaniTheme.Palette.textPrimary)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .padding(AjaniTheme.Spacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                            .fill(AjaniTheme.Palette.surfaceMuted)
                    )
                    .accessibilityIdentifier(AccessibilityID.assistantInput)
                    .accessibilityLabel("Ask your own question")

                Button {
                    send(draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: AjaniTheme.Layout.minimumTapTarget, height: AjaniTheme.Layout.minimumTapTarget)
                }
                .buttonStyle(AjaniSendButtonStyle())
                .disabled(!canSend)
                .accessibilityIdentifier(AccessibilityID.assistantSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, AjaniTheme.Spacing.l)
        .padding(.vertical, AjaniTheme.Spacing.m)
        .background(.bar)
    }

    // MARK: - Behaviour

    private static let statusAnchor = "assistant.status.anchor"

    private func send(_ question: String) {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !isThinking else { return }

        draft = ""
        let round = store.assistantRound
        Task { await conversation.ask(asked, round: round) }
    }

    /// Brings the newest exchange into view without taking focus from the input.
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let scroll = {
            if conversation.status == .thinking {
                proxy.scrollTo(Self.statusAnchor, anchor: .bottom)
            } else if let last = conversation.messages.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }

        if reduceMotion {
            scroll()
        } else {
            withAnimation(.easeOut(duration: 0.2), scroll)
        }
    }
}

/// One message, attributed to whoever said it.
private struct MessageBubble: View {
    let message: AssistantMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.xs) {
            Text(author)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AjaniTheme.Palette.textSecondary)

            Text(message.text)
                .font(.body)
                .foregroundStyle(AjaniTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AjaniTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                .fill(isUser ? AjaniTheme.Palette.primarySoft : AjaniTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                .strokeBorder(AjaniTheme.Palette.separator, lineWidth: isUser ? 0 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isUser ? AccessibilityID.assistantUserMessage : AccessibilityID.assistantReply)
    }

    /// Each message keeps its own source, so a later live reply never relabels an
    /// earlier built-in one.
    private var author: String {
        guard !isUser else { return "You" }
        guard let source = message.source else { return "Assistant" }
        return "Assistant · \(source.label)"
    }
}

/// The send control: square, and muted when there is nothing to send.
private struct AjaniSendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? AjaniTheme.Palette.surface : AjaniTheme.Palette.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                    .fill(isEnabled ? AjaniTheme.Palette.primary : AjaniTheme.Palette.surfaceMuted)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
    }
}

#Preview {
    NavigationStack {
        AssistantScreen()
    }
    .environment(FieldOperationsStore())
    .environment(AssistantConversation())
}
