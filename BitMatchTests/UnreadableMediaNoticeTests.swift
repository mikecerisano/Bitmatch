// UnreadableMediaNoticeTests.swift
// A card macOS can see but not mount used to produce nothing at all. Sony
// SxS cards need Sony's SxS UDF Driver, and AXS cards Sony's AXS software;
// the notice says so instead of leaving the user guessing.
import Foundation
import Testing
@testable import BitMatch

struct UnreadableMediaNoticeTests {
    private func media(
        vendor: String? = nil,
        model: String? = nil,
        mediaName: String? = nil,
        volumeKind: String? = nil,
        isLeaf: Bool = true,
        isRemovable: Bool = true,
        isInternal: Bool = false
    ) -> UnreadableMediaNotice.Media {
        UnreadableMediaNotice.Media(
            bsdName: "disk9s1",
            vendor: vendor,
            model: model,
            mediaName: mediaName,
            volumeKind: volumeKind,
            isLeaf: isLeaf,
            isRemovable: isRemovable,
            isInternal: isInternal
        )
    }

    /// Fails if the SxS match is removed from `UnreadableMediaNotice.make`.
    @Test func sonySxSCardWithoutAFileSystemPointsToTheSxSDriver() throws {
        let notice = try #require(UnreadableMediaNotice.make(for: media(vendor: "Sony", model: "SxS PRO+ Card Reader")))
        #expect(notice.kind == .sonySxS)
        #expect(notice.title.contains("SxS"))
        // Apple's article links Sony's SxS UDF Driver (Sony's pages block scripted checks).
        #expect(notice.helpURL?.absoluteString == "https://support.apple.com/en-us/101826")
    }

    /// Fails if AXS media falls through to the SxS or generic notice.
    @Test func sonyAXSCardPointsToSonysAXSSoftware() throws {
        let notice = try #require(UnreadableMediaNotice.make(for: media(vendor: "SONY", model: "AXS-AR1")))
        #expect(notice.kind == .sonyAXS)
        #expect(notice.title.contains("AXS"))
    }

    /// Other unreadable removable media still get a plain explanation.
    @Test func otherUnreadableCardsGetAGenericNotice() throws {
        let notice = try #require(UnreadableMediaNotice.make(for: media(vendor: "Generic", model: "STORAGE DEVICE")))
        #expect(notice.kind == .unknownFormat)
    }

    /// No notice for anything macOS can read, for internal disks, or for a
    /// whole disk whose partitions carry the file systems. Fails if any of
    /// those guards is dropped.
    @Test func readableInternalAndParentDisksGetNoNotice() {
        #expect(UnreadableMediaNotice.make(for: media(vendor: "Sony", model: "SxS", volumeKind: "exfat")) == nil)
        #expect(UnreadableMediaNotice.make(for: media(vendor: "Sony", model: "SxS", volumeKind: "udf")) == nil)
        #expect(UnreadableMediaNotice.make(for: media(vendor: "Sony", model: "SxS", isInternal: true)) == nil)
        #expect(UnreadableMediaNotice.make(for: media(vendor: "Sony", model: "SxS", isLeaf: false)) == nil)
        #expect(UnreadableMediaNotice.make(for: media(vendor: "Sony", model: "SxS", isRemovable: false)) == nil)
    }
}
