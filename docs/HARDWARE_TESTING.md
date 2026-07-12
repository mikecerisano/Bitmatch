# Hardware fault-testing procedure

Hardware fault tests can destroy or corrupt media. Use throwaway source data only. Before any cable-pull exercise, keep two independently verified backups on devices that will not be connected to the test system. A second copy on another partition of the same device is not an independent backup.

## Before each run

1. Disconnect every storage device that is not part of the test.
2. Label the throwaway source and both throwaway destinations unambiguously.
3. Verify the two offline backups by recomputing their hashes; do not rely on file counts or Finder previews.
4. Record macOS version, BitMatch revision, filesystem, enclosure, cable, hub, power source, and verification mode.
5. Start with small synthetic files whose expected SHA-256 manifest is already saved offline.
6. Confirm which device may be unplugged before starting the transfer.

Never remove the last known-good copy. Never run these procedures against client media, irreplaceable camera cards, or a mounted production archive.

## Fault matrix

Run each case with APFS destinations, exFAT destinations, and mixed APFS/exFAT destinations where the hardware supports them. Repeat direct-attached and through a low-power or bus-powered hub, but do not exceed the hub or computer vendor's electrical limits.

### Source removal

Start a Standard transfer to two destinations, wait until active copying is visible, then remove only the throwaway source. Record the displayed failure, whether cancellation remains responsive, whether temporary files remain, and whether previously published outputs still match the offline manifest. Reconnect the source only after the operation has stopped.

### One-destination removal

Start a Standard transfer to two destinations and remove one throwaway destination while leaving the other connected. The removed destination must report failures; the remaining destination must finish and every successful output must match the manifest. Inspect both destinations for `.bitmatch.tmp.*` files after reconnecting the removed device.

### Sleep and backgrounding

During copy and again during verification, put the Mac to sleep and wake it after at least 30 seconds. Also send BitMatch to the background and switch users if that is part of the deployment workflow. Record whether progress resumes, fails explicitly, or stalls. Hash all successful outputs independently after the run.

### Cancel and relaunch

Cancel during copy, confirm activity stops, then quit and relaunch BitMatch. Repeat cancellation during verification. Confirm no temporary files remain and no canceled or failed row is classified as successful. A relaunch must not silently convert an incomplete transfer into success.

### Low-power hubs

Repeat the one-destination-removal and sleep cases through the approved low-power hub using the intended cable lengths. Watch for both explicit disconnects and transient resets. Record System Information's USB or Thunderbolt topology and system logs with the test notes. Do not intentionally overload, short, or thermally stress hardware.

## Evidence to retain

For every run, retain the seed or source manifest, BitMatch result export, independent post-run hashes, exact fault timing, expected outcome, actual outcome, and photos or topology notes that identify the devices. Treat a hang, silent retry, stale success row, unexpected overwrite, or leftover temporary file as a failure even if another destination completes.

The automated APFS image test in `Scripts/run_apfs_fault_tests.sh` is a safer first step, but it does not simulate cable, bridge firmware, power-loss, or exFAT behavior. Passing it is not evidence that physical removal is safe.
