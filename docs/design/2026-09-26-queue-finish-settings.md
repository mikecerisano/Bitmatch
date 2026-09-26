# Queue, finish screen and Settings redesign (2026-09-26)

Adjudicated by the lead after three independent design reviews (Codex gpt-5.6-sol, GLM 5.3, muse), two rounds each. Final verdicts: Codex PASS_WITH_NOTES, GLM PASS_WITH_NOTES (its Copy Summary blocker resolved by A1), muse PASS_WITH_NOTES. Raw reviews are in the session record, not the repo.

Core rule: only a result where every file on every backup passed checksum verification may be green, say "verified" or "safe to erase", offer Eject as a primary action, or count as safe anywhere (summary, Dock, notification, VoiceOver). Everything else never.

Facts about the app you may not have had: it already holds a sleep assertion during transfers; the engine reports stages (preparing, copying, verifying); queued cards are snapshots (source, destinations, verification mode, ASC MHL, report settings are stored per queued card; editing the setup screen does not change them); queued/running/finished records persist in a journal and a transfer that was running when the app quit reads as Interrupted on relaunch, never green; transfers run strictly one at a time; a destination that is missing or full makes that card fail (it cannot silently copy to fewer backups than the card was queued with).

## 1. One safety state (all surfaces derive from it)
States: waiting, copying(progress), verifying(progress), safeToErase, copiedNotVerified (Quick, nothing else wrong), needsAttention (any file failed/mismatched, report/handoff/project failure), failed (transfer could not complete), interrupted (quit/crash/cancel mid-run). Heading, explanation, color, symbol, actions, notification copy, Dock state, VoiceOver label and canEject all derive from this one value. Invariant tests: no state but safeToErase can produce green, "safe", "verified", a primary Eject, an "eject verified cards" inclusion, or a success notification.

## 2. Transfer Queue (Mac main window, inline, not a sidebar or separate window)
- A "Queue" section in the main window's central column, the same component in setup and while running (rows animate in place, no layout jump). Shown whenever the queue has any card (waiting, running, or finished in this session). The old "2 cards queued · Run queue · Show" strip is removed. The Transfers sheet becomes History only.
- Row: card icon, card name (middle-truncated, full name in tooltip and VoiceOver), size · file count, "→ Shuttle A, Shuttle B" (backup drive names, not folder names), a status pill that is always symbol + words + color: Waiting (grey), Copying 42% / Verifying 31% (blue, with a thin determinate bar; never green), Safe to erase (green, checkmark), Copied, not verified: size check only (grey/indigo, no check), Needs attention (amber), Failed (red), Interrupted (amber). Trailing action by state: Eject (only when safe to erase and mounted), Review (needs attention/failed/interrupted), none otherwise; after eject the pill keeps its verdict and the action reads "Ejected".
- Row editing: waiting rows can be removed (context menu, Delete key); "Move to Top" in the context menu. Drag reorder is out of scope for this pass.
- Header while running: "Copying A002" (or "Verifying A002"), secondary "1 done · 2 waiting", current card's progress bar with throughput and time left. No "card 2 of 4" as the heading.
- No finish screen between queued cards: each result lands in its row.
- Problem during a queue: the queue pauses. A banner above the queue: "Queue paused — A003 needs attention" + one plain line of cause ("3 files failed on Shuttle B" / "Shuttle B is not connected"). Actions: [Review A003] (primary), [Skip A003 and Continue]. Skipped cards stay Needs attention permanently. No keyboard shortcut for Skip.
- Cancel while a queue runs: Cancel on the progress panel cancels the current card (confirmation); a separate "Stop After This Card" stops the queue; the canceled card reads Interrupted.
- Adding cards: "Add to Queue" next to Start (queues the chosen card with the chosen backups, clears only the card). While a card copies, a newly connected card shows "Queue A004 Next" (one click). Settings option "Queue new cards automatically" (off by default; only camera cards or removable media, never system or backup drives).
- End of queue (queue of 2+ cards): the progress panel is replaced by a summary; the queue list stays. Title "Queue finished" or "Queue stopped". Subtitle enumerates every class: "3 safe to erase · 1 copied, not verified · 1 needs attention" (never "complete"). Actions: [Eject 3 Verified Cards] (only safeToErase cards still mounted; disabled with explanation if none), [Copy Summary] (plain text line for Slack/WhatsApp: card names, total size, algorithm, backups, time), [Export Report ▾], [New Transfer]. A queue of one card shows the normal finish screen.

## 3. Finish screen (single transfer), one skeleton for every state
Top to bottom: verdict banner → action row → collapsed Transfer details / File details.
- Safe to erase: green banner, checkmark.circle.fill, "SD_CARD_042 is safe to erase", subtitle "184 files · 128.4 GB verified on Shuttle A and Shuttle B · SHA-256 · 1m 35s", trailing Eject button inside the banner (bordered/white on green, not green on green; ⌘E). After eject it reads "Ejected". Per-backup boxes removed (one line in the subtitle). Actions: [New Transfer] (primary), [Export Report ▾], [Copy Summary]. No Retry.
- Copied, not verified (Quick): grey/indigo banner, no green anywhere, no checkmark, "SD_CARD_042 copied, not verified", "Only file sizes were compared on Shuttle A and Shuttle B. Do not erase the card." No Eject on this screen. Actions: [New Transfer], [Export Report]. ("Verify Now" is a good future feature; not in this pass.)
- Needs attention: amber, exclamationmark.triangle.fill, "SD_CARD_042 needs attention", one-line cause. Per-backup rows shown, named by drive and folder ("Shuttle B › Day 3"), neutral styling with factual counts ("Checksums matched for 184 of 184 files" / "3 files failed"). Actions: [Retry Failed Files] or [Retry Transfer] (primary), [Export Report]. No Eject.
- Failed: red, xmark.circle.fill, "Transfer failed", specific cause in plain words; "Do not erase SD_CARD_042." Actions: [Retry Transfer] (primary), [Export Report]. No Eject.
- Interrupted/canceled: amber, "Transfer interrupted — SD_CARD_042 is not safe to erase". [Retry Transfer], [Export Report].
- The "Notify me" checkbox and the "Keeps the same 2 backups…" caption leave this screen; New Transfer gets the help text "Start again with the same backups".

## 4. Settings
- Native SwiftUI Settings scene with a TabView (macOS lays out the centered toolbar tabs; window title follows the pane; last pane restored; ⌘,). Menu item and title say "Settings".
- New first pane "General": Notifications (see 5), "Queue new cards automatically" (off), "Eject cards automatically when safe to erase" (off; moved from the finish screen), sounds.
- Existing panes unchanged in content: Verification, Backups, Reports, Cameras.

## 5. Notifications, Dock, sound, keyboard
- Settings shows the real state: "Notify when a card needs attention" (on), "Notify when a transfer or queue finishes" (on), "Notify for each card in a queue" (off). Plus the system permission state with [Open Notification Settings] when denied.
- Permission: the first time Start is pressed, the transfer starts immediately and a small in-app prompt appears: "Get notified when this finishes or needs attention?" [Enable Notifications] [Not Now]. Only Enable triggers the system prompt. Never at launch, never re-asked after a denial.
- When BitMatch is frontmost, no system banner (in-app state only).
- Wording: "A002 is safe to erase. Verified on Shuttle A and Shuttle B." / "A003 needs attention. Do not erase the card." / "A004 was copied without checksum verification." Queue end: "Queue finished: 3 safe to erase · 1 needs attention." Clicking a notification selects the card's row. Notification actions: Show; Eject only for safe-to-erase.
- Dock: keep the segmented progress tile; when a card needs attention and BitMatch is not frontmost, bounce once (critical request) and show a "!" badge until the card is reviewed.
- Sounds: off by default; setting "Play sounds": quiet tick when a card is safe, distinct tone for attention; never the only signal.
- Keyboard: ⌘N New Transfer, ⌘Return Start / Run Queue, ⌘⇧N Add to Queue, ⌘E Eject (enabled only when safe), ⌘. Cancel (confirm), ⌘1/2/3 modes, ⌘, Settings, arrow keys + Space over queue rows.

## 6. Accessibility
Every verdict is symbol + words + color. Each banner and row is one VoiceOver element ("A003, needs attention, not safe to erase, 3 files failed on Shuttle B"); progress read as text; stage changes announced (not every percent); buttons name their object ("Eject A003"); Increased Contrast and Reduce Motion respected; minimum-window layouts don't truncate verdicts.

## Amendments (after round 2)

A1. Copy Summary (single card and queue) always carries per-card verdicts, never an aggregate "verified":
  Queue finished 18:42 · 3 safe to erase · 1 copied, not verified · 1 needs attention
  A001 · 64 GB · safe to erase · SHA-256 · Shuttle A, Shuttle B
  A002 · 64 GB · copied, not verified (size check only) · Shuttle A, Shuttle B
  A003 · 128 GB · needs attention: 3 files failed on Shuttle B · Shuttle A, Shuttle B
  A004 · not started
Single card: one line of the same form. Available for every state, not only verified.

A2. Skip: "Skip A003 and Continue" keeps A003's own state (Needs attention or Failed, whichever it was); it stays retryable from its row (Review → Retry Transfer). Retry always reuses the card's snapshot backups; it can never reach Safe to erase with fewer backups than the card was queued with.
A3. Stop After This Card / Queue stopped: cards that never ran stay Waiting and the summary counts them ("1 not started"). Run Queue resumes them.
A4. Interrupted (on relaunch or cancel): row reads Interrupted with Retry; the finish screen for it offers [Retry Transfer] [New Transfer] [Export Report]; never green.
A5. While the queue is paused, ⌘Return does nothing; no shortcut reaches Skip.
A6. copiedNotVerified rows get a Review action too. Preparing stage shows "Preparing" (blue), never verifying or safe.
A7. A queued card whose source is missing when its turn comes: the card becomes Failed ("A004 is not connected"), the queue pauses. Never silently skipped.
A8. Notifications: needs-attention, failed and interrupted notifications are always sent (if notifications are allowed), independent of the per-card toggle; wording "A003 needs attention. Do not erase the card." / "A003 failed. Do not erase the card." / "A003 was interrupted. Do not erase the card." Queue-end notification uses the A1 tally line.
A9. Dock "!" badge shows the number of unresolved attention cards (needs attention, failed, interrupted) in this session; a card counts as resolved when its Review opens or it is retried to safe to erase.
A10. VoiceOver: each row's status is one element; its action buttons are separate elements named with the card ("Eject A001", "Review A003").
A11. "Retry Failed Files" is dropped from this pass (the engine retries whole cards); needs-attention primary action is [Retry Transfer].
A12. Transfers sheet: the Queue tab lists only waiting and running cards; finished cards (any verdict) are History only. History pills use the same state words as everywhere else ("Copied, not verified", not "Needs review", for Quick results).
A13. Scope: Mac first. The finish screen is a shared view, so iPad/iPhone get the same verdict layout (no Eject, no Dock); the in-app notification prompt is shared.


Round-3 notes, adopted: the tally lists every class present, including "not started" ("Queue stopped" when cards never ran); Copy Summary is offered on every finish state; the "Notify when a card needs attention" setting controls attention, failure and interruption notifications, and "Notify for each card in a queue" only adds per-card success notifications.

## Deferred (recorded, not in this pass)
Drag reorder; "Verify Now" for Quick copies; duplicate-card detection by volume UUID/manifests; per-card missing-card prompt ("A004 not found — insert or skip"); scoped "Retry Shuttle B"; optional menu bar extra; drag a volume onto the Dock icon.

