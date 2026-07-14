# Photographer Jobs and Remote Backup Design

**Date:** July 13, 2026  
**Status:** Approved for implementation planning

## Summary

BitMatch will add a wedding and event photography workflow, then extend verified local ingests with resumable off-site backups. The photographer workflow organizes exact card copies into job packages without renaming or flattening original media. The remote stage reads only from a verified local copy, persists across app launches, supports saved provider profiles, and reports verification evidence honestly.

The work will ship in stages:

1. Photographer jobs, folder presets, card provenance, and a local-only session dashboard.
2. A persistent remote queue and SFTP provider on macOS.
3. WebDAV and S3-compatible providers.
4. iPad support through the same shared models, adapted to iPadOS background limits.
5. A separate delivery workflow for JPEG proxies and client services.

## Goals

- Make BitMatch useful to wedding and event photographers who ingest several cards from several photographers and cameras.
- Preserve each card's exact internal structure and source provenance.
- Let studios save job, folder, local-copy, verification, and remote-backup defaults.
- Require a verified local copy before any remote upload begins.
- Support saved SFTP, WebDAV, and S3-compatible destinations through one provider model.
- Resume remote work after network loss, app relaunch, credential renewal, or server interruption.
- Distinguish local safety, successful upload, and verified off-site backup.
- Preserve BitMatch's fail-closed conflict, reporting, and completion semantics.

## Non-goals

- Plain FTP. BitMatch will support SFTP and other encrypted transports only.
- Direct camera-card-to-server uploads.
- Remote-only ingest.
- File renaming, flattening, RAW conversion, or destructive reorganization.
- Photo selection, culling, editing, or catalog management.
- JPEG proxy generation, resizing, watermarking, galleries, or client delivery in the first release.
- More than one active remote target per job in the first release. Users may save any number of destination profiles and select one for a job. The queue and result models will use destination identifiers so a later release can support several active remote targets without a data migration.
- Unattended iPad uploads in the macOS-first release.

## Product model

### Photographer job

A `PhotographerJob` groups every card ingest for one event. It contains:

- event date;
- client or job name;
- event type;
- saved photographer identities;
- a folder recipe;
- required local-copy count;
- verification and report settings;
- an optional remote destination selection;
- card-ingest records and their independent local and remote states.

The Wedding preset requires at least one verified local copy and defaults to two. A studio may lower the required count to one, but BitMatch never permits zero when remote backup is enabled.

### Card ingest

Each `CardIngest` belongs to one job and records:

- photographer;
- detected or chosen camera;
- monotonically assigned card number within the job and camera;
- source volume metadata;
- source manifest fingerprint;
- exact relative paths, sizes, modification dates, and final checksums;
- local and remote results for every manifest entry.

BitMatch computes a preliminary card fingerprint from sorted relative paths, sizes, and modification dates during preflight. It computes a confirmed fingerprint from the final manifest and file checksums. A preliminary match warns that the card may have been ingested. A confirmed match identifies the earlier ingest and its verified destinations. The warning never suppresses a new ingest without the user's action.

### RAW, JPEG, and sidecar awareness

BitMatch preserves all files. It groups files with the same directory and base name for reporting only. Reports show RAW+JPEG pairs, RAW-only files, JPEG-only files, and recognized sidecars. A missing companion creates an informational warning; it does not fail an ingest because many photographers intentionally shoot RAW-only or JPEG-only.

## Folder recipes

The Wedding preset renders this package structure:

```text
2026-07-13_Smith-Wedding/
└── Originals/
    └── Mike/
        └── Sony-A7IV/
            └── Card-001/
                └── [exact card contents]
```

The setup screen shows the preset and a live path preview. A collapsed **Customize layers** drawer lets users enable, disable, and reorder these layers:

- date and job;
- `Originals` literal;
- photographer;
- camera;
- card number.

The job root always remains present. BitMatch sanitizes generated path segments, rejects traversal and portable-name collisions, and shows the final rendered path before ingest. It never changes names inside the card package. Users may save a customized recipe as a studio preset.

## User experience

### Setup

The photographer creates or opens a job, assigns the source card to a photographer and camera, reviews the folder preview, and chooses local destinations. Existing camera detection supplies the default camera name. Saved photographer names and camera nicknames reduce repeated entry.

Destinations appear as two stages:

1. **Local backups** — required local folders or volumes processed by BitMatch's existing safe-copy and verification engine.
2. **Off-site backup** — an optional, collapsed stage that uploads from a verified local copy.

The off-site stage occupies one compact toggle row while disabled. Enabling it reveals:

- a picker of saved destination profiles;
- **Manage destinations** and **Test connection** actions;
- a remote-folder policy;
- the rendered remote path;
- the chosen remote verification policy.

### Saved destination profiles

Users may save profiles such as `Studio SFTP`, `Synology WebDAV`, and `Backblaze Archive`. A profile stores:

- stable identifier and display name;
- provider kind;
- host, port, username, and provider-specific endpoint settings;
- default remote root;
- concurrency, retry, and verification defaults;
- a Keychain credential reference.

Passwords, SSH private keys, key passphrases, and service secrets live in macOS Keychain. Jobs, reports, queue records, analytics, and logs never contain secret material.

### Remote-folder policy

Each job selects one policy:

- **Create job folder** renders the job's folder recipe beneath the profile's default root.
- **Use existing folder** selects a remote directory and places the job package there.

Preflight confirms connection, host identity, credentials, root containment, directory access, write access, and conflicts. The rendered path remains visible before ingest.

### Status and completion

Local and remote stages retain independent states. The job dashboard may show:

- `Copying`;
- `Locally Safe`;
- `Remote Queued`;
- `Remote Uploading`;
- `Uploaded · Unverified`;
- `Fully Backed Up`;
- `Issues`.

`Locally Safe` means the configured number of local destinations completed successfully. A remote upload may start as soon as its designated local source copy verifies, even if other local copies continue. The local stage does not reach `Locally Safe` until the configured count succeeds. The photographer may begin the next card after the job reaches `Locally Safe`.

`Fully Backed Up` requires successful checksum evidence from the selected remote destination. Upload-only mode ends at `Uploaded · Unverified` and never receives a green verified state. Disabling remote backup leaves the job at `Locally Safe`.

## Architecture

### Preserve the local engine

The first release will not replace the URL-based local copy engine. A `LocalDestinationAdapter` will translate job targets into the existing `SharedFileOperationsService` inputs and translate authoritative file results back into job-stage results. This boundary limits risk to local transfer behavior.

### Shared target identity

A `BackupTarget` carries a stable destination identifier, display metadata, and either a local target or remote profile selection. Reports, progress, queue items, and result keys will use the stable identifier rather than treating a path as identity.

The first remote release allows one active remote target per job, but every API and persisted record will identify its target explicitly.

### Authoritative job manifest

One immutable manifest connects both stages. Each entry includes:

- stable entry identifier;
- safe relative path;
- size and source identity metadata;
- source checksum;
- local artifact location;
- one result per destination target.

The local stage produces the manifest's trusted artifact reference. The remote stage consumes that reference and the expected checksum. Providers never enumerate or read the camera card.

### Persistence

BitMatch will use its existing Core Data stack for jobs, card ingests, destination profiles, manifest references, queue items, attempts, and stage results. The queue commits state after every material transition: created, uploading, paused, retrying, uploaded, verifying, verified, unverified, failed, or cancelled.

A persistent local artifact reference contains a security-scoped bookmark to the verified local package root. BitMatch resolves and validates the bookmark before each queued run. A missing, stale, or changed artifact pauses the item and asks the user to locate or restore the verified copy. BitMatch never substitutes the source card.

### Remote provider boundary

Every remote adapter implements one provider contract with these responsibilities:

- connect and authenticate;
- validate host or service identity;
- preflight a root and path policy;
- inspect remote entries and capabilities;
- create directories safely;
- upload or resume a temporary entry;
- promote a temporary entry to its final name;
- produce server checksum evidence or a read-back stream;
- cancel and close resources.

Providers advertise capabilities such as resumable upload, atomic promotion, trustworthy SHA-256 evidence, read-back streaming, and remote free-space reporting. Shared orchestration selects behavior from these capabilities. It never assumes that an ETag, upload acknowledgment, or remote size is a content checksum.

### Persistent upload queue

The queue creates one item per manifest entry and remote target. Each item records the expected relative path, size, SHA-256, local artifact bookmark, remote temporary path, uploaded byte count, retry count, next attempt, and terminal evidence. It contains no credentials.

Workers use bounded concurrency per destination profile. They apply exponential backoff with jitter to transient failures and pause immediately for authentication, host-identity, local-artifact, root-containment, or permission errors. Relaunching BitMatch restores unfinished items and revalidates local and remote state before resuming.

### Remote write protocol

For each file, BitMatch will:

1. Revalidate the local artifact's identity, size, and checksum expectation.
2. Inspect the final remote path.
3. Reuse an existing final object only when provider-aware verification proves it matches.
4. Otherwise report a conflict; never overwrite the final object silently.
5. Upload to a provider-specific temporary name in the same logical parent.
6. Resume only after the provider confirms that the temporary length and stored queue state agree.
7. Promote the temporary object without replacing an existing final object.
8. Verify the final object and persist the evidence.

Providers that cannot guarantee atomic promotion must use a create-if-absent or equivalent conditional operation. If neither behavior exists, the provider fails preflight for verified backup mode.

## Remote verification

Verified mode uses the local manifest's SHA-256 as the expected digest. The provider follows this order:

1. Use a trustworthy provider-generated SHA-256 when the protocol returns one for the final object.
2. Otherwise stream the final remote object back through BitMatch's checksum service and compare SHA-256 values.
3. Fail verification if neither method is available.

SFTP uses a trustworthy server checksum extension when available. Otherwise it reads the final file back over SFTP and hashes the stream locally. The app labels the extra network cost before starting.

Upload-only mode confirms successful finalization and remote size but performs no checksum comparison. Its terminal state is `Uploaded · Unverified`.

WebDAV ETags count as cache validators, not checksums, unless a server explicitly documents and exposes a cryptographic checksum property. S3-compatible adapters will request SHA-256 checksum support and retrieve the stored checksum after finalization; they will fall back to read-back verification when the service cannot return trustworthy evidence.

## Security

- SFTP validates the SSH host key. First use requires explicit fingerprint confirmation. A changed key blocks the destination until the user reviews it.
- Credentials remain in Keychain and are addressed by opaque profile identifier.
- Logs redact usernames when practical and always redact passwords, keys, tokens, query credentials, and authorization headers.
- Remote paths are relative to the confirmed profile root. Standardization rejects absolute escapes, `..`, unsafe separators, and provider-specific reserved names.
- The queue never uploads from a path that fails bookmark, root, identity, size, or manifest checks.
- BitMatch continues to collect no cloud analytics and sends data only to destinations configured by the user.

## Failure handling

- Network loss pauses or retries the affected queue item without changing local success.
- Authentication failure pauses the destination and requests new credentials.
- Host-key change, path escape, and credential-scope errors fail closed.
- Missing local artifacts pause remote work and identify the required verified copy.
- Server-full and permission errors remain attached to the exact file and destination.
- Remote conflicts preserve both the local artifact and existing remote object.
- Partial remote objects retain temporary names and never count as backups.
- Removing a destination profile or disabling a job's remote stage requires confirmation when work remains queued.
- Cancelling remote work does not alter local completion or delete verified local files.
- Reports preserve separate local and remote verdicts and evidence.

## Photographer report

Reports will summarize:

- job, date, client, and event type;
- photographer, camera, and card provenance;
- files and bytes by card and file type;
- RAW+JPEG and sidecar grouping;
- preliminary and confirmed duplicate-card findings;
- local target results and checksums;
- remote target, path, provider, attempts, and terminal evidence;
- local-safe and fully-backed-up timestamps;
- every warning, conflict, unverified upload, and failed entry.

## Testing

### Unit tests

- Folder-recipe rendering, sanitization, ordering, disabled layers, and collisions.
- Preliminary and confirmed card fingerprints.
- RAW+JPEG and sidecar grouping.
- Job and stage state transitions.
- Profile persistence without secret material.
- Queue persistence, retry schedules, restoration, cancellation, and destination removal.
- Provider-capability selection and truthful result labels.
- Remote-path containment and conflict policy.

### Provider contract tests

Every provider runs the same contract suite against a controlled endpoint:

- connection and identity validation;
- directory preflight;
- clean upload and finalization;
- interrupted upload and resume;
- existing identical object;
- existing conflicting object;
- temporary-object collision;
- checksum mismatch and corrupt read-back;
- authentication expiry and renewal;
- permission denial and full destination;
- cancellation and app-style restoration from persisted state.

Fake providers will drive deterministic unit and fault tests. Controlled SFTP, WebDAV, and S3-compatible services will drive integration tests. Physical-server testing will cover long uploads, sleep/wake, network switching, bandwidth limits, and remote storage exhaustion.

### Regression tests

- Local-only jobs retain current behavior and reports.
- Existing source and destination safety checks remain unchanged.
- Remote failures never change a successful local verdict.
- No upload can read from the camera card.
- No unverified upload can display `Fully Backed Up`.
- Credentials never appear in persisted jobs, queue exports, reports, or captured logs.

## Rollout

### Stage 1: Photographer jobs

Add job models, Wedding presets, folder recipes, card provenance, duplicate warnings, pair-aware reports, and the session dashboard. Keep transfers local.

### Stage 2: SFTP on macOS

Add destination profiles, Keychain credentials, persistent queueing, SFTP preflight, resumable temporary uploads, provider-aware verification, and remote reporting.

### Stage 3: WebDAV and S3-compatible providers

Implement new adapters against the same contract suite. Add no provider-specific workflow screens beyond profile fields and capabilities.

### Stage 4: iPad

Reuse job, manifest, profile, provider, queue, and report models. Adapt scheduling to iPadOS background execution. The UI must disclose when uploads require BitMatch to remain foregrounded.

### Stage 5: Delivery mode

Add a separate destination role for generated JPEG proxies, resize and quality settings, metadata preservation, optional watermarking, selects, and client-facing services. Delivery results remain distinct from archival backup results.

## Acceptance criteria

- A photographer can create a Wedding job, ingest several cards, and trace every file to a photographer, camera, and card.
- The default package follows `Date_Job / Originals / Photographer / Camera / Card` and preserves exact card contents.
- Studios can save and reuse folder and safety presets.
- The off-site stage remains collapsed when disabled.
- A user can save several remote profiles and select one for a job without storing credentials outside Keychain.
- Remote upload begins only from a verified local artifact.
- SFTP uploads survive interruption and app relaunch without publishing partial files as final.
- Existing remote conflicts never get overwritten silently.
- Verified mode compares trustworthy SHA-256 evidence or performs a full read-back hash.
- Upload-only mode ends at `Uploaded · Unverified`.
- Local and remote verdicts remain independent in the UI and reports.
- Local-only BitMatch behavior continues to pass its existing safety, fault, and soak tests.
