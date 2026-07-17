# Project Workflow Framing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Projects and Off-site Backup the shared BitMatch workflow while retaining Photography and Video/DIT as safe, optional presets.

**Architecture:** Keep the established photographer persistence and transfer engine as the compatibility substrate for this release. Add a Codable `ProjectWorkflow` with a default of `.photography` when decoding old payloads, then derive UI labels and safe folder defaults from that workflow. Existing wedding records retain their current paths, provenance, reports, and behavior.

**Tech Stack:** Swift 6, SwiftUI, Core Data Codable payloads, existing `FolderRecipe` and remote queue.

## Global Constraints

- Existing persisted jobs must decode as `.photography` and render unchanged paths.
- This release changes product language and presets; it does not rename Core Data entities, report keys, or internal compatibility types.
- Video/DIT creates exact verified copies; it does not transcode, generate proxies, or alter media.
- Off-site backup remains macOS OpenSSH/agent-only and is optional for every workflow.
- No app, simulator, test binary, or runtime test may be launched locally; compile-only builds only.

## Task 1: Persist a workflow discriminator compatibly

**Files:** Modify `Shared/Core/Models/PhotographerJobModels.swift`; test `BitMatchTests/PhotographerJobStoreTests.swift`.

- [ ] Define `enum ProjectWorkflow: String, Codable, CaseIterable, Sendable { case photography, videoDIT, general }` with title, contributor label, and source-unit label.
- [ ] Add `workflow: ProjectWorkflow` to `PhotographerJob` and `PhotographerPreset`; use `decodeIfPresent(... ) ?? .photography` in custom decoding so every old payload remains valid.
- [ ] Add source tests for an old job payload decoding to photography and a video/DIT job retaining `.videoDIT` after persistence.
- [ ] Compile-only validate macOS and iPad; commit `feat: persist project workflows`.

## Task 2: Create workflow-specific safe defaults

**Files:** Modify `Shared/Core/Models/PhotographerJobModels.swift`, `BitMatch/Core/ViewModels/PhotographerJobViewModel.swift`; test `BitMatchTests/FolderRecipeRendererTests.swift`, `BitMatchTests/PhotographerJobViewModelTests.swift`.

- [ ] Define recipes for Photography (`date/job/Originals/photographer/camera/card`), Video/DIT (`date/job/Camera Originals/camera/card`), and General (`date/job/Originals/card`).
- [ ] Add a view-model workflow selection entry point that updates only unstarted draft/project setup; never changes an existing card's rendered destination.
- [ ] Test that every workflow's rendered components are sanitized and that changing the selected workflow after a card is prepared invalidates the draft rather than rewriting it.
- [ ] Compile-only validate macOS and iPad; commit `feat: add project workflow presets`.

## Task 3: Reframe the setup and dashboard UI

**Files:** Modify `BitMatch/Views/Photographer/PhotographerJobSetupView.swift`, `BitMatch/Views/Photographer/PhotographerSessionDashboard.swift`, `BitMatch/Views/CopyAndVerify/TransferPlanView.swift`, and presentation models/tests.

- [ ] Replace user-facing “Photography job” framing with “Project setup”; show a compact workflow picker before card preparation.
- [ ] Drive labels from the selected workflow: Photographer/Camera/Card for photography, Operator/Camera/Media for video/DIT, and Contributor/Source/Package for general.
- [ ] Keep setup compact and show Off-site Backup once, independent of workflow.
- [ ] Preserve local/off-site evidence wording exactly; test that fully backed up remains unavailable unless every remote manifest item verifies.
- [ ] Compile-only validate macOS and iPad; commit `feat: present projects with media workflow presets`.

## Task 4: Generalize exported copy while preserving schema compatibility

**Files:** Modify `BitMatch/Core/Services/ReportExporter.swift`, `BitMatch/Views/ReportView.swift`, report tests.

- [ ] Add a human-facing workflow label to report headings and CSV/PDF descriptions, but retain existing machine-readable photography keys for backward compatibility.
- [ ] Ensure labels never expose credentials or host keys.
- [ ] Compile-only validate macOS and iPad; commit `feat: label reports by project workflow`.
