# Hardware validation status

No physical-device test reports are recorded in this matrix yet. APFS, exFAT, enclosures, hubs, and cable combinations remain **unverified here** until a reproducible report is published. This is an evidence register, not a certification or a list of unsupported hardware.

| Evidence type | Available workflow | What it establishes |
| --- | --- | --- |
| Automated transfer tests | `bash test.sh mac-test` | Behavior exercised by the test suite on its host; optional tests may skip without their harness. |
| Automated seeded soak | `bash Scripts/run_soak_tests.sh` | Repeated synthetic transfers with independent output hashes on the host filesystem, for the recorded seed and iteration count. |
| Automated APFS fault | `bash Scripts/run_apfs_fault_tests.sh` | Handling of an injected inaccessible destination in a disposable APFS image. |
| Physical storage and connection tests | [Hardware testing procedure](HARDWARE_TESTING.md) | Only the specific device, filesystem, connection, revision, and scenario recorded in a report. No physical results have been entered. |

These rows describe available tests, not claims that they passed. A published automated result must include the run date, revision, working-tree state, exit status, test totals (including skipped tests), and a link to retained evidence. Automated results do not count as physical cable-pull or power-loss results.

## Recorded automated validation

[2026-09-06 development validation](validation/2026-09-06/README.md): the Mac suite passed on rerun, the iPad simulator build passed, and the seeded soak verified 450 destination outputs. The report retains the initial pause-reset timeout. APFS image creation was blocked by the host's “Resource busy” error before tests began. The real app demo independently verified 24 local copies. None of these results establishes physical-device compatibility.

[2026-09-08 development validation](validation/2026-09-08/README.md) covers the shared queue, recovery, ASC MHL reference checks, and Mac/iPhone/iPad interface checks. These are source and simulator results; v0.1.4 remains the downloadable release.

[2026-09-19 release-readiness validation](validation/2026-09-19/README.md) covers the audit integrity fixes and priorities 1–6 in source: retained comparison paths with export, journal-backed completion exports, identity-checked reconnection, report-failure completion with queue stop, and Mac off-site queue restore with bounded retries. Full Mac suite, both app targets, and both Release configurations pass except the known pre-existing `testRejectsPathTraversal` failure. Physical-device results remain unrecorded.

## Physical results

| Report | Date | App revision / OS | Source and destinations / filesystems | Connection | Scenario | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| No reports recorded | — | — | — | — | — | Not tested |

Use **Pass**, **Fail**, **Inconclusive**, or **Not tested**. A pass requires the scenario's expected behavior and independent hashes for all outputs reported as successful. Document failures and incomplete runs as well as passes. Use the [report template](HARDWARE_REPORT_TEMPLATE.md) and link the evidence when adding a row.
