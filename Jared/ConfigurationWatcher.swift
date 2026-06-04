//
//  ConfigurationWatcher.swift
//  Jared
//

import Foundation

class ConfigurationWatcher {
    private let configURL: URL
    private let onChange: () -> Void
    private weak var applier: ConfigurationApplier?
    private var source: DispatchSourceFileSystemObject?

    init(configURL: URL, applier: ConfigurationApplier? = nil, onChange: @escaping () -> Void) {
        self.configURL = configURL
        self.applier = applier
        self.onChange = onChange
    }

    func start() {
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("ConfigurationWatcher: could not open %@", configURL.path)
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.handleChange()
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func handleChange() {
        if source?.data.contains(.rename) == true || source?.data.contains(.delete) == true {
            stop()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.start()
            }
        }
        if let applier = applier,
           let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(ConfigurationFile.self, from: data) {
            applier.apply(config)
        }
        onChange()
    }

    deinit {
        stop()
    }
}
