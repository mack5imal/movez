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

.PHONY: gen build test lint app run snapshots hygiene assets clean

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

# A binary exec'd from a shell gets no activation rights from Launch Services, so its overlay can
# never become key. Launching through `open` is the only faithful test of window hygiene.
HYGIENE_REPORT := $(HOME)/Library/Application Support/movez/overlay-hygiene.txt

hygiene: build
	@rm -f "$(HYGIENE_REPORT)"
	@open -n -a "$(CURDIR)/$(APP)" --args --overlay-hygiene
	@for i in $$(seq 1 20); do [ -f "$(HYGIENE_REPORT)" ] && break; sleep 1; done
	@cat "$(HYGIENE_REPORT)"
	@grep -q "key=true" "$(HYGIENE_REPORT)" || { echo "overlay never became key" >&2; exit 1; }
	@grep -q "windowsAfterSleep=0" "$(HYGIENE_REPORT)" || { echo "overlay left windows behind" >&2; exit 1; }
	@grep -q "focusRestored=true" "$(HYGIENE_REPORT)" || { echo "focus was not restored" >&2; exit 1; }

assets:
	bash scripts/fetch_font.sh
	python3 scripts/gen_chimes.py

clean:
	rm -rf build
