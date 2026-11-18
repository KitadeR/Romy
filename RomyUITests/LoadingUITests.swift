import XCTest

final class LoadingUITests: XCTestCase {
    @MainActor
    func testLoadingLeavesThePlaceAndScheduleReadable() {
        let app = XCUIApplication()
        app.launchArguments = ["-loading-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["確認中"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["徒歩4分 · 休憩 約56分"].exists)
        XCTAssertTrue(app.staticTexts["10:04到着 · 11:00出発"].exists)
        XCTAssertTrue(app.staticTexts["確認中"].exists)
    }

    @MainActor
    func testNoImageryAndFailedHoursEndTheirLoadingStates() {
        let app = XCUIApplication()
        app.launchArguments = ["-loading-preview"]
        app.launch()
        app.segmentedControls.buttons["画像なし"].tap()
        XCTAssertTrue(app.staticTexts["営業時間を確認できませんでした。Appleマップや公式ページもご確認ください。"]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["確認中"].exists)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "読み込み確認用カフェの周辺の写真を読み込み中").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["徒歩4分 · 休憩 約56分"].exists)
    }

    @MainActor
    func testSuccessReplacesThePlaceholders() {
        let app = XCUIApplication()
        app.launchArguments = ["-loading-preview"]
        app.launch()
        app.segmentedControls.buttons["取得成功"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "開発用の出典").firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "読み込み確認用カフェの前の通りの写真（Look Around）").firstMatch
            .waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["確認中"].exists)
    }
}
