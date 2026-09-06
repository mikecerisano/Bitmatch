# Hardware test report

Use synthetic or disposable data and follow [the procedure](HARDWARE_TESTING.md). Leave unknown fields as **Unknown**; never infer a device or filesystem from its brand. Remove serial numbers, client names, and private paths before publishing.

- Date / tester:
- BitMatch version and Git revision:
- Working tree: clean / modified (attach relevant patch or describe changes)
- Host model, OS version, architecture:
- Verification mode:
- Source device model, filesystem, capacity / available space:
- Destination A model, filesystem, capacity / available space:
- Destination B model, filesystem, capacity / available space:
- Connection: direct / hub; hub or dock model, bridge/enclosure, cable type and length:
- Power source / external power:
- Synthetic dataset: generation method or seed, file count, total bytes, size range:
- Offline source SHA-256 manifest reference:

| Scenario | Expected behavior | Actual behavior and fault timing | Outcome | Evidence |
| --- | --- | --- | --- | --- |
| Baseline transfer | All reported successes independently hash correctly | | Not tested | |
| Source removal | Explicit failure; responsive stop; no false success | | Not tested | |
| One destination removed | Affected destination fails; healthy destination completes and hashes correctly | | Not tested | |
| Sleep during copy | Explicit failure or safe resumption; no false success | | Not tested | |
| Sleep during verification | Explicit failure or safe resumption; no false success | | Not tested | |
| Cancel during copy and relaunch | Activity stops; no incomplete output classified successful | | Not tested | |
| Cancel during verification and relaunch | Activity stops; no incomplete output classified successful | | Not tested | |

Use **Pass**, **Fail**, **Inconclusive**, or **Not tested**. Repeat the report for another filesystem or connection setup. Include whether `.bitmatch.tmp.*` files remained, whether existing outputs changed, time to stop or resume, and any hang or stale status. Preserve the export and independent destination SHA-256 comparisons for each tested case. Describe any missing evidence explicitly.

## Evidence and reproduction

- Exact steps and timing (copy / verification phase, elapsed time):
- BitMatch result export (redacted):
- Independent destination hash comparisons (method, command, and result):
- Screenshots / topology notes / relevant logs (redacted):
- Automated harness evidence, if run separately (do not substitute for physical tests):
- Limitations, skipped cases, and follow-up issues:
