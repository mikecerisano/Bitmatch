# BitMatch

**A free, open source alternative to ShotPut Pro, Silverstack, and Hedge.** Offload camera cards to multiple drives, verify every byte with SHA-256, generate reports. For indie filmmakers, YouTubers, and small productions that don't want a $300/year subscription to copy files.

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iPadOS-blue)](https://github.com/mikecerisano/Bitmatch)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mikecerisano/Bitmatch?include_prereleases)](https://github.com/mikecerisano/Bitmatch/releases)

![BitMatch macOS app](screenshot.png)

## Download

Signed and notarized macOS build on the [Releases page](https://github.com/mikecerisano/Bitmatch/releases).

Requires macOS 15.5 or newer. For iPad, build from source (see below).

## How It Works

```
📷 Camera Card
       │
       ▼
   BitMatch
    │    │
    ▼    ▼
  💾 A   💾 B
```

Plug in your card and drives. BitMatch figures out which is which (1TB+ are destinations, 512GB and under are sources). Hit copy. It writes to both backups at once, verifies with checksums, and generates a report.

## What It Does

- **Multi destination copy** with SHA-256 verification
- **Four verification modes**: Quick (copy only, no checksum verification), Standard (SHA-256, the default), Thorough (multiple checksums), Paranoid (byte by byte plus MHL files)
- **Camera detection** for Sony, Canon, ARRI, RED, Blackmagic, Panasonic, Fujifilm, GoPro, DJI, Insta360, generic DCIM. Names backup folders after the camera. Autosorts A/B/C
- **Folder compare** for stuff you already copied
- **PDF reports** for producers who want documentation
- **Transfer preflight on Mac and iPad** shows the source, destinations, verification/report choices, and blockers before Start
- **Truthful completion and reports** count every result, including sidecars and failures, from the authoritative operation manifest
- **Stable source verification** rejects files that grow, shrink, or change identity while BitMatch reads them
- **Safe by default**: never modifies the source, never overwrites destination conflicts, copies through temp files, and verifies by default with SHA-256

## Safety Model

### Enforced by code

- Transfers, verification, and reports stay local; BitMatch has no cloud or analytics upload path.
- BitMatch reads the source and never writes to it.
- Destination conflicts never overwrite existing files. Checksum modes reuse an existing file only after local verification proves it matches.
- Source enumeration fails closed: missing roots, unreadable metadata, traversal errors, unsafe paths, and portable-name collisions stop the transfer.
- Hidden files and empty folders remain in the manifest because camera sidecar data matters.
- Verification rejects files that grow, shrink, or change identity while they are being read.
- Completion screens and reports derive their verdicts from the full authoritative result set, including sidecars and failed files.

### Tested failures

Automated tests cover source mutation and truncation, I/O and metadata failures, destination conflicts, cancellation races, late result delivery, large manifests, multi-destination faults, and repeatable soak transfers. See [`docs/HARDWARE_TESTING.md`](docs/HARDWARE_TESTING.md) for the physical-media procedure and fault harnesses.

### Known limits

BitMatch is beta software from a one-person project. It has not been tested with every camera, filesystem, drive, hub, macOS release, or iPadOS release. Quick mode copies without checksum verification, so it cannot prove byte-for-byte equality. BitMatch is not a certified replacement for an established DIT workflow on regulated, insured, or high-budget productions.

### Field procedure

Test BitMatch with disposable files before using it on a job. Keep the source card until every destination completes cleanly and you have reviewed the report. Inspect every failed file before clearing media, and maintain another independent copy of irreplaceable footage.

## Who It's For

YouTube creators, short film folks, web commercials, Instagram ads, anyone who doesn't want to pay $300/year to copy files.

Not for big budget shows or union shoots with a full DIT cart. Use the enterprise tools, you can afford them.

## License (MIT, but read this)

MIT licensed, do what you want. The spirit:

**Please do** fork it, use it, improve it, credit me.
**Please don't** slap it on the App Store unchanged and charge for it. I can't legally stop you, but it's lazy. If you redistribute commercially, actually do something with it.

I might eventually put a compiled version on the App Store for the price of a coffee. Source stays here either way.

## Building

Requirements: Xcode 16+, macOS 15.5+ for the Mac app. The iPad target currently builds for iPadOS 18.5+.

1. Open `BitMatch.xcodeproj`
2. Pick the `BitMatch` scheme for Mac or `BitMatch-iPad` for iOS
3. For iOS, set your development team in Signing and Capabilities
4. Build and run

Tests:
```bash
bash test.sh mac-test       # macOS unit and integration tests
bash test.sh mac-build      # macOS Debug build
bash test.sh ipad-build     # iPad simulator Debug build
bash test.sh ipad-test      # requires IOS_SIMULATOR_DESTINATION
bash test.sh release-builds # macOS and iPad Release builds
```

CI runs `mac-test` and `ipad-build` on every push and pull request. For the
physical-media test procedure and the APFS fault/soak harnesses, see
[`docs/HARDWARE_TESTING.md`](docs/HARDWARE_TESTING.md).

## FAQ

**Does it generate MHL files?** Yes, in Paranoid mode.

**Will it work with my camera?** Probably. I personally shoot Sony, so that's the path I've beaten on. The other brands should work. Open an issue if they don't.

**Does it work on iPad?** Yes. It uses the Files app for external SSDs.

**Why open source?** So you can trust it. The code is here. Read it before you trust your footage to it.

## Contributing

PRs welcome. If you contribute, build both the Mac and iPad schemes before submitting. Shared code means changes can break one platform silently.

---

Built over six months of "I'll just add one more feature." MIT License, be a good person. See [LICENSE](LICENSE) for the legal text.
