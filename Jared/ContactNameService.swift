//
//  ContactNameService.swift
//  Jared
//
//  Port hiding CNContactStore behind a small interface so `/name` is testable
//  without Contacts permission, and contact create/update has no `try!`.
//

import Foundation
import Contacts

protocol ContactNameService {
    var isAuthorized: Bool { get }
    /// Sets the given name for the contact matching `handle`, creating the
    /// contact when none exists. Throws if the contact store write fails.
    func setGivenName(_ name: String, forHandle handle: String) throws
}

struct CNContactNameService: ContactNameService {
    var isAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    func setGivenName(_ name: String, forHandle handle: String) throws {
        let store = CNContactStore()

        let searchPredicate: NSPredicate
        if !handle.contains("@") {
            searchPredicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        } else {
            searchPredicate = CNContact.predicateForContacts(matchingEmailAddress: handle)
        }

        let found = try store.unifiedContacts(
            matching: searchPredicate,
            keysToFetch: [CNContactFamilyNameKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor]
        )

        let saveRequest = CNSaveRequest()
        if let existing = found.first {
            let mutable = existing.mutableCopy() as! CNMutableContact
            mutable.givenName = name
            saveRequest.update(mutable)
        } else {
            let newContact = CNMutableContact()
            newContact.givenName = name
            newContact.note = "Created By jared.app"
            if handle.contains("@") {
                newContact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: handle as NSString)]
            } else {
                newContact.phoneNumbers = [CNLabeledValue(label: "iPhone", value: CNPhoneNumber(stringValue: handle))]
            }
            saveRequest.add(newContact, toContainerWithIdentifier: nil)
        }

        try store.execute(saveRequest)
    }
}
