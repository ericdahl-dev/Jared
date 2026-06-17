//
//  CoreModule.swift
//  Jared 3.0 - Swiftified
//
//  Created by Zeke Snider on 4/3/16.
//  Copyright © 2016 Zeke Snider. All rights reserved.
//

import Foundation
import Cocoa
import JaredFramework

class CoreModule: RoutingModule {
    static let MAXIMUM_CONCURRENT_SENDS = 3
    var description: String = NSLocalizedString("CoreDescription")
    var routes: [Route] = []
    var sender: MessageSender
    private let clock: Clock
    private let rateLimiter: SendRateLimiter
    private let contacts: ContactNameService

    required convenience public init(sender: MessageSender) {
        self.init(sender: sender, clock: RealClock(),
                  rateLimiter: SendRateLimiter(max: CoreModule.MAXIMUM_CONCURRENT_SENDS),
                  contacts: CNContactNameService())
    }

    init(sender: MessageSender, clock: Clock = RealClock(),
         rateLimiter: SendRateLimiter = SendRateLimiter(max: CoreModule.MAXIMUM_CONCURRENT_SENDS),
         contacts: ContactNameService = CNContactNameService()) {
        self.sender = sender
        self.clock = clock
        self.rateLimiter = rateLimiter
        self.contacts = contacts

        let ping = Route(name:"/ping", comparisons: [.startsWith: ["/ping"]], call: {[weak self] in self?.pingCall($0)}, description: NSLocalizedString("pingDescription"))
        
        let thankYou = Route(name:"Thank You", comparisons: [.startsWith: [NSLocalizedString("ThanksJaredCommand")]], call: {[weak self] in self?.thanksJared($0)}, description: NSLocalizedString("ThanksJaredResponse"))
        
        let version = Route(name: "/version", comparisons: [.startsWith: ["/version"]], call: {[weak self] in self?.getVersion($0)}, description: "Get the version of Jared running")
        
        let whoami = Route(name: "/whoami", comparisons: [.startsWith: ["/whoami"]], call: {[weak self] in self?.getWho($0)}, description: "Get your name")
        
        let send = Route(name: "/send", comparisons: [.startsWith: ["/send"]], call: {[weak self] in self?.sendRepeat($0)}, description: NSLocalizedString("sendDescription"),parameterSyntax: NSLocalizedString("sendSyntax"))
        
        let name = Route(name: "/name", comparisons: [.startsWith: ["/name"]], call: {[weak self] in self?.changeName($0)}, description: "Change what Jared calls you", parameterSyntax: "/name,[your preferred name]")
        
        
        let barf = Route(name: "/barf", comparisons: [.startsWith: ["/barf"]], call: {[weak self] in self?.barf($0)}, description: NSLocalizedString("barfDescription"))
        
        routes = [ping, thankYou, version, send, whoami, name, barf]
        
    }
    
    
    
    func pingCall(_ incoming: Message) -> Void {
        sender.send(NSLocalizedString("PongResponse"), to: incoming.RespondTo())
    }
    
    func barf(_ incoming: Message) -> Void {
        let encoded = (try? JSONEncoder().encode(incoming)).flatMap { String(data: $0, encoding: .utf8) }
        sender.send(encoded ?? "nil", to: incoming.RespondTo())
    }
    
    func getWho(_ message: Message) -> Void {
        if message.sender.givenName != nil {
            sender.send("Your name is \(message.sender.givenName!).", to: message.RespondTo())
        }
        else {
            sender.send("I don't know your name.", to: message.RespondTo())
        }
    }
    
    func thanksJared(_ message: Message) -> Void {
        sender.send(NSLocalizedString("WelcomeResponse"), to: message.RespondTo())
    }
    
    func getVersion(_ message: Message) -> Void {
        sender.send(NSLocalizedString("versionResponse"), to: message.RespondTo())
    }
    
    func sendRepeat(_ message: Message) -> Void {
        guard let parameters = message.getTextParameters() else {
            return sender.send("Inappropriate input type.", to: message.RespondTo())
        }
        
        //Validating and parsing arguments
        guard let repeatNum: Int = Int(parameters[1]) else {
            return sender.send("Wrong argument. The first argument must be the number of message you wish to send", to: message.RespondTo())
        }
        
        guard let delay = Int(parameters[2]) else {
            return sender.send("Wrong argument. The second argument must be the delay of the messages you wish to send", to: message.RespondTo())
        }
        
        guard var textToSend = parameters[safe: 3] else {
            return sender.send("Wrong arguments. The third argument must be the message you wish to send.", to: message.RespondTo())
        }
        
        guard rateLimiter.tryAcquire(message.sender.handle) else {
            return sender.send("You can only have \(CoreModule.MAXIMUM_CONCURRENT_SENDS) send operations going at once.", to: message.RespondTo())
        }

        //If there are commas in the message, take the whole message
        if parameters.count > 4 {
            textToSend = parameters[3...(parameters.count - 1)].joined(separator: ",")
        }

        let finalText = textToSend
        Task { [weak self] in
            await self?.performSend(message, text: finalText, times: repeatNum, delay: delay)
        }
    }

    /// Sends `text` to the message's responder `times` times, pausing `delay`
    /// seconds between sends, then releases the rate-limiter slot. Extracted so
    /// the send loop is awaitable/testable with an injected `Clock`.
    func performSend(_ message: Message, text: String, times: Int, delay: Int = 0) async {
        for _ in 1...times {
            sender.send(text, to: message.RespondTo())
            await clock.sleep(seconds: delay)
        }
        rateLimiter.release(message.sender.handle)
    }
    


    func changeName(_ message: Message) {
        guard let parsedMessage = message.getTextParameters() else {
            return sender.send("Inappropriate input type", to: message.RespondTo())
        }

        guard parsedMessage.count > 1 else {
            return sender.send("Wrong arguments.", to: message.RespondTo())
        }

        guard contacts.isAuthorized else {
            return sender.send("Sorry, I do not have access to contacts.", to: message.RespondTo())
        }

        do {
            try contacts.setGivenName(parsedMessage[1], forHandle: message.sender.handle)
            sender.send("Ok, I'll call you \(parsedMessage[1]) from now on.", to: message.RespondTo())
        } catch {
            sender.send("There was an error saving your contact..", to: message.RespondTo())
        }
    }
    




}
