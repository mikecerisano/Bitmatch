# Adaptive Interface Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver one recognizably BitMatch workflow across Mac, iPad, and iPhone, with each device reflowing the same transfer, project, destination, safety, and evidence states.

**Architecture:** The existing Mac workflow and presentation models become the source of truth. iOS stops maintaining parallel transfer-plan and state vocabulary; adaptive SwiftUI containers compose shared presentation models into compact and expanded arrangements. Platform-specific file selection, lifecycle, and background execution remain behind platform adapters.

**Tech Stack:** Swift 5, SwiftUI, iOS 18.5+, macOS 15.5+, XCTest/Swift Testing.

## Global Constraints

- Preserve existing transfer and verification safety behavior.
- Use plain, product-facing copy; no testing scaffolding in user-facing controls.
- Respect Reduce Motion and support compact widths, split-screen iPad, and Dynamic Type.
- Keep credentials and private-key data outside BitMatch.
- Remove temporary derived data after validation.

---

### Task 1: Establish a shared adaptive shell

**Files:**
- Create: `BitMatch/Views/Adaptive/AdaptiveBitMatchShell.swift`
- Create: `BitMatch/Views/Adaptive/AdaptiveNavigationPresentation.swift`
- Modify: `BitMatch-iPad/ContentView.swift`
- Test: `BitMatchTests/AdaptiveNavigationPresentationTests.swift`

- [ ] Write tests for compact, regular, and expanded navigation presentations.
- [ ] Implement a width-based presentation policy that selects bottom navigation for compact widths, a compact toolbar for regular widths, and a sidebar/workbench navigation for expanded widths.
- [ ] Route iOS entry points through the adaptive shell while retaining iOS file-picking adapters.
- [ ] Build the iOS target and run presentation tests.

### Task 2: Share the transfer setup and destination route

**Files:**
- Create: `BitMatch/Views/Adaptive/AdaptiveTransferSetupView.swift`
- Modify: `BitMatch/Views/CopyAndVerify/TransferPlanView.swift`
- Modify: `BitMatch-iPad/Views/CopyAndVerifyView.swift`
- Test: `BitMatchTests/AdaptiveTransferSetupPresentationTests.swift`

- [ ] Write tests for source/destination presentation, preflight status, and transfer workflow choice.
- [ ] Extract the common route, workflow, preflight, and primary-action composition from the Mac transfer plan.
- [ ] Use a vertical source-to-destinations route on iPhone, a two-column route on sufficiently wide iPad and Mac, and the same titles and actions in each.
- [ ] Build Mac and iOS targets; run the focused presentation tests.

### Task 3: Bring project and remote-backup stages to iOS

**Files:**
- Modify: `BitMatch/Views/Photographer/PhotographerJobSetupView.swift`
- Modify: `BitMatch/Views/Photographer/RemoteBackupDestinationView.swift`
- Modify: `BitMatch-iPad/Views/CopyAndVerifyView.swift`
- Test: `BitMatchTests/PhotographerStartPresentationTests.swift`

- [ ] Write tests proving project-transfer readiness and remote-backup copy use the same presentation state on both platforms.
- [ ] Make project setup and the optional remote stage responsive rather than desktop-only.
- [ ] Expose saved destinations through the iOS settings route; preserve host-trust and SSH-agent safety rules on supported platforms.
- [ ] Build and run focused photographer presentation tests.

### Task 4: Unify active transfer, evidence, and recovery states

**Files:**
- Create: `BitMatch/Views/Adaptive/AdaptiveTransferStatusView.swift`
- Create: `BitMatch/Views/Adaptive/AdaptiveEvidenceView.swift`
- Modify: `BitMatch/Views/CopyAndVerify/CopyAndVerifyView.swift`
- Modify: `BitMatch-iPad/Views/OperationProgressView.swift`
- Modify: `BitMatch-iPad/Views/CompletionSummaryView.swift`
- Test: `BitMatchTests/TransferOperationPresentationTests.swift`

- [ ] Write tests for copying, paused, verifying, safe, and issue-required state copy and control availability.
- [ ] Compose compact and expanded layouts from the same transfer operation and completion presentation models.
- [ ] Verify no active transfer state offers a fictional control or hides the recovery action.
- [ ] Build Mac and iOS targets and exercise compact, regular, and expanded UI smoke paths.

### Task 5: Retire duplicate iOS-only shells and verify the product surface

**Files:**
- Modify: `BitMatch-iPad/Views/ModularContentView.swift`
- Modify: `BitMatch-iPad/Views/PhoneContentView.swift`
- Modify: `BitMatch-iPad/Views/HeaderTabsView.swift`
- Test: `BitMatch-iPadUITests/BitMatch_iPadUITests.swift`

- [ ] Replace or remove duplicated navigation and transfer-plan composition after the shared shell owns it.
- [ ] Add smoke assertions for iPhone portrait, iPad portrait split view, and iPad landscape.
- [ ] Build and test both targets; review screenshots at all three sizes.
- [ ] Commit each independently verified task and remove build artifacts.
