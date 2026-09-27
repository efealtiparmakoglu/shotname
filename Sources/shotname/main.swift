import Foundation

let version = "1.0.0"

let usage = """
shotname \(version) — rule-based screenshot renamer (macOS)

usage:
  shotname plan --dir <DIR> [--template T] [--rules FILE] [--dry-run]
  shotname run  --dir <DIR> [--template T] [--rules FILE] [--log FILE]
  shotname undo [--log FILE] [--count N]
  shotname launchagent --dir <DIR> [--interval SECONDS] --out <FILE>
  shotname --help

template placeholders: {name} {ext} {date} {time} {index} {size} {app}
default template:       {date}-{app}-{name}

rules file lines:  match => replacement      (suffix " (regex)" for regex)

exit codes: 0 ok, 1 runtime error, 2 usage error
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("shotname: \(message)\n".utf8))
    exit(code)
}

struct Flags {
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if let next = args[safe: i + 1], !next.hasPrefix("--") {
                    values[name] = next
                    i += 2
                    continue
                }
                flags.insert(name)
            }
            i += 1
        }
    }

    func string(_ name: String, default defaultValue: String) -> String {
        values[name] ?? defaultValue
    }

    func int(_ name: String, default defaultValue: Int) -> Int {
        guard let raw = values[name], let parsed = Int(raw) else { return defaultValue }
        return parsed
    }

    func has(_ name: String) -> Bool { flags.contains(name) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(arguments.isEmpty ? 2 : 0)
}

let command = arguments[0]
let flags = Flags(Array(arguments.dropFirst()))
let directory = flags.string("dir", default: "")
let template = NameTemplate(flags.string("template", default: "{date}-{app}-{name}"))
let rules: RuleSet
if let rulesPath = flags.values["rules"] {
    do {
        rules = try RuleSet(contentsOfFile: rulesPath)
    } catch {
        fail("cannot read rules file: \(error)")
    }
} else {
    rules = RuleSet()
}
let logPath = flags.string("log", default: "\(NSHomeDirectory())/.shotname-undo.log")

switch command {
case "plan", "run":
    if directory.isEmpty { fail("--dir is required", code: 2) }
    let dryRun = command == "plan" || flags.has("dry-run")
    do {
        let actions = try planRenames(in: directory, template: template, rules: rules, dryRun: dryRun)
        for action in actions where action.changed {
            print("\(action.from) -> \(action.to)")
        }
        let changed = actions.filter { $0.changed }.count
        print("\(dryRun ? "plan" : "renamed"): \(actions.count) file(s), \(changed) changed")
        if !dryRun {
            let written = try UndoLog(path: logPath).record(actions, in: directory)
            if written > 0 { print("undo log: \(logPath) (\(written) entries)") }
        }
    } catch {
        fail("\(error)")
    }

case "undo":
    let log = UndoLog(path: logPath)
    let count = flags.int("count", default: 1)
    do {
        let undone = try log.undo(count: count)
        print("undid \(undone) rename(s)")
        if undone == 0 { exit(1) }
    } catch {
        fail("undo failed: \(error)")
    }

case "launchagent":
    guard let out = flags.values["out"] else { fail("--out is required", code: 2) }
    let interval = flags.int("interval", default: 3600)
    let logOut = flags.string("logpath", default: NSHomeDirectory() + "/.shotname-agent.log")
    let plist = launchAgentPlist(
        executable: "/usr/local/bin/shotname",
        directory: directory,
        intervalSeconds: interval,
        logPath: logOut
    )
    do {
        try plist.write(toFile: out, atomically: true, encoding: .utf8)
        print("wrote \(out) (every \(interval)s over \(directory.isEmpty ? "<dir>" : directory))")
        print("load it with: launchctl load \(out)")
    } catch {
        fail("cannot write \(out): \(error)")
    }

default:
    fail("unknown command '\(command)'", code: 2)
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
