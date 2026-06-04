//
//  ConfigurationWatcher.swift
//  Jared
//

import Foundation

class ConfigurationWatcher {
    private let configURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(configURL: URL, onChange: @escaping () -> Void) {
        self.configURL = configURL
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
        // Re-open after rename/delete (atomic writes replace the file)
        if source?.data.contains(.rename) == true || source?.data.contains(.delete) == true {
            stop()
            // Small delay to let the new file appear
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.start()
            }
        }
        onChange()
    }

    deinit {
        stop()
    }
}
