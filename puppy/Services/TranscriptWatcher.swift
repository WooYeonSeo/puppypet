import Foundation

/// Watches Claude Code state and surfaces three signals:
///   * `onThinkingChanged(busy)`           — any live session has status=="busy"
///                                            (from ~/.claude/sessions/*.json).
///   * `onWaitingApprovalChanged(waiting)` — any live session paused on a
///                                            permission prompt.
///   * `onTurnEnded(prompt, body)`         — an assistant turn just hit
///                                            `end_turn` in a jsonl transcript.
///
/// Thinking/approval state come from the session-state JSON files because
/// Claude Code itself maintains them; deriving them from jsonl parsing left
/// stuck states when end_turn was missed.
///
/// Self-contained: no external hook setup is required.
@MainActor
final class TranscriptWatcher {
    private let projectsDir: URL
    private let sessionsDir: URL
    private var timer: Timer?
    private var fileOffsets: [String: UInt64] = [:]
    private var notifiedAssistantUUIDs: Set<String> = []
    private var lastThinking: Bool = false
    private var lastWaitingApproval: Bool = false

    /// Fires on the main actor when overall thinking state flips.
    var onThinkingChanged: ((Bool) -> Void)?
    /// Fires on the main actor when an assistant turn ends. Args:
    /// `(lastUserPrompt, assistantTextBody)`.
    var onTurnEnded: ((String?, String?) -> Void)?
    /// Fires when any Claude Code session pauses for a permission prompt
    /// (status == "waiting" && waitingFor starts with "approve").
    var onWaitingApprovalChanged: ((Bool) -> Void)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsDir = home.appendingPathComponent(".claude/projects")
        self.sessionsDir = home.appendingPathComponent(".claude/sessions")
    }

    func start() {
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        seedOffsets()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Scan

    private func seedOffsets() {
        for url in jsonlFiles() {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                fileOffsets[url.path] = UInt64(size)
            }
        }
    }

    private func jsonlFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files
    }

    private func scan() {
        for url in jsonlFiles() {
            processFile(at: url.path)
        }
        publishSessionStates()
    }

    /// `~/.claude/sessions/*.json`을 단일 진실 소스로 사용해 두 상태를 동시에 산출.
    ///   • status=="busy" 인 세션이 하나라도 있으면 → isThinking (💭)
    ///   • status=="waiting" + waitingFor가 "approve"로 시작 → isWaitingApproval (🔔)
    /// Claude Code가 직접 갱신하는 파일이라 jsonl 추론보다 stuck 위험이 적음.
    private func publishSessionStates() {
        var anyBusy = false
        var anyWaiting = false
        let cutoffMs = Date().timeIntervalSince1970 * 1000 - 60_000  // 60s stale window
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        )) ?? []
        for url in entries where url.pathExtension == "json" {
            // `active.json` is a registry, not a session.
            if url.lastPathComponent == "active.json" { continue }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let status = obj["status"] as? String ?? ""
            let waitingFor = obj["waitingFor"] as? String ?? ""
            let updatedAt = obj["updatedAt"] as? Double ?? 0
            if updatedAt < cutoffMs { continue }
            if status == "waiting" && waitingFor.lowercased().hasPrefix("approve") {
                anyWaiting = true
            } else if status == "busy" {
                anyBusy = true
            }
        }
        if anyBusy != lastThinking {
            lastThinking = anyBusy
            onThinkingChanged?(anyBusy)
        }
        if anyWaiting != lastWaitingApproval {
            lastWaitingApproval = anyWaiting
            onWaitingApprovalChanged?(anyWaiting)
        }
    }

    private func processFile(at path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            fileOffsets[path] = 0
            return
        }
        defer { try? handle.close() }

        let lastOffset = fileOffsets[path] ?? 0
        let endOffset = (try? handle.seekToEnd()) ?? 0

        if endOffset < lastOffset {
            fileOffsets[path] = endOffset
            return
        }
        if endOffset == lastOffset { return }

        do {
            try handle.seek(toOffset: lastOffset)
        } catch {
            fileOffsets[path] = endOffset
            return
        }

        let data = handle.readDataToEndOfFile()
        let newOffset = lastOffset + UInt64(data.count)
        fileOffsets[path] = newOffset

        guard let chunk = String(data: data, encoding: .utf8) else { return }
        let trailingNewline = chunk.hasSuffix("\n")
        let parts = chunk.split(separator: "\n", omittingEmptySubsequences: false)
        let completeLines = trailingNewline ? Array(parts) : Array(parts.dropLast())

        for line in completeLines where !line.isEmpty {
            handleLine(String(line), inFile: path)
        }
    }

    // MARK: - Parse

    /// jsonl 라인은 end_turn 감지(완료 알림 트리거)에만 사용. 그 외 상태는
    /// session JSON에서 가져오므로 user 라인 추적은 불필요.
    private func handleLine(_ line: String, inFile path: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        guard (obj["type"] as? String) == "assistant",
              let message = obj["message"] as? [String: Any],
              (message["stop_reason"] as? String) == "end_turn"
        else { return }

        let uuid = (obj["uuid"] as? String) ?? UUID().uuidString
        guard !notifiedAssistantUUIDs.contains(uuid) else { return }
        notifiedAssistantUUIDs.insert(uuid)
        if notifiedAssistantUUIDs.count > 500 {
            notifiedAssistantUUIDs.removeAll()
        }

        let prompt = lastUserPrompt(in: path)
        let body = extractAssistantText(from: message)
        onTurnEnded?(prompt, body)
    }

    private func extractAssistantText(from message: [String: Any]) -> String? {
        guard let content = message["content"] as? [[String: Any]] else { return nil }
        let texts = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
        let joined = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private func lastUserPrompt(in path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let cap: UInt64 = 1_048_576
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > cap ? size - cap : 0
        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if start > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }

        var found: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            guard (obj["type"] as? String) == "user",
                  (obj["isMeta"] as? Bool) != true,
                  let message = obj["message"] as? [String: Any]
            else { continue }

            let content = message["content"]
            var prompt: String?
            if let str = content as? String {
                prompt = str
            } else if let arr = content as? [[String: Any]],
                      !arr.isEmpty,
                      arr.allSatisfy({ ($0["type"] as? String) == "text" }) {
                prompt = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
            }
            if let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                found = p
            }
        }
        return found
    }

}
