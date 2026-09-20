# Recovery and layout follow-up

## Changes

- Queue-store write failures now stop further remote work, retain the exact unsaved transition, and schedule automatic save retries with capped backoff. Pause, Cancel, and promotion/completion intent survive delayed worker callbacks. The scheduler resumes eligible work only after the intended state is saved.
- If a paused upload advances beyond its recorded offset, retry discards only that item’s UUID-named temporary object and restarts from zero. It never appends at an unproven offset or replaces an existing final object. Cleanup failures pause with an explanation. Validation rejects final/temp path collisions; zero-byte recovery distinguishes an absent temp from an existing empty file.
- Mac Compare Folders now explains the results export menu instead of showing an ineffective report toggle. Mobile comparison now has a working verification-mode picker instead of three constant toggles.
- Mac setup has space below the header, phone navigation has a title, and completion/history use singular wording for one result.

## Validation

- Mac full suite: **548 passing executions, 528 unique passing tests, two skips, zero failures**. Skips are the opt-in soak test and the case-sensitive-filesystem metadata collision test.
- iPhone 17 Pro and iPad Air 11-inch (M4), iOS 26.5 simulators: **12 tests passed on each**, including opt-in screenshots.
- Mac and shared iPhone/iPad simulator Release builds passed with code signing disabled.
- Regression coverage includes repeated write failures, retained failed Pause/Cancel intent, drift after Pause, failed temporary cleanup, path collisions, zero-byte recovery, and rejection of unsafe cleanup paths before SSH.
- The final focused queue/provider rerun passed after an additional guard against retrying a superseded save.
- Test summaries are alongside this file. Build logs and xcresults remain in ignored `.derived-data` directories.

## Screenshots

These are production SwiftUI views rendered in XCTest with seeded data, scratch folders, and an isolated project store. They are layout evidence, not evidence of actual transfers. Mac captures use 680-point width; mobile captures use 393-point phone, 820-point iPad, and 500-point narrow iPad constraints. They do not simulate every system sheet, multitasking gesture, or Dynamic Type size. The phone setup screen scrolls to its remaining options and start action. The Mac Transfers sheet was inspected live in its empty/add-transfer state; its seeded offscreen capture could not render native controls faithfully, so that image is excluded. Seeded recovery-queue screenshots are from the mobile target.

| Mac | Mobile |
| --- | --- |
| [Setup](screenshots/mac-setup.png) | [Phone setup](screenshots/iphone-setup.png) |
| [Comparison](screenshots/mac-comparison-differences.png) | [iPad comparison](screenshots/ipad-comparison-differences.png) |
| [Completion](screenshots/mac-completion.png) | [Phone completion](screenshots/iphone-completion.png) |
| | [Phone recovery queue](screenshots/iphone-queue-recovery.png) |
| | [Narrow iPad completion](screenshots/narrowpad-completion.png) |
| | [iPad recovery queue](screenshots/ipad-queue-recovery.png) |

To capture again, prefix `test.sh mac-test` or `test.sh ipad-test` with `TEST_RUNNER_BITMATCH_CAPTURE_WORKFLOW_SNAPSHOTS=1`. Mobile tests also require `IOS_SIMULATOR_DESTINATION`. PNGs are retained as XCTest attachments; `BITMATCH_WORKFLOW_SNAPSHOT_OUTPUT_DIR` is optional. Use `xcresulttool export attachments` to export them.

## Limits

Save retries retain pending state **while BitMatch stays open**. If the process is terminated before unavailable storage can accept a write, the next launch can only restore the last durable state; an unsaved Pause/Cancel is not guaranteed across that restart. The error message tells the user to keep the app open during recovery. An already-running provider operation can continue sending bytes until its next checkpoint, but cannot promote or finalize after its run is invalidated.

Physical-device transfers, real SFTP-server interruption tests, and ASC MHL acceptance in a receiving tool still need field validation. No new binary was signed, notarized, or published. GitHub Actions remains disabled.
