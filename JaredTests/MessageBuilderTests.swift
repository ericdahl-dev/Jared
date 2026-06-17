//
//  MessageBuilderTests.swift
//  JaredTests
//
//  Unit tests for MessageBuilder in isolation — pure DTO → entity conversion,
//  no SQLite or Contacts dependency.
//

import XCTest
@testable import Jared
import JaredFramework

class MessageBuilderTests: XCTestCase {

    private func makeRow(
        senderHandle: String? = "+15551234567",
        text: String? = "hello",
        rowID: String? = "42",
        roomName: String? = nil,
        isFromMe: Bool = false,
        destination: String? = "+15559998888",
        epochDate: TimeInterval = 1_495_061_841,
        hasAttachment: Bool = false,
        sendStyle: String? = nil,
        associatedMessageType: Int32 = 0,
        associatedMessageGUID: String? = nil,
        guid: String? = "msg-guid",
        destinationCallerID: String? = "+15559998888",
        messageHandleID: Int32 = 1
    ) -> MessageRow {
        MessageRow(senderHandle: senderHandle, text: text, rowID: rowID, roomName: roomName,
                   isFromMe: isFromMe, destination: destination, epochDate: epochDate,
                   hasAttachment: hasAttachment, sendStyle: sendStyle,
                   associatedMessageType: associatedMessageType, associatedMessageGUID: associatedMessageGUID,
                   guid: guid, destinationCallerID: destinationCallerID, messageHandleID: messageHandleID)
    }

    private func builder(resolver: @escaping (String) -> String? = { _ in nil }) -> MessageBuilder {
        MessageBuilder(contactNameResolver: resolver)
    }

    // MARK: - buildMessage

    func testIncomingMessageSenderIsRemoteRecipientIsMe() {
        let row = makeRow(senderHandle: "+15551234567", isFromMe: false, destination: "+15559998888")
        let message = builder().buildMessage(from: row, senderHandle: "+15551234567",
                                             text: "hi", destination: "+15559998888",
                                             group: nil, attachments: [])

        let sender = message.sender as? Person
        let recipient = message.recipient as? Person
        XCTAssertEqual(sender?.handle, "+15551234567")
        XCTAssertEqual(sender?.isMe, false)
        XCTAssertEqual(recipient?.handle, "+15559998888")
        XCTAssertEqual(recipient?.isMe, true)
    }

    func testOutgoingMessageSenderIsMeRecipientIsRemote() {
        let row = makeRow(isFromMe: true)
        let message = builder().buildMessage(from: row, senderHandle: "+15551234567",
                                             text: "hi", destination: "+15559998888",
                                             group: nil, attachments: [])

        let sender = message.sender as? Person
        let recipient = message.recipient as? Person
        XCTAssertEqual(sender?.handle, "+15559998888")
        XCTAssertEqual(sender?.isMe, true)
        XCTAssertEqual(recipient?.handle, "+15551234567")
        XCTAssertEqual(recipient?.isMe, false)
    }

    func testMailtoPrefixIsStrippedFromHandles() {
        let row = makeRow(isFromMe: false)
        let message = builder().buildMessage(from: row, senderHandle: "mailto:zeke@example.com",
                                             text: "hi", destination: "mailto:me@example.com",
                                             group: nil, attachments: [])

        let sender = message.sender as? Person
        let recipient = message.recipient as? Person
        XCTAssertEqual(sender?.handle, "zeke@example.com")
        XCTAssertEqual(recipient?.handle, "me@example.com")
    }

    func testGroupBecomesRecipientForIncomingMessage() {
        let group = Group(name: "Squad", handle: "iMessage;+;chat123",
                          participants: [Person(givenName: nil, handle: "+15551234567", isMe: false)])
        let row = makeRow(roomName: "chat123", isFromMe: false)
        let message = builder().buildMessage(from: row, senderHandle: "+15551234567",
                                             text: "hi", destination: "+15559998888",
                                             group: group, attachments: [])

        XCTAssertEqual((message.recipient as? Group)?.handle, "iMessage;+;chat123")
    }

    func testContactNameResolverPopulatesGivenName() {
        let resolver: (String) -> String? = { $0 == "+15551234567" ? "Zeke" : nil }
        let row = makeRow(isFromMe: false)
        let message = builder(resolver: resolver).buildMessage(from: row, senderHandle: "+15551234567",
                                                               text: "hi", destination: "+15559998888",
                                                               group: nil, attachments: [])

        XCTAssertEqual((message.sender as? Person)?.givenName, "Zeke")
    }

    func testMessageCarriesBodyDateAndGuid() {
        let row = makeRow(epochDate: 1_495_061_841, guid: "abc-123")
        let message = builder().buildMessage(from: row, senderHandle: "+15551234567",
                                             text: "expressive!", destination: "+15559998888",
                                             group: nil, attachments: [])

        XCTAssertEqual((message.body as? TextBody)?.message, "expressive!")
        XCTAssertEqual(message.guid, "abc-123")
        XCTAssertEqual(message.date, Date(timeIntervalSince1970: 1_495_061_841))
    }

    // MARK: - buildGroup

    func testBuildGroupReturnsNilForEmptyRows() {
        XCTAssertNil(builder().buildGroup(chatHandle: "chat123", participantRows: []))
    }

    func testBuildGroupUsesChatGUIDWhenPresent() {
        let rows = [
            GroupParticipantRow(handle: "+15551234567", groupName: "Squad", chatGUID: "iMessage;+;guid"),
            GroupParticipantRow(handle: "+15559998888", groupName: "Squad", chatGUID: "iMessage;+;guid"),
        ]
        let group = builder().buildGroup(chatHandle: "fallback", participantRows: rows)
        XCTAssertEqual(group?.handle, "iMessage;+;guid")
        XCTAssertEqual(group?.name, "Squad")
        XCTAssertEqual(group?.participants.count, 2)
    }

    func testBuildGroupFallsBackToChatHandleWhenGUIDMissing() {
        let rows = [GroupParticipantRow(handle: "+15551234567", groupName: nil, chatGUID: nil)]
        let group = builder().buildGroup(chatHandle: "fallback-handle", participantRows: rows)
        XCTAssertEqual(group?.handle, "fallback-handle")
        XCTAssertNil(group?.name)
    }

    // MARK: - buildAttachments

    func testBuildAttachmentsMapsRows() {
        let rows = [
            AttachmentRow(rowID: "7", fileName: "~/img.jpg", mimeType: "image/jpeg",
                          transferName: "img.jpg", isSticker: false),
        ]
        let attachments = builder().buildAttachments(from: rows)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.id, 7)
        XCTAssertEqual(attachments.first?.mimeType, "image/jpeg")
        XCTAssertEqual(attachments.first?.isSticker, false)
    }

    func testBuildAttachmentsSkipsNonNumericRowID() {
        let rows = [
            AttachmentRow(rowID: "not-a-number", fileName: "f", mimeType: "m",
                          transferName: "t", isSticker: false),
        ]
        XCTAssertEqual(builder().buildAttachments(from: rows).count, 0)
    }
}
