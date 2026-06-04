//
//  ScheduleModule.swift
//  Jared
//

import Foundation
import CoreData
import JaredFramework

enum IntervalType: String {
    case Minute
    case Hour
    case Day
    case Week
    case Month
}

let intervalSeconds: [IntervalType: Double] =
    [
        .Minute: 60.0,
        .Hour: 3600.0,
        .Day: 86400.0,
        .Week: 604800.0,
        .Month: 2592000.0
    ]

class ScheduleModule: RoutingModule {
    var description: String = "Scheduled message management"
    var routes: [Route] = []
    var sender: MessageSender

    let MAXIMUM_CONCURRENT_SENDS = 3
    var currentSends: [String: Int] = [:]
    let scheduleCheckInterval = 30.0 * 60.0
    var timer: Timer?

    var persistentContainer: PersistentContainer

    required convenience init(sender: MessageSender) {
        let container = PersistentContainer(name: "CoreModule")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        self.init(sender: sender, persistentContainer: container)
    }

    init(sender: MessageSender, persistentContainer: PersistentContainer) {
        self.sender = sender
        self.persistentContainer = persistentContainer

        let appsupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jared")
            .appendingPathComponent("CoreModule")
        try? FileManager.default.createDirectory(at: appsupport, withIntermediateDirectories: true, attributes: nil)

        let schedule = Route(
            name: "/schedule",
            comparisons: [.startsWith: ["/schedule"]],
            call: { [weak self] in self?.schedule($0) },
            description: NSLocalizedString("scheduleDescription"),
            parameterSyntax: "Must be one of these type of inputs: /schedule,add,1,Week,5,full Message\n/schedule,delete,1\n/schedule,list"
        )

        routes = [schedule]

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.scheduleThread()
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Route handler

    func schedule(_ message: Message) {
        guard let parameters = message.getTextBody()?.components(separatedBy: ",") else {
            return sender.send("Inappropriate input type", to: message.RespondTo())
        }
        guard parameters.count > 1 else {
            return sender.send("More parameters required.", to: message.RespondTo())
        }

        switch parameters[1] {
        case "add":
            guard parameters.count > 5 else {
                return sender.send("Incorrect number of parameters specified.", to: message.RespondTo())
            }
            guard let sendIntervalNumber = Int(parameters[2]) else {
                return sender.send("Send interval number must be an integer.", to: message.RespondTo())
            }
            guard let sendIntervalType = IntervalType(rawValue: parameters[3]) else {
                return sender.send("Send interval type must be a valid input (hour, day, week, month).", to: message.RespondTo())
            }
            guard let sendTimes = Int(parameters[4]) else {
                return sender.send("Send times must be an integer.", to: message.RespondTo())
            }
            let sendMessage = parameters[5]
            guard let respondToHandle = message.RespondTo()?.handle else { return }

            let post = NSEntityDescription.insertNewObject(forEntityName: "SchedulePost", into: persistentContainer.viewContext) as! SchedulePost
            post.sendIntervalNumber = Int64(sendIntervalNumber)
            post.sendNumberTimes = Int64(sendTimes)
            post.sendIntervalType = sendIntervalType.rawValue
            post.currentSendCount = 0
            post.text = sendMessage
            post.handle = respondToHandle
            post.startDate = Date()
            post.sendNext = getNextSendTime(number: sendIntervalNumber, type: sendIntervalType)

            persistentContainer.saveContext()
            sender.send("Your post has been succesfully scheduled.", to: message.RespondTo())

        case "delete":
            guard let respondHandle = message.RespondTo()?.handle else { return }
            guard parameters.count > 2 else {
                return sender.send("The second parameter must be a valid id.", to: message.RespondTo())
            }
            guard let deleteID = Int(parameters[2]) else {
                return sender.send("The delete ID must be an integer.", to: message.RespondTo())
            }
            guard deleteID > 0 else {
                return sender.send("The delete ID must be an positive integer.", to: message.RespondTo())
            }
            let posts = getPosts(for: respondHandle)
            guard posts.count >= deleteID else {
                return sender.send("The specified post ID is not valid.", to: message.RespondTo())
            }
            persistentContainer.viewContext.delete(posts[deleteID - 1])
            persistentContainer.saveContext()
            sender.send("The specified scheduled post has been deleted.", to: message.RespondTo())

        case "list":
            guard let respondHandle = message.RespondTo()?.handle else { return }
            let posts = getPosts(for: respondHandle)
            var sendMessage = "\(message.sender.givenName ?? "Hello"), you have \(posts.count) posts scheduled."
            for (index, post) in posts.enumerated() {
                sendMessage += "\n\(index + 1): Send a message every \(post.sendIntervalNumber) \(post.sendIntervalType!)(s) \(post.sendNumberTimes) time(s), starting on \(post.startDate!.description(with: Locale.current))."
            }
            sender.send(sendMessage, to: message.RespondTo())

        default:
            sender.send("Invalid schedule command type. Must be add, delete, or list", to: message.RespondTo())
        }
    }

    // MARK: - Background thread

    @objc func scheduleThread() {
        for post in getPendingPosts() {
            guard let handle = post.handle, let text = post.text else { continue }
            sender.send(text, to: AbstractRecipient(handle: handle))
            bumpPost(post: post)
        }
    }

    // MARK: - CoreData helpers

    private func getNextSendTime(number: Int, type: IntervalType) -> Date {
        return Date().addingTimeInterval(Double(number) * (intervalSeconds[type] ?? 0))
    }

    private func getPosts(for handle: String) -> [SchedulePost] {
        let request: NSFetchRequest<SchedulePost> = SchedulePost.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        request.predicate = NSPredicate(format: "handle == %@", handle)
        return (try? persistentContainer.viewContext.fetch(request)) ?? []
    }

    private func getPendingPosts() -> [SchedulePost] {
        let request: NSFetchRequest<SchedulePost> = SchedulePost.fetchRequest()
        request.predicate = NSPredicate(format: "sendNext <= %@", NSDate())
        return (try? persistentContainer.viewContext.fetch(request)) ?? []
    }

    private func bumpPost(post: SchedulePost) {
        post.currentSendCount += 1
        if post.currentSendCount == post.sendNumberTimes {
            persistentContainer.viewContext.delete(post)
        } else {
            post.sendNext = getNextSendTime(
                number: Int(post.sendIntervalNumber),
                type: IntervalType(rawValue: post.sendIntervalType!)!
            )
        }
        persistentContainer.saveContext()
    }
}
