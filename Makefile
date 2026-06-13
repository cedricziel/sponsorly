# Sponsorly developer & CI tasks.
#
# These targets are the single source of truth for build/lint/test commands:
# `.github/workflows/ci.yml` invokes them so CI and local runs stay identical,
# and CLAUDE.md's `make lint` / `make format` resolve here.
#
# Override the simulator or paths as needed, e.g.
#   make test DESTINATION='platform=iOS Simulator,name=iPhone 16 Pro'

SCHEME       ?= Sponsorly
PROJECT      ?= Sponsorly.xcodeproj
DESTINATION  ?= platform=iOS Simulator,name=iPhone 17 Pro
DERIVED_DATA ?= build/DerivedData
SPM_CACHE    ?= build/SourcePackages
XCODEBUILD   ?= xcodebuild
# Directories swiftformat/swiftlint must never descend into (build output,
# resolved package sources, vendored pods).
FORMAT_EXCLUDE ?= build,.build,Pods,DerivedData

.PHONY: generate secrets resolve format lint build test build-for-testing test-without-building

## Regenerate Sponsorly.xcodeproj from project.yml (it is git-ignored).
generate:
	xcodegen generate

## Create a placeholder Secrets.xcconfig only if one is not already present.
secrets:
	@test -f Secrets.xcconfig || cp Secrets.example.xcconfig Secrets.xcconfig

## Resolve and cache Swift Package dependencies.
resolve:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-resolvePackageDependencies -clonedSourcePackagesDirPath $(SPM_CACHE)

## Format Swift sources in place.
format:
	swiftformat . --exclude $(FORMAT_EXCLUDE)

## Verify formatting and lint without writing; fails on drift or violations.
lint:
	swiftformat --lint . --exclude $(FORMAT_EXCLUDE)
	swiftlint lint --quiet

## Build the app + test bundle for the simulator (no signing).
build-for-testing: secrets generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		-clonedSourcePackagesDirPath $(SPM_CACHE) \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO build-for-testing

## Run tests using the products produced by build-for-testing.
test-without-building:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO test-without-building

## Convenience: one-shot build for a concrete simulator.
build: secrets generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

## Convenience: one-shot build + test for a concrete simulator.
test: secrets generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test
