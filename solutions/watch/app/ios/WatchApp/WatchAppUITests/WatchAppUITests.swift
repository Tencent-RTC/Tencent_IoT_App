import XCTest

final class WatchAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
    }

    func testLoginAndNavigateAcrossTabs() throws {
        loginIfNeeded()

        for identifier in ["tab.messages", "tab.location", "tab.devices", "tab.profile", "tab.call"] {
            XCTAssertTrue(element(identifier).waitForExistence(timeout: 10), "missing accessibility identifier: \(identifier)")
        }

        element("tab.location").tap()
        XCTAssertTrue(element("page.location").waitForExistence(timeout: 2), app.debugDescription)
        element("tab.devices").tap()
        XCTAssertTrue(element("page.devices").waitForExistence(timeout: 2), app.debugDescription)
        element("tab.profile").tap()
        XCTAssertTrue(element("page.profile").waitForExistence(timeout: 2), app.debugDescription)
        element("tab.messages").tap()
        XCTAssertTrue(element("page.messages").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(element("message.add").waitForExistence(timeout: 5))
    }

    func testBindWatchAndOpenConversation() throws {
        loginIfNeeded()
        element("message.add").tap()
        XCTAssertTrue(element("add.watch").waitForExistence(timeout: 5))
        element("add.watch").tap()

        let deviceField = element("watch.deviceName")
        XCTAssertTrue(deviceField.waitForExistence(timeout: 5), app.debugDescription)
        deviceField.tap()
        deviceField.typeText("lele")
        deviceField.typeText("\n")

        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("chat.send").exists)
    }

    func testMessageListOpensBoundConversationAfterReturning() throws {
        loginIfNeeded()
        if !element("message.conversation.lele").waitForExistence(timeout: 2) {
            element("message.add").tap()
            XCTAssertTrue(element("add.watch").waitForExistence(timeout: 5))
            element("add.watch").tap()

            let deviceField = element("watch.deviceName")
            XCTAssertTrue(deviceField.waitForExistence(timeout: 5), app.debugDescription)
            deviceField.tap()
            deviceField.typeText("lele")
            deviceField.typeText("\n")
            XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10), app.debugDescription)
            element("chat.back").tap()
        }

        let conversation = element("message.conversation.lele")
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), app.debugDescription)
        conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10), app.debugDescription)
        let back = element("chat.back")
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), app.debugDescription)
        conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testChatInfoBackAndMemberAddEntry() throws {
        loginIfNeeded()
        let conversation = element("message.conversation.lele")
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), app.debugDescription)
        conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10), app.debugDescription)

        element("chat.info").tap()
        XCTAssertTrue(element("chat.info.back").waitForExistence(timeout: 10), app.debugDescription)
        let addMember = element("chat.member.add")
        XCTAssertTrue(addMember.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(addMember.frame.width, 56, accuracy: 1, app.debugDescription)
        XCTAssertEqual(addMember.frame.height, 56, accuracy: 1, app.debugDescription)
        addMember.tap()
        XCTAssertTrue(element("group.back").waitForExistence(timeout: 10), app.debugDescription)
        element("group.back").tap()
        XCTAssertTrue(element("chat.info.back").waitForExistence(timeout: 10), app.debugDescription)
        element("chat.info.back").tap()
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testAddAndBindBackButtonsRespond() throws {
        loginIfNeeded()
        element("message.add").tap()
        XCTAssertTrue(element("add.back").waitForExistence(timeout: 5))
        element("add.back").tap()
        XCTAssertTrue(element("message.add").waitForExistence(timeout: 5))

        element("message.add").tap()
        element("add.watch").tap()
        XCTAssertTrue(element("watch.bind.back").waitForExistence(timeout: 5))
        element("watch.bind.back").tap()
        XCTAssertTrue(element("add.watch").waitForExistence(timeout: 5))
    }

    func testCallPickerExposesBoundWatchAndMediaModes() throws {
        loginIfNeeded()
        element("tab.call").tap()

        XCTAssertTrue(element("call.cancel").waitForExistence(timeout: 5))
        XCTAssertTrue(element("call.video").exists)
        XCTAssertTrue(element("call.voice").exists)
        element("call.cancel").tap()
    }

    func testMultipleBoundWatchesCanSelectCallTarget() throws {
        loginIfNeeded()
        bindWatchIfNeeded("lele")
        bindWatchIfNeeded("xiaoya")

        element("tab.devices").tap()
        let deviceCard = element("device.card.lele")
        let devicePager = element("device.page.1")
        XCTAssertTrue(deviceCard.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(devicePager.exists)
        XCTAssertLessThanOrEqual(devicePager.frame.minY - deviceCard.frame.maxY, 1, app.debugDescription)
        element("tab.location").tap()
        let locationCard = element("location.card.lele")
        let locationPager = element("location.page.1")
        XCTAssertTrue(locationCard.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(locationPager.exists)
        XCTAssertLessThanOrEqual(locationPager.frame.minY - locationCard.frame.maxY, 5, app.debugDescription)

        element("tab.call").tap()
        let lele = element("call.target.lele")
        let xiaoya = element("call.target.xiaoya")
        XCTAssertTrue(lele.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(xiaoya.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(lele.value as? String, "已选中")
        xiaoya.tap()
        XCTAssertEqual(xiaoya.value as? String, "已选中", app.debugDescription)
        XCTAssertNotEqual(lele.value as? String, "已选中")
        element("call.cancel").tap()
    }

    func testRealVideoCallControlsWithOnlinePeer() throws {
        try requireRealCallEnvironment()
        loginIfNeeded()
        ensureBoundWatchIfNeeded()
        element("tab.call").tap()
        XCTAssertTrue(element("call.target.lele").waitForExistence(timeout: 5))
        element("call.video").tap()
        XCTAssertTrue(element("call.hangup").waitForExistence(timeout: 15))
        XCTAssertTrue(element("call.status").exists)
        element("call.hangup").tap()
    }

    func testRealVoiceCallControlsWithOnlinePeer() throws {
        try requireRealCallEnvironment()
        loginIfNeeded()
        ensureBoundWatchIfNeeded()
        element("tab.call").tap()
        XCTAssertTrue(element("call.target.lele").waitForExistence(timeout: 5))
        element("call.voice").tap()
        XCTAssertTrue(element("call.hangup").waitForExistence(timeout: 15))
        XCTAssertTrue(element("call.status").exists)
        element("call.hangup").tap()
    }

    func testRealC2CMessageWithBoundWatch() throws {
        guard ProcessInfo.processInfo.environment["WATCH_E2E_REAL_IM"] == "1" else {
            throw XCTSkip("需要设置 WATCH_E2E_REAL_IM=1，并准备在线手表 lele")
        }
        loginIfNeeded()
        ensureBoundWatchIfNeeded()
        XCTAssertTrue(element("message.conversation.lele").waitForExistence(timeout: 10))
        element("message.conversation.lele").tap()

        let message = "ios_real_\(Int(Date().timeIntervalSince1970))"
        let input = app.textViews["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(message)
        if app.keyboards.element.exists {
            app.keyboards.element.swipeDown()
        }
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testIncomingCallControlsWithOnlinePeer() throws {
        try requireRealCallEnvironment()
        throw XCTSkip("来电 UI 需要在线手表实际发送 call 信令；测试 Runner 不注入伪造信令")
    }

    private func loginIfNeeded() {
        let loginButton = app.buttons["login.submit"]
        if loginButton.waitForExistence(timeout: 8) {
            XCTAssertTrue(app.textFields["login.room"].exists)
            loginButton.tap()
        }
        XCTAssertTrue(element("tab.messages").waitForExistence(timeout: 30), "login did not reach the main tab")
    }

    private func requireRealCallEnvironment() throws {
        guard ProcessInfo.processInfo.environment["WATCH_E2E_REAL_CALL"] == "1" else {
            throw XCTSkip("需要设置 WATCH_E2E_REAL_CALL=1，并准备在线手表 lele 或第二终端")
        }
    }

    private func ensureBoundWatchIfNeeded() {
        element("tab.call").tap()
        if element("call.target.lele").waitForExistence(timeout: 2) {
            element("call.cancel").tap()
            return
        }
        element("call.cancel").tap()
        element("message.add").tap()
        element("add.watch").tap()
        let deviceField = element("watch.deviceName")
        XCTAssertTrue(deviceField.waitForExistence(timeout: 5))
        deviceField.tap()
        deviceField.typeText("lele")
        deviceField.typeText("\n")
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10))
        element("chat.back").tap()
    }

    private func bindWatchIfNeeded(_ deviceName: String) {
        element("tab.call").tap()
        if element("call.target.\(deviceName)").waitForExistence(timeout: 2) {
            element("call.cancel").tap()
            return
        }
        element("call.cancel").tap()
        element("message.add").tap()
        element("add.watch").tap()
        let deviceField = element("watch.deviceName")
        XCTAssertTrue(deviceField.waitForExistence(timeout: 5), app.debugDescription)
        deviceField.tap()
        deviceField.typeText(deviceName)
        deviceField.typeText("\n")
        XCTAssertTrue(app.textViews["chat.input"].waitForExistence(timeout: 10), app.debugDescription)
        element("chat.back").tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
