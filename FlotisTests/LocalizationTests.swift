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
}
