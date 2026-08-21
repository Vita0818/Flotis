import AppKit
import CoreText
import XCTest
@testable import Flotis

final class LocalizationTests: XCTestCase {
    func testSimplifiedChinesePrimaryLanguagesUseSimplifiedChinese() {
        let identifiers = [
            "zh-Hans",
            "zh-Hans-CN",
            "zh-CN",
            "zh-SG",
            "zh_MY"
        ]

        for identifier in identifiers {
            XCTAssertEqual(
                AppLanguage.resolve(preferredLanguages: [identifier]),
                .simplifiedChinese,
                identifier
            )
        }
    }

    func testEveryOtherPrimaryLanguageUsesEnglish() {
        let identifiers = [
            "en",
            "en-US",
            "fr-FR",
            "ja-JP",
            "zh",
            "zh-Hant",
            "zh-Hant-TW",
            "zh-TW",
            "zh-HK",
            "zh-MO",
            "yue-Hant-HK",
            "not-a-locale"
        ]

        for identifier in identifiers {
            XCTAssertEqual(
                AppLanguage.resolve(preferredLanguages: [identifier]),
                .english,
                identifier
            )
        }
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: []), .english)
    }

    func testOnlyThePrimaryLanguageControlsTheAppLanguage() {
        XCTAssertEqual(
            AppLanguage.resolve(
                preferredLanguages: ["ja-JP", "zh-Hans-CN", "en-US"]
            ),
            .english
        )
        XCTAssertEqual(
            AppLanguage.resolve(
                preferredLanguages: ["zh-Hans-CN", "ja-JP", "en-US"]
            ),
            .simplifiedChinese
        )
    }

    func testLanguageSelectsTheExpectedCopy() {
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.localized(
                english: "Settings",
                simplifiedChinese: "设置"
            ),
            "设置"
        )
        XCTAssertEqual(
            AppLanguage.english.localized(
                english: "Settings",
                simplifiedChinese: "设置"
            ),
            "Settings"
        )
    }

    func testBundledJetBrainsMonoDependencyIsAvailable() throws {
        XCTAssertNoThrow(try FlotisType.validateBundledFont())
        XCTAssertEqual(FlotisType.appKit(14).familyName, FlotisType.familyName)
        XCTAssertEqual(
            FlotisType.appKit(14, .medium).familyName,
            FlotisType.familyName
        )
        XCTAssertNotNil(
            Bundle.main.url(
                forResource: "JetBrainsMono-OFL",
                withExtension: "txt"
            )
        )
    }

    func testMissingJetBrainsMonoResourceFailsClosed() {
        XCTAssertThrowsError(
            try FlotisType.validateBundledFont(
                in: Bundle(for: LocalizationTests.self)
            )
        ) { error in
            XCTAssertEqual(
                error as? FlotisFontDependencyError,
                .missingResource
            )
        }
    }

    func testJetBrainsMonoUsesPingFangForChineseFallback() {
        let baseFont = CTFontCreateWithName(
            FlotisType.regularPostScriptName as CFString,
            14,
            nil
        )
        let sample = "A中" as CFString
        let latinFont = CTFontCreateForString(
            baseFont,
            sample,
            CFRange(location: 0, length: 1)
        )
        let chineseFont = CTFontCreateForString(
            baseFont,
            sample,
            CFRange(location: 1, length: 1)
        )

        XCTAssertEqual(
            CTFontCopyFamilyName(latinFont) as String,
            FlotisType.familyName
        )
        XCTAssertTrue(
            (CTFontCopyFamilyName(chineseFont) as String).hasPrefix("PingFang")
        )
    }
}
