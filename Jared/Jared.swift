//
//  Jared.swift
//  JaredFramework
//
//  Created by Zeke Snider on 2/3/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

/// Actor-isolated send queue — enforces serial execution without OperationQueue.
private actor SendQueue {
    func enqueue(_ work: @escaping () -> Void) {
        work()
    }
}

public class Jared: MessageSender {
    private let sendQueue = SendQueue()
    private let flags: RuntimeFlags

    init(flags: RuntimeFlags = UserDefaultsRuntimeFlags()) {
        self.flags = flags
    }
    
    public func send(_ body: String, to recipient: RecipientEntity?) {
        guard var recipient = recipient else {
            return
        }
        if let abstract = recipient as? AbstractRecipient {
            recipient = abstract.getSpecificEntity()
        }
        
        let me = Person(givenName: nil, handle: "", isMe: true)
        let message = Message(body: TextBody(body), date: Date(), sender: me, recipient: recipient, attachments: [])
        send(message)
    }
    
    public func send(_ message: Message) {
        NSLog("Attemping to send message: \(message)")
        
        //Don't send the message if Jared is currently disabled.
        guard !flags.isDisabled else {
            return
        }
        
        let recipient = message.recipient.handle
        
        if let textBody = message.body as? TextBody {
            var scriptPath: String?
            let body = textBody.message
            
            if message.recipient.isGroupHandle() {
                scriptPath = Bundle.main.url(forResource: "SendText", withExtension: "scpt")?.path
            } else {
                scriptPath = Bundle.main.url(forResource: "SendTextSingleBuddy", withExtension: "scpt")?.path
            }
            
            Task {
                await sendQueue.enqueue {
                    self.executeScript(scriptPath: scriptPath, body: body, recipient: recipient)
                }
            }
        }
        
        if let attachments = message.attachments {
            var scriptPath: String?
            
            if message.recipient.isGroupHandle() {
                scriptPath = Bundle.main.url(forResource: "SendImage", withExtension: "scpt")?.path
            } else {
                scriptPath = Bundle.main.url(forResource: "SendImageSingleBuddy", withExtension: "scpt")?.path
            }
            
            attachments.forEach { attachment in
                let filePath = attachment.filePath
                Task {
                    await sendQueue.enqueue {
                        self.executeScript(scriptPath: scriptPath, body: filePath, recipient: recipient)
                    }
                }
            }
        }
    }
    
    private func executeScript(scriptPath: String?, body: String?, recipient: String?) {
        guard(scriptPath != nil && body != nil && recipient != nil) else {
            return
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptPath!, body!, recipient!]
        task.launch()
        task.waitUntilExit()
    }
}
