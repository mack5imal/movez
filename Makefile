export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

PROJECT := movez.xcodeproj
SCHEME := movez
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/movez.app
BIN := $(APP)/Contents/MacOS/movez
XCB := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: gen build test lint app run snapshots assets clean

gen:
	xcodegen generate --spec project.yml

build: gen
	$(XCB) -quiet build

test: gen
	@mkdir -p build
	@set +e; \
	$(XCB) test 2>&1 | tee build/test.log | grep -E "Test Suite|Executed|error:|failed|\*\* TEST"; \
	status=$${PIPESTATUS[0]}; \
	exit $$status

lint:
	swiftlint lint --strict --quiet

app:
	@echo $(APP)

run: build
	open $(APP)

snapshots:
	@echo "snapshots: no surfaces yet"

assets:
	bash scripts/fetch_font.sh
	python3 scripts/gen_chimes.py

clean:
	rm -rf build
