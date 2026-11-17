import XCTest

final class ViewingRoomTests: XCTestCase {
    func testAutomaticCaptionsKeepVideoPlaying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-automaticCaptions", "YES"]
        app.launch()
        let video = app.otherElements["videoRegion"]
        XCTAssertTrue(video.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: video)
        waitForExpectations(timeout: 60)
        XCUIRemote.shared.press(.menu)
        let text = app.staticTexts["captionText"]
        XCTAssertTrue(text.waitForExistence(timeout: 45), "Captions should show transcription, model preparation, or an availability explanation")
        XCTAssertFalse(text.label.isEmpty)
        XCTAssertEqual(video.value as? String, "Playing", "Speech setup must not interrupt playback")
        attach(app, "Automatic captions availability on this Apple TV")
    }

    func testGuideNavigationAndNativeControls() throws {
        let app = XCUIApplication()
        app.launch()
        let mini = app.staticTexts["MINI GUIDE"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["fullScreenButton"].exists)
        XCTAssertFalse(app.buttons["pauseButton"].exists)
        let video = app.otherElements["videoRegion"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertEqual(video.frame.height, app.frame.height, accuracy: 2)
        XCTAssertEqual(video.frame.minX, 0, accuracy: 2)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(mini.waitForNonExistence(timeout: 5))
        XCTAssertEqual(video.frame.width, app.frame.width, accuracy: 2)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.right)
        let full = app.staticTexts["PROGRAM GUIDE"]
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule-")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 45))
        let nativePicture = app.otherElements["videoSurface"]
        XCTAssertEqual(nativePicture.frame.height, app.frame.height * 0.30, accuracy: 2)
        XCTAssertGreaterThan(nativePicture.frame.minX, app.frame.width * 0.60)
        // A single arrow press moves exactly one channel row.
        let now = app.buttons["Now"]
        for _ in 0..<45 {
            if now.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(now.hasFocus)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.staticTexts["guideSelectedChannel"].label.contains("CH 02"))
        XCUIRemote.shared.press(.down, forDuration: 0.30)
        XCTAssertTrue(app.staticTexts["guideSelectedChannel"].label.contains("CH 08"))
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(now.hasFocus)
        let time = app.staticTexts["guideTime-0"]
        let initialTime = time.label
        XCUIRemote.shared.press(.right) // Later
        XCUIRemote.shared.press(.select)
        expectation(for: NSPredicate(format: "label != %@", initialTime), evaluatedWith: time)
        waitForExpectations(timeout: 10)
        XCUIRemote.shared.press(.left) // Return to the preceding two-hour page.
        expectation(for: NSPredicate(format: "label == %@", initialTime), evaluatedWith: time)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(full.exists)
        attach(app, "Full schedule with live video in the top right")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(mini.waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.down)
        attach(app, "Native controls immediately after Down")
        let live = app.cells["Rejoin Live"]
        XCTAssertTrue(live.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.cells["Last Channel"].exists)
        XCTAssertTrue(app.cells["Automatic Captions"].exists)
        attach(app, "Native tvOS player controls")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(live.waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(live.waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(live.waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(live.waitForExistence(timeout: 3))
    }

    func testMiniGuideBrowseAndLiveVideo() throws {
        let app = XCUIApplication()
        app.launch()
        let mini = app.staticTexts["MINI GUIDE"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        let channelName = app.staticTexts["nowPlayingChannel"]
        expectation(for: NSPredicate(format: "label != %@", "TUNING THE DIAL"), evaluatedWith: channelName)
        waitForExpectations(timeout: 45)
        let initial = channelName.label
        let targetID = initial == "HAPPY TREES" ? "computer-chronicles" : "happy-trees"
        let target = app.buttons["channel-\(targetID)"]
        for _ in 0..<20 {
            if target.exists && target.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(target.hasFocus)
        XCTAssertEqual(channelName.label, initial, "Browsing must not retune")
        XCUIRemote.shared.press(.select)
        XCTAssertNotEqual(channelName.label, initial)
        let video = app.otherElements["videoRegion"]
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: video)
        waitForExpectations(timeout: 60)
        XCTAssertEqual(video.frame.height, app.frame.height, accuracy: 2)
        attach(app, "Full height video beside the mini guide")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(mini.waitForNonExistence(timeout: 5))
        XCTAssertEqual(video.value as? String, "Playing")
        attach(app, "Full height original aspect ratio without a guide")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
