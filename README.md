# shotname

**Rule-based screenshot renamer for macOS — templates, ordered rewrite rules, an undo log you can read, and a launchd agent template. Swift, Foundation only.**

```
$ shotname run --dir ~/Pictures/Screenshots --template 'shot-{date}-{app}-{index}'
Screenshot 2026-09-27 at 14.05.09.png -> shot-2026-09-27-Screenshot-001.png
IMG_0001.png                           -> shot-2026-09-27-unknown-002.png

renamed: 2 file(s), 2 changed
undo log: ~/.shotname-undo.log (2 entries)

$ shotname undo
undid 1 rename(s)
```

The Downloads folder full of `Screenshot 2026-09-27 at 14.05.09.png` is
the macOS equivalent of the Windows `Screenshot (7).png` problem. shotname
renames them on a schedule, by rules you can read, with a log that lets
you put anything back.

## Why shotname

- **Templates with real placeholders.** `{name}` `{ext}` `{date}`
  `{time}` `{index}` `{size}` `{app}` — and unknown placeholders are left
  alone instead of silently vanishing. A template that forgets `{ext}`
  gets the original extension back rather than stripping it.
- **Rules that read like rules.** `Screenshot => screen`, and
  `IMG (\d+) => capture-$1 (regex)` for the rest. The first matching rule
  wins; unmatched names pass through untouched.
- **App inference.** macOS's own screenshot names, plus Chrome, Safari,
  Slack, Discord, Terminal — from the file name, no metadata APIs
  required, and `unknown` rather than a guess when nothing matches.
- **Undo that keeps its promises.** Every run appends JSON lines
  (`old -> new`, directory, timestamp) to a log; `undo` reverses the
  newest entries, keeps the ones it could not reverse, and leaves the
  older ones intact so a second `undo` still works.
- **LaunchAgent template.** `shotname launchagent` writes a plist with
  `StartInterval`, `RunAtLoad` and log paths, and prints the
  `launchctl load` line — the scheduled version is one command away.
- **Dry run by default for planning.** `plan` prints the whole mapping
  and touches nothing; `run` moves files and writes the log.

## Usage

```sh
shotname plan --dir ~/Pictures/Screenshots            # print, change nothing
shotname run  --dir ~/Pictures/Screenshots --template 'shot-{date}-{index}'
shotname run  --dir ~/Pictures --rules rules.txt      # ordered rewrite rules
shotname undo --count 3
shotname launchagent --dir ~/Pictures/Screenshots --interval 3600 \
    --out ~/Library/LaunchAgents/com.shotname.agent.plist
```

Exit codes: 0 ok, 1 runtime error (nothing to undo, unreadable
directory), 2 usage error.

## Development

```sh
make test    # 22 XCTest cases + a CLI end-to-end run
```

The suite covers rule parsing (including the regex form), template
rendering, app inference, dry-run versus real runs, collision
uniquification, the undo log's newest-first bookkeeping, and the generated
plist.

## License

MIT — see [LICENSE](LICENSE).
