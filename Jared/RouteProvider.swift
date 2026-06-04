//
//  RouteProvider.swift
//  Jared
//
//  Created by Zeke Snider on 4/20/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

protocol RouteProvider {
    func getAllRoutes() -> [Route]
    func enabled(routeName: String) -> Bool
}

protocol PluginController: AnyObject {
    func getAllModules() -> [RoutingModule]
    func reload()
}
