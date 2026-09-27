import Foundation

/// One renaming rule: a pattern to match and a replacement template.
/// Patterns are plain substrings or simple `*` wildcards so a rules file
/// stays readable without a regular expression dialect.
public struct Rule: Equatable {
    public let match: String
    public let replace: String
    public let isRegex: Bool

    public init(match: String, replace: String, isRegex: Bool = false) {
        self.match = match
        self.replace = replace
        self.isRegex = isRegex
    }

    /// Parse one line of a rules file: `match => replace` or
    /// `match => replace (regex)`.
    public static func parse(_ line: String) -> Rule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let parts = trimmed.components(separatedBy: "=>")
        guard parts.count == 2 else { return nil }
        let match = parts[0].trimmingCharacters(in: .whitespaces)
        var replace = parts[1].trimmingCharacters(in: .whitespaces)
        var isRegex = false
        if replace.hasSuffix("(regex)") {
            isRegex = true
            replace = String(replace.dropLast("(regex)".count))
                .trimmingCharacters(in: .whitespaces)
        }
        guard !match.isEmpty, !replace.isEmpty else { return nil }
        return Rule(match: match, replace: replace, isRegex: isRegex)
    }

    /// Apply this rule to a name, or return nil when it does not match.
    public func apply(to name: String) -> String? {
        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: match) else { return nil }
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            let matches = regex.matches(in: name, range: range)
            guard let matchRange = matches.first?.range else { return nil }
            guard let swiftRange = Range(matchRange, in: name) else { return nil }
            return regex.stringByReplacingMatches(in: name, range: range, withTemplate: replace)
                as String? ?? String(name[swiftRange])
        }
        guard name.contains(match) else { return nil }
        return name.replacingOccurrences(of: match, with: replace)
    }
}

/// The ordered rule set used for a run.
public struct RuleSet {
    public let rules: [Rule]

    public init(rules: [Rule] = []) {
        self.rules = rules
    }

    public init(contentsOfFile path: String) throws {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        self.rules = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Rule.parse(String($0)) }
    }

    /// Apply the first matching rule; names with no match pass through.
    public func transform(_ name: String) -> String {
        for rule in rules {
            if let result = rule.apply(to: name) {
                return result
            }
        }
        return name
    }
}
