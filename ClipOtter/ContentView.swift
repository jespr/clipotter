import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    private enum Tab: Hashable { case original, processed }

    @State private var model = TranscriptionModel()
    @State private var processing = ProcessingModel()
    @State private var settings = AppSettings()
    @State private var library = PromptLibrary()
    @State private var playback = PlaybackModel()
    @State private var sessions = SessionStore()

    @State private var promptText = PromptLibrary.starters.first?.text ?? ""
    @State private var tab: Tab = .original
    @State private var isTargeted = false
    @State private var copied = false
    @State private var sessionSaved = false
    @State private var showRawProcessed = false
    @State private var showTimestamps = true

    @State private var showSettings = false
    @State private var showSessions = false
    @State private var showSavePrompt = false
    @State private var newPromptName = ""
    @State private var isVideoExpanded = false
    @State private var showFileImporter = false
    @State private var selectedSegmentID: Int?
    @State private var hoveredSegmentID: Int?
    @State private var starred: Set<Int> = []
    /// Signature of the last saved/loaded state; compared against `currentSignature`
    /// to know whether there are unsaved changes. `nil` means never saved this session.
    @State private var savedSignature: Int?
    @State private var starToast: String?
    @State private var statusTick = 0
    @State private var searchText = ""
    /// Debounced copy of `searchText` that actually drives filtering/highlighting,
    /// so typing stays smooth instead of re-filtering on every keystroke.
    @State private var searchQuery = ""
    @State private var searchDebounce: Task<Void, Never>?
    @FocusState private var transcriptFocused: Bool
    @FocusState private var searchFocused: Bool

    /// Rotating "working" lines shown while transcribing.
    private static let workingPhrases = [
        "Diving in…",
        "Listening closely…",
        "Catching every word…",
        "Tuning my whiskers…",
        "Almost got it…"
    ]

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
        .background(WindowCloseGuard(
            hasUnsavedChanges: { hasTranscript && savedSignature != currentSignature },
            onSave: { saveSession() }
        ))
        .onChange(of: model.mediaURL) { _, newValue in
            playback.load(newValue)
        }
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            if model.isRunning { statusTick &+= 1 }
        }
        .sheet(isPresented: $showSessions) {
            SessionsSheet(store: sessions, onLoad: loadSession)
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
        .tint(.orange)
    }

    private var normalLayout: some View {
        VStack(spacing: 16) {
            header

            if hasMedia {
                HStack(alignment: .top, spacing: 16) {
                    mediaColumn
                    transcriptColumn
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dropZone
                if let error = model.errorMessage {
                    banner(error, color: .red, icon: "exclamationmark.triangle.fill")
                }
            }
        }
        .padding(20)
        .frame(minWidth: 1000, minHeight: 620)
    }

    /// Left side: drop target + video player.
    private var mediaColumn: some View {
        VStack(spacing: 12) {
            dropZone
            playerView(expanded: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.errorMessage {
                banner(error, color: .red, icon: "exclamationmark.triangle.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Right side: prompt + transcript/processed output.
    private var transcriptColumn: some View {
        VStack(spacing: 12) {
            if hasTranscript {
                promptSection
            }
            outputSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text("Transcript")
                .font(.title2.weight(.semibold))
            Spacer()
            if hasTranscript {
                Button {
                    saveSession()
                } label: {
                    Label(sessionSaved ? "Saved" : "Save session",
                          systemImage: sessionSaved ? "checkmark" : "bookmark")
                }
                .help("Save session — restore transcript, stars, and processed output later")
            }
            Button {
                showSessions = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("Saved sessions")
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
                .foregroundStyle(isTargeted ? Color.orange : Color.secondary.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isTargeted ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.05))
                )
            if hasMedia {
                Label(isTargeted ? "Yes! Drop it 🦦" : "Toss me another file 🦦", systemImage: "arrow.down.doc")
                    .font(.callout)
                    .foregroundStyle(isTargeted ? Color.orange : .secondary)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isTargeted ? Color.orange : .secondary)
                    Text(isTargeted ? "Yes! Drop it 🦦" : "Feed me a file and I'll dive in 🦦")
                        .font(.headline)
                    Text("Drop a video or audio file, or click to browse — it all stays on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, minHeight: hasMedia ? 56 : 0, maxHeight: hasMedia ? 56 : .infinity)
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
                SegmentedPills(selection: $settings.backend, options: LLMBackendKind.allCases.map { ($0.label, $0) })

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
                    SegmentedPills(selection: $tab, options: [("Original", Tab.original), ("Processed", Tab.processed)])
                }

                if model.isRunning {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if tab == .original && !starred.isEmpty {
                    Menu {
                        Button { copyStarredText() } label: { Label("Copy text", systemImage: "doc.on.doc") }
                        Button { copyStarredImage() } label: { Label("Copy image", systemImage: "photo.on.rectangle") }
                        Divider()
                        Button(role: .destructive) { starred.removeAll() } label: { Label("Clear stars", systemImage: "star.slash") }
                    } label: {
                        Label("\(starred.count)", systemImage: "star.fill")
                    }
                    .fixedSize()
                    .tint(.yellow)
                    .help("Export starred lines")
                }

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
                if processing.hasOutput && hasTranscript {
                    Button {
                        copyProcessedAndOriginal()
                    } label: {
                        Label("Copy both", systemImage: "doc.on.doc.fill")
                    }
                    .help("Copy processed result followed by the original transcript")
                }
                Button {
                    copyActiveText()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(activeText.isEmpty)

                Button {
                    saveBundle()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasTranscript && !processing.hasOutput)
                .help("Save transcript, processed Markdown, and starred frames to a folder")
            }

            if tab == .original && hasTranscript {
                searchBar
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06))
                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            // ⌘F focuses the transcript search field.
            Button("") { if tab == .original && hasTranscript { searchFocused = true } }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcript", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onChange(of: searchText) { _, newValue in
                    searchDebounce?.cancel()
                    searchDebounce = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        searchQuery = newValue
                    }
                }
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("\(visibleSegments.count) line\(visibleSegments.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }

    @ViewBuilder
    private var contentArea: some View {
        if tab == .original {
            if model.segments.isEmpty {
                placeholderText(model.isRunning ? "" : "Nothing here yet — toss me a file.")
            } else if !trimmedSearch.isEmpty {
                if visibleSegments.isEmpty {
                    placeholderText("No lines match “\(trimmedSearch)”.")
                } else {
                    segmentList
                }
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
                    (hasTranscript ? "Pick a prompt, hit Run, and I'll rework it here." : "")
            )
        }
    }

    private var segmentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleSegments) { segment in
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
            .onAppear { if !searchFocused { transcriptFocused = true } }
        }
    }

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        let playing = isCurrent(segment)
        let selected = selectedSegmentID == segment.id
        let hovered = hoveredSegmentID == segment.id
        let isStarred = starred.contains(segment.id)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                toggleStar(segment)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(isStarred ? "Unstar this line" : "Star this line")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(segment.timecode)
                    .font(.system(.callout, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.orange)
                Text(highlighted(segment.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { select(segment) }
            .help("Jump to \(segment.timecode)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(segmentBackground(selected: selected, playing: playing, hovered: hovered))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { inside in
            if inside {
                hoveredSegmentID = segment.id
            } else if hoveredSegmentID == segment.id {
                hoveredSegmentID = nil
            }
        }
    }

    private func segmentBackground(selected: Bool, playing: Bool, hovered: Bool) -> Color {
        if selected { return Color.orange.opacity(0.28) }
        if playing { return Color.orange.opacity(0.12) }
        if hovered { return Color.secondary.opacity(0.12) }
        return Color.clear
    }

    /// Selects a segment and seeks the player to its start.
    private func select(_ segment: TranscriptSegment) {
        selectedSegmentID = segment.id
        playback.seek(to: segment.start)
    }

    private var starredSegments: [TranscriptSegment] {
        model.segments.filter { starred.contains($0.id) }
    }

    private func toggleStar(_ segment: TranscriptSegment) {
        if starred.contains(segment.id) {
            starred.remove(segment.id)
        } else {
            starred.insert(segment.id)
        }
    }

    private func copyStarredText() {
        let segments = starredSegments
        guard !segments.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(StarredExport.text(for: segments), forType: .string)
        toast("Copied starred text — ⌘V into your LLM")
    }

    private func copyStarredImage() {
        let segments = starredSegments
        guard !segments.isEmpty else { return }
        toast("Capturing frames…")
        Task {
            if let image = await StarredExport.image(mediaURL: model.mediaURL, segments: segments) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                toast("Starred image copied — ⌘V into your LLM")
            } else {
                toast("Couldn't build the image")
            }
        }
    }

    private func toast(_ message: String) {
        starToast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if starToast == message { starToast = nil }
        }
    }

    /// Arrow-key navigation: first press jumps to the playing/first segment,
    /// subsequent presses step by `delta`.
    private func moveSelection(_ delta: Int) {
        let segments = visibleSegments
        guard !segments.isEmpty else { return }
        let target: Int
        if let id = selectedSegmentID, let index = segments.firstIndex(where: { $0.id == id }) {
            target = max(0, min(segments.count - 1, index + delta))
        } else {
            target = segments.firstIndex(where: isCurrent) ?? 0
        }
        select(segments[target])
    }

    /// Debounced search query with surrounding whitespace trimmed.
    private var trimmedSearch: String {
        searchQuery.trimmingCharacters(in: .whitespaces)
    }

    private func clearSearch() {
        searchDebounce?.cancel()
        searchText = ""
        searchQuery = ""
        searchFocused = false
    }

    /// Segments shown in the list — all of them, or only those matching the search.
    private var visibleSegments: [TranscriptSegment] {
        let query = trimmedSearch
        guard !query.isEmpty else { return model.segments }
        return model.segments.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    /// A segment's text with every case-insensitive match of the search query highlighted.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let query = trimmedSearch
        guard !query.isEmpty else { return attributed }
        var searchStart = text.startIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow.opacity(0.45)
                attributed[attrRange].foregroundColor = .primary
            }
            searchStart = range.upperBound
        }
        return attributed
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
                SegmentedPills(selection: $settings.backend, options: LLMBackendKind.allCases.map { ($0.label, $0) })
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

    /// Hash of everything a saved session captures. Compared against `savedSignature`
    /// to detect unsaved changes. (Hasher is seeded per app run — fine for in-run compares.)
    private var currentSignature: Int {
        var hasher = Hasher()
        hasher.combine(model.segments)
        hasher.combine(starred)
        hasher.combine(processing.output)
        hasher.combine(promptText)
        return hasher.finalize()
    }

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
        if let starToast { return starToast }
        if tab == .processed {
            if processing.isProcessing { return "Thinking it over…" }
            if let error = processing.errorMessage { return error }
        }
        if model.isRunning {
            // Keep the (rare) one-time model-download message visible; otherwise rotate.
            if model.status.localizedCaseInsensitiveContains("model") { return model.status }
            return Self.workingPhrases[statusTick % Self.workingPhrases.count]
        }
        return model.status
    }

    // MARK: - Actions

    private func saveSession() {
        let mediaName = model.mediaURL
            .map { $0.deletingPathExtension().lastPathComponent } ?? ""
        let session = SavedSession(
            createdAt: Date(),
            mediaURL: model.mediaURL,
            mediaName: mediaName,
            segments: model.segments,
            starred: Array(starred),
            processedOutput: processing.output,
            promptText: promptText
        )
        sessions.save(session)
        savedSignature = currentSignature
        toast("Session saved")
        sessionSaved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            sessionSaved = false
        }
    }

    private func loadSession(_ session: SavedSession) {
        processing.reset()
        tab = .original
        selectedSegmentID = nil
        starToast = nil
        clearSearch()
        starred = Set(session.starred)
        promptText = session.promptText
        processing.output = session.processedOutput
        let mediaURL: URL? = session.mediaURL.flatMap { url in
            FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        model.restore(segments: session.segments, mediaURL: mediaURL)
        savedSignature = currentSignature
    }

    private func startTranscription(_ source: MediaSource) {
        processing.reset()
        tab = .original
        selectedSegmentID = nil
        starred.removeAll()
        starToast = nil
        clearSearch()
        savedSignature = nil
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

    private func copyProcessedAndOriginal() {
        let combined = """
        \(processing.output)

        Stemming from this original transcript from a video:
        \(model.transcript)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        toast("Copied processed + transcript")
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

    /// Pick a folder, then write the original transcript, the processed Markdown,
    /// and (if any lines are starred) a contact sheet of those frames into it.
    private func saveBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose where to save the transcript and processed Markdown."
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let segments = starredSegments
        let transcript = model.transcript
        let processed = processing.output
        toast("Saving…")
        Task {
            let image = segments.isEmpty
                ? nil
                : await StarredExport.image(mediaURL: model.mediaURL, segments: segments)
            do {
                let bundle = TranscriptExport.Bundle(
                    transcript: transcript,
                    processed: processed,
                    image: image
                )
                let written = try TranscriptExport.write(bundle, to: directory)
                if written.isEmpty {
                    toast("Nothing to save yet")
                } else {
                    toast("Saved \(written.joined(separator: ", "))")
                }
            } catch {
                toast("Couldn't save: \(error.localizedDescription)")
            }
        }
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .foregroundStyle(color)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact orange-pill segmented control — the branded look used across the app and website.
struct SegmentedPills<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = selection == option.1
                Text(option.0)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .background(selected ? Color.orange : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.1 }
            }
        }
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }
}
