# Accessibility audit, 2026-09-25

Read-only audit of every reachable SwiftUI view on Mac, iPad and iPhone. It checks five things:

- controls with no accessibility label
- actions that only appear on hover
- touch targets under 44pt
- fixed font sizes that break Dynamic Type
- status shown by color alone

It judges them against AGENTS.md ("essential information and actions must work with touch and without hover") and THESIS P2 ("green means verified, red means real").

No code was changed. Nothing here was compiled or run: there is no Xcode in the audit environment. Line numbers are from `origin/main` at the time of writing. They come from reading the source and were spot-checked a second time. They were not checked in VoiceOver, the Accessibility Inspector, or on a device.

## Short answer on P2: can a colorblind user tell verified from failed?

**Mostly yes, on the final verdict. No in several places before and around it.** Some of those gaps would mislead every user, not only colorblind ones.

**Colorblind-safe (distinct shape and distinct text):**
- the completion verdict header on all platforms, which uses `CompletionVerdictPresentation`
- the per-destination completion rows
- the preflight cards
- the Photographer dashboard rows
- per-row status in the Mac results table

**Not safe:**
1. **The iPad/iPhone destination queue shows a green checkmark and "Done" for every destination as soon as copying ends.** That includes the whole verify stage and destinations where every copy failed (C1). This is a false green for everyone.
2. **"✅ Copied" rows (no checksum) get the same green checkmark as "✅ Verified"**, and can produce a "Transfer complete" verdict and a "VERIFICATION SUCCESSFUL" PDF seal (C2).
3. **The Mac live counters are two identical 6pt dots with bare numbers, green and orange** (H1). A red/green colorblind user cannot tell which number is the failures.
4. **A checksum mismatch uses the same yellow triangle as "missing" or a warning** (H2). It is not visibly worse than an I/O error.
5. **Green is also used for "in progress" and "selected"** (H5). That weakens green as the "verified" signal.

A root cause shared by 2 and 4: there is **no shared per-row status model**. `ResultsTableView` and `ReportView` each parse emoji status strings into symbols and colors. The main structural fix is one `ResultStatusPresentation` in `Shared/Core/Models` that gives a symbol, tint and spoken label for each of Verified, Copied (not verified), Checksum mismatch, Failed and Missing (see C2).

## Cross-cutting facts

- **No VoiceOver announcements anywhere.** A grep of `BitMatch/`, `BitMatch-iPad/` and `Shared/` finds no `AccessibilityNotification`, `UIAccessibility.post` or `NSAccessibility.post` (C3).
- **No Dynamic Type support in custom text.** There are 527 `.font(.system(size:))` literals and no `@ScaledMetric` or `dynamicTypeSize` anywhere. `DesignSystem.Typography` (`BitMatch/UI/DesignSystem.swift:105-123`) fixes every token at 9–16pt. The Shared views (`CompareResultsView`, `TransferLibraryView`) are the exception: they use only text styles.
- **Reduce Motion is honored in only a few places.** It is used in `ContentView` (Mac), `CopyAndVerifyView` (Mac), `TransferPlanView`, `InterfaceLabView` and `MobileTransferWorkflowPicker`. Every `.repeatForever` pulse ignores it (M9).
- **Hover:** no essential action is hover-only. `.onHover` in `CompactTransferCard.swift:381` only changes the highlight and cursor. The problem next to it is a click-only non-button (H9).
- **No `.isSelected` trait anywhere.** Every custom picker, chip and tab shows selection only by color, opacity or a glyph (M1).

## Where each view runs

| Area | Files | Platform |
|---|---|---|
| Mac shell | `BitMatch/App/ContentView.swift`, `BitMatch/Views/**`, `BitMatch/UI/**` | macOS only |
| iPad/iPhone shell | `BitMatch-iPad/**` | iOS (iPhone and iPad) |
| Shared views | `Shared/Views/CompareResultsView.swift`, `Shared/Views/TransferLibraryView.swift` | all three |
| PDF only | `BitMatch/Views/ReportView.swift` (rendered by `ReportExporter.swift:254`) | evidence file |

These look unreachable or dev-only and are listed only where they matter:
- `DestinationDetailView` (only its `TransferState.displayName` extension is used)
- `MHLStatusBadge`, `Card`, `CompletionView` and `DropZoneModifier`
- `EnhancedDestinationCard` and `IpadTransferPlanOptionSummary` (iPad)
- `ReadinessBannerView` (always passed `showsReadinessBanner: false`)
- `InterfaceLabView` (DEBUG only)

`HeaderTabsView` **is** live: it is the iPad mode switcher at widths 600–959pt (`HeaderTabsView.swift:85`).

---

## Critical

### C1. The iPad/iPhone destination queue says "Done" (green checkmark) before verification, and for failed destinations
**Platforms:** iPad, iPhone · `BitMatch-iPad/Views/OperationProgressView.swift:84-92`, `:498`, `:507`, `:520`

`queueState` returns `.completed` when `progressFraction >= 1.0`. `.completed` renders as `checkmark.circle.fill`, `.green` and "Done". The fraction comes from `perDestinationCompleted`. In the service, that count is only increased in the copy phase, and it also counts failures:
- `Shared/Core/Services/SharedFileOperationsService.swift:504` counts a destination that could not be pinned.
- `:540` counts a copied file.
- `:715` counts a copy error.

Verification never touches this count, and the verify snapshots at `:776-777` report the same counts. So every row reaches 1.0 when copying finishes, and shows a green "Done" through the whole verify stage. That happens even for a destination where every file failed. There is no failed or issue state for a queue row.

**Fix:**
- Track verified and failed counts per destination alongside `completed`.
- Derive the row state from those counts:
  - `.copied`: "Copied, verifying…", `doc.on.doc`, neutral tint
  - `.verified`: only when `verified == total && failed == 0`, `checkmark.seal.fill`, green, "Verified"
  - `.failed`: "N failed", `xmark.octagon.fill`, red
- Rename "Done" to "Verified".
- The counter change belongs in the shared service. That file is not on the hands-off list, but it sits next to `CopyVerifyExecutor`, so coordinate with the Mac session.

### C2. "✅ Copied" (no checksum) looks the same as "✅ Verified"
**Platforms:** Mac results, PDF evidence; the verdict affects all three

- **Where it comes from:** `Shared/Core/Services/ServiceProtocols.swift:116-125` returns `"✅ Copied"` when there is no `verificationResult`.
- **Counted as success:** `ResultRow.isSuccessStatus` (`Shared/Core/Models/TransferModels.swift:112-116`) needs only "✅" and no failure marker, so it treats Copied as success.
- **Mac results table:** these rows get the same green `checkmark.circle` as Verified (`BitMatch/Views/ResultsTableView.swift:487-491`, `:502-506`).
- **PDF:** `ReportView.swift:142` and `:635-639` show the success seal "VERIFICATION SUCCESSFUL / All files verified with 100% accuracy".
- **Verdict:** `CompletionVerdict` returns `.success` from `ResultPresentation.swift:84-88` unless there are errors. That shows "Transfer complete — Every reported file has a verified result." (`CompletionVerdictPresentation.swift:13-15`).
- **The only warning:** `DestinationResultSummary.unverifiedCount` (`ResultPresentation.swift:138`).

This breaks P2 for every user. It is also a colorblind issue, because the only thing that separates Copied from Verified is the word in the status column.

**Fix:**
- Add a shared `ResultStatusPresentation` with a distinct `copiedUnverified` case: `doc.on.doc` or `checkmark.circle.badge.questionmark`, a neutral or amber tint, and the label "Copied – not verified". Use it in `ResultsTableView` and `ReportView` in place of their duplicated `statusSymbol` and `statusColor`.
- Show the PDF success seal only when `unverifiedCount == 0`.
- **Hands-off:** the verdict change (return a "copied, not verified" or `.issues` verdict when any row is unverified) belongs in `CompletionVerdict*.swift`, which the Mac session owns. It is listed here for that session.
- **Not verified:** which verification modes emit rows with no `verificationResult` in practice. Check whether Quick mode sets a size-only `verificationResult` before judging how common this is.

### C3. No VoiceOver announcement when a transfer or comparison finishes, fails or is cancelled
**Platforms:** all three · no `AccessibilityNotification`, `UIAccessibility.post` or `NSAccessibility.post` in the codebase

Transfers run for minutes to hours. Here is where the verdict appears:
- On iPad/iPhone the screen swaps from `OperationProgressView` to `CompletionSummaryView` (`ModularContentView.swift:83-101`, `PhoneContentView.swift:72-80`). VoiceOver focus is lost, and the only `onChange(of: operationState)` (`ModularContentView.swift:41-46`) just logs.
- On Mac the verdict appears silently in `ResultsTableView.swift:44-48`.
- Compare results (`Shared/Views/CompareResultsView.swift:22`) are silent too.

A blind user is never told whether the copy passed.

**Fix:**
- Where the view observes `operationState` or `completionPresentation`, post `AccessibilityNotification.Announcement("\(p.title). \(p.detail)").post()`, using `CompletionVerdictPresentation`, which already has the right words. On iOS that is iPad `ModularContentView` plus the phone path in `ContentView`; on Mac it is `ContentView` or `ResultsTableView`.
- On iOS, also add `@AccessibilityFocusState` to `CompletionStatusHeaderView` and focus it on appear.
- Announce Copying → Verifying phase changes.
- Announce compare completion from `CompareResultsView.onAppear`.
- Announce queue completion in `TransferLibraryView`.
- **Hands-off:** do not add this inside `SharedAppCoordinator`. Keep it in the views.

---

## High

### H1. Mac live match and issue counts are same-shape dots, green vs orange, with bare numbers
**Mac** · `BitMatch/Views/ResultsTableView.swift:250-259` (match), `:262-271` (issues), `:238-247` (file count)

```swift
Circle().fill(.green).frame(width: 6, height: 6)
Text("\(progress.matchCount)")...foregroundColor(.green)
```
The issue view is the same with orange. It is the only live summary during a Mac transfer. A red/green colorblind user sees "480 ● 3 ●", and VoiceOver reads "480", "3", "12/40".

**Fix:** `Label("\(n) verified", systemImage: "checkmark.circle.fill")` and `Label("\(n) issues", systemImage: "exclamationmark.triangle.fill")`. You can keep the counts compact visually with `.labelStyle(.titleAndIcon)` or `.accessibilityLabel(...)`. For the file count, add `.accessibilityLabel("\(done) of \(total) files processed")`.

### H2. A checksum mismatch looks like a minor warning
**Mac results and PDF** · `ResultsTableView.swift:492-495`, `:507-510`; duplicated in `ReportView.swift:783-786`, `:798-801`

`"⚠️ Checksum Mismatch"` does not match the `❌ / error / failed` branch, so it falls through to the yellow `exclamationmark.triangle`. That is the same symbol and color as "missing" or a generic warning. A real I/O error gets red `xmark.circle`, so corrupted data looks less serious than a failed read.

**Fix:** in the shared `ResultStatusPresentation` (C2), map mismatch to `xmark.octagon.fill`, red, "Checksum mismatch". Until then, check `mismatch` before the warning branch in both files.

### H3. Mac queue card: a failed completion shows as a green "✓ Complete", and states are shown by color alone
**Mac** · `BitMatch/Views/CompactTransfer/TransferQueueView.swift:268-275`; `CompactTransferCard.swift:30-36`, `:236-280`, `:310-326`, `:346-347`

**Wrong state:**
- `CompactTransferCard.TransferState` has no failed, issues, paused or cancelled case.
- `case .completed: return .completed` ignores `OperationCompletionInfo.success`, so a failed completion renders as green "Complete".
- `default: return .idle` renders paused, failed and cancelled as "Ready".
- How often this shows is limited: the card only renders while `isOperationInProgress`, and the completed list is DEBUG-only. It is still a green shown for a failure.

**Color alone:**
- Copying and verifying are told apart only by the bar tint (blue or orange).
- Each destination row is a tinted fill with a 7pt percentage.
- The card has no accessibility element, and the `ProgressView` (`:238`) has no label.

**Fix:**
- Drive the card from a shared presentation (title, symbol, tone) and map `.completed(let info)` to `info.success ? .verified : .issues`.
- Show state text next to the bar.
- Use `.accessibilityElement(children: .combine)` with `.accessibilityLabel("\(source), \(state), \(pct)%")`.
- Longer term, this card goes away when the UI shells are merged (THESIS plan step 4).

### H4. iPad/iPhone controls with no accessible name
- `BitMatch-iPad/Views/CopyAndVerifyView.swift:1505`: `Toggle("", isOn: $coordinator.reportSettings.makeReport)`. VoiceOver says "switch button, on".
  - **Fix:** `Toggle("Generate reports", isOn: …).labelsHidden()`.
- `CopyAndVerifyView.swift:425-429` (`setupField`): the visible title is a separate `Text`, and the field is `TextField(prompt, …)`. VoiceOver reads the example ("Smith"), not "Client".
  - **Fix:** `TextField(title, text: text, prompt: Text(prompt))`.
- **Mac, same pattern:**
  - `BitMatch/Views/CopyAndVerify/CameraLabelView.swift:110` (TextField labelled by its placeholder)
  - `:136` (`Picker("", …)`)
  - `BitMatch/Views/Photographer/RemoteBackupDestinationView.swift:240-246` (TextFields)
  - `:229-232` (`Menu` with only `ellipsis.circle`)
  - **Fix:** give each a real title plus `.labelsHidden()`, or add `.accessibilityLabel`.

### H5. Green used for "in progress" and "selected", not only "verified"
- `BitMatch/Views/CopyAndVerify/CopyAndVerifyView.swift:108-110`: the in-progress header icon is green (orange when paused). While verifying, that icon is `checkmark.shield.fill`, the same glyph as the dashboard's "Locally Safe".
- `BitMatch-iPad/Views/OperationProgressView.swift:178`: `LinearProgressViewStyle(tint: .green)`. The bar stays green even when `hasErrors`.
- `BitMatch/Views/CompactTransfer/TransferQueueView.swift:114-122`: pulsing green "LIVE".
- Selected state shown in green:
  - `TransferPlanView.swift:143`, `:149`, `:155-156`: the selected workflow gets green `checkmark.circle.fill`, the same glyph as "completed".
  - `CameraLabelView.swift:166`, `:259`
  - `HorizontalFlowView.swift:110`, `:176`
  - `PhotographerJobSetupView.swift:111-116`
  - `CompactTransferCard.swift:426`
- The in-progress "Verifying" symbol `checkmark.shield.fill` (from `TransferOperationPresentation`) and the "Verification" stat card (`BitMatch-iPad/Views/CompletionSummaryView.swift:152-157`, shown even when a transfer fails) both use a check before anything is verified.

**Fix:** reserve green and `checkmark.*` for verified results.
- Use `.accentColor` or blue, and a non-check symbol (`shield`, `magnifyingglass`, `largecircle.fill.circle`), for progress and selection.
- Turn the progress bar orange when `hasErrors`.
- Add `DesignSystem.Colors.selection` and write the rule in a doc comment in `DesignSystem.swift`.

### H6. Primary iPad/iPhone controls are below 44pt
| Control | Location | Approx. size |
|---|---|---|
| Settings gear, the only way into Settings at iPad widths (it does have a label) | `ModularContentView.swift:119-127` | ~22×22 |
| Pause / Resume / Cancel during a transfer | `OperationProgressView.swift:254-311` | ~37pt tall |
| Compare Cancel | `ModularContentView.swift:466-479` | ~37pt tall |
| Compact mode `Menu` (iPhone's only mode switch) | `HeaderTabsView.swift:73-78` | ~32pt |
| Mode tabs (explicit `minHeight: 36`) | `HeaderTabsView.swift:30` | 36pt |

**Fix:** `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`, or system button styles with `.controlSize(.large)`.

### H7. Mac Compare: verification mode can only be picked with a tap gesture
**Mac** · `BitMatch/Views/CompareFoldersView.swift:195-237`

Each mode is an `HStack` with `.contentShape(Rectangle()).onTapGesture { coordinator.verificationMode = mode }`. It is not a Button, so Tab, Full Keyboard Access and VoiceOver cannot activate it or read which mode is selected.

**Fix:** use `Picker(selection:)` with `.pickerStyle(.radioGroup)`. Or wrap each row in `Button { … }.buttonStyle(.plain)` with `.accessibilityAddTraits(selected ? .isSelected : [])`.

### H8. The PDF evidence shows status by icon alone and has no failure headline
**PDF** · `BitMatch/Views/ReportView.swift:539-542`, `:696-710`, `:738-741`

- The manifest "Status" column is a 10pt tinted glyph with no word. Copied and Verified look the same (C2). In grayscale print, or for a colorblind reader, the tiny shapes are all there is.
- On failure there is only an orange "Issues Summary (n)" box. There is no "VERIFICATION FAILED" headline to mirror the success seal.
- `ImageRenderer` PDFs are untagged, so the CSV and JSON exports are the only screen-reader-readable record.

**Fix:**
- Put a short word next to the icon ("VERIFIED", "COPIED", "MISMATCH", "FAILED", "MISSING"), and widen the column to ~70pt.
- Add a headline row: `xmark.octagon.fill` "VERIFICATION FAILED – n files did not verify".
- Mention the CSV and JSON exports in the export UI as the accessible format.

### H9. Mac destination details: click-only non-button, no Escape, and made-up data
**Mac** · `CompactTransferCard.swift:372-389`; `TransferQueueView.swift:79-83`; `ContextualDestinationPopup.swift:20-24`, `:221-281`

- An 18pt row with `.onTapGesture` opens the popup. It has no button trait and cannot take keyboard focus.
- The popup closes only by clicking a `Color.clear`. There is no Escape key, no close button and no focus move.
- The popup shows guessed values as if they were facts, which breaks P2 "red means real":
  - Capacity "1TB" and connection "USB 3.2" are guessed from the drive name.
  - Time left is `remaining * 45` minutes.
  - The priority icons are "simulated based on index" (`CompactTransferCard.swift:423`).

**Fix:**
- Make each row a `Button`.
- Show details in `.popover(isPresented:)`, which handles Escape and focus.
- Delete the guessed fields and the fake priority icons.

### H10. Master Report (Mac): unlabeled icon controls and nested buttons
- `BitMatch/Views/MasterReport/TransferCardView.swift:30-37`: the selection button's label is only a `checkmark.circle.fill`/`circle` image.
  - **Fix:** `Toggle` with `.toggleStyle(.checkbox)`, or `.accessibilityLabel("Include \(name)")` plus `.isSelected`.
- `TransferCardView.swift:72-81`: verified vs not verified is a 12pt icon with no text or label (the shapes do differ).
  - **Fix:** `Label(transfer.verified ? "Verified" : "Not verified", systemImage: …)`.
- `TransferCardView.swift:13-15`: `.onTapGesture` on the whole card.
  - **Fix:** make the card a Button.
- `MasterReport/Components/CameraGroupView.swift:34-41`: a "select all" Button nested inside the header Button (`:13-48`), with an unlabeled `square` icon.
  - **Fix:** move it out of the header and label it "Select all \(camera)". Add an expanded or collapsed value to the header.

### H11. Status text too small to read, and fixed heights that clip it
- **Mac `CompactTransferCard.swift`:**
  - overall % 8pt (`:258`)
  - destination % 7pt (`:347`)
  - destination names 9pt (`:338`)
  - current file 8pt (`:247`)
  - fixed heights `:280` (12pt), `:286` (20pt), `:353` (18pt)
- **Mac `TransferQueueView.swift`:** headers 9pt (`:106`, `:162`, `:213`); "N PENDING", "N DONE" and "LIVE" 8pt (`:121`, `:169`, `:221`).
- **Mac Photographer dashboard verdict** ("Locally Safe" / "Issues"): `Typography.micro`, 9pt (`PhotographerSessionDashboard.swift:79-81`).
- **Mac results verdict banner:** detail 11pt (`ResultsTableView.swift:108`); "Keep source media intact…" guidance 10pt (`:112`). Row status is 10pt (`:420`) and 9pt (`:451`).
- **iPad/iPhone** (does not scale with Dynamic Type):
  - progress title 24pt (`OperationProgressView.swift:111`)
  - percent 13pt (`:172`)
  - queue state 11pt (`:460`)
  - file counts 10pt (`:474`)
  - issue counts 11pt (`:373`)
  - ErrorDetailsView counts and guidance 12–13pt (`CompletionSummaryView.swift:245`, `:259`, `:273`, `:282`)
  - Start 16pt (`CopyAndVerifyView.swift:1371`)
  - Pause and Cancel 14pt (`OperationProgressView.swift:261`, `:280`, `:301`)
  - project status 11pt (`CopyAndVerifyView.swift:150`)
  - toast 13pt (`ToastView.swift:13`)

**Fix:**
- iOS:
  - Use text styles for status, verdict and button text (`.headline`, `.subheadline`, `.footnote`, `.caption`), and `@ScaledMetric` for icon sizes.
  - Wrap the stats row (`OperationProgressView.swift:183`) and the controls row (`:251`) in `ViewThatFits`, so they reflow at accessibility sizes.
- Mac:
  - Keep no status text below 11pt.
  - Replace fixed `height:` with `minHeight:`.
  - Raise or retire the `micro` (9pt) and `caption` (10pt) tokens for status use.
- Replace `DesignSystem.Typography`'s fixed sizes with text-style-relative fonts, e.g. `.system(.caption, weight: .semibold)`. This one change fixes most tokenized uses on both platforms.

Fixed-size literal counts (`.font(.system(size:))`, 527 total):

| File | Count | Platform |
|---|---|---|
| `BitMatch-iPad/Views/CopyAndVerifyView.swift` | 92 | iOS |
| `BitMatch/Views/ReportView.swift` | 71 | PDF (acceptable, but the 8pt text at `:592`, `:598`, `:605`, `:717`, `:720` is too small) |
| `BitMatch/Views/InterfaceLab/InterfaceLabView.swift` | 54 | DEBUG |
| `BitMatch-iPad/Views/ModularContentView.swift` | 45 | iOS |
| `BitMatch/Views/ResultsTableView.swift` | 34 | Mac |
| `BitMatch-iPad/Views/OperationProgressView.swift` | 31 | iOS |
| `BitMatch/Views/HorizontalFlowView.swift` | 22 | Mac |
| `BitMatch/Views/CopyAndVerify/TransferPlanView.swift` | 19 | Mac |
| `BitMatch/Views/CompareFoldersView.swift` | 17 (plus a fixed `.frame(height: 180)` at `:104`) | Mac |
| `CameraLabelView`, `TransferQueueView`, `ContextualDestinationPopup`, `CompactTransferCard`, `CompletionSummaryView` | 14 each | Mac / iOS |
| All others | ≤ 12 each | |
| `Shared/Views/CompareResultsView.swift`, `Shared/Views/TransferLibraryView.swift` | 0 | all three (good) |

### H12. Result rows aren't grouped for VoiceOver and have no column headers
**Mac** · `ResultsTableView.swift:368`, `:384-424` (detailed), `:427-457` (compact)

Each row is five or more separate VoiceOver stops: the icon's auto-label, name, size, drive and status. There can be up to 1,000 rows. The detailed layout has no header row, so "80 KB" has no column name.

**Fix:**
- On the row, add `.accessibilityElement(children: .ignore)` and `.accessibilityLabel("\(file), \(status label), \(size), \(destination)")`.
- Add `.accessibilityRotor("Issues", …)` so users can jump between failures.
- Consider SwiftUI `Table` on Mac.

---

## Medium

### M1. Selected state shown only by color, opacity or a glyph, with no `.isSelected` trait
- **iPad/iPhone:**
  - mode tabs and sidebar: `HeaderTabsView.swift:27`, `:33`, `:102`, `:106`
  - Position and Separator chips (fill color only; separator labels are bare "_", "-", "."): `CopyAndVerifyView.swift:1111-1145`
  - `VerificationModeRow`: `:1243-1245`
  - `TransferSelectionCard`: `ModularContentView.swift:873-875`
- **Mac:**
  - `ModeSelectorView`: `BitMatch/UI/Components/Components.swift:65-86`
  - Preferences tabs: `PreferencesWindow.swift:68-86`
  - workflow choice: `TransferPlanView.swift:109-136`
  - separator and preset chips: `CameraLabelView.swift:154-170`, `:246-263`

**Fix:** use `Picker(...).pickerStyle(.segmented)` where it fits. Otherwise add `.accessibilityAddTraits(isSelected ? .isSelected : [])` and hide the indicator image. Give the separator chips spoken names ("Underscore", "Hyphen", "Period").

### M2. Collapsible headers don't expose expanded or collapsed state
- iPad:
  - `CollapsibleLabelingSection` (`CopyAndVerifyView.swift:943-975`)
  - `CollapsibleVerificationSection` (`:1155-1199`)
  - the project setup header (`:292-307`)
- Mac:
  - Compare verification header (`CompareFoldersView.swift:145-190`)
  - `CameraGroupView` header (`:13-48`)

**Fix:** use `DisclosureGroup`, as the iPad Advanced section at `CopyAndVerifyView.swift:65` already does. Otherwise add `.accessibilityValue(isExpanded ? "Expanded" : "Collapsed")` and hide the chevron.

### M3. Status rows and stat tiles read as scattered fragments
- iPad queue rows: `OperationProgressView.swift:446-482` (six or more stops each; fix together with C1)
- completion destination rows and verdict header: `CompletionSummaryView.swift:28-36`, `:102-116`. The verdict is not a heading.
- `StatView`: `OperationProgressView.swift:223-234`, `BitMatch/Views/MasterReport/Components/StatView.swift:10-17`
- `SummaryStatCard`: `CompletionSummaryView.swift:188-202`
- Mac verdict banner: `ResultsTableView.swift:94-122`
- history cards and file rows: `TransferLibraryView.swift:88-151`, `:141-144`

**Fix:**
- Add `.accessibilityElement(children: .combine)`, or `.ignore` with a composed label.
- Add `.accessibilityAddTraits(.isHeader)` to verdict titles.
- Hide the verdict symbol image.

### M4. Mac verdict: the failure rows are collapsed by default
**Mac** · `ResultsTableView.swift:52`

`DisclosureGroup("File details")` starts collapsed even when the verdict is Review required or Failed. The rows that show *what* failed take an extra step to reach for every user, and for VoiceOver users they are the only evidence.

**Fix:** start expanded (or filtered to issues) when the verdict is not success.

### M5. Transfer history: issue and interrupted states are no more prominent than "Queued"
**All three** · `Shared/Views/TransferLibraryView.swift:92-93`

`foregroundStyle(record.state == .completed ? .green : .secondary)`. The text differs, so this is colorblind-safe, but "Issues" and "Interrupted" are drawn in the same gray as "Queued".

**Fix:** use a `Label(stateTitle, systemImage:)` for each state, with a distinct symbol and an orange or red tint for issues.

### M6. Compare verdict says "Folders match" in quick mode
**All three** · `Shared/Views/CompareResultsView.swift:22-23`

The headline is text-only (colorblind-safe) but has no symbol or header trait. In quick mode it still says "Folders match"; the size-only caveat is only in the secondary text at `:32`.

**Fix:** use `Label(isQuick ? "Sizes match" : "Folders match", systemImage: …)` with `.isHeader`, and `xmark.circle.fill` "Folders differ".

### M7. iPhone and iPad secondary controls below 44pt
- Camera preset chips (~25pt): `CopyAndVerifyView.swift:1020-1033`
- Position and Separator chips (~20pt): `:1111-1145`
- "Clear Selection" (~13pt): `ModularContentView.swift:360-367`
- "Select All / Deselect All" (~17pt): `:823-834`
- Preparing "Cancel" with `.controlSize(.small)` (~28pt): `CopyAndVerifyView.swift:410`
- Transfer history row actions ("Remove from queue", "Reconnect…", "Retry", the "Export" menu, ~22pt): `TransferLibraryView.swift:103-120`
- "Retry without ASC MHL" inside a `.caption` container (~16pt): `:133`, `:147`
- The history "Details" disclosure: `:126`
- Compare Export menu: `CompareResultsView.swift:66-69`

**Fix:** `.frame(minHeight: 44).contentShape(Rectangle())`, or `.buttonStyle(.bordered).controlSize(.large)`. Drop `.controlSize(.small)` on iOS.

### M8. Mac small hit targets and icon buttons with only a tooltip
- **Preferences gear:** `ContentView.swift:231-240` has only `.help("Preferences")` (a tooltip is not a reliable label), a 28pt frame and no `contentShape`.
  - **Fix:** `.accessibilityLabel("Settings").contentShape(Rectangle())`.
- **Clear-folder `xmark`:** `CompareFoldersView.swift:307-313` has no label and a ~13pt hit area.
  - **Fix:** `.accessibilityLabel("Clear \(name)").frame(width: 24, height: 24).contentShape(Rectangle())`.
- **Glyph-only hit areas:**
  - remove-source is a bare 14pt glyph: `HorizontalFlowView.swift:143-151`
  - remove-backup has a 32pt frame, but without `contentShape` only the glyph is hittable: `:347-356`
  - the history button has the same frame problem: `ContentView.swift:225-228`
  - layer arrows: `PhotographerJobSetupView.swift:323-334`
  - **Fix:** `.frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())`.

### M9. Reduce Motion ignored
- Repeating pulses:
  - `OperationProgressView.swift:398` (issues border)
  - `TransferQueueView.swift:118`, `:149`
  - `MasterReportScanningView.swift:29`
- Transitions and springs:
  - iPad: `CopyAndVerifyView.swift:119-120`, `:1094-1097`, `:1215-1218`; `ModularContentView.swift:34`
  - Mac: `CompactTransferCard.swift:390-391`; `ContextualDestinationPopup.swift:38-44`, `:313`; `HorizontalFlowView.swift:215`, `:262`, `:381-382`; `CameraLabelView.swift:231`, `:247`; `Components.swift:66`, `:103`; `PhotographerJobSetupView.swift:85-86`; the toast in `ContentView.swift:574-591`

**Fix:** read `@Environment(\.accessibilityReduceMotion)`. Don't start a pulse when it is on, and use `nil` animation or an `.opacity` transition, as `ContentView.swift:125-127` already does.

### M10. Toasts vanish quickly and are silent
- Mac: `ContentView.swift:135-146`, `:573-594`. Drop-rejection reasons last 2.5s; cancel lasts 1.8s.
- iPad: `ModularContentView.swift:31-38`, `:56-65`.

**Fix:** post an `AccessibilityNotification.Announcement`. For a drop rejection, keep the reason on screen until the next action.

### M11. Photographer dashboard rows combine children that include buttons
**Mac** · `PhotographerSessionDashboard.swift:122-126` (buttons at `:92`, `:105`, `:109`)

`.accessibilityElement(children: .combine)` plus a custom label may absorb the Queue, Retry and Cancel buttons into one element. Check this in VoiceOver.

Also, "Remote Failed" uses the `warning` (orange) color, not `error` (`:100`).

**Fix:**
- Use `.contain` with the summary on an inner element, or add `.accessibilityActions { … }` for each button.
- Color "Remote Failed" with `error`.

### M12. Mac results filter toggle label changes with its own state
**Mac** · `ResultsTableView.swift:225-233`

The label is `Label(showOnlyIssues ? "Show All" : "Issues Only", …)`, so VoiceOver says "Show All, on".

**Fix:** use a stable label, `Toggle("Show issues only", systemImage: "exclamationmark.triangle", isOn:)`.

---

## Low

- **L1. Swipe-only delete for saved SFTP destinations** (`ModularContentView.swift:1154`). VoiceOver exposes it as a custom action, but touch and pointer users get no visible alternative.
  - **Fix:** add an Edit mode or a visible delete button, plus `.contextMenu`.
- **L2. Replacing a Mac backup is drag-only** (`HorizontalFlowView.swift:375-380`). Remove then Add works as an alternative, but the hint at `TransferPlanView.swift:224` says "replace".
  - **Fix:** add a "Replace…" button or a context-menu item.
- **L3. Decorative images not hidden** from VoiceOver.
  - Locations:
    - `CopyAndVerifyView.swift` (iPad): `:567`, `:637`, `:696`, `:750`
    - `CompletionSummaryView.swift:189`
    - `ToastView.swift:10`
    - `HorizontalFlowView.swift:108-111`, `:183`, `:230`, `:325`
    - `CompactTransferCard.swift:193`
    - `CameraLabelView.swift:69`
    - `ResultsTableView.swift:168`, `:240`, `:280`, `:304`, `:408`
    - `CompareFoldersView.swift:152`, `:156`
    - `MasterReportEmptyState.swift:12`
    - `MasterReportScanningView.swift:13-33`
  - **Fix:** `.accessibilityHidden(true)`.
- **L4. A selected folder card still announces as a button that does nothing** (`ModularContentView.swift:275-280`).
  - **Fix:** disable it once a folder is chosen.
- **L5. An "Active" dot that is always green** (`PreferencesWindow.swift:271-278`). It shows green whatever the real state is.
  - **Fix:** bind it to the real state, or remove it.
- **L6. Low-contrast text:** `.white.opacity(0.3–0.4)` on dark backgrounds, likely below 4.5:1.
  - Locations: `CompareFoldersView.swift:318`, `ResultsTableView.swift:291`, `:315`, `:336`, `MasterReportTransfersView.swift:114`.
  - **Fix:** use at least 0.6 opacity, or `.secondary`.
- **L7. Emoji in status strings** ("⚠️ Checksum Mismatch") are read aloud, e.g. "warning sign Checksum Mismatch".
  - **Fix:** the spoken label from the shared `ResultStatusPresentation` (C2) fixes this.
- **L8. Dead completion helpers** in Mac `ContentView.swift:361-392`. Cancelled (`xmark.circle`) and failed (`xmark.circle.fill`) use near-identical shapes there.
  - **Fix:** delete them (THESIS plan step 1).
- **L9. `ReadinessBannerView` separates issues from warnings only by 4pt red vs orange dots** (`CopyAndVerifyView.swift:1429-1433`, `:1469-1471`). Its spoken summary is fine, and the banner is not shown today.
  - **Fix:** fix the dots before the banner is reused.

---

## Done well (keep these patterns)

- **Colorblind-safe verdicts:**
  - `CompletionVerdictPresentation` gives each verdict both a distinct symbol and a distinct title (`checkmark.circle.fill` / `exclamationmark.triangle.fill` / `xmark.circle.fill`).
  - Per-destination completion rows pair check or triangle with text.
  - Mac per-row status always shows a symbol plus the status text.
- **Preflight cards** use distinct symbols and text for each tone, and combine into one spoken summary: `TransferPlanView.swift:238-252`, and `BitMatch-iPad/Views/CopyAndVerifyView.swift:512-513`.
- **Photographer dashboard:**
  - Shared status title and symbol, with "N of M verified" text.
  - Distinct remote states ("Fully Backed Up" vs "Uploaded · Unverified" vs "Remote Failed").
  - `@AccessibilityFocusState` and `@FocusState` handling.
- **iPad buttons:**
  - Clear-source and remove-destination buttons are 44×44 with `contentShape`, labels and hints (`CopyAndVerifyView.swift:625-628`, `:917-920`).
  - Add Destinations, the Transfers button, the Advanced disclosure and the completion actions all set `minHeight: 44`.
  - `MobileTransferWorkflowPicker` has a label, a "Selected" value and Reduce Motion support.
- **Mac:**
  - The Start button has a blocker-aware hint.
  - Menu commands and keyboard shortcuts exist (⌘R, ⌘., ⌘1-3, ⌘,).
  - `CompactModeSelectorView` has a label and a value.
- **Shared views** `CompareResultsView` and `TransferLibraryView` use only Dynamic Type text styles. `TransferLibraryView.swift:226-229` uses an icon-only `Label` that still gives VoiceOver the text.
- **Safe status fallback:** `ResultRow.isSuccessStatus` treats any unknown status as an issue.

## Suggested order

1. **C1 and C2:** P2 correctness for every user, and the largest colorblind risk. C2's verdict part needs the Mac session (it owns `CompletionVerdict*.swift`).
2. **C3, H1 and H2:** announcements, labelled counters, and mismatch shown as a failure.
3. **H4 and H6:** the missing names and undersized primary targets on iPhone and iPad.
4. **H11:** convert `DesignSystem.Typography` to text-style-relative fonts, then the iPad status and button text.
5. **The rest,** preferably folded into THESIS plan step 4 (merging the UI shells), so each fix is made once in the shared screen rather than twice.

## What this audit could not verify

- Nothing was compiled, and nothing was run in the simulator, in VoiceOver, in the Accessibility Inspector or on a device. Every "approx. size" comes from reading frames, padding and font sizes, not from measuring.
- Contrast ratios were not measured.
- It was not checked which verification modes produce `"✅ Copied"` rows in practice (C2).
- It was not checked whether the Photographer dashboard's `.combine` actually hides its buttons (M11).
- Whether each view is reachable was inferred by grepping for references. The Xcode project uses folder-based membership, so a file that exists but is never instantiated was treated as unreachable.
