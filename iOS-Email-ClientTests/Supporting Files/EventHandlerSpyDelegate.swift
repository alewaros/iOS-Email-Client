//
//  EventHandlerSpyDelegate.swift
//  iOS-Email-ClientTests
//
//  Created by Pedro Aim on 6/5/18.
//  Copyright © 2018 Criptext Inc. All rights reserved.
//

import XCTest
import Foundation
@testable import iOS_Email_Client

class EventHandlerSpyDelegate: EventHandlerDelegate {
    
    var expectation: XCTestExpectation?
    var delegateEmails: [Email]?
    var delegateOpens: [FeedItem]?
    
    func didReceiveEvents(result: EventData.Result) {
        guard let expect = expectation else {
            XCTFail("Unable to parse opens")
            return
        }
        delegateOpens = result.opens
        delegateEmails = result.emails
        expect.fulfill()
    }
}
