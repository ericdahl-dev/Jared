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
    static let removeLikeJSON = "{\"type\":\"like\",\"targetGUID\":\"goodGUID\",\"event\":\"removed\"}"
    static let placeLoveJSON = "{\"type\":\"love\",\"targetGUID\":\"goodGUID\",\"event\":\"placed\"}"
    override func setUp() {
    }
    
    override func tearDown() {
    }
    
    func testFromActionTypeInt() {
        let targetGUID = "goodGUID"
        let encoder = JSONEncoder()
        var action = Action(actionTypeInt: 3001, targetGUID: targetGUID)
        
        XCTAssertEqual(action.event, .removed, "Event marked as removed")
        XCTAssertEqual(action.type, .like, "Type is correct")
        let removeLikeData = try! encoder.encode(action)
        let removeLikeObject = try! JSONSerialization.jsonObject(with: removeLikeData) as! [String: Any]
        let removeLikeExpected = try! JSONSerialization.jsonObject(with: Data(ActionTest.removeLikeJSON.utf8)) as! [String: Any]
        XCTAssertEqual(removeLikeObject as NSDictionary, removeLikeExpected as NSDictionary, "Encoding works as expected")
        
        action = Action(actionTypeInt: 2000, targetGUID: targetGUID)
        
        XCTAssertEqual(action.event, .placed, "Event marked as removed")
        XCTAssertEqual(action.type, .love, "Type is correct")
        let placeLoveData = try! encoder.encode(action)
        let placeLoveObject = try! JSONSerialization.jsonObject(with: placeLoveData) as! [String: Any]
        let placeLoveExpected = try! JSONSerialization.jsonObject(with: Data(ActionTest.placeLoveJSON.utf8)) as! [String: Any]
        XCTAssertEqual(placeLoveObject as NSDictionary, placeLoveExpected as NSDictionary, "Encoding works as expected")
    }
}
