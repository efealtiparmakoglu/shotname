import Foundation

/// Builds new file names from a template.
///
/// Placeholders: `{name}` original stem, `{ext}` extension, `{date}`
/// creation date (yyyy-MM-dd), `{time}` (HHmmss), `{index}` running
/// number, `{size}` bytes, `{app}` best-guess source app.
public struct NameTemplate {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public struct Context {
        public var stem: String
        public var ext: String
        public var date: Date
        public var index: Int
        public var size: Int
        public var app: String
    }

    public func render(_ context: Context) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: context.date)
        formatter.dateFormat = "HHmmss"
        let time = formatter.string(from: context.date)

        var out = ""
        var iterator = raw.makeIterator()
        while let ch = iterator.next() {
            guard ch == "{" else {
                out.append(ch)
                continue
            }
            var key = ""
            var closed = false
            while let next = iterator.next() {
                if next == "}" {
                    closed = true
                    break
                }
                key.append(next)
            }
            guard closed else {
                out.append("{")
                out.append(key)
                out.append("}")
                continue
            }
            switch key {
            case "name": out.append(context.stem)
            case "ext": out.append(context.ext)
            case "date": out.append(date)
            case "time": out.append(time)
            case "index": out.append(String(format: "%03d", context.index))
            case "size": out.append(String(context.size))
            case "app": out.append(context.app)
            default:
                out.append("{")
                out.append(key)
                out.append("}")
            }
        }
        // an empty template still has to produce a file name
        return out.isEmpty ? context.stem : out
    }
}

/// Guess which app a screenshot came from, from macOS metadata when
/// available, otherwise from the file name itself.
public func inferApp(from fileName: String) -> String {
    let patterns: [(String, String)] = [
        ("Screenshot (\\d{4}-\\d{2}-\\d{2}) at (\\d{2})[.:](\\d{2})[.:](\\d{2}).*", "Screenshot"),
        ("Screen Shot (\\d{4}-\\d{2}-\\d{2}) at (\\d{2})[.:](\\d{2})[.:](\\d{2}).*", "Screen Shot"),
        ("(?i)chrome", "Chrome"),
        ("(?i)safari", "Safari"),
        ("(?i)firefox", "Firefox"),
        ("(?i)slack", "Slack"),
        ("(?i)discord", "Discord"),
        ("(?i)terminal", "Terminal"),
        ("(?i)notes", "Notes"),
    ]
    for (pattern, label) in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)) != nil {
            return label
        }
    }
    return "unknown"
}

/// One planned rename.
public struct RenameAction: Equatable {
    public let from: String
    public let to: String
    public let changed: Bool
}

public enum PlanError: Error, CustomStringConvertible {
    case directoryMissing(String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .directoryMissing(let path): return "not a directory: \(path)"
        case .unreadable(let path): return "cannot read directory: \(path)"
        }
    }
}

/// Build the rename plan for a directory.
public func planRenames(
    in directory: String,
    template: NameTemplate,
    rules: RuleSet,
    dryRun: Bool
) throws -> [RenameAction] {
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: directory, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw PlanError.directoryMissing(directory)
    }
    guard let entries = try? manager.contentsOfDirectory(atPath: directory) else {
        throw PlanError.unreadable(directory)
    }

    let imageExtensions = Set(["png", "jpg", "jpeg", "heic", "webp", "tiff"])
    let sorted = entries.sorted()
    var used: Set<String> = []
    var actions: [RenameAction] = []
    var index = 1

    for entry in sorted {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(entry)
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent
        guard imageExtensions.contains(ext) else { continue }

        let date = values?.creationDate ?? Date(timeIntervalSince1970: 0)
        let size = values?.fileSize ?? 0
        var candidate = template.render(NameTemplate.Context(
            stem: stem,
            ext: ext,
            date: date,
            index: index,
            size: size,
            app: inferApp(from: entry)
        ))
        candidate = rules.transform(candidate)
        if candidate.isEmpty { candidate = stem }
        // a template that omits {ext} must not strip the file's extension
        if (candidate as NSString).pathExtension.isEmpty && !ext.isEmpty {
            candidate = "\(candidate).\(ext)"
        }

        // never plan two files onto the same name
        var unique = candidate
        var counter = 2
        while used.contains(unique) {
            let base = (candidate as NSString).deletingPathExtension
            let extPart = (candidate as NSString).pathExtension
            unique = extPart.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(extPart)"
            counter += 1
        }
        used.insert(unique)
        index += 1

        if unique == entry {
            actions.append(RenameAction(from: entry, to: entry, changed: false))
            continue
        }
        if !dryRun {
            let from = url
            let to = URL(fileURLWithPath: directory).appendingPathComponent(unique)
            try manager.moveItem(at: from, to: to)
        }
        actions.append(RenameAction(from: entry, to: unique, changed: true))
    }
    return actions
}
