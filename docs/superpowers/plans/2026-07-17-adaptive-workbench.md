# Adaptive Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BitMatch compact by default and genuinely responsive when its window or workflow expands.

**Architecture:** A small, pure layout policy establishes the responsive breakpoint. `ContentView` supplies the available window canvas without a fixed width or width-reset observer; `TransferPlanView` uses the policy to reflow the transfer route and workflow selector.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Xcode.

## Global Constraints

- Preserve the compact 680-point default window intent while respecting manual resize.
- Keep the background visible across the entire available window.
- Use existing semantic colors and system fonts; source amber, backup blue, and verification green retain their meanings.
- Do not auto-select unreadable camera cards.
- Remove `.derived-data` after build and runtime verification.

---

### Task 1: Define the responsive presentation policy

**Files:**
- Create: `BitMatch/Views/CopyAndVerify/AdaptiveWorkbenchLayout.swift`
- Create: `BitMatchTests/AdaptiveWorkbenchLayoutTests.swift`

**Interfaces:**
- Produces: `AdaptiveWorkbenchLayout.presentation(for:) -> AdaptiveWorkbenchPresentation`
- Consumes: available SwiftUI width as `CGFloat`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func compactWindowUsesStackedPresentation() {
    #expect(AdaptiveWorkbenchLayout.presentation(for: 679) == .compact)
}

@Test func workbenchWindowUsesExpandedPresentation() {
    #expect(AdaptiveWorkbenchLayout.presentation(for: 680) == .expanded)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `xcodebuild -project BitMatch.xcodeproj -scheme BitMatch -destination 'platform=macOS' -derivedDataPath .derived-data test -only-testing:BitMatchTests/AdaptiveWorkbenchLayoutTests`

Expected: compilation failure because `AdaptiveWorkbenchLayout` does not exist.

- [ ] **Step 3: Implement the smallest pure policy**

```swift
enum AdaptiveWorkbenchPresentation: Equatable { case compact, expanded }

enum AdaptiveWorkbenchLayout {
    static let expandedThreshold: CGFloat = 680
    static func presentation(for availableWidth: CGFloat) -> AdaptiveWorkbenchPresentation {
        availableWidth >= expandedThreshold ? .expanded : .compact
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run the Task 1 command. Expected: both tests pass.

### Task 2: Remove fixed root width and respect manual resizing

**Files:**
- Modify: `BitMatch/App/ContentView.swift:74-155, 514-580`
- Test: `BitMatchTests/AdaptiveWorkbenchLayoutTests.swift`

**Interfaces:**
- Consumes: `AdaptiveWorkbenchLayout` through descendant views.
- Produces: a root content area filling the host window at every width.

- [ ] **Step 1: Add a regression assertion**

Add a test that the policy remains expanded beyond the initial size:

```swift
@Test func expandedWindowStaysExpandedAtLargeWidths() {
    #expect(AdaptiveWorkbenchLayout.presentation(for: 1_200) == .expanded)
}
```

- [ ] **Step 2: Run the focused test and verify the new assertion fails**

Run the Task 1 command. Expected: failure because the policy has not yet covered the new assertion.

- [ ] **Step 3: Make the root canvas fluid**

Remove `.frame(width: 680)` from `mainContentArea`, give it infinite width and height, retain the compact ideal width for first appearance and mode-driven sizing, and remove the width change observer that snaps a manually resized window back to 680.

- [ ] **Step 4: Run the focused test and macOS build**

Run the focused test, then:

`xcodebuild -project BitMatch.xcodeproj -scheme BitMatch -configuration Debug -derivedDataPath .derived-data build-for-testing CODE_SIGNING_ALLOWED=NO`

Expected: tests pass and build succeeds.

### Task 3: Reflow the transfer route and workflow selector

**Files:**
- Modify: `BitMatch/Views/CopyAndVerify/TransferPlanView.swift:4-157`
- Modify: `BitMatch/Views/CopyAndVerify/AdaptiveWorkbenchLayout.swift`
- Test: `BitMatchTests/AdaptiveWorkbenchLayoutTests.swift`

**Interfaces:**
- Consumes: `AdaptiveWorkbenchPresentation`.
- Produces: a vertical compact route and a horizontal expanded rail.

- [ ] **Step 1: Add a test for threshold boundary behavior**

```swift
@Test func widthAtTheThresholdUsesExpandedPresentation() {
    #expect(AdaptiveWorkbenchLayout.presentation(for: AdaptiveWorkbenchLayout.expandedThreshold) == .expanded)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run the Task 1 command. Expected: failure until the exact threshold policy is supplied.

- [ ] **Step 3: Build the adaptive rail**

Wrap `TransferPlanView` in a local `GeometryReader`. Use the policy to show source, directional arrow, and backups in an `HStack` at expanded widths; stack them with a downward arrow at compact widths. Give the rail a subtle connected background and let workflow choices switch from a compact vertical arrangement to an equal-width horizontal pair. Preserve the existing selection, preflight, options, and action behavior.

- [ ] **Step 4: Run focused tests and build-for-testing**

Run the Task 1 command and the Task 2 build command. Expected: pass/succeed.

### Task 4: Visual runtime validation and cleanup

**Files:**
- No source changes expected.

- [ ] **Step 1: Launch the Debug app**

Run: `open -n .derived-data/Build/Products/Debug/BitMatch.app`

- [ ] **Step 2: Verify**

Confirm the app remains open, widening the window does not leave black side bars, and the transfer rail adapts at the threshold without the card access alert.

- [ ] **Step 3: Stop the local Debug app and remove generated output**

Run: `pkill -f '/BitMatch.app/Contents/MacOS/BitMatch' || true; rm -rf .derived-data`

Expected: no generated build directory remains.
