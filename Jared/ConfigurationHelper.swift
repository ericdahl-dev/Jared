//
//  ConfigurationHelper.swift
//  Jared
//
//  Created by Zeke Snider on 8/22/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.zekesnider.jared", category: "configuration")

struct ConfigurationHelper {
    static let fileManager = FileManager.default

    static func getConfiguration() -> ConfigurationFile {
        let configPath = ConfigurationHelper.getSupportDirectory()
            .appendingPathComponent("config.json")
        ConfigurationHelper.createConfigFileIfNotExists(at: configPath, using: fileManager)

        var config: ConfigurationFile
        if let data = try? Data(contentsOf: configPath) {
            do {
                config = try JSONDecoder().decode(ConfigurationFile.self, from: data)
                logger.notice("Config loaded from \(configPath.path, privacy: .public)")
            } catch {
                logger.error("Failed to parse config.json: \(error.localizedDescription, privacy: .public) — check syntax at https://jsonlint.com")
                config = ConfigurationFile()
            }
        } else {
            logger.error("Could not read config.json at \(configPath.path, privacy: .public)")
            config = ConfigurationFile()
        }

        return config
    }

    static func getSupportDirectory() -> URL {
        let filemanager = FileManager.default
        let appsupport = filemanager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let supportDir = appsupport.appendingPathComponent("Jared")

        try! filemanager.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)

        return supportDir
    }

    static func getPluginDirectory() -> URL {
        let supportDir = getSupportDirectory()
            .appendingPathComponent("Plugins")

        try! fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)

        return supportDir
    }

    private static func createConfigFileIfNotExists(at path: URL, using fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: path.path) else { return }
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("config.json") else {
            logger.error("Default config.json missing from app bundle")
            return
        }
        do {
            try fileManager.copyItem(at: source, to: path)
            logger.notice("Created default config.json at \(path.path, privacy: .public)")
        } catch {
            logger.error("Could not create default config.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
