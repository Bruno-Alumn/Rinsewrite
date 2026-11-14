import AppKit
import XCTest
@testable import Rinsewrite

final class ShortcutTests: XCTestCase {
    func testStandardIsOptionSpace() {
        XCTAssertEqual(Shortcut.standard.display, "⌥Space")
        XCTAssertEqual(Shortcut.standard.spoken, "Option Space")
    }

    func testAllowedCombinations() {
        XCTAssertTrue(Shortcut.isAllowed([.option], keyCode: 49))            // ⌥Space
        XCTAssertTrue(Shortcut.isAllowed([.control], keyCode: 15))           // ⌃R
        XCTAssertTrue(Shortcut.isAllowed([.command, .option], keyCode: 15))  // ⌥⌘R
    }

    func testRefusedCombinations() {
        XCTAssertFalse(Shortcut.isAllowed([], keyCode: 15))                  // R while typing
        XCTAssertFalse(Shortcut.isAllowed([.shift], keyCode: 15))            // ⇧R
        XCTAssertFalse(Shortcut.isAllowed([.option], keyCode: 14))           // ⌥E types é
        XCTAssertFalse(Shortcut.isAllowed([.command], keyCode: 8))           // ⌘C
    }

    func testCodableRoundTrip() throws {
        let shortcut = Shortcut(keyCode: 15, flags: [.control, .shift], key: "R")
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), shortcut)
        XCTAssertEqual(shortcut.display, "⌃⇧R")
    }
}

final class LevelsTests: XCTestCase {
    func testStepsMapToNames() {
        XCTAssertEqual(Levels.name(0, in: Levels.grammar), "Minimal")
        XCTAssertEqual(Levels.name(0.5, in: Levels.grammar), "Standard")
        XCTAssertEqual(Levels.name(1, in: Levels.grammar), "Formal")
        XCTAssertEqual(Levels.name(0.5, in: Levels.humanize), "Natural")
        XCTAssertEqual(Levels.name(0.74, in: Levels.grammar), "Polished")
    }

    func testOutOfRangeValuesClamp() {
        XCTAssertEqual(Levels.index(-1, count: 5), 0)
        XCTAssertEqual(Levels.index(2, count: 5), 4)
    }

    func testValueForStep() {
        XCTAssertEqual(Levels.value(2, count: 5), 0.5)
        XCTAssertEqual(Levels.value(2, count: 3), 1)
    }
}

final class StatusTests: XCTestCase {
    func testOnlyReadyStatesCanRinse() {
        XCTAssertTrue(Status.ready(note: nil).canRinse)
        XCTAssertTrue(Status.unloaded.canRinse)
        XCTAssertFalse(Status.loading.canRinse)
        XCTAssertFalse(Status.needsAccess.canRinse)
        XCTAssertFalse(Status.rinsing.canRinse)
    }

    func testReadyNoteJoinsTitle() {
        XCTAssertEqual(Status.ready(note: "rinsed in 210 ms").title, "Ready — rinsed in 210 ms")
        XCTAssertEqual(Status.ready(note: nil).title, "Ready")
    }

    func testAttention() {
        XCTAssertTrue(Status.needsAccess.needsAttention)
        XCTAssertTrue(Status.notInstalled.needsAttention)
        XCTAssertFalse(Status.ready(note: nil).needsAttention)
    }
}
