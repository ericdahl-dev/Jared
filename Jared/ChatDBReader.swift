//
//  ChatDBReader.swift
//  Jared
//
//  SQLite access layer for the Messages chat.db. Owns the read-only database
//  handle and the SQL queries, returning plain row DTOs with no knowledge of
//  `Message`, routing, or contact resolution.
//

import Foundation
import SQLite3

// MARK: - Row DTOs

/// One row from the new-message query. `text` is already resolved from either the
/// `text` column or the Ventura-era `attributedBody` blob.
struct MessageRow {
    let senderHandle: String?
    let text: String?
    let rowID: String?
    let roomName: String?
    let isFromMe: Bool
    let destination: String?
    let epochDate: TimeInterval
    let hasAttachment: Bool
    let sendStyle: String?
    let associatedMessageType: Int32
    let associatedMessageGUID: String?
    let guid: String?
    let destinationCallerID: String?
    let messageHandleID: Int32
}

/// One participant row for a group chat lookup.
struct GroupParticipantRow {
    let handle: String
    let groupName: String?
    let chatGUID: String?
}

struct AttachmentRow {
    let rowID: String
    let fileName: String
    let mimeType: String
    let transferName: String
    let isSticker: Bool
}

// MARK: - Reader

class ChatDBReader {
    private static let groupQuery = """
		SELECT handle.id, display_name, chat.guid
			FROM chat_handle_join INNER JOIN handle ON chat_handle_join.handle_id = handle.ROWID
			INNER JOIN chat ON chat_handle_join.chat_id = chat.ROWID
			WHERE chat.chat_identifier = ?
	"""
    private static let attachmentQuery = """
	SELECT ROWID,
	filename,
	mime_type,
	transfer_name,
	is_sticker
	FROM attachment
	INNER JOIN message_attachment_join
	ON attachment.ROWID = message_attachment_join.attachment_id
	WHERE message_id = ?
	"""
    private static let newRecordquery = """
		SELECT handle.id, message.text, message.ROWID, message.cache_roomnames, message.is_from_me, message.destination_caller_id,
			message.date/1000000000 + strftime("%s", "2001-01-01"),
			message.cache_has_attachments,
			message.expressive_send_style_id,
			message.associated_message_type,
			message.associated_message_guid, message.guid, destination_caller_id,
			message.handle_id, message.attributedBody
			FROM message LEFT JOIN handle
			ON message.handle_id = handle.ROWID
			WHERE message.ROWID > ? ORDER BY message.ROWID ASC
	"""
    private static let maxRecordIDQuery = "SELECT MAX(rowID) FROM message"

    private var db: OpaquePointer?

    /// Opens the chat database read-only. Returns nil if the database cannot be
    /// opened (e.g. missing Full Disk Access).
    init?(databaseLocation: URL) {
        if sqlite3_open_v2(databaseLocation.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let errorMessage = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            NSLog("Error opening SQLite database at %@: %@", databaseLocation.path, errorMessage)
            if let db = db { sqlite3_close(db) }
            db = nil
            return nil
        }
    }

    deinit {
        if let db = db, sqlite3_close(db) != SQLITE_OK {
            print("error closing database")
        }
        db = nil
    }

    // MARK: - Queries

    func currentMaxRecordID() -> String {
        var id: String?
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, ChatDBReader.maxRecordIDQuery, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("error preparing select: \(errmsg)")
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idcString = sqlite3_column_text(statement, 0) else {
                break
            }
            id = String(cString: idcString)
        }

        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("error finalizing prepared statement: \(errmsg)")
        }

        return id ?? "0"
    }

    func fetchNewMessageRows(sinceID: String?) -> [MessageRow] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        if sqlite3_prepare_v2(db, ChatDBReader.newRecordquery, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("error preparing select: \(errmsg)")
        }

        if sqlite3_bind_text(statement, 1, sinceID ?? "1000000000", -1, SQLITE_TRANSIENT) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("failure binding: \(errmsg)")
        }

        var rows = [MessageRow]()
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawText = unwrapStringColumn(for: statement, at: 1)
            let text = (rawText?.isEmpty == false ? rawText : nil) ?? extractAttributedBodyText(for: statement, at: 14)
            rows.append(MessageRow(
                senderHandle: unwrapStringColumn(for: statement, at: 0),
                text: text,
                rowID: unwrapStringColumn(for: statement, at: 2),
                roomName: unwrapStringColumn(for: statement, at: 3),
                isFromMe: sqlite3_column_int(statement, 4) == 1,
                destination: unwrapStringColumn(for: statement, at: 5),
                epochDate: TimeInterval(sqlite3_column_int64(statement, 6)),
                hasAttachment: sqlite3_column_int(statement, 7) == 1,
                sendStyle: unwrapStringColumn(for: statement, at: 8),
                associatedMessageType: sqlite3_column_int(statement, 9),
                associatedMessageGUID: unwrapStringColumn(for: statement, at: 10),
                guid: unwrapStringColumn(for: statement, at: 11),
                destinationCallerID: unwrapStringColumn(for: statement, at: 12),
                messageHandleID: sqlite3_column_int(statement, 13)
            ))
        }
        return rows
    }

    func fetchGroupParticipantRows(chatID: String) -> [GroupParticipantRow] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        if sqlite3_prepare_v2(db, ChatDBReader.groupQuery, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("error preparing select: \(errmsg)")
        }

        if sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("failure binding foo: \(errmsg)")
        }

        var rows = [GroupParticipantRow]()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idcString = sqlite3_column_text(statement, 0) else {
                break
            }
            rows.append(GroupParticipantRow(
                handle: String(cString: idcString),
                groupName: unwrapStringColumn(for: statement, at: 1),
                chatGUID: unwrapStringColumn(for: statement, at: 2)
            ))
        }
        return rows
    }

    func fetchAttachmentRows(messageID: String) -> [AttachmentRow] {
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, ChatDBReader.attachmentQuery, -1, &statement, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("error preparing select: \(errmsg)")
        }

        if sqlite3_bind_text(statement, 1, messageID, -1, SQLITE_TRANSIENT) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("failure binding: \(errmsg)")
        }

        var rows = [AttachmentRow]()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rowID = unwrapStringColumn(for: statement, at: 0) else { continue }
            guard let fileName = unwrapStringColumn(for: statement, at: 1) else { continue }
            guard let mimeType = unwrapStringColumn(for: statement, at: 2) else { continue }
            guard let transferName = unwrapStringColumn(for: statement, at: 3) else { continue }
            let isSticker = sqlite3_column_int(statement, 4) == 1
            rows.append(AttachmentRow(rowID: rowID, fileName: fileName, mimeType: mimeType,
                                      transferName: transferName, isSticker: isSticker))
        }

        if sqlite3_finalize(statement) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            print("error finalizing prepared statement: \(errmsg)")
        }

        return rows
    }

    // MARK: - Column helpers

    private func unwrapStringColumn(for sqlStatement: OpaquePointer?, at column: Int32) -> String? {
        if let cString = sqlite3_column_text(sqlStatement, column) {
            return String(cString: cString)
        } else {
            return nil
        }
    }

    /// Decodes the NSAttributedString blob in `attributedBody` to extract plain text.
    /// Apple moved message text from the `text` column to `attributedBody` in macOS Ventura/Sonoma.
    private func extractAttributedBodyText(for sqlStatement: OpaquePointer?, at column: Int32) -> String? {
        let byteCount = sqlite3_column_bytes(sqlStatement, column)
        guard byteCount > 0, let bytes = sqlite3_column_blob(sqlStatement, column) else {
            return nil
        }
        let data = Data(bytes: bytes, count: Int(byteCount))
        let obj: Any? = NSUnarchiver.unarchiveObject(with: data)
            ?? (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data))
        guard let attributed = obj as? NSAttributedString else { return nil }
        let text = attributed.string
        return text.isEmpty ? nil : text
    }
}
