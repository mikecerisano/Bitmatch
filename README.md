# BitMatch

**A free, open source alternative to ShotPut Pro, Silverstack, and Hedge.** Offload camera cards to multiple backup drives, verify every byte with SHA-256, and generate reports. For indie filmmakers, YouTubers, and small productions that don't want a $300/year subscription to copy files.

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iPadOS-blue)](https://github.com/mikecerisano/Bitmatch)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mikecerisano/Bitmatch?include_prereleases)](https://github.com/mikecerisano/Bitmatch/releases)

![BitMatch macOS app](screenshot.png)

## Download

Grab the latest signed and notarized macOS build from the [Releases page](https://github.com/mikecerisano/Bitmatch/releases).

Apple notarized it, so you shouldn't see any "unidentified developer" warnings. If you do somehow, right click the app and pick Open.

For iPad and iPhone, build from source for now (see Building below). App Store submission is on the maybe pile.

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

Plug in your card and your drives. BitMatch figures out which is which (drives 1TB and up are destinations, 512GB and under are sources). Hit copy. It writes to both backups at once, verifies with checksums, and generates a report.

## What It Does

### Copy and Verify
Copies files from a source (camera card, SSD, whatever) to multiple destinations at the same time. Verifies they copied correctly using checksums. You know your footage is safe.

### Transfer Safety
BitMatch copies into temp files first, flushes data to disk, checks the source file didn't change during the copy, then promotes the finished file into place. If a destination file already exists and doesn't match the source, BitMatch reports a failure instead of replacing it. It also preflights unsafe source and destination relationships, duplicate destinations, symlinked output roots, nested output folders, and path collisions that break on case insensitive volumes.

### Verification Modes
- **Quick**: File size and mtime reuse checks only. Fast, not recommended for footage you can't reshoot.
- **Standard**: SHA-256 checksums. The default. What you probably want.
- **Thorough**: Multiple checksum algorithms.
- **Paranoid**: Byte by byte comparison, multiple checksums, MHL files. For when you really need to be sure, or want to pretend you're going to Netflix.

### Camera Detection
Recognizes cards from Sony, Canon, ARRI, RED, Blackmagic, Panasonic, Fujifilm, GoPro, DJI, Insta360, and generic DCIM structures. Names your backup folders based on the camera. Can autosort folders by A/B/C camera. I shoot Sony so that's the one I've actually beaten on. The others should work. Open an issue if they don't.

### Compare Folders
Already copied something manually? Compare two folders to see if they match.

### Reports
Generates PDF reports of what you transferred. Useful for producers who want documentation.

## Why It's Safe

- 🚫 No cloud, no servers, no uploads
- 🔒 Verification happens locally on your machine
- ✅ The source card is never modified
- 🛑 Existing destination files are never overwritten unless BitMatch proves they already match the source
- 🔢 Standard mode uses fresh SHA-256 checksum verification by default
- 📁 Hidden files and empty folders are included, because camera cards often have important sidecar data
- 🧾 Reports keep the latest verified status for every file and destination, even on very large transfers

## Who This Is For

- YouTube creators
- People shooting shorts
- Small productions like web commercials, Instagram ads, whatever
- Anyone who doesn't want to pay $300/year for software that copies files

Who it's not for:
- Big budget productions (use the enterprise tools, you can afford them)
- Union shoots with a full DIT cart

## Why I Made This

I was on a small film set offloading camera cards. It was a friend's grad film, and Silverstack, ShotPut Pro, Hedge are all either expensive, subscription based, or way overkill for what I needed. I just wanted to copy files to two drives and know they weren't corrupted.

So I started building my own. It worked. It was simple. Then I kept working on it. Six months later, around 32,000 lines of Swift, running on macOS and iPad. The mobile version is actually useful. When you're shooting run and gun and don't have a laptop, you can still offload to a portable SSD from your phone.

## Why Open Source

Nobody's going to trust a vibe coded app from a random person with their irreplaceable footage. Fair. So the code is here. Read it. Test it. Decide.

If you download it, run it on throwaway files, see that it works, and start using it on real jobs? That's the whole point.

## License (MIT, but read this)

It's MIT licensed, so legally you can do whatever you want with it. I may eventually put a compiled version on the App Store for the price of a coffee, but the source stays here either way.

The spirit:

**Please do:**
- Download it, use it, love it
- Use it on every shoot
- Fork it, extend it, make it better
- Credit me if you build something from it

**Please don't:**
- Just slap it on the App Store unchanged and charge money for it

I can't legally stop you on that last one, but it's lazy and rude. If you redistribute this commercially, actually do something with it. Add features. Make it better. Don't be a middleman.

## Platform Support

- **macOS**: Full desktop app with drag and drop
- **iPad and iPhone**: Touch interface, works with external drives through the Files app

The iPad build is the same core code, not a dumbed down port. It just has a touch friendly UI.

## Building

### Requirements
- Xcode 15+
- macOS 14+

### To Build
1. Open `BitMatch.xcodeproj`
2. Select the `BitMatch` scheme for Mac or `BitMatch-iPad` for iOS
3. For iOS, set your development team in Signing and Capabilities
4. Build and run

### iOS Notes
The iPad app uses iOS security scoped URLs. You pick folders through the document picker. You can't hardcode paths. That's an iOS thing, not a limitation of the app. It can't autoselect drives and cards like the Mac app does, which is annoying but it is what it is.

## Running Tests

```bash
xcodebuild test -scheme BitMatch -project BitMatch.xcodeproj -configuration Debug -destination platform=macOS,arch=arm64 -only-testing:BitMatchTests
xcodebuild -scheme BitMatch-iPad -project BitMatch.xcodeproj -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build
```

Or just run `bash test.sh` from the repo root.

## Technical Stuff

- Around 32,000 lines of Swift
- SwiftUI for the interface
- Async/await for file operations
- About 80% of the code is shared between platforms
- No external dependencies, all native frameworks

### Architecture
```
Shared/           # Core logic (works on both platforms)
├── Models/       # Data structures
└── Services/     # File operations, checksums, camera detection

Platforms/        # Platform specific code
├── iOS/          # iPad and iPhone
└── macOS/        # Mac

BitMatch/         # macOS app
BitMatch-iPad/    # iOS app
```

## Contributing

Found a bug? Want to add a feature? PRs welcome.

Stuff that would be cool:
- More camera detection patterns
- Better progress UI
- Network drive support improvements
- Localization

If you contribute, build both the macOS and iPad schemes before submitting. The shared code means you can break one platform without noticing.

## Known Issues

- iPad can't see some external drives until you explicitly grant access through the Files app first
- UI automation can be sensitive to local Xcode and device state. The unit target is the reliable safety regression suite

## FAQ

**Is this really a ShotPut Pro, Silverstack, or Hedge alternative?**

For most indie use cases, yes. Multi destination copy, SHA-256 verification, camera card detection, MHL generation, PDF reports. It doesn't do LTO archiving, network distributed offload, or studio grade asset management. If you're on a Netflix show, stay with the paid tools.

**Does it generate MHL files?**

Yes, in Paranoid mode. MHL (Media Hash List) files are written alongside transfers for downstream verification.

**Does it support RED, ARRI, Blackmagic, Sony, Canon?**

Yes. Card detection covers Sony, Canon, ARRI, RED, Blackmagic, Panasonic, Fujifilm, GoPro, DJI, Insta360, and generic DCIM. Backup folders are named based on the detected camera.

**Does it work on iPad?**

Yes. The iPad app works with external SSDs through the Files app. Useful when you're shooting run and gun and don't have a laptop.

**Is the source card safe?**

Yes. BitMatch never modifies the source. It copies into temp files, verifies, then promotes into place. Existing destination files are never overwritten unless BitMatch proves they already match the source.

**Why open source?**

Trust. Nobody should hand their irreplaceable footage to a closed source app from a random developer. The code is here. Read it. Test it. Then decide.

**Is there a paid version?**

Maybe a future App Store build for the price of a coffee, with a notarized installer and updates. The source will always be here, MIT licensed, free.

## Credits

Built by me over six months of "I'll just add one more feature" syndrome.

If you use this and it makes your life easier, cool. If you improve it and share those improvements back, even cooler.

---

MIT License (be a good person). See [LICENSE](LICENSE) for the legal text.
