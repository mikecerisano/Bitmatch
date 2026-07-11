# BitMatch Reliability and CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reproducible builds, CI, disposable fault fixtures, a seeded soak test, and an honest hardware-failure procedure.

**Architecture:** Shell entry points choose explicit Xcode jobs and isolate derived data. XCTest owns deterministic transfer exercises; shell wrappers prepare disposable APFS volumes and opt into long soak runs. CI builds both schemes and runs the macOS unit suite.

**Tech Stack:** Bash, Xcode 16+, XCTest/Swift Testing, GitHub Actions, APFS disk images, SHA-256 through `SharedChecksumService`.

## Global Constraints

- Keep macOS 15.5 and iPadOS 18.5 deployment targets.
- Add no third-party dependency.
- Automated destructive operations may target only a marked temporary directory or a disk image created by the harness.
- Use a unique DerivedData directory for every concurrent Xcode job.
- Keep the existing 163-test macOS baseline green.

---

### Task 1: Explicit local build and test commands

**Files:**
- Modify: `test.sh`

**Interfaces:**
- Produces: `bash test.sh mac-test|mac-build|ipad-build|ipad-test|release-builds`

- [ ] **Step 1: Capture the baseline**

Run: `bash test.sh`
Expected: 163 tests pass and the command exits 0.

- [ ] **Step 2: Replace implicit arguments with named jobs**

Implement a `case` statement with these exact defaults and commands:

```bash
ROOT=$(cd "$(dirname "$0")" && pwd)
JOB=${1:-mac-test}
DERIVED_DATA_ROOT=${DERIVED_DATA_ROOT:-"$ROOT/.derived-data"}

run_xcodebuild() {
  local name=$1
  shift
  xcodebuild -project "$ROOT/BitMatch.xcodeproj" \
    -derivedDataPath "$DERIVED_DATA_ROOT/$name" \
    CODE_SIGNING_ALLOWED=NO "$@"
}

case "$JOB" in
  mac-test)
    run_xcodebuild mac-test test -scheme BitMatch -destination 'platform=macOS' -only-testing:BitMatchTests
    ;;
  mac-build)
    run_xcodebuild mac-build build -scheme BitMatch -configuration Debug -destination 'platform=macOS'
    ;;
  ipad-build)
    run_xcodebuild ipad-build build -scheme BitMatch-iPad -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
    ;;
  ipad-test)
    : "${IOS_SIMULATOR_DESTINATION:?Set IOS_SIMULATOR_DESTINATION, for example platform=iOS Simulator,name=iPad (A16)}"
    run_xcodebuild ipad-test test -scheme BitMatch-iPad -destination "$IOS_SIMULATOR_DESTINATION" -only-testing:BitMatch-iPadTests
    ;;
  release-builds)
    run_xcodebuild mac-release build -scheme BitMatch -configuration Release -destination 'platform=macOS'
    run_xcodebuild ipad-release build -scheme BitMatch-iPad -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
    ;;
  *)
    echo "Usage: $0 {mac-test|mac-build|ipad-build|ipad-test|release-builds}" >&2
    exit 64
    ;;
esac
```

- [ ] **Step 3: Ignore local DerivedData**

Add `.derived-data/` to `.gitignore`.

- [ ] **Step 4: Verify all non-device jobs**

Run: `bash test.sh mac-test && bash test.sh mac-build && bash test.sh ipad-build`
Expected: all commands exit 0; macOS reports 163 passing tests.

- [ ] **Step 5: Commit**

```bash
git add test.sh .gitignore
git commit -m "build: add explicit platform verification jobs"
```

### Task 2: GitHub Actions verification

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: named jobs from Task 1.

- [ ] **Step 1: Add isolated macOS test and iPad build jobs**

Create a workflow triggered by `push` and `pull_request`. Use `macos-15`, `actions/checkout@v4`, `DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer`, and these commands:

```yaml
jobs:
  mac-tests:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild -version
      - run: bash test.sh mac-test
        env:
          DERIVED_DATA_ROOT: ${{ runner.temp }}/bitmatch-derived-data
  ipad-build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild -version
      - run: bash test.sh ipad-build
        env:
          DERIVED_DATA_ROOT: ${{ runner.temp }}/bitmatch-derived-data
```

- [ ] **Step 2: Validate YAML and commands locally**

Run: `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml")'`
Expected: exits 0.

Run: `bash test.sh mac-test && bash test.sh ipad-build`
Expected: both commands exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: verify macOS tests and iPad build"
```

### Task 3: Disposable transfer fixture

**Files:**
- Create: `BitMatchTests/TestHelpers/DisposableTransferFixture.swift`
- Create: `BitMatchTests/DisposableTransferFixtureTests.swift`

**Interfaces:**
- Produces: `DisposableTransferFixture.init(seed:fileCount:bytesPerFile:)`, `source`, `destinations`, `manifest`, and `cleanup()`.

- [ ] **Step 1: Write failing safety tests**

Cover deterministic bytes for equal seeds, different bytes for different seeds, creation of hidden files and empty directories, and refusal to clean a URL that lacks the `.bitmatch-disposable-fixture` marker.

```swift
@Test func identicalSeedsCreateIdenticalManifest() throws {
    let left = try DisposableTransferFixture(seed: 42, fileCount: 3, bytesPerFile: 1024)
    let right = try DisposableTransferFixture(seed: 42, fileCount: 3, bytesPerFile: 1024)
    defer { left.cleanup(); right.cleanup() }
    #expect(left.manifest == right.manifest)
}
```

- [ ] **Step 2: Run the new tests and confirm the type is missing**

Run: `xcodebuild test -project BitMatch.xcodeproj -scheme BitMatch -destination 'platform=macOS' -only-testing:BitMatchTests/DisposableTransferFixtureTests`
Expected: compilation fails because `DisposableTransferFixture` is undefined.

- [ ] **Step 3: Implement the marked fixture**

Create a root under `FileManager.default.temporaryDirectory`, write `.bitmatch-disposable-fixture`, create `SOURCE`, `DEST_A`, and `DEST_B`, and generate bytes with `(seed &+ UInt64(fileIndex) &+ UInt64(byteIndex)) & 0xff`. Include `.camera-metadata`, `DCIM/100MEDIA`, and `EMPTY_SIDECARS`. Store manifest values as relative path to SHA-256.

`cleanup()` must verify both conditions before removal:

```swift
guard root.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path),
      FileManager.default.fileExists(atPath: root.appendingPathComponent(".bitmatch-disposable-fixture").path)
else { return }
try? FileManager.default.removeItem(at: root)
```

- [ ] **Step 4: Verify focused and full tests**

Run: `bash test.sh mac-test`
Expected: all baseline and fixture tests pass.

- [ ] **Step 5: Commit**

```bash
git add BitMatchTests/TestHelpers/DisposableTransferFixture.swift BitMatchTests/DisposableTransferFixtureTests.swift
git commit -m "test: add safe deterministic transfer fixtures"
```

### Task 4: Fault and soak coverage

**Files:**
- Create: `BitMatchTests/TransferFaultIntegrationTests.swift`
- Create: `BitMatchTests/TransferSoakTests.swift`
- Create: `Scripts/run_soak_tests.sh`
- Create: `Scripts/run_apfs_fault_tests.sh`
- Create: `docs/HARDWARE_TESTING.md`

**Interfaces:**
- Consumes: `DisposableTransferFixture` and `SharedFileOperationsService.performFileOperation(...)`.
- Produces: opt-in environment variables `BITMATCH_RUN_SOAK`, `BITMATCH_SOAK_SEED`, `BITMATCH_SOAK_ITERATIONS`, and `BITMATCH_FAULT_VOLUME`.

- [ ] **Step 1: Add failing integration tests**

Add tests for source mutation, a conflicting pre-existing file, cancellation cleanup, and one inaccessible destination while another destination succeeds. Assert that successful output hashes equal the fixture manifest and that failures remain failures in `ResultRow` classification.

- [ ] **Step 2: Implement the soak test**

Skip unless `BITMATCH_RUN_SOAK == "1"`. For each seeded iteration, create a fixture, run Standard verification to both destinations, recompute every SHA-256 with `SharedChecksumService.generateChecksum(... useCache: false ...)`, and write a Codable JSON summary to `BITMATCH_SOAK_RESULT` when set.

- [ ] **Step 3: Add safe shell wrappers**

`run_soak_tests.sh` must set the opt-in variables and invoke only `TransferSoakTests`. `run_apfs_fault_tests.sh` must create its image under `mktemp -d`, attach it with `hdiutil`, place a `.bitmatch-disposable-fixture` marker at the mount point, pass the mount path through `BITMATCH_FAULT_VOLUME`, and detach it in a `trap`.

- [ ] **Step 4: Document physical tests honestly**

Document source removal, one-destination removal, sleep/backgrounding, cancel/relaunch, low-power hubs, and exFAT/APFS combinations. Require throwaway data and two independently verified backups before any cable-pull exercise.

- [ ] **Step 5: Verify short tests and one soak iteration**

Run: `bash test.sh mac-test`
Expected: all short tests pass; the soak test reports skipped.

Run: `BITMATCH_SOAK_ITERATIONS=1 bash Scripts/run_soak_tests.sh`
Expected: one iteration passes and emits valid JSON.

- [ ] **Step 6: Commit**

```bash
git add BitMatchTests/TransferFaultIntegrationTests.swift BitMatchTests/TransferSoakTests.swift Scripts/run_soak_tests.sh Scripts/run_apfs_fault_tests.sh docs/HARDWARE_TESTING.md
git commit -m "test: add transfer fault and soak verification"
```
