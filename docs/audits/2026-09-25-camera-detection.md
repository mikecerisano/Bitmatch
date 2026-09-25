# Camera detection audit, 2026-09-25

Scope: `Shared/Core/Services/Camera/` (the orchestrator and its 11 stage services), `Shared/Core/Services/CameraStructureDetector.swift`, and `Shared/Core/Services/SharedCameraDetectionService.swift`. I checked them against the card layouts of every camera the README lists, plus Sony VENICE and VENICE 2 on AXS and SxS cards (the camera in GitHub #8). I also reviewed the 12 `.shared` singletons.

**Method.** I read the code and traced each layout through each detector by hand. Nothing was compiled or run: this was a Linux session with no Xcode. Layouts come from public sources, listed per brand below. Most of those pages were read through search summaries, not opened. Anything not confirmed is marked *inferred*. The fixtures in `BitMatchTests/TestHelpers/CameraCardLayouts.swift` carry the same source and inferred notes.

**Status, 2026-09-25 (later):** items 2–6 are fixed. `CardLayoutClassifier` (`Shared/Core/Services/Camera/CardLayoutClassifier.swift`) is now the one set of card-layout rules. `CameraStructureDetector`, the orchestrator's first step and its folder-structure stage, and through them `SharedCameraDetectionService`, all take the brand from it. The brand stages only read models. Finding C's `(null)` is treated as missing. Findings F (Canon, Fuji and Panasonic tables), G, H (folder-name substrings when no brand marker is found) and I remain open. The tables below describe the code before the fix.

## Summary

1. **On Mac, auto-select can pick part of a card as the source.** When "Auto-populate source" is on (off by default), the Mac app uses `CameraCard.mediaPath` as the transfer source (`BitMatch/App/AppCoordinator.swift:660`). `CameraStructureDetector` sets `mediaPath` to a subfolder, not the card root.
   - A Sony Alpha or FX3 card gets `PRIVATE/`, so the `DCIM/` stills are left out.
   - A Canon C70 SD card is detected as Sony and gets `PRIVATE/`, which holds only the slow-motion audio.
   - The copy would then verify green for the files it was given. This breaks Promise 1: a partial copy must never look complete. **This is the one safety finding.** It is opt-in and Mac-only, which limits the damage. `AppCoordinator.swift` is hands-off for this session, so this audit only records it.
2. **On Mac, auto-detect puts any card with an MP4 in `DCIM/` down as Sony.** That covers GoPro, DJI, Canon R-series video and Lumix video. Nikon cards and Fuji cards with movies come out as Canon. The detector order in `CameraStructureDetector.swift:104-118` makes Sony and Canon catch-alls.
3. **The label pipeline (the orchestrator) calls GoPro, older DJI and Lumix cards "Canon".** Its folder rules treat `DCIM` plus `MISC` as Canon, and the Canon stage runs before Panasonic. On iPad and iPhone that label can become the destination folder name (see finding D).
4. **Pro cinema cards are not auto-detected on Mac.** That covers VENICE (AXS and SxS), FX6/FX9 `XDROOT`, XDCAM EX `BPAV`, Canon XF-AVC, ARRI, RED, Blackmagic and P2. This is safe, because nothing gets auto-selected, but it is the opposite of what the README implies.
5. **Sony VENICE on AXS (GitHub #8) is not recognised anywhere.** The orchestrator labels it "Professional". Detection does **not** explain the "1 only destination" error in #8. That is a compare-side problem; Promise 2 already names Finder's `.DS_Store` as the suspect.
6. **Three separate detectors give three different answers** (Promise 5): `CameraStructureDetector` (Mac auto-select), `CameraDetectionOrchestrator` (Mac labels and hints), and `SharedCameraDetectionService` (the verdict on all platforms). There are also two camera-name cleaners with different rules.

## How detection is wired

| Path | Used by | Returns | Consequence |
| --- | --- | --- | --- |
| `CameraStructureDetector.detectCameraType` | Mac `CameraCardDetectionService` → `.cameraCardDetected` → `AppCoordinator` | `CameraCard` with `cameraType` and `mediaPath` | `mediaPath` becomes the **source** when auto-populate is on |
| `CameraDetectionOrchestrator.detectCamera` | Mac `VolumeMonitorService`, `FileSelectionViewModel` (source label), `CameraLabelViewModel`; and step 0 of `SharedCameraDetectionService` | `String?` such as "Sony FX6" | Label shown for the source; seeds the camera type |
| `SharedCameraDetectionService.detectCamera(from:)` | `SharedAppCoordinator.detectCameraFromSource` (Mac, iPad, iPhone) | `CameraDetectionResult` | If confidence > 0.8 and the label is empty, `camera.name` becomes `cameraLabelSettings.label`, which `CopyVerifyExecutor` uses to name the destination folder |

The orchestrator stops at the first stage that returns anything. The stages run in this order:

1. Spotlight metadata (Mac only; runs `mdls` on the first MP4/MOV/M4V/AVI/MKV, and `NSMetadataItem` on JPG/TIFF/DNG/HEIC)
2. Fujifilm RAF
3. Sony (`MEDIAPRO.XML`, then folder shape)
4. Canon (`MISC/CANON*`, CR2/CR3, folder shape)
5. Panasonic
6. ARRI `.ale`
7. Folder-pattern table
8. File-name regexes
9. Extension scores
10. Any XML

## Per brand

Legend for the two detector columns:
- **✓**: correct.
- **✗ X**: detected as brand X.
- **—**: not detected.

The **Mac auto-detect** column is `CameraStructureDetector`. The **Label** column is the orchestrator.

The Label column assumes files with no Spotlight metadata. With real footage, stage 1 may answer first for MP4/MOV cards (see finding C). That can give a better label, or it can give `"(null) (null)"`.

| Camera / card | Expected layout (source) | Mac auto-detect | Label (orchestrator) | Fixture |
| --- | --- | --- | --- | --- |
| **Sony VENICE / VENICE 2, X-OCN on AXS** | Volume and top folder named Cam ID + Reel, e.g. `A001/`. One OP1a `.mxf` per clip. exFAT. Clip subfolders and XML sidecars are *inferred*. [AbelCine X-OCN](https://www.abelcine.com/articles/blog-and-knowledge/tutorials-and-guides/x-ocn-workflows-with-the-sony-venice), [Sony X-OCN white paper](https://pro.sony/s3/2023/09/21144038/Sony_X-OCN_White_Paper_v1.1.pdf), [AXS card](https://pro.sony/ue_US/products/axs-memory-cards/axs-a1ts66) | — | ✗ "Professional" (2+ MXF). With a single clip: nil | `sonyVeniceAXS` |
| **Sony VENICE, XAVC/ProRes on SxS** | `XDROOT/Clip/*.MXF` plus `XDROOT/MEDIAPRO.XML`. Firmware 3.0+ can rename `XDROOT` to Cam ID + Reel. [AbelCine VENICE fw 3.0](https://www.abelcine.com/articles/blog-and-knowledge/tech-news/venice-firmware-30) | — (`XDROOT` is not checked) | ✓ "Sony" (the model code MPC-3610 is not mapped). With the renamed root: ✗ "Professional". With ProRes `.mov`, stage 1 runs first. | `sonyVeniceSxS` |
| Sony FX6 / FX9 / FS7 / F55 XAVC | `XDROOT/{Clip,Sub,General,…}`, `MEDIAPRO.XML`. On SD cards: `PRIVATE/XDROOT`. [AbelCine F55](https://www.abelcine.com/articles/blog-and-knowledge/tutorials-and-guides/how-to-import-f5f55-footage-in-fcp-avid-and-premiere), [Nablet](https://support.nablet.com/hc/en-us/articles/4415856736788-nablet-XAVC-XDCAM-AMA-Plug-in) | — | ✓ "Sony FX6" (from `systemKind`). The SD layout under `PRIVATE/XDROOT` is not checked. | `sonyXAVCPro` |
| Sony XDCAM EX (SxS) | `BPAV/{CLPR,TAKR}`, `MEDIAPRO.XML`, `CUEUP.XML`. [Avid forum PDF](https://community.avid.com/cfs-filesystemfile.ashx/__key/CommunityServer.Components.PostAttachments/00.00.60.25.02/XDCAM-HD_5F00_EX-folder-structure.pdf) | — | ✓ "Sony" (folder stage). The `MEDIAPRO.XML` path is not checked. | `sonyXDCAMEX` |
| Sony Alpha / FX3 / FX30 | `PRIVATE/M4ROOT/CLIP/C0001.MP4`, `DCIM/100MSDCF/DSC00001.ARW`; AVCHD under `PRIVATE/AVCHD/BDMV/STREAM`. [Sony Alpha forum](https://www.sonyalphaforum.com/topic/9230-cant-find-sony-a7iii-video-files-on-your-computer/), [DPReview](https://www.dpreview.com/forums/thread/4521107) | ✓ Sony, **but `mediaPath` = `PRIVATE/`** (finding A) | ✓ "Sony A7S III" or "Sony A7S" at random (finding F) | `sonyAlpha` |
| Canon EOS stills | `DCIM/100CANON/IMG_0001.CR3`, `MISC/`. [Canon KB ART153030](https://support.usa.canon.com/kb/s/article/ART153030) | ✓ | ✓ "Canon" | `canonEOSStills` |
| Canon EOS with MP4 movies (R5/R6) | Same, plus `MVI_0002.MP4` (*inferred* name) | ✗ Sony | ✓ "Canon" (after stage 1) | `canonEOSWithMP4` |
| Canon Cinema EOS XF-AVC (C300 II/III, C500 II, C70 on CFexpress) | `CONTENTS/CLIPS001/INDEX.MIF`, one folder per clip holding `.MXF`, `.CIF`, `.XML`. [Canon KB ART165712](https://support.usa.canon.com/kb/s/article/ART165712), [AbelCine C300 II](https://www.abelcine.com/articles/blog-and-knowledge/tutorials-and-guides/how-to-import-c300-mark-ii-footage-in-avid-fcp-x-premiere-and-resolve) | — | ✓ "Canon" | `canonXFAVC` |
| Canon C70 MP4 / XF-HEVC S on SD | `DCIM/XXX_mmdd/*.MP4`; slow/fast-motion audio in `PRIVATE/AUDIO`. [C70 manual p.37](https://www.manualslib.com/manual/2096455/Canon-Eos-C70.html?page=37) | ✗ Sony, **`mediaPath` = `PRIVATE/`** | Depends on stage 1 and on whether `MISC/` exists (*inferred*) | `canonC70SD` |
| Canon Cinema RAW Light (.CRM) | Not confirmed (`DCIM/…` or `CRM/…`) | — | Unknown. `.CRM` is not recognised by any stage. | none (layout unconfirmed) |
| ARRI ALEXA Mini / Mini LF / 35 / AMIRA | Reel folder such as `A001R0Z3/`, one MXF per take (older ALEXA: `.ari` per frame), an `ARRI/` support folder, `.ale`. The clip-folder shape and the `.ale` location are *inferred*. [ARRI file formats](https://www.arri.com/en/learn-help/learn-help-camera-system/pre-postproduction/file-formats-data-handling), [Codex Mini workflow](https://help.codex.online/content/Workflows/ALEXA_Mini_Workflow) | — (the `ARRI/` folder holds no media) | ✓ "ARRI …" from the `.ale`, but Mini LF reads as "Alexa LF" (finding G). Without an `.ale`: ✓ "ARRI" (folder stage). | `arriMiniLF` |
| RED (KOMODO, V-RAPTOR, DSMC2) | `A001_0925AB.RDM/A001_C001_0925AB.RDC/A001_C001_0925AB_001.R3D`. [RED R3D structure](https://docs.red.com/955-0004_v50/REDCINE-XProOperationGuide/Content/4_LoadOrganize/R3D_Structure.htm), [RED clip naming](https://docs.red.com/955-0196_v1.6/Content/5_How_To/Media/ClipName.htm) | — (it looks for a `RED/` folder) | ✓ "RED" (extension stage). With `.mov` proxies, stage 1 runs first. | `redR3D` |
| Blackmagic | Flat root: `A001_09251512_C001.braw`. [BMD forum](https://forum.blackmagicdesign.com/viewtopic.php?f=2&t=105347) | — (it looks for a `BRAW/` folder) | ✓ "Blackmagic" (extension stage). The file-name regex never matches real names. | `blackmagicBRAW` |
| Panasonic Lumix | `DCIM/100_PANA/P1000001.RW2`, `MISC/`, `PRIVATE/PANA_GRP`; AVCHD under `PRIVATE/AVCHD`. [Panasonic help](https://help.na.panasonic.com/answers/how-to-set-the-folder-and-file-names-lumix/) | Stills ✓. Video (MP4/MTS) ✗ Sony. | ✗ "Canon" (DCIM + MISC); ✗ "Sony" if `PRIVATE/AVCHD` exists | `panasonicLumixStills` |
| Panasonic P2 | `CONTENTS/{AUDIO,CLIP,ICON,PROXY,VIDEO,VOICE}`, `LASTCLIP.TXT`. [Panasonic P2 FAQ](https://eww.pass.panasonic.co.jp/pro-av/support/content/faq/EN/p2card_handling_en.htm), [Ingex P2 structure](https://ingex.sourceforge.net/P2_structure.html) | — (it looks for a `P2/` folder) | ✓ "Panasonic" | `panasonicP2` |
| Fujifilm | `DCIM/100_FUJI/DSCF0001.RAF` (and `.MOV`, *inferred*). [pal2tech](https://pal2tech.com/guides/camera/fujifilm-camera-file-and-folder-naming-setup/) | Stills ✓. With a `.MOV`: ✗ Canon. | ✓ "Fujifilm …". Model can be wrong: X-T30 → X-T3 (finding F). | `fujifilmStills`, `fujifilmWithMovie` |
| Nikon | `DCIM/100NIKON` (or e.g. `100NZ_9`, *inferred*), `DSC_0001.NEF`. [Nikon Z8 manual](https://onlinemanual.nikonimglib.com/z8/en/psm_file_naming_116.html) | ✗ Canon (`\d{3}[A-Z]+` matches `100NIKON`/`100NZ_9`). With MP4: ✗ Sony. | ✗ "Generic" (the folder stage answers before the NEF extension is counted) | `nikonStills` |
| GoPro HERO | `DCIM/100GOPRO/GX010001.MP4` plus `.THM`/`.LRV`, `MISC/`. [GoPro naming](https://community.gopro.com/s/article/GoPro-Camera-File-Naming-Convention), [GoPro root level](https://community.gopro.com/s/article/How-to-Find-the-Root-Level-of-Your-SD-Card) | ✗ Sony | ✗ "Canon", or `"(null) (null)"` from stage 1 | `goPro` |
| DJI (older) | `DCIM/100MEDIA/DJI_0001.MP4`, `MISC/`. [DJI forum](https://forum.dji.com/thread-277539-1-1.html) | ✗ Sony | ✗ "Canon" | `djiLegacy` |
| DJI (Mavic 3, Mini 4 Pro, Avata 2) | `DCIM/DJI_001/DJI_20250925130032_0001_D.MP4` plus `.SRT`/`.LRF`. [DJI forum](https://forum.dji.com/forum.php?mod=viewthread&tid=311643) | ✗ Sony | ✗ "Generic" | `djiCurrent` |
| Insta360 | `DCIM/Camera01/VID_…_00_001.insv`, `LRV_…lrv`, `IMG_…insp`. [Insta360 X3 manual](https://onlinemanual.insta360.com/x3/en-us/operating-tutorials/storage/fileformat) | ✓ | ✗ "Generic" (no stage knows `.insv`) | `insta360` |
| Generic DCIM | DCF `DCIM/NNNXXXXX` | Almost never reached: the Sony and Canon detectors catch DCIM first | "Generic" | covered by the above |

## Findings

### A. `mediaPath` is a subfolder, and Mac auto-select copies only that (safety, Promise 1)

- `SonyCameraDetector` returns `findBestMediaPath(candidates: ["PRIVATE","XDCAM","DCIM"])` (`CameraStructureDetector.swift:209`), which is the first of those folders that exists.
- Every other detector returns the folder it matched (`DCIM`, `PRIVATE`, `P2`, `RED`, `CLIPS`, …).
- `AppCoordinator.swift:660` sets `fileSelectionViewModel.sourceURL = cameraCard.mediaPath`.

With auto-populate on:
- A Sony Alpha card copies only `PRIVATE/`. The `DCIM` stills are skipped.
- A Canon C70 SD card copies `PRIVATE/`, which holds only the slow-motion WAVs. The clips in `DCIM` are skipped.
- A Lumix or Canon card copies `DCIM/` and skips `MISC/` and `PRIVATE/`. Those are small, but still part of the card.

Verification then passes for what was copied. Mitigations: auto-populate defaults to off (`TransferModels.swift:135`, guarded by `AutoSourceSelectionPolicyTests`), and the source path is visible in the UI.

**Recommendation:** the source for a detected card is always `volumeURL`. Keep `mediaPath` for display only, or remove it. This is a one-line change at `AppCoordinator.swift:660` (hands-off this session), or have every detector return `volume`.

Tests: `sonyAlphaMediaPathIsCardRoot` and `canonC70SDIsCanonWithRootMediaPath` (both known issues).

### B. `CameraStructureDetector` order turns Sony and Canon into catch-alls (misfire)

- `SonyCameraDetector` accepts any `DCIM/` that contains `.mp4` or `.mts` within four levels. That covers GoPro, DJI, Canon R video and Lumix video.
- `CanonCameraDetector` accepts any `DCIM/` that contains `.mov`, or any subfolder matching the unanchored regex `\d{3}[A-Z]+`. That covers the Fujifilm MOV movies, Nikon `100NIKON`/`100NZ_9`, and every DCF camera whose folder suffix begins with a letter.
- Both run before the brand-specific detectors. The GoPro, DJI, Nikon and GenericDCIM detectors are effectively dead for real cards.
- In the other direction, the pro layouts that detector *should* find (`XDROOT`, `BPAV`, `*.RDM`, root `.braw`, `CONTENTS/`, ARRI reel folders) are not in its patterns.

**Recommendation:** check brand-unique markers first (`100GOPRO`, `DJI_`/`100MEDIA`, `100_PANA`, `100_FUJI`, `NIKON`/`NZ_`, `.insv`, `XDROOT`, `BPAV`, `M4ROOT`, `.RDM`, `CONTENTS/CLIPS001`, `CONTENTS/VIDEO`). Use DCIM plus a generic extension only as a last resort, and anchor the regex.

Test: `structureDetectorMisclassifiesOrMisses` (15 layouts, known issues).

### C. Orchestrator stage 1 on Mac probably returns `"(null) (null)"` (misfire, needs a Mac check)

- `parseMdlsOutput` (`UnifiedMetadataDetectionService.swift:201-222`) takes whatever follows `= `.
- `mdls` prints `kMDItemAcquisitionMake = (null)` when an attribute is missing. That describes most MP4/MOV files from GoPro, DJI, Sony and Canon cameras, and anything on a volume Spotlight hasn't indexed.
- The result would be `make = "(null)"` and `model = "(null)"`, and the orchestrator returns `"(null) (null)"` before any brand stage runs.
- I could not run `mdls` here. To check: `mdls -name kMDItemAcquisitionMake -name kMDItemAcquisitionModel some.MP4`.
- If confirmed:
  - The source label on Mac for most video cards is garbage. `CleanCameraNameService` turns it into `(NULL)(N`.
  - `SharedCameraDetectionService` ignores it (not a known make), then carries on.
  - Separately, `extractVideoMetadataWithFFProbe` hard-codes `/usr/local/bin/ffprobe`, which is the Intel Homebrew path. Apple Silicon Homebrew installs to `/opt/homebrew/bin`.

**Recommendation:** treat `(null)` and empty values as missing. Stage 1 should also yield to a brand-specific structure match rather than running first.

Test: `orchestratorLabelsGoPro` (known issue; it fails whichever of the two wrong answers comes back).

### D. Orchestrator folder rules: DCIM + MISC means Canon (misfire, reaches destination folder names)

- In `FolderStructureDetectionService.swift:50`, `(["DCIM","MISC"], "Canon", 2)` is listed before GoPro (`100GOPRO`, line 62) and DJI (`100MEDIA`, line 75). GoPro, DJI, Lumix and most other stills cameras write `MISC/`.
- `CanonDetectionService.checkCanonFolderStructure` counts `DCIM` + `MISC` the same way. It runs before `PanasonicDetectionService`, so a Lumix card (RW2 only) becomes "Canon".
- `SonyDetectionService.checkSonyFolderStructure` counts `DCIM` + `PRIVATE/AVCHD` as Sony. AVCHD is a shared standard that Panasonic and Canon camcorders also write.
- Substring matching (`$0.contains(pattern)`, line 92) means any folder path containing `MISC`, `ARRI`, `R3D`, `BRAW`, `CLIPS` or `CONTENTS` matches. For example, a user folder named `CARRIE` triggers ARRI.
- The relative-path trim (line 24) fails when the enumerator returns a `/private/var/…` path for a `/var/…` root. The absolute path then takes part in the match, and the `^DCIM/` regex on line 104 never matches.

Consequence: on every platform, `SharedCameraDetectionService` raises a known make to 0.9 confidence. `SharedAppCoordinator.detectCameraFromSource` then writes `camera.name` (e.g. `CANON`) into an empty `cameraLabelSettings.label`, and `CopyVerifyExecutor` uses that to name the destination folder. The files are intact, but the GoPro footage lands in a folder named `CANON`.

**Recommendation:** use brand-unique markers only, match on path components rather than substrings, and put generic `DCIM` last.

Tests: `orchestratorLabelsLumixAsPanasonic`, `folderStructureLabelsGoProAndDJI` (known issues).

### E. VENICE / VENICE 2 (GitHub #8)

- **AXS (X-OCN):** no stage knows the layout. With two or more clips the extension stage answers "Professional".
  - `SharedCameraDetectionService` then scores 0.6 ("Professional Camera"). `inferCameraType` maps `.mxf` to `.sony`, and the name becomes `PROFESSI`.
  - Confidence is under 0.8, so the label is not applied to destinations.
  - On Mac, `CameraStructureDetector` returns nil, so nothing is auto-selected. That is safe.
- **SxS (XAVC):** labelled "Sony" through `XDROOT/MEDIAPRO.XML`. The VENICE model codes (MPC-3610; VENICE 2 is MPC-3628) are not in `mapSonySystemKind`. The firmware 3.0 option that renames the root to Cam ID + Reel defeats every `XDROOT` check.
- **The #8 symptom ("1 only destination") is not caused by detection.** Detection only picks a label (and, on Mac with auto-populate, a source folder, which would give *fewer* files on the destination, not an extra one). The thesis already points at Finder's `.DS_Store` on the destination. AXS cards are exFAT and Sony's AXSM tooling can also leave files behind, so the compare-ignore list should be checked against a real AXS dump. That work is out of scope here.

**Recommendation:** add a Sony pro rule: a root folder holding `*.MXF` whose names match `^[A-Z]\d{3}C\d{3}_\d{6}[A-Z0-9]{2}` (*inferred* pattern). Also add `PRIVATE/XDROOT` and `BPAV/MEDIAPRO.XML`, and map MPC-3610 to VENICE and MPC-3628 to VENICE 2.

Tests: `orchestratorLabelsVeniceAXSAsSony`, `orchestratorNamesVenice` (known issues), `orchestratorLabelsVeniceSxSAsSony` (guard).

### F. Model tables are Dictionaries matched by substring (nondeterministic labels)

Swift `Dictionary` iteration order changes per process. Several lookups iterate one and return the first `contains` hit, so overlapping keys give different answers from run to run:

- `SonyDetectionService.mapSonySystemKind` (`:149`): `ILCE-7S` ⊂ `ILCE-7SM3`/`ILCE-7SM2`; `ILCE-7C` ⊂ `ILCE-7CM2`; `ILME-FX3` ⊂ `ILME-FX30`; `PXW-FS7` ⊂ `PXW-FS7M2`.
- `CanonDetectionService` (`:140`, `:173`): `EOS R` ⊂ `EOS R5`/`R6`/`R8`/`R10`/`R50`; `EOS R6` ⊂ `EOS R6 Mark II`; `M50` ⊂ `M50 Mark II`.
- `FujiDetectionService` (`:80`): `X-T3` ⊂ `X-T30`; `X-T2` ⊂ `X-T20`; `X-H2` ⊂ `X-H2S`; `X100V` ⊂ `X100VI`; `GFX100` ⊂ `GFX100S`.
- `PanasonicDetectionService` (`:132`): `DC-GH5` ⊂ `DC-GH5S`; `DC-S1` ⊂ `DC-S1H`/`DC-S1R`.

`CleanCameraNameService` is ordered, but the order is wrong in places:
- `X-T3` is checked before `X-T30`, so X-T30 becomes `XT3`.
- `R5` matches `R50`.
- `RED` is matched as a substring, so "INFRARED" and similar strings count.

`SonyDetectionService.mapSonySystemId`'s hex IDs (`0x0123`…) look invented. I found no source for them.

**Recommendation:** use ordered arrays, longest key first, and match exact tokens.

Test: `sonyStageReadsA7SIII` (intermittent known issue).

### G. ARRI `.ale` parsing is case-sensitive

`ARRIDetectionService.swift:44-48` tests `contains("MINI LF")` and `contains("MINI")` on the raw line. A mixed-case "ALEXA Mini LF" therefore reads as "Alexa LF", and "ALEXA Mini" as "Alexa". The model string's case in real ALEs is *inferred*; I could not check a real file. Any line containing "arri" (for example in a path) also returns "ARRI" early.

Test: `arriStageReadsMiniLFFromALE` (known issue).

### H. `SharedCameraDetectionService` specifics

- `detectFromFolderName` (`:285-313`) substring-matches the source folder name. A folder named `SHARED`, `TRANSFERRED` or `CREDITS` scores RED 0.9; `CARRIE` scores ARRI 0.9; any name containing `C70` scores Canon C70. At 0.9 the label is auto-applied to the destination folder name.
- `inferCameraType` maps any `.mxf` to `.sony`. That covers ARRI, Canon XF-AVC, P2 and VENICE; ARRI is only saved because its check runs first.
- `cleanCameraName` (`:177`) duplicates `CleanCameraNameService` with different rules. The same card is named `A7S3` on one path and `A7SIII` on the other (Promise 5).
- It walks the whole source tree three times (`analyzeFolderStructure` and `getFileList` twice), on top of the orchestrator's walks. The ≥1 TB guard doesn't help on a 512 GB card with 100k files.

### I. Performance: most orchestrator stages are unbounded full walks

The Fuji, Canon RAW, Panasonic RAW, ARRI, folder-structure, extension and XML stages each enumerate the whole volume, and the XML stage reads every `.xml`. The Mac `VolumeMonitorService` runs the orchestrator on **every** mounted volume, including multi-TB backup drives, before it classifies them by size (`VolumeMonitorService.swift:420`). I did not measure this. `CameraStructureDetector` bounds its scan (depth 3, 50k entries); the orchestrator does not.

## The 12 `.shared` singletons

The 12 are: `CameraDetectionOrchestrator`, `UnifiedMetadataDetectionService`, `CleanCameraNameService`, `FujiDetectionService`, `SonyDetectionService`, `CanonDetectionService`, `PanasonicDetectionService`, `ARRIDetectionService`, `FileNamingDetectionService`, `FileExtensionDetectionService`, `FolderStructureDetectionService`, `XMLMetadataDetectionService`.

What they have in common:
- Each is a `final class` with `private init()`.
- None has mutable stored state. The orchestrator only holds `let` references to the other 11.
- Scratch state (arrays, counters) is local to each call.
- The XML stage's test hook is a per-call parameter.

What that means:
- **Thread safety:** they are safe today. They are called concurrently from `Task.detached` in `FileSelectionViewModel` and `CameraLabelViewModel`, and from a global queue.
- **Swift 6:** none is marked `Sendable`. Under complete strict concurrency, each `static let shared` of a non-`Sendable` class is an error ("not concurrency-safe"). The fix is mechanical and safe: add `: Sendable` to each class, since none has mutable state. The orchestrator's stored properties then need no change. The project is currently Swift 5 with `targeted` checking, so this is not urgent. It belongs with thesis plan step 5.
- **Reach:** 9 of the 12 are used only by the orchestrator.
  - `FujiDetectionService` is also called by a debug routine in `FileSelectionViewModel` (~line 233).
  - `CleanCameraNameService` is also used directly by the two Mac view models.
  - `CameraDetectionOrchestrator` is used by 4 production callers.
- **Design:** the classes are pure functions dressed as objects. They cannot be injected, so the stage order can only be tested end to end. That order is where most of the bugs above live.
  - Simplest direction: one `enum CardLayoutClassifier` with static functions over a bounded directory listing, returning `(brand, model?, confidence, evidence)`.
  - It would feed both the Mac auto-detect and the shared service, replacing the three detectors and two name cleaners.
  - That converges with the thesis target of an engine package; it is not a rewrite for its own sake.
- **Dead or stale:** `CameraDetectionOrchestrator.getCleanCameraName` has no caller outside the file; callers use `CleanCameraNameService.shared` directly. The migration-notes comment at the bottom of the orchestrator lists a `VideoMetadataDetectionService` and a `MediaMetadataDetectionService` that do not exist (they were merged into `UnifiedMetadataDetectionService`).

## Tests added

- **`BitMatchTests/TestHelpers/CameraCardLayouts.swift`**: 21 layouts, each with a source URL and an "inferred" note. `build()` creates the tree with empty files, plus text contents for `MEDIAPRO.XML` and the ARRI `.ale`. No layout had a test before; the only existing tests used a synthetic DCIM + MISC folder. The Canon Cinema RAW Light layout is left out because I couldn't confirm it.
- **`BitMatchTests/CameraCardLayoutDetectionTests.swift`** (Swift Testing):
  - **Guards** pin behaviour that is right today.
  - **`withKnownIssue`** tests record today's misfires. They are strict: a fix makes them fail, which is the prompt to remove the wrapper and keep the test as a guard. The one exception is `sonyStageReadsA7SIII`, which is intermittent by nature.

The one-line change that should make each guard fail:

| Guard | Plant this to make it fail |
| --- | --- |
| `everyLayoutBuildsItsDeclaredTree` | In `CameraCardLayout.build()`, delete the `try Data(...).write(to: url)` line |
| `structureDetectorFindsSonyAlpha` | Delete `SonyCameraDetector(),` at `CameraStructureDetector.swift:108` |
| `structureDetectorFindsCanonStills` | Delete `CanonCameraDetector(),` at `CameraStructureDetector.swift:109` |
| `structureDetectorFindsLumixStills` | Delete `PanasonicDetector(),` at `CameraStructureDetector.swift:110` |
| `structureDetectorFindsFujifilmStills` | Delete `FujifilmDetector(),` at `CameraStructureDetector.swift:111` |
| `structureDetectorFindsInsta360` | Delete `Insta360Detector(),` at `CameraStructureDetector.swift:115` |
| `orchestratorLabelsVeniceSxSAsSony` | `CameraDetectionOrchestrator.swift:36`: `{ return sonyInfo }` → `{ return "Canon" }` |
| `orchestratorReadsFX6ModelFromMediaPro` | Delete `"ILME-FX6": "FX6",` at `SonyDetectionService.swift:136` |
| `orchestratorLabelsXFAVCAsCanon` | `FolderStructureDetectionService.swift:53`: `"Canon", 1)` → `"Professional", 1)` |
| `orchestratorLabelsP2AsPanasonic` | `FolderStructureDetectionService.swift:58`: `"Panasonic", 2)` → `"Canon", 2)` |
| `orchestratorLabelsR3DAsRED` | `FileExtensionDetectionService.swift:44`: `("RED", 10)` → `("Professional", 10)` |
| `orchestratorLabelsBRAWAsBlackmagic` | `FileExtensionDetectionService.swift:45`: `("Blackmagic", 10)` → `("Professional", 10)` |
| `folderStructureLabelsXDCAMEXAsSony` | `FolderStructureDetectionService.swift:47`: `"Sony", 1)` → `"Professional", 1)` |
| `folderStructureLabelsMiniLFAsARRI` | `FolderStructureDetectionService.swift:82`: `"ARRI", 1)` → `"Professional", 1)` |
| `fujiStageFindsRAF` | `FujiDetectionService.swift:24`: `== "RAF"` → `== "RAW"` |

The known-issue tests need no planted bug: each must record an issue on today's code. If one reports "known issue was not recorded", my trace for that layout was wrong. Please note which one, so this document can be corrected.

## Recommended order of fixes

1. **Finding A:** the source is always the card root. This is the only item touching Promise 1.
2. **Findings C and D:** stop wrong labels reaching destination folder names. Ignore `(null)` from `mdls`, remove the DCIM + MISC = Canon rules, and only auto-apply a label when a brand-unique marker was seen.
3. **Findings B and E:** brand-unique markers first; add VENICE (AXS, SxS), `PRIVATE/XDROOT`, `.RDM`, root `.braw`, `CONTENTS/`, ARRI reel folders.
4. **Finding F:** ordered model tables.
5. Collapse the three detectors into one classifier (see "The 12 `.shared` singletons").

## Not verified

- Nothing was compiled or run. The detector outcomes above are hand traces of the code.
- Most sources were read through search summaries, not the pages themselves. These items are *inferred* and need a real card or the manual:
  - VENICE AXS clip-folder shape and sidecars
  - ARRI clip-folder shape, `.ale` location and model-string case
  - Canon CRM location and `CANONMSC`
  - Nikon default folder names
  - whether Blackmagic uses a root reel folder
  - `MEDIAPRO.XML` attribute formats
- `mdls` output for files with no acquisition metadata (finding C).
- Real-footage behaviour of orchestrator stage 1. The fixtures are empty files, so stage 1 finds nothing in them. With real footage it may answer first, correctly or not.
