SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

APP_NAME    := SiliconReader
CONFIG      ?= debug
BUILD_DIR   := build
APP         := $(BUILD_DIR)/$(APP_NAME).app
MUPDF_SRC   := Vendor/mupdf
MUPDF_OUT   := $(BUILD_DIR)/deps/mupdf
MUPDF_STAMP := $(MUPDF_OUT)/.built
JOBS        := $(shell sysctl -n hw.ncpu)

# The oldest macOS the app runs on. The SDK below only decides which AppKit
# behavior the app opts into on newer systems; this is what keeps macOS 14 working.
MIN_MACOS := 14.0

# SwiftPM with the Command Line Tools links through clang with --sysroot only (and
# does not pass SDKROOT on), so clang cannot read the SDK version and records the
# deployment target instead (sdk 14.0). Xcode builds (CI, releases) record the real
# SDK. Hand the linker driver -isysroot so local builds link the same way and look
# the same as the published app; scripts/check-binary.sh guards it.
SDK_PATH    := $(shell xcrun --sdk macosx --show-sdk-path)
SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
SWIFT_FLAGS := -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc $(SDK_PATH)

# Version from the latest v* tag (v1.0.0 → 1.0.0) unless given; build number = commit count.
VERSION      ?= $(or $(shell git describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//'),0.1.0)
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
DMG          := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

# swiftbuild intermittently drops the swift-testing macro plugin when building
# with the Command Line Tools toolchain ("plugin for module 'TestingMacros' not
# found"). Loading it explicitly makes the build deterministic.
TESTING_PLUGIN := $(shell dirname "$$(dirname "$$(xcrun --find swift)")")/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_FLAGS     := $(if $(wildcard $(TESTING_PLUGIN)),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN))

MUPDF_FLAGS := build=release HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no \
	extract=no barcode=no tesseract=no XCFLAGS=-mmacosx-version-min=$(MIN_MACOS)

.PHONY: help deps build test e2e lint format app dmg release smoke check-library run clean distclean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: $(MUPDF_STAMP) ## Fetch submodules and build MuPDF static libraries

$(MUPDF_STAMP):
	git submodule update --init --depth 1 $(MUPDF_SRC)
	git -C $(MUPDF_SRC) submodule update --init --depth 1 --recursive
	$(MAKE) -C $(MUPDF_SRC) -j$(JOBS) libs $(MUPDF_FLAGS) OUT="$(CURDIR)/$(MUPDF_OUT)"
	touch "$@"

build: deps ## Build the app binary (CONFIG=debug|release)
	swift build -c $(CONFIG) $(SWIFT_FLAGS)

test: deps ## Run unit tests
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS) --skip E2ETests

e2e: app ## Run end-to-end tests against the built app over its control channel
	SILICON_READER_APP="$(abspath $(APP))" swift test $(SWIFT_FLAGS) $(TEST_FLAGS) --filter E2ETests

lint: ## Check formatting with swift-format
	swift format lint --strict --recursive Package.swift Sources Tests

format: ## Reformat sources in place with swift-format
	swift format --in-place --recursive Package.swift Sources Tests

app: ## Assemble an ad-hoc signed .app bundle (release build, VERSION=x.y.z)
	$(MAKE) build CONFIG=release
	scripts/bundle-app.sh "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)" \
		"$(VERSION)" "$(BUILD_NUMBER)"
	scripts/check-binary.sh "$(APP)/Contents/MacOS/$(APP_NAME)" "$(MIN_MACOS)" "$(SDK_VERSION)"

dmg: app ## Pack the app into build/SiliconReader-$(VERSION).dmg (+ .sha256)
	scripts/make-dmg.sh "$(APP)" "$(DMG)"

release: ## Tag a release: make release VERSION=1.0.0 (checks tree, changelog and tests; push the tag yourself)
	@[[ "$(origin VERSION)" == "command line" ]] || { echo "usage: make release VERSION=x.y.z"; exit 64; }
	@[[ -z "$$(git status --porcelain)" ]] || { echo "error: working tree is not clean"; exit 1; }
	@! git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null || { echo "error: tag v$(VERSION) exists"; exit 1; }
	scripts/release-notes.sh "$(VERSION)" >/dev/null
	$(MAKE) lint test e2e
	git tag -a "v$(VERSION)" -m "Silicon Reader $(VERSION)"
	@echo "Tagged v$(VERSION). Publish with: git push origin v$(VERSION)"

SMOKE_DOCS := Tests/ReaderCoreTests/Fixtures/djvu2spec.djvu \
	"$(MUPDF_SRC)/thirdparty/lcms2/doc/LittleCMS2.19 tutorial.pdf"
# Each entry is name=comma-separated canvas actions run before the snapshot.
SMOKE_VIEWS := default= book=viewBook,zoomFitWidth paged=toggleContinuous,goToNextPage,rotateRight \
	zoomed=zoomActualSize,zoomIn,zoomIn,zoomIn

SMOKE_DIR := $(BUILD_DIR)/smoke
# A throwaway library so smoke runs never touch the user's history.
SMOKE_LIBRARY := $(SMOKE_DIR)/library.json

smoke: app ## Open sample PDF/DjVu in several view modes, then the home page; snapshots go to build/smoke
	rm -rf "$(SMOKE_DIR)" && mkdir -p "$(SMOKE_DIR)"
	for doc in $(SMOKE_DOCS); do \
		for view in $(SMOKE_VIEWS); do \
			out="$(SMOKE_DIR)/$$(basename "$$doc" | tr ' ' '_')-$${view%%=*}.png"; \
			"$(APP)/Contents/MacOS/$(APP_NAME)" -library "$(SMOKE_LIBRARY)" -snapshot "$$out" -actions "$${view#*=}" "$$doc"; \
			echo "ok $$out"; \
		done; \
	done
	"$(APP)/Contents/MacOS/$(APP_NAME)" -library "$(SMOKE_LIBRARY)" -snapshot "$(SMOKE_DIR)/home.png"
	echo "ok $(SMOKE_DIR)/home.png"

CHECK_JOBS    ?= $(shell echo $$(( $(JOBS) / 2 )))
CHECK_TIMEOUT ?= 180

check-library: deps ## Check every PDF/DjVu under DIR (ALL_PAGES=1 renders every page); report in build/check
	@test -n "$(DIR)" || { echo "usage: make check-library DIR=/path/to/books [ALL_PAGES=1]"; exit 64; }
	swift build -c release --product ReaderCheck $(SWIFT_FLAGS)
	"$$(swift build -c release --show-bin-path)/ReaderCheck" --batch "$(DIR)" --jobs $(CHECK_JOBS) \
		--timeout $(CHECK_TIMEOUT) --report $(BUILD_DIR)/check/report.jsonl $(if $(ALL_PAGES),--all-pages)

run: app ## Build and launch the app (FILE=path/to/doc to open a document)
	open "$(APP)" $(if $(FILE),--args "$(abspath $(FILE))")

clean: ## Remove Swift build products and the app bundle
	swift package clean
	rm -rf "$(APP)"

distclean: clean ## Also remove the MuPDF build
	rm -rf .build "$(BUILD_DIR)"
