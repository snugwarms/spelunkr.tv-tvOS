import XCTest

final class ViewingRoomTests: XCTestCase {
    func testQuickSettingsDoesNotPausePlayback() throws {
        let app = XCUIApplication()
        app.launch()
        let video = app.otherElements["videoRegion"]
        XCTAssertTrue(video.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: video)
        waitForExpectations(timeout: 60)
        XCUIRemote.shared.press(.home, forDuration: 1.2)
        attach(app, "Playback while Quick Settings is open")
        XCTAssertEqual(video.value as? String, "Playing")
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(video.value as? String, "Playing")
    }

    func testThreeDigitNumbersAndGuideOpeningFocus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lastChannel", "dusty-trails"]
        app.launch()
        let number = app.staticTexts["nowPlayingChannelNumber"]
        expectation(for: NSPredicate(format: "label == %@", "CH 100"), evaluatedWith: number)
        waitForExpectations(timeout: 45)
        let current = app.buttons["channel-dusty-trails"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.hasFocus)
        let digits = current.staticTexts["100"]
        XCTAssertLessThan(digits.frame.height, 40, "Three-digit channel numbers must remain one line")
        attach(app, "Three-digit mini-guide channel")
        XCUIRemote.shared.press(.right)
        let full = app.staticTexts["PROGRAM GUIDE"]
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "CH 100"), evaluatedWith: app.staticTexts["guideSelectedChannel"])
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts["100"].firstMatch.exists)
        attach(app, "Full guide opening on the playing three-digit channel")
    }

    func testReturningToAppResumesLiveAfterPause() throws {
        let app = XCUIApplication()
        app.launch()
        let video = app.otherElements["videoRegion"]
        XCTAssertTrue(video.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: video)
        waitForExpectations(timeout: 60)
        XCUIRemote.shared.press(.playPause)
        expectation(for: NSPredicate(format: "value == %@", "Paused"), evaluatedWith: video)
        waitForExpectations(timeout: 5)
        XCUIRemote.shared.press(.home)
        if !app.wait(for: .runningBackground, timeout: 3), app.state == .runningForeground {
            XCUIApplication(bundleIdentifier: "com.apple.TVSettings").activate()
        }
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.wait(for: .runningBackgroundSuspended, timeout: 5))
        app.activate()
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: video)
        waitForExpectations(timeout: 60)
        app.terminate()
        app.launch()
        expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: video)
        waitForExpectations(timeout: 60)
    }

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
        XCTAssertTrue(text.waitForExistence(timeout: 45), "Speech setup or an availability explanation should appear on the simulator")
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
        XCTAssertEqual(nativePicture.frame.height, app.frame.height * 0.36, accuracy: 2)
        XCTAssertGreaterThan(nativePicture.frame.minX, app.frame.width * 0.60)
        XCTAssertFalse(app.buttons["watchTV"].exists)
        for title in ["Watch TV", "Earlier", "Now", "Later"] { XCTAssertFalse(app.buttons[title].exists) }
        // A single arrow press moves exactly one channel row.
        let selectedChannel = app.staticTexts["guideSelectedChannel"]
        for _ in 0..<45 {
            if selectedChannel.label.contains("CH 02") { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(selectedChannel.label.contains("CH 02"))
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(selectedChannel.label.contains("CH 02"), "Up at the first channel should stay in the grid")
        XCUIRemote.shared.press(.down, forDuration: 0.30)
        XCTAssertTrue(selectedChannel.label.contains("CH 08"))
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(selectedChannel.label.contains("CH 02"))
        let time = app.staticTexts["guideTime-0"]
        let initialTime = time.label
        for _ in 0..<30 {
            if time.label != initialTime { break }
            XCUIRemote.shared.press(.right)
        }
        expectation(for: NSPredicate(format: "label != %@", initialTime), evaluatedWith: time)
        waitForExpectations(timeout: 10)
        for _ in 0..<30 {
            if time.label == initialTime { break }
            XCUIRemote.shared.press(.left)
        }
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
        XCTAssertTrue(app.cells["Volume Leveling"].exists)
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
        let currentNumber = Int(app.staticTexts["nowPlayingChannelNumber"].label.split(separator: " ").last ?? "0") ?? 0
        let targetNumber = targetID == "happy-trees" ? 12 : 13
        let direction: XCUIRemote.Button = targetNumber > currentNumber ? .down : .up
        let target = app.buttons["channel-\(targetID)"]
        for _ in 0..<45 {
            if target.exists && target.hasFocus { break }
            XCUIRemote.shared.press(direction)
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
