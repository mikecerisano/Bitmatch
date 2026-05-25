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
- **Safe by default**: never modifies the source, never overwrites destination conflicts, copies through temp files and verifies by default with SHA-256

## Why It's Safe (probably)

- 🚫 No cloud, no servers, no uploads
- 🔒 Verification happens locally
- ✅ Source card is never modified
- 🛑 Existing destination files are never overwritten. In checksum modes, matching files can be reused only after local verification
- 📁 Hidden files and empty folders included (camera sidecar data matters)

**Heads up though.** I think it's safe. I've used it on my own jobs. But I haven't shot every camera on every drive on every macOS version, and this is a one person project. It's open source so you can read the code and decide for yourself. **Test it on throwaway files first. Don't trust irreplaceable footage to it until you've shaken it out on a few jobs.**

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
bash test.sh
```

## FAQ

**Does it generate MHL files?** Yes, in Paranoid mode.

**Will it work with my camera?** Probably. I personally shoot Sony, so that's the path I've beaten on. The other brands should work. Open an issue if they don't.

**Does it work on iPad?** Yes. It uses the Files app for external SSDs.

**Why open source?** So you can trust it. The code is here. Read it before you trust your footage to it.

## Contributing

PRs welcome. If you contribute, build both the Mac and iPad schemes before submitting. Shared code means changes can break one platform silently.

---

Built over six months of "I'll just add one more feature." MIT License, be a good person. See [LICENSE](LICENSE) for the legal text.
