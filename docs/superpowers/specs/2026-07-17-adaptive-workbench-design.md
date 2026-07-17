# Adaptive Workbench Design

## Intent

BitMatch is a calm transfer instrument for people who need confidence without a control-room interface. It opens as a compact, focused window for a simple copy; when a person widens the window or selects a project workflow, the interface earns that space with clearer structure rather than leaving empty black margins.

## Product stance

The primary audience is a photographer or filmmaker transferring media on set, in a studio, or at a desk. Their immediate job is to answer four questions with little thought: what am I copying, where is it going, is it safe to start, and what will prove it worked. Project work adds context and off-site backup without turning a quick transfer into a setup ritual.

## Visual direction

The workbench uses a graphite field rather than pure black, warm source amber, cool backup blue, and one restrained verification green. System typography remains San Francisco for legibility; technical values use the existing monospaced treatment. The signature element is a responsive transfer rail: source and destination cards read as one continuous route on wide windows and fold into a clear vertical route on compact windows.

## Responsive behavior

- The app opens at a compact, task-appropriate size, but no root view fixes its width.
- At compact widths, the transfer route stacks source, direction marker, and backups. Controls stay one-column and touch targets remain comfortable.
- At workbench widths, the route becomes a three-part horizontal rail, folder selection can use the full canvas, and the two workflow choices sit beside their explanation rather than competing for vertical space.
- The content background always fills the available window. Maximum reading widths are applied only to dense prose, never as a fixed app canvas.
- Automatic window sizing happens only when BitMatch changes modes or reveals a substantial setup area. A manual resize is respected.

## Flow

1. Choose a source and one or more backups in the transfer rail.
2. Pick Quick transfer or Project transfer. Project setup appears only after it is chosen.
3. Read one plain-language readiness state, adjust options only when needed, and start the transfer from one stable action area.
4. During and after a transfer, see the evidence and the controls that matter, with cancellation always reachable.

## Architecture

`AdaptiveWorkbenchLayout` is a small pure policy that maps available width to compact or expanded presentation. It is testable without SwiftUI and used by `ContentView` and `TransferPlanView`. SwiftUI geometry supplies current width locally; window management keeps a compact initial size but stops forcing width after a user-resizeable window is visible.

## Validation

- Policy tests lock the compact and expanded thresholds.
- macOS build-for-testing validates compilation.
- A local app launch verifies that the root background fills a manually widened window and the transfer route reflows without the card-access popup.
- Generated build products are removed after verification.
