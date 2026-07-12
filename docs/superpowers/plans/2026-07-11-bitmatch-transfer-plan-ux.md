# BitMatch Transfer-Plan UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the configuration-heavy idle screen with a concise transfer plan, preflight verdict, and one Options surface on macOS and iPadOS.

**Architecture:** A pure presentation model summarizes existing selection and settings state. Views render it, but `SafetyValidator` and shared operation services remain authoritative. Platform layouts share hierarchy and copy without requiring identical geometry.

**Tech Stack:** SwiftUI, existing design system, Swift Testing, macOS 15.5+, iPadOS 18.5+.

## Global Constraints

- Preserve drag and drop, keyboard shortcuts, recent destinations, mode navigation, saved preferences, and the compact in-progress UI.
- Keep the current dark palette, typography, and window footprint.
- Keep Quick-mode warnings and blocking readiness errors visible outside Options.
- Add no third-party dependency.
- Respect Reduce Motion and provide useful accessibility labels and focus order.

---

### Task 1: Pure transfer-plan presentation model

**Files:**
- Create: `Shared/Core/Models/TransferPlanPresentation.swift`
- Create: `BitMatchTests/TransferPlanPresentationTests.swift`

**Interfaces:**
- Produces: `TransferPlanPresentation`, `TransferPlanPresentation.Status`, and `TransferPlanPresentation.make(...)`.

- [ ] **Step 1: Write failing state tests**

Test empty, analyzing, ready, warning, and blocked inputs. Verify Quick mode produces `Start copy without checksum verification`; Standard produces `Start verified copy`; report and camera labels appear in `optionSummary`.

```swift
@Test func standardReadyPlanUsesVerifiedAction() {
    let plan = TransferPlanPresentation.make(
        sourceURL: URL(fileURLWithPath: "/Source/A001"),
        sourceInfo: nil,
        destinationURLs: [URL(fileURLWithPath: "/Volumes/RAID_A")],
        verificationMode: .standard,
        cameraSettings: CameraLabelSettings(),
        reportSettings: ReportPrefs(),
        isAnalyzing: false,
        blockingIssues: [],
        warnings: []
    )
    #expect(plan.status == .ready)
    #expect(plan.actionTitle == "Start verified copy")
}
```

- [ ] **Step 2: Run focused tests and confirm the model is missing**

Run: `xcodebuild test -project BitMatch.xcodeproj -scheme BitMatch -destination 'platform=macOS' -only-testing:BitMatchTests/TransferPlanPresentationTests`
Expected: compilation fails because the type is undefined.

- [ ] **Step 3: Implement the pure model**

Define `Status: Equatable { case incomplete(String), analyzing(String), ready, warning([String]), blocked([String]) }`. Store `sourceTitle`, `sourceDetail`, `[String] destinationTitles`, `destinationDetail`, `status`, `[String] optionSummary`, `actionTitle`, and `canStart`. Format sizes with `ByteCountFormatter` and counts with `NumberFormatter`. Apply precedence: blocked, incomplete, analyzing, warning, ready.

- [ ] **Step 4: Verify focused and full tests**

Run: `bash test.sh mac-test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Core/Models/TransferPlanPresentation.swift BitMatchTests/TransferPlanPresentationTests.swift
git commit -m "feat: model transfer plan presentation states"
```

### Task 2: macOS transfer-plan components

**Files:**
- Create: `BitMatch/Views/CopyAndVerify/TransferPlanView.swift`
- Modify: `BitMatch/Views/CopyAndVerify/CopyAndVerifyView.swift`
- Modify: `BitMatch/App/ContentView.swift`

**Interfaces:**
- Consumes: `TransferPlanPresentation` and existing `AppCoordinator` models.
- Produces: `TransferPlanView`, `TransferPlanSourceCard`, `TransferPlanDestinationsCard`, `TransferPlanPreflightCard`, and `TransferOptionsView`.

- [ ] **Step 1: Add testable plan construction to `CopyAndVerifyView`**

Move existing readiness issue and warning calculations into pure helper inputs for `TransferPlanPresentation.make`. Keep calls to `SafetyValidator.validateResolvedDestinationRoots` and existing free-space checks.

- [ ] **Step 2: Build source and backup cards**

Reuse existing selection and drag/drop actions from `HorizontalFlowView`. Source shows `Choose source`, `Analyzing…`, or `<count> files · <size>`. Backups show `Add at least one backup`, destination names, and capacity status. Do not remove existing drop rejection handling.

- [ ] **Step 3: Build the preflight and action hierarchy**

Render green ready, blue analyzing, orange warning, and red blocked states. Put the reason beside every disabled action. Use the model's exact `actionTitle`; never label Quick mode as verified.

- [ ] **Step 4: Consolidate secondary controls**

Move the existing camera-label, verification, and report controls into one `TransferOptionsView` disclosure group. Outside it, render option-summary chips plus any Quick-mode warning. Remove the two independent expansion-height calculations from `ContentView` and use one Options expansion state.

- [ ] **Step 5: Add accessibility and motion behavior**

Use `@Environment(\.accessibilityReduceMotion)` to replace spring transitions with opacity when enabled. Add labels and hints for source selection, adding/removing backups, preflight state, Options, and start action.

- [ ] **Step 6: Verify macOS states**

Run: `bash test.sh mac-test && bash test.sh mac-build`
Expected: tests and build pass. Manually inspect empty, analyzing, ready, Quick warning, insufficient-space, duplicate-destination, and active states.

- [ ] **Step 7: Commit**

```bash
git add BitMatch/Views/CopyAndVerify BitMatch/App/ContentView.swift
git commit -m "feat: simplify macOS transfer setup"
```

### Task 3: iPadOS transfer-plan hierarchy

**Files:**
- Modify: `BitMatch-iPad/Views/CopyAndVerifyView.swift`
- Modify: `BitMatch-iPad/Views/ModularContentView.swift`

**Interfaces:**
- Consumes: `TransferPlanPresentation` and `SharedAppCoordinator`.

- [ ] **Step 1: Replace the idle stack with the shared hierarchy**

Retain `ProfessionalSourceCard`, destination picker behavior, and `StartTransferButtonView` actions, but order them as source, backups, preflight, option summary, Options, and primary action.

- [ ] **Step 2: Merge iPad option disclosures**

Place `CollapsibleLabelingSection`, `CollapsibleVerificationSection`, and `ReportToggleCard` inside one Options disclosure. Keep Quick warnings and readiness banners outside it.

- [ ] **Step 3: Adapt for width and touch**

Use side-by-side source/backups when regular horizontal size class has enough width; stack them otherwise. Preserve 44-point tap targets, VoiceOver order, Files picker sheets, and existing background-operation behavior.

- [ ] **Step 4: Verify iPadOS and the macOS regression suite**

Run: `bash test.sh ipad-build && bash test.sh mac-test`
Expected: both commands exit 0. Inspect compact and regular iPad widths in previews or an installed simulator.

- [ ] **Step 5: Commit**

```bash
git add BitMatch-iPad/Views/CopyAndVerifyView.swift BitMatch-iPad/Views/ModularContentView.swift
git commit -m "feat: simplify iPad transfer setup"
```

### Task 4: Final visual and documentation alignment

**Files:**
- Modify: `README.md`
- Modify: `ARCHITECTURE.md`
- Modify: `DEVELOPMENT.md`
- Modify: `screenshot.png`

- [ ] **Step 1: Verify final Debug and Release artifacts**

Run: `bash test.sh mac-test && bash test.sh ipad-build && bash test.sh release-builds`
Expected: every command exits 0.

- [ ] **Step 2: Capture the stable macOS setup screen**

Use a representative disposable source and two disposable destinations. Capture the ready transfer-plan state at native resolution without personal volume names or client data.

- [ ] **Step 3: Correct only stale documentation**

Update architecture ownership, local/CI commands, soak and hardware-test links, the screenshot, and setup-flow descriptions. Preserve the README's candid trust story.

- [ ] **Step 4: Run final checks**

Run: `git diff --check && bash test.sh mac-test && bash test.sh ipad-build && bash test.sh release-builds`
Expected: no whitespace errors; all tests and builds pass.

- [ ] **Step 5: Commit**

```bash
git add README.md ARCHITECTURE.md DEVELOPMENT.md screenshot.png
git commit -m "docs: align BitMatch guides with the transfer plan workflow"
```
