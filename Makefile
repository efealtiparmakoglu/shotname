SWIFT ?= swift
BIN = .build/release/shotname

all: $(BIN)

$(BIN): Package.swift Sources/shotname/*.swift
	$(SWIFT) build -c release

shotname: $(BIN)
	@cp $(BIN) shotname

test: $(BIN)
	$(SWIFT) test -c release
	./$(BIN) --help >/dev/null
	mkdir -p /tmp/shotname-e2e && rm -f /tmp/shotname-e2e/*
	head -c 32 /dev/urandom > /tmp/shotname-e2e/IMG_0001.png
	head -c 32 /dev/urandom > "/tmp/shotname-e2e/Screenshot 2026-09-27 at 14.05.09.png"
	./$(BIN) run --dir /tmp/shotname-e2e --template 'shot-{index}-{app}' \
	    --log /tmp/shotname-e2e/undo.log | grep -q 'renamed: 2 file(s), 2 changed'
	test -f "/tmp/shotname-e2e/shot-002-Screenshot.png"
	./$(BIN) undo --log /tmp/shotname-e2e/undo.log | grep -q 'undid 1 rename'
	./$(BIN) launchagent --dir /tmp/shotname-e2e --interval 900 --out /tmp/shotname-e2e/agent.plist >/dev/null
	grep -q '<integer>900</integer>' /tmp/shotname-e2e/agent.plist
	rm -rf /tmp/shotname-e2e
	echo "e2e: rename/undo/launchagent OK"

clean:
	rm -rf .build
	rm -rf /tmp/shotname-e2e

.PHONY: all shotname test clean
