# Reproduce the BitMatch demo

The public screenshots show the real macOS app copying **synthetic local test
files**. Both destinations are folders on the same Mac. This demonstrates the
workflow; it does not establish independent-drive redundancy, camera support,
transfer performance, or resilience to hardware faults.

## Create disposable data

From the repository root, run:

```bash
python3 docs/demo/create_fixture.py
```

The script creates a unique `/tmp/BitMatch-Demo-*` directory containing:

- `Demo Card`: 12 deterministic `.bin` files, 2 MiB each.
- `Backup A` and `Backup B`: empty destination folders.
- `expected-sha256.json`: an independent SHA-256 manifest outside the source.

The payloads contain repeated demonstration text, not photographs or client
media. Each run creates new directories and leaves existing data untouched.

## Capture the workflow

1. Build and open the current macOS app (`bash test.sh mac-build`).
2. Remove automatically detected destinations from the transfer route before
   choosing any source. Do not copy demo files to real drive roots.
3. Choose `Demo Card` as the source and the two demo backup folders as
   destinations. In a macOS folder picker, use **Command–Shift–G** to enter the
   exact path printed by the script.
4. Select **One-time transfer**. Keep **Standard** verification and PDF/CSV reports.
5. Capture the ready state with both source and destination labels readable.
6. Select **Start verified copy**, review the plan if shown, and run the transfer.
7. Capture the completion state and destination results.
8. Compare every copied file against `expected-sha256.json`, using the verifier
   below. A green UI alone is not an independent data check.

Only capture the application window. Exclude folder pickers, personal paths,
notifications, other windows, report history, and client information. Keep an
adjacent caption identifying the files and destinations as synthetic local demo
data. A GIF assembled from stills should be described as a screenshot sequence;
its playback timing is not measured transfer time.

## Independently check the copies

Pass the exact directory printed by the fixture script:

```bash
python3 docs/demo/verify_fixture.py /tmp/BitMatch-Demo-EXAMPLE
```

Keep the resulting files for review. Remove the disposable directory manually
when finished; the helper scripts do not delete anything.

## Published capture (2026-09-06)

- [`01-ready.png`](01-ready.png) and [`../../screenshot.png`](../../screenshot.png):
  the current transfer setup, Standard SHA-256 verification, and two local demo
  destinations.
- [`02-complete.png`](02-complete.png): the completed transfer, with 24 verified
  file results (12 source files × 2 destinations) and zero issues.
- [`bitmatch-demo.gif`](bitmatch-demo.gif): an animated sequence of those two
  screenshots. Each state is held for readability; playback is not transfer
  timing. No simulated progress or Interface Lab state is shown.

Captured from the macOS Debug build, version 0.1.4 (5), built from the working
source on 2026-09-06. The independent verifier passed all 24 destination copies.
The same verifier failed on the empty destinations before the transfer, as
expected. Both backups live on the same local filesystem; use separate physical
drives for real backup redundancy.
