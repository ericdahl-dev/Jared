//
//  DatabaseHandler.swift
//  JaredUI
//
//  Created by Zeke Snider on 11/9/18.
//  Copyright © 2018 Zeke Snider. All rights reserved.
//

internal let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
internal let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

import JaredFramework
import SQLite3

class DatabaseHandler {
    var querySinceID: String?
    var refreshSeconds = 5.0
    var router: RouterDelegate?
    private let reader: ChatDBReader?
    private let builder: MessageBuilder
    private var walSource: DispatchSourceFileSystemObject?
    private var walContinuation: AsyncStream<Void>.Continuation?
    private var backgroundTask: Task<Void, Never>?
    /// Inbound rows deferred once while Messages backfills `handle_id` / handle join.
    private var deferredIncomingRowIDs = Set<String>()

    /// Triggers an immediate poll, bypassing the refresh interval. Used in tests.
    func triggerImmediateQuery() {
        walContinuation?.yield(())
    }

    init(router: RouterDelegate, databaseLocation: URL, diskAccessDelegate: DiskAccessDelegate?, enableBackgroundPolling: Bool = true, contactNameResolver: @escaping (String) -> String? = { ContactHelper.RetreiveContact(handle: $0)?.givenName }) {
        self.router = router
        self.builder = MessageBuilder(contactNameResolver: contactNameResolver)

        guard let reader = ChatDBReader(databaseLocation: databaseLocation) else {
            self.reader = nil
            UserDefaults.standard.set(false, forKey: JaredConstants.fullDiskAccess)
            diskAccessDelegate?.displayAccessError()
            return
        }
        self.reader = reader
        UserDefaults.standard.set(true, forKey: JaredConstants.fullDiskAccess)

        querySinceID = reader.currentMaxRecordID()
        if enableBackgroundPolling {
            start()
            startWALWatcher(databaseLocation: databaseLocation)
        }
    }

    deinit {
        backgroundTask?.cancel()
        walContinuation?.finish()
        walSource?.cancel()
    }

    func start() {
        var cont: AsyncStream<Void>.Continuation?
        let stream = AsyncStream<Void> { cont = $0 }
        walContinuation = cont
        backgroundTask = Task.detached(priority: .background) { [weak self] in
            var walIterator = stream.makeAsyncIterator()
            while !Task.isCancelled {
                let timeoutNs: UInt64
                if let self {
                    _ = self.queryNewRecords()
                    timeoutNs = UInt64(self.refreshSeconds * 1_000_000_000)
                } else {
                    break
                }

                // Wait for WAL change OR timeout, whichever comes first.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try? await Task.sleep(nanoseconds: timeoutNs)
                    }
                    group.addTask {
                        _ = await walIterator.next()
                    }
                    await group.next()
                    group.cancelAll()
                }
            }
        }
    }

    private func startWALWatcher(databaseLocation: URL) {
        let walURL = URL(fileURLWithPath: databaseLocation.path + "-wal")

        if !FileManager.default.fileExists(atPath: walURL.path) {
            NSLog("WAL watcher: %@ missing, falling back to polling", walURL.path)
            return
        }

        let fd = open(walURL.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("WAL watcher: could not open %@, falling back to polling", walURL.path)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in
            self?.walContinuation?.yield(())
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        walSource = source
    }

    @discardableResult
    internal func queryNewRecords() -> Double {
        let start = Date()
        guard let reader = reader else { return 0 }

        for row in reader.fetchNewMessageRows(sinceID: querySinceID) {
            var senderHandleOptional = row.senderHandle

            if !row.isFromMe, senderHandleOptional == nil {
                if row.messageHandleID > 0 {
                    // handle_id points at a missing row — never substitute destination_caller_id.
                    querySinceID = row.rowID
                    continue
                }
                // handle_id still 0: Messages may not have linked the sender yet. Defer one poll
                // so we don't treat a remote message as self-chat (destination_caller_id as sender).
                if let id = row.rowID, !deferredIncomingRowIDs.contains(id) {
                    deferredIncomingRowIDs.insert(id)
                    break
                }
                senderHandleOptional = row.destinationCallerID ?? row.destination
            }

            guard let senderHandle = senderHandleOptional, let text = row.text, let destination = row.destination else {
                querySinceID = row.rowID
                continue
            }

            let group = row.roomName.flatMap { roomName in
                builder.buildGroup(chatHandle: roomName,
                                   participantRows: reader.fetchGroupParticipantRows(chatID: roomName))
            }
            let attachments = row.hasAttachment
                ? builder.buildAttachments(from: reader.fetchAttachmentRows(messageID: row.rowID ?? ""))
                : []

            let message = builder.buildMessage(from: row, senderHandle: senderHandle, text: text,
                                               destination: destination, group: group, attachments: attachments)

            router?.route(message: message)
            querySinceID = row.rowID
            if let rowID = row.rowID {
                deferredIncomingRowIDs.remove(rowID)
            }
        }

        return NSDate().timeIntervalSince(start)
    }
}
