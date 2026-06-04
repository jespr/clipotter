import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    private enum Tab: Hashable { case original, processed }

    @State private var model = TranscriptionModel()
    @State private var processing = ProcessingModel()
    @State private var settings = AppSettings()
    @State private var library = PromptLibrary()
    @State private var playback = PlaybackModel()

    @State private var promptText = PromptLibrary.starters.first?.text ?? ""
    @State private var tab: Tab = .original
    @State private var isTargeted = false
    @State private var copied = false
    @State private var showRawProcessed = false
    @State private var showTimestamps = true

    @State private var showSettings = false
    @State private var showSavePrompt = false
    @State private var newPromptName = ""
    @State private var isVideoExpanded = false
    @State private var showFileImporter = false
    @State private var selectedSegmentID: Int?
    @FocusState private var transcriptFocused: Bool

    private var hasTranscript: Bool { !model.segments.isEmpty }
    private var hasMedia: Bool { model.mediaURL != nil }

    var body: some View {
        Group {
            if isVideoExpanded && hasMedia {
                expandedLayout
            } else {
                normalLayout
            }
        }
        .onChange(of: model.mediaURL) { _, newValue in
            playback.load(newValue)
        }
        .popover(isPresented: $showSettings, arrowEdge: .top) { settingsPopover }
        .alert("Save prompt", isPresented: $showSavePrompt) {
            TextField("Name", text: $newPromptName)
            Button("Save") {
                library.save(name: newPromptName, text: promptText)
                newPromptName = ""
            }
            Button("Cancel", role: .cancel) { newPromptName = "" }
        } message: {
            Text("Save this prompt to reuse it later.")
        }
    }

    private var normalLayout: some View {
        VStack(spacing: 16) {
            header
            dropZone

            if hasMedia {
                playerView(expanded: false)
                    .frame(height: 220)
            }

            if let error = model.errorMessage {
                banner(error, color: .red, icon: "exclamationmark.triangle.fill")
            }

            if hasTranscript {
                promptSection
            }

            outputSection
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 780)
    }

    private var expandedLayout: some View {
        VStack(spacing: 12) {
            header
            playerView(expanded: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 480)
    }

    private func playerView(expanded: Bool) -> some View {
        PlayerView(player: playback.player)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isVideoExpanded.toggle() }
                } label: {
                    Image(systemName: expanded
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .help(expanded ? "Shrink video" : "Expand video")
            }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Transcript")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Backend & Claude API key")
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
                )
            if hasMedia {
                Label("Drop another file, or click to browse", systemImage: "arrow.down.doc")
                    .font(.callout)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    Text("Drop a file here, or click to browse")
                        .font(.headline)
                    Text("Transcribed locally on your Mac — nothing is uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(height: hasMedia ? 56 : 120)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .animation(.default, value: hasMedia)
        .onTapGesture { showFileImporter = true }
        .help("Click to choose a file, or drag one in")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            startTranscription(.local(url))
            return true
        } isTargeted: { isTargeted = $0 }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .audio, .audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                startTranscription(.local(url))
            }
        }
    }

    // MARK: - Prompt section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt").font(.headline)
                Spacer()
                Menu {
                    ForEach(library.prompts) { prompt in
                        Button(prompt.name) { promptText = prompt.text }
                    }
                    if !library.prompts.isEmpty {
                        Divider()
                        Menu("Delete") {
                            ForEach(library.prompts) { prompt in
                                Button(prompt.name, role: .destructive) { library.delete(prompt) }
                            }
                        }
                    }
                } label: {
                    Label("Saved prompts", systemImage: "text.badge.star")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    showSavePrompt = true
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            TextEditor(text: $promptText)
                .font(.body)
                .frame(height: 64)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))

            HStack {
                Picker("", selection: $settings.backend) {
                    ForEach(LLMBackendKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()

                if backendHint != nil {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .help(backendHint ?? "")
                }

                Spacer()

                if processing.isProcessing {
                    ProgressView().controlSize(.small)
                    Button("Cancel", role: .cancel) { processing.cancel() }
                }
                Button {
                    runPrompt()
                } label: {
                    Label("Run on transcript", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRun)
            }

            if let hint = backendHint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
    }

    // MARK: - Output (tabs)

    private var outputSection: some View {
        VStack(spacing: 8) {
            HStack {
                if hasTranscript {
                    Picker("", selection: $tab) {
                        Text("Original").tag(Tab.original)
                        Text("Processed").tag(Tab.processed)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }

                if model.isRunning {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if tab == .original && hasTranscript {
                    Button {
                        showTimestamps.toggle()
                    } label: {
                        Label("Timestamps", systemImage: showTimestamps ? "clock.fill" : "clock")
                    }
                    .help(showTimestamps ? "Hide timestamps" : "Show timestamps")
                }

                if tab == .processed && processing.hasOutput {
                    Button {
                        showRawProcessed.toggle()
                    } label: {
                        Label(showRawProcessed ? "Rendered" : "Raw",
                              systemImage: showRawProcessed ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                    }
                    .help(showRawProcessed ? "Show rendered Markdown" : "Show raw Markdown")
                }

                if model.isRunning {
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
                Button {
                    copyActiveText()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(activeText.isEmpty)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06))
                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if tab == .original {
            if model.segments.isEmpty {
                placeholderText(model.isRunning ? "Transcribing…" : "The transcript will appear here.")
            } else if showTimestamps {
                segmentList
            } else {
                TextEditor(text: .constant(model.transcript))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
        } else if processing.hasOutput {
            if showRawProcessed {
                TextEditor(text: .constant(processing.output))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                ScrollView {
                    MarkdownView(markdown: processing.output)
                        .padding(12)
                }
            }
        } else {
            placeholderText(
                processing.isProcessing ? "" :
                    (hasTranscript ? "Run a prompt to see the processed result here." : "")
            )
        }
    }

    private var segmentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.segments) { segment in
                        segmentRow(segment).id(segment.id)
                    }
                }
                .padding(8)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($transcriptFocused)
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            .onChange(of: selectedSegmentID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { transcriptFocused = true }
        }
    }

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        let playing = isCurrent(segment)
        let selected = selectedSegmentID == segment.id
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                select(segment)
            } label: {
                Text(segment.timecode)
                    .font(.system(.callout, design: .monospaced))
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Jump to \(segment.timecode)")

            Text(segment.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(segmentBackground(selected: selected, playing: playing))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func segmentBackground(selected: Bool, playing: Bool) -> Color {
        if selected { return Color.accentColor.opacity(0.28) }
        if playing { return Color.accentColor.opacity(0.12) }
        return Color.clear
    }

    /// Selects a segment and seeks the player to its start.
    private func select(_ segment: TranscriptSegment) {
        selectedSegmentID = segment.id
        playback.seek(to: segment.start)
    }

    /// Arrow-key navigation: first press jumps to the playing/first segment,
    /// subsequent presses step by `delta`.
    private func moveSelection(_ delta: Int) {
        guard !model.segments.isEmpty else { return }
        let target: Int
        if let id = selectedSegmentID, let index = model.segments.firstIndex(where: { $0.id == id }) {
            target = max(0, min(model.segments.count - 1, index + delta))
        } else {
            target = model.segments.firstIndex(where: isCurrent) ?? 0
        }
        select(model.segments[target])
    }

    private func isCurrent(_ segment: TranscriptSegment) -> Bool {
        let time = playback.currentTime
        guard time >= segment.start else { return false }
        if let next = model.segments.first(where: { $0.start > segment.start }) {
            return time < next.start
        }
        return true
    }

    private func placeholderText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .allowsHitTesting(false)
    }

    // MARK: - Settings popover

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Backend").font(.subheadline.weight(.medium))
                Picker("", selection: $settings.backend) {
                    ForEach(LLMBackendKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(AppleModel.isAvailable
                     ? "On-device runs fully locally via Apple Intelligence."
                     : (AppleModel.unavailableReason ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Claude API").font(.subheadline.weight(.medium))
                SecureField("API key (sk-ant-…)", text: $settings.claudeAPIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.claudeModel)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in your Keychain. The transcript is sent to Anthropic when this backend is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: - Derived state

    private var canRun: Bool {
        hasTranscript
        && !processing.isProcessing
        && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var backendHint: String? {
        switch settings.backend {
        case .appleOnDevice:
            return AppleModel.unavailableReason
        case .claude:
            return settings.claudeAPIKey.isEmpty ? "Add your Claude API key in Settings." : nil
        }
    }

    private var originalText: String {
        showTimestamps ? model.timestampedTranscript : model.transcript
    }

    private var activeText: String {
        tab == .original ? originalText : processing.output
    }

    private var statusText: String {
        if tab == .processed {
            if processing.isProcessing { return "Running prompt…" }
            if let error = processing.errorMessage { return error }
        }
        return model.status
    }

    // MARK: - Actions

    private func startTranscription(_ source: MediaSource) {
        processing.reset()
        tab = .original
        selectedSegmentID = nil
        model.start(source)
    }

    private func runPrompt() {
        tab = .processed
        do {
            let processor = try settings.makeProcessor()
            processing.run(systemPrompt: promptText, transcript: model.transcript, processor: processor)
        } catch {
            processing.cancel()
            processing.errorMessage = error.localizedDescription
        }
    }

    private func copyActiveText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .foregroundStyle(color)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
