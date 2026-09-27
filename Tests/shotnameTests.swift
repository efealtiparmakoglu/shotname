import XCTest
@testable import shotname

final class RuleTests: XCTestCase {
    func testParsesSimpleRule() {
        let rule = Rule.parse("old => new")
        XCTAssertEqual(rule, Rule(match: "old", replace: "new"))
    }

    func testSkipsCommentsAndBlanks() {
        XCTAssertNil(Rule.parse("# a comment"))
        XCTAssertNil(Rule.parse("   "))
        XCTAssertNil(Rule.parse("no arrow here"))
        XCTAssertNil(Rule.parse("=> missing match"))
        XCTAssertNil(Rule.parse("missing replace =>"))
    }

    func testRegexFlag() {
        let rule = Rule.parse("Shot (\\d+) => shot-$1 (regex)")
        XCTAssertEqual(rule?.isRegex, true)
        XCTAssertEqual(rule?.apply(to: "Shot 42.png"), "shot-42.png")
    }

    func testAppliesFirstMatchingRule() {
        let rules = RuleSet(rules: [
            Rule(match: "Screenshot", replace: "screen"),
            Rule(match: "screen", replace: "never-reached")
        ])
        XCTAssertEqual(rules.transform("Screenshot 2026.png"), "screen 2026.png")
    }

    func testUnmatchedNamesPassThrough() {
        let rules = RuleSet(rules: [Rule(match: "Screenshot", replace: "screen")])
        XCTAssertEqual(rules.transform("photo.png"), "photo.png")
    }

    func testRulesFileLoading() throws {
        let path = NSTemporaryDirectory() + "/shotname-rules-\(UUID().uuidString).txt"
        try """
        # comment
        Screenshot => screen
        IMG => capture (regex)
        """.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let rules = try RuleSet(contentsOfFile: path)
        XCTAssertEqual(rules.rules.count, 2)
        XCTAssertEqual(rules.transform("Screenshot 1.png"), "screen 1.png")
        XCTAssertEqual(rules.transform("IMG_9.png"), "capture_9.png")
    }
}

final class TemplateTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_512_496) // 2026-09-27T12:34:56Z

    func testRendersEveryPlaceholder() {
        let template = NameTemplate("{date}_{time}_{index}_{app}_{name}.{ext}")
        let out = template.render(NameTemplate.Context(
            stem: "Screenshot", ext: "png", date: date, index: 7, size: 42, app: "Chrome"))
        XCTAssertTrue(out.hasPrefix("2026-09-27_"), "got \(out)")
        XCTAssertTrue(out.contains("_007_Chrome_Screenshot.png"), "got \(out)")
    }

    func testUnknownPlaceholderIsLeftAlone() {
        let template = NameTemplate("{date}-{nope}")
        XCTAssertTrue(template.render(NameTemplate.Context(
            stem: "a", ext: "png", date: date, index: 1, size: 0, app: "x"))
            .hasSuffix("-{nope}"))
    }

    func testEmptyTemplateFallsBackToStem() {
        let template = NameTemplate("")
        XCTAssertEqual(template.render(NameTemplate.Context(
            stem: "fallback", ext: "png", date: date, index: 1, size: 0, app: "x")),
            "fallback")
    }
}

final class AppInferenceTests: XCTestCase {
    func testMacOSScreenshotNames() {
        XCTAssertEqual(inferApp(from: "Screenshot 2026-09-27 at 14.05.09.png"), "Screenshot")
        XCTAssertEqual(inferApp(from: "Screen Shot 2026-09-27 at 14.05.09.png"), "Screen Shot")
    }

    func testKnownAppNames() {
        XCTAssertEqual(inferApp(from: "chrome-screenshot.png"), "Chrome")
        XCTAssertEqual(inferApp(from: "Safari_2026.png"), "Safari")
    }

    func testUnknownFallsBack() {
        XCTAssertEqual(inferApp(from: "IMG_1234.png"), "unknown")
    }
}

final class PlanTests: XCTestCase {
    private var directory: String!

    override func setUpWithError() throws {
        directory = NSTemporaryDirectory() + "/shotname-plan-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
    }

    private func addFile(_ name: String, bytes: Int = 8) throws {
        let data = Data(repeating: 0x41, count: bytes)
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    func testDryRunChangesNothing() throws {
        try addFile("Screenshot 2026-09-27 at 14.05.09.png")
        let actions = try planRenames(
            in: directory,
            template: NameTemplate("shot-{index}"),
            rules: RuleSet(),
            dryRun: true)
        XCTAssertEqual(actions.count, 1)
        XCTAssertTrue(actions[0].changed)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory + "/Screenshot 2026-09-27 at 14.05.09.png"))
    }

    func testRealRunRenamesOnDisk() throws {
        try addFile("Screenshot 2026-09-27 at 14.05.09.png")
        let actions = try planRenames(
            in: directory,
            template: NameTemplate("shot-{index}"),
            rules: RuleSet(),
            dryRun: false)
        XCTAssertEqual(actions.first?.to, "shot-001.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/shot-001.png"))
    }

    func testCollisionsGetUniqueNames() throws {
        try addFile("a.png")
        try addFile("b.png")
        let actions = try planRenames(
            in: directory,
            template: NameTemplate("same"),
            rules: RuleSet(),
            dryRun: true)
        let names = actions.map { $0.to }
        XCTAssertEqual(Set(names).count, names.count, "names must be unique: \(names)")
    }

    func testNonImagesAreIgnored() throws {
        try addFile("notes.txt")
        try addFile("photo.png")
        let actions = try planRenames(
            in: directory,
            template: NameTemplate("x-{name}"),
            rules: RuleSet(),
            dryRun: true)
        XCTAssertEqual(actions.count, 1)
    }

    func testMissingDirectoryFails() {
        XCTAssertThrowsError(try planRenames(
            in: directory + "-does-not-exist",
            template: NameTemplate("x"),
            rules: RuleSet(),
            dryRun: true))
    }
}

final class UndoLogTests: XCTestCase {
    private var directory: String!
    private var logPath: String!

    override func setUpWithError() throws {
        directory = NSTemporaryDirectory() + "/shotname-undo-\(UUID().uuidString)"
        logPath = directory + ".log"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
        try? FileManager.default.removeItem(atPath: logPath)
    }

    private func addFile(_ name: String) throws {
        try Data("x".utf8).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    func testRecordAndUndo() throws {
        try addFile("old.png")
        let actions = try planRenames(
            in: directory, template: NameTemplate("new"), rules: RuleSet(), dryRun: false)
        XCTAssertTrue(actions[0].changed)

        let log = UndoLog(path: logPath)
        XCTAssertEqual(try log.record(actions, in: directory), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/new.png"))
        XCTAssertEqual(log.entries().count, 1)

        XCTAssertEqual(try log.undo(count: 1), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/old.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory + "/new.png"))
        XCTAssertTrue(log.entries().isEmpty)
    }

    func testRecordingNoChangesWritesNothing() throws {
        let log = UndoLog(path: logPath)
        let unchanged = [RenameAction(from: "a.png", to: "a.png", changed: false)]
        XCTAssertEqual(try log.record(unchanged, in: directory), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logPath))
    }

    func testUndoWithEmptyLog() throws {
        let log = UndoLog(path: logPath)
        XCTAssertEqual(try log.undo(count: 1), 0)
    }

    func testUndoUndoesNewestFirst() throws {
        // two real runs, so the files on disk match what the log claims
        try addFile("a.png")
        let log = UndoLog(path: logPath)
        let first = try planRenames(in: directory, template: NameTemplate("b"),
                                    rules: RuleSet(), dryRun: false)
        _ = try log.record(first, in: directory)
        let second = try planRenames(in: directory, template: NameTemplate("c"),
                                     rules: RuleSet(), dryRun: false)
        _ = try log.record(second, in: directory)
        XCTAssertEqual(log.entries().count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/c.png"))

        XCTAssertEqual(try log.undo(count: 1), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/b.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory + "/c.png"))
        XCTAssertEqual(log.entries().count, 1)
    }
}

final class LaunchAgentTests: XCTestCase {
    func testPlistContainsTheEssentials() {
        let plist = launchAgentPlist(
            executable: "/usr/local/bin/shotname",
            directory: "/Users/me/Screenshots",
            intervalSeconds: 1800,
            logPath: "/tmp/shotname.log")
        XCTAssertTrue(plist.hasPrefix("<?xml"))
        XCTAssertTrue(plist.contains("<key>StartInterval</key>"))
        XCTAssertTrue(plist.contains("<integer>1800</integer>"))
        XCTAssertTrue(plist.contains("/Users/me/Screenshots"))
        XCTAssertTrue(plist.contains("com.shotname.agent"))
        // balanced dictionary tags
        XCTAssertEqual(plist.components(separatedBy: "<dict>").count,
                       plist.components(separatedBy: "</dict>").count)
    }
}
