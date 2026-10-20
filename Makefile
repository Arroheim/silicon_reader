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

# swiftbuild intermittently drops the swift-testing macro plugin when building
# with the Command Line Tools toolchain ("plugin for module 'TestingMacros' not
# found"). Loading it explicitly makes the build deterministic.
TESTING_PLUGIN := $(shell dirname "$$(dirname "$$(xcrun --find swift)")")/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_FLAGS     := $(if $(wildcard $(TESTING_PLUGIN)),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN))

MUPDF_FLAGS := build=release HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no \
	extract=no barcode=no tesseract=no XCFLAGS=-mmacosx-version-min=14.0

.PHONY: help deps build test e2e lint format app smoke run clean distclean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: $(MUPDF_STAMP) ## Fetch submodules and build MuPDF static libraries

$(MUPDF_STAMP):
	git submodule update --init --depth 1 $(MUPDF_SRC)
	git -C $(MUPDF_SRC) submodule update --init --depth 1 --recursive
	$(MAKE) -C $(MUPDF_SRC) -j$(JOBS) libs $(MUPDF_FLAGS) OUT="$(CURDIR)/$(MUPDF_OUT)"
	touch "$@"

build: deps ## Build the app binary (CONFIG=debug|release)
	swift build -c $(CONFIG)

test: deps ## Run unit tests
	swift test $(TEST_FLAGS) --skip E2ETests

e2e: app ## Run end-to-end tests against the built app over its control channel
	SILICON_READER_APP="$(abspath $(APP))" swift test $(TEST_FLAGS) --filter E2ETests

lint: ## Check formatting with swift-format
	swift format lint --strict --recursive Package.swift Sources Tests

format: ## Reformat sources in place with swift-format
	swift format --in-place --recursive Package.swift Sources Tests

app: ## Assemble an ad-hoc signed .app bundle (release build)
	$(MAKE) build CONFIG=release
	scripts/bundle-app.sh "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)"

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

run: app ## Build and launch the app (FILE=path/to/doc to open a document)
	open "$(APP)" $(if $(FILE),--args "$(abspath $(FILE))")

clean: ## Remove Swift build products and the app bundle
	swift package clean
	rm -rf "$(APP)"

distclean: clean ## Also remove the MuPDF build
	rm -rf .build "$(BUILD_DIR)"
