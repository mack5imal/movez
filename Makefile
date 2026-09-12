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

snapshots: build
	@rm -rf build/snapshots
	@$(BIN) --snapshot all --out build/snapshots
	@expected=$$($(BIN) --snapshot list); \
	missing=""; \
	for surface in $$expected; do \
	  [ -f "build/snapshots/$$surface.png" ] || missing="$$missing $$surface"; \
	done; \
	if [ -n "$$missing" ]; then echo "missing snapshots:$$missing" >&2; exit 1; fi; \
	echo "--- build/snapshots ---"; \
	for surface in $$expected; do \
	  printf '%-28s %s\n' "$$surface.png" "$$(sips -g pixelWidth -g pixelHeight build/snapshots/$$surface.png | tail -2 | tr -d ' \n')"; \
	done

assets:
	bash scripts/fetch_font.sh
	python3 scripts/gen_chimes.py

clean:
	rm -rf build
