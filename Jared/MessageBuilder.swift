//
//  MessageBuilder.swift
//  Jared
//
//  Converts raw chat.db row DTOs into `Message` / `Person` / `Group` entities.
//  Has no SQLite knowledge — contact-name resolution is injected so the builder
//  is unit-testable without the Contacts framework or a live database.
//

import Foundation
import JaredFramework

struct MessageBuilder {
    /// Resolves a handle to a contact's given name. Injectable so tests can avoid
    /// the Contacts XPC service, which hangs in the xctest sandbox.
    let contactNameResolver: (String) -> String?

    init(contactNameResolver: @escaping (String) -> String?) {
        self.contactNameResolver = contactNameResolver
    }

    /// Builds a `Group` from participant rows, or nil when the chat has no rows.
    func buildGroup(chatHandle: String, participantRows: [GroupParticipantRow]) -> Group? {
        guard !participantRows.isEmpty else { return nil }

        let people = participantRows.map { row in
            Person(givenName: contactNameResolver(row.handle), handle: row.handle, isMe: false)
        }
        let groupName = participantRows.compactMap { $0.groupName }.last
        let chatGUID = participantRows.compactMap { $0.chatGUID }.last

        return Group(name: groupName, handle: chatGUID ?? chatHandle, participants: people)
    }

    func buildAttachments(from rows: [AttachmentRow]) -> [Attachment] {
        rows.compactMap { row in
            guard let id = Int(row.rowID) else { return nil }
            return Attachment(id: id, filePath: row.fileName, mimeType: row.mimeType,
                              fileName: row.transferName, isSticker: row.isSticker)
        }
    }

    /// Builds a `Message` from a row whose sender handle, text, and destination have
    /// already been resolved by the caller's inbound policy.
    func buildMessage(from row: MessageRow,
                      senderHandle: String,
                      text: String,
                      destination: String,
                      group: Group?,
                      attachments: [Attachment]) -> Message {
        let cleanDestination = stripMailto(destination)
        let cleanSenderHandle = stripMailto(senderHandle)
        let buddyName = contactNameResolver(cleanSenderHandle)
        let myName = contactNameResolver(cleanDestination)

        let sender: Person
        let recipient: RecipientEntity
        if row.isFromMe {
            sender = Person(givenName: myName, handle: cleanDestination, isMe: true)
            recipient = group ?? Person(givenName: buddyName, handle: cleanSenderHandle, isMe: false)
        } else {
            sender = Person(givenName: buddyName, handle: cleanSenderHandle, isMe: false)
            recipient = group ?? Person(givenName: myName, handle: cleanDestination, isMe: true)
        }

        return Message(body: TextBody(text),
                       date: Date(timeIntervalSince1970: row.epochDate),
                       sender: sender,
                       recipient: recipient,
                       guid: row.guid,
                       attachments: attachments,
                       sendStyle: row.sendStyle,
                       associatedMessageType: Int(row.associatedMessageType),
                       associatedMessageGUID: row.associatedMessageGUID)
    }

    private func stripMailto(_ handle: String) -> String {
        handle.hasPrefix("mailto:") ? String(handle.dropFirst(7)) : handle
    }
}
