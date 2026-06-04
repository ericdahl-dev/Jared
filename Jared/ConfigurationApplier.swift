//
//  ConfigurationApplier.swift
//  Jared
//

import Foundation

protocol ConfigurationApplier: AnyObject {
    func apply(_ newConfig: ConfigurationFile)
}
