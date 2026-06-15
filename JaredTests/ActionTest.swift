//
//  MessageTests.swift
//  JaredTests
//
//  Created by Zeke Snider on 2/3/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import XCTest
import JaredFramework

class ActionTest: XCTestCase {
    override func setUp() {}
    override func tearDown() {}

    func testFromActionTypeInt() {
        let targetGUID = "goodGUID"
        let encoder = JSONEncoder()
        var action = Action(actionTypeInt: 3001, targetGUID: targetGUID)

        XCTAssertEqual(action.event, .removed, "Event marked as removed")
        XCTAssertEqual(action.type, .like, "Type is correct")
        let removeLikeData = try! encoder.encode(action)
        let removeLikeDict = try! JSONSerialization.jsonObject(with: removeLikeData) as! [String: String]
        XCTAssertEqual(removeLikeDict["type"], "like", "Encoding round-trips type")
        XCTAssertEqual(removeLikeDict["event"], "removed", "Encoding round-trips event")
        XCTAssertEqual(removeLikeDict["targetGUID"], targetGUID, "Encoding round-trips targetGUID")

        action = Action(actionTypeInt: 2000, targetGUID: targetGUID)

        XCTAssertEqual(action.event, .placed, "Event marked as placed")
        XCTAssertEqual(action.type, .love, "Type is correct")
        let placeLoveData = try! encoder.encode(action)
        let placeLoveDict = try! JSONSerialization.jsonObject(with: placeLoveData) as! [String: String]
        XCTAssertEqual(placeLoveDict["type"], "love", "Encoding round-trips type")
        XCTAssertEqual(placeLoveDict["event"], "placed", "Encoding round-trips event")
        XCTAssertEqual(placeLoveDict["targetGUID"], targetGUID, "Encoding round-trips targetGUID")
    }
}
