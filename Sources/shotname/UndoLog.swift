import Foundation

/// Append-only log of renames, one JSON object per line, so a run can be
/// undone. Deliberately boring: plain text you can read with `cat`.
public struct UndoLog {
    public struct Entry: Codable, Equatable {
        public let directory: String
        public let from: String
        public let to: String
        public let at: String

        public init(directory: String, from: String, to: String, at: String) {
            self.directory = directory
            self.from = from
            self.to = to
            self.at = at
        }
    }

    public let path: String

    public init(path: String) {
        self.path = path
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    public static func timestamp(_ date: Date = Date()) -> String {
        stamp.string(from: date)
    }

    /// Append entries for the actions that changed something.
    @discardableResult
    public func record(_ actions: [RenameAction], in directory: String, at date: Date = Date()) throws -> Int {
        let changed = actions.filter { $0.changed }
        guard !changed.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var text = ""
        for action in changed {
            let entry = Entry(directory: directory, from: action.from, to: action.to,
                              at: UndoLog.timestamp(date))
            let line = String(data: try encoder.encode(entry), encoding: .utf8) ?? "{}"
            text += line + "\n"
        }
        let manager = FileManager.default
        if !manager.fileExists(atPath: path) {
            _ = manager.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw PlanError.unreadable(path)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        return changed.count
    }

    public func entries() -> [Entry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? decoder.decode(Entry.self, from: Data(line.utf8))
            }
    }

    /// Undo the last `count` entries (newest first). Returns how many
    /// renames were actually reversed.
    @discardableResult
    public func undo(count: Int) throws -> Int {
        let all = entries()
        guard !all.isEmpty else { return 0 }
        let windowStart = all.count > count ? all.count - count : 0
        let manager = FileManager.default
        var undone = 0
        // Entries the window could not undo (the file moved on) stay in the
        // log; entries we did undo are dropped, older ones are untouched.
        var keep = Array(all[0..<windowStart])
        for index in windowStart..<all.count {
            let entry = all[index]
            let from = URL(fileURLWithPath: entry.directory).appendingPathComponent(entry.to)
            let to = URL(fileURLWithPath: entry.directory).appendingPathComponent(entry.from)
            if manager.fileExists(atPath: from.path) {
                if manager.fileExists(atPath: to.path) {
                    try manager.removeItem(at: to)
                }
                try manager.moveItem(at: from, to: to)
                undone += 1
            } else {
                keep.append(entry)
            }
        }
        let remaining = keep
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var text = ""
        for entry in remaining {
            let line = String(data: try encoder.encode(entry), encoding: .utf8) ?? "{}"
            text += line + "\n"
        }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return undone
    }
}

/// A launchd plist that runs shotname on a schedule.
public func launchAgentPlist(
    executable: String,
    directory: String,
    intervalSeconds: Int,
    logPath: String
) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.shotname.agent</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(executable)</string>
            <string>run</string>
            <string>--dir</string>
            <string>\(directory)</string>
        </array>
        <key>StartInterval</key>
        <integer>\(intervalSeconds)</integer>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardOutPath</key>
        <string>\(logPath)</string>
        <key>StandardErrorPath</key>
        <string>\(logPath)</string>
    </dict>
    </plist>
    """
}
