import XCTest
import AppKit
import Carbon
@testable import Lockpaw

final class HotkeyConfigTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: HotkeyConfig.requireAuthenticationToUnlockKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: HotkeyConfig.requireAuthenticationToUnlockKey)
        super.tearDown()
    }

    // MARK: - Unlock authentication preference

    func testRequiresAuthenticationToUnlockDefaultsToFalse() {
        XCTAssertFalse(HotkeyConfig.requiresAuthenticationToUnlock)
    }

    func testRequiresAuthenticationToUnlockPersists() {
        HotkeyConfig.saveRequireAuthenticationToUnlock(true)
        XCTAssertTrue(HotkeyConfig.requiresAuthenticationToUnlock)

        HotkeyConfig.saveRequireAuthenticationToUnlock(false)
        XCTAssertFalse(HotkeyConfig.requiresAuthenticationToUnlock)
    }

    // MARK: - System conflict detection

    func testCmdQIsConflict() {
        let result = HotkeyConfig.systemConflict(keyCode: 12, modifiers: .command)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Quit"), "Cmd+Q should report a Quit conflict")
    }

    func testCmdTabIsConflict() {
        let result = HotkeyConfig.systemConflict(keyCode: 48, modifiers: .command)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("App Switcher"), "Cmd+Tab should report an App Switcher conflict")
    }

    func testCmdShiftLIsNotConflict() {
        let result = HotkeyConfig.systemConflict(keyCode: 37, modifiers: [.command, .shift])
        XCTAssertNil(result, "Cmd+Shift+L should not conflict with any system shortcut")
    }

    func testCtrlCmdQIsConflict() {
        let result = HotkeyConfig.systemConflict(keyCode: 12, modifiers: [.command, .control])
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Lock Screen"), "Ctrl+Cmd+Q should report a Lock Screen conflict")
    }

    // MARK: - Additional cases

    func testCmdSpaceIsConflict() {
        let result = HotkeyConfig.systemConflict(keyCode: 49, modifiers: .command)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Spotlight"))
    }

    func testCmdShiftZIsConflict() {
        let result = HotkeyConfig.systemConflict(keyCode: 6, modifiers: [.command, .shift])
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Redo"))
    }

    func testNoConflictForUnusedCombination() {
        // Cmd+Shift+K (keyCode 40) is not a system shortcut
        let result = HotkeyConfig.systemConflict(keyCode: 40, modifiers: [.command, .shift])
        XCTAssertNil(result)
    }

    // MARK: - matches (the password field's local key monitor)

    func testHotkeyMatchesWithItsModifiers() {
        XCTAssertTrue(HotkeyConfig.matches(keyCode: 37, modifierFlags: [.command, .shift], savedKeyCode: 37, savedModifiers: cmdKey | shiftKey))
    }

    func testHotkeyNeedsEverySavedModifier() {
        XCTAssertFalse(HotkeyConfig.matches(keyCode: 37, modifierFlags: [.command], savedKeyCode: 37, savedModifiers: cmdKey | shiftKey))
        XCTAssertFalse(HotkeyConfig.matches(keyCode: 37, modifierFlags: [.command, .option], savedKeyCode: 37, savedModifiers: cmdKey | controlKey))
    }

    func testHotkeyNeedsTheSavedKey() {
        XCTAssertFalse(HotkeyConfig.matches(keyCode: 38, modifierFlags: [.command, .shift], savedKeyCode: 37, savedModifiers: cmdKey | shiftKey))
    }

    func testExtraModifiersStillMatchLikeTheTap() {
        // While locked, extras still match, so the lock & sleep shortcut unlocks too.
        XCTAssertTrue(HotkeyConfig.matches(keyCode: 37, modifierFlags: [.command, .shift, .option], savedKeyCode: 37, savedModifiers: cmdKey | shiftKey))
    }

    func testSleepShortcutAddsTheFirstMissingModifier() {
        XCTAssertEqual(HotkeyConfig.sleepModifiers(for: controlKey | optionKey), controlKey | optionKey | shiftKey)
        XCTAssertEqual(HotkeyConfig.sleepModifiers(for: cmdKey | shiftKey), cmdKey | shiftKey | optionKey)
        XCTAssertNil(HotkeyConfig.sleepModifiers(for: cmdKey | shiftKey | optionKey | controlKey))
    }

    func testPressedShortcutMatchesExactModifiers() {
        let main = controlKey | optionKey
        let pressed = { (key: Int, mods: Int, sleepOn: Bool) in
            HotkeyConfig.pressedShortcut(keyCode: key, modifiers: mods, savedKeyCode: 31, savedModifiers: main, sleepEnabled: sleepOn)
        }
        XCTAssertEqual(pressed(31, main, true), false, "plain lock")
        XCTAssertEqual(pressed(31, main | shiftKey, true), true, "lock & sleep")
        XCTAssertNil(pressed(31, main | shiftKey, false), "sleep shortcut off")
        XCTAssertNil(pressed(31, main | cmdKey, true), "extra modifier is neither")
        XCTAssertNil(pressed(31, controlKey, true))
        XCTAssertNil(pressed(32, main, true))
        XCTAssertEqual(pressed(31, main | 0x10000, true), false, "non-modifier bits ignored")
    }
}
