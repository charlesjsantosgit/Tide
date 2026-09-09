import AppKit

/// Self-update from a GitHub Releases feed (or anything that speaks the same JSON — see tools/serve.py).
/// Check → download the .zip asset → extract → verify it's Tide → swap the bundle on disk → relaunch.
final class Updater: NSObject {
    static let shared = Updater()

    static let defaultFeed = "https://api.github.com/repos/charlesjsantosgit/Tide/releases/latest"
    static let feedKey = "updateFeedURL"
    static let autoKey = "autoCheckForUpdates"
    static let lastCheckKey = "lastUpdateCheck"
    static let skipKey = "skippedUpdateVersion"

    enum UpdateError: LocalizedError {
        case badFeed, noAsset, download(String), extract, verify(String), install(String), unsaved
        var errorDescription: String? {
            switch self {
            case .badFeed: return "The update feed could not be read."
            case .noAsset: return "The release has no .zip to download."
            case .download(let s): return "The download failed (\(s))."
            case .extract: return "The downloaded archive could not be unpacked."
            case .verify(let s): return "The download does not look like Tide (\(s))."
            case .install(let s): return "The new version could not be installed (\(s))."
            case .unsaved: return "Save your documents before updating."
            }
        }
    }

    struct ReleaseInfo {
        let version: String
        let title: String
        let notes: String
        let assetURL: URL
        let assetName: String
        let size: Int?
    }

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    var feedURL: URL {
        let s = UserDefaults.standard.string(forKey: Self.feedKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return URL(string: s.isEmpty ? Self.defaultFeed : s) ?? URL(string: Self.defaultFeed)!
    }

    /// Quiet mode prints to stdout instead of showing windows (used by the CLI switches and tests).
    var quiet = false
    private var checking = false
    private var progressWindow: NSWindow?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Checking

    func checkAutomaticallyIfDue() {
        guard UserDefaults.standard.bool(forKey: Self.autoKey) else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool, feed: URL? = nil, completion: ((Result<ReleaseInfo?, Error>) -> Void)? = nil) {
        guard !checking else { return }
        checking = true
        fetchLatest(from: feed ?? feedURL) { [weak self] result in
            guard let self else { return }
            self.checking = false
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            switch result {
            case .failure(let error):
                if userInitiated { self.alert("Couldn't check for updates", error.localizedDescription) }
                completion?(.failure(error))
            case .success(let info):
                if Self.isNewer(info.version, than: Self.currentVersion) {
                    if !userInitiated, UserDefaults.standard.string(forKey: Self.skipKey) == info.version {
                        completion?(.success(nil))
                        return
                    }
                    completion?(.success(info))
                    if !self.quiet { self.offer(info) }
                } else {
                    if userInitiated { self.alert("You're up to date", "Tide \(Self.currentVersion) is the newest version.") }
                    completion?(.success(nil))
                }
            }
        }
    }

    func fetchLatest(from url: URL, completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Tide/\(Self.currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(error)); return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    completion(.failure(UpdateError.download("HTTP \(http.statusCode)")))
                    return
                }
                guard let data, let info = Self.parse(feed: data) else { completion(.failure(UpdateError.badFeed)); return }
                completion(.success(info))
            }
        }.resume()
    }

    /// GitHub's `releases/latest` shape: tag_name, name, body, assets[{name, browser_download_url, size}].
    static func parse(feed data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let assets = obj["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }),
              let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString) else { return nil }
        return ReleaseInfo(version: version,
                           title: (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Tide \(version)",
                           notes: obj["body"] as? String ?? "",
                           assetURL: url,
                           assetName: asset["name"] as? String ?? "Tide.zip",
                           size: asset["size"] as? Int)
    }

    static func isNewer(_ a: String, than b: String) -> Bool { compare(a, b) > 0 }

    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] { s.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0.filter(\.isNumber)) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    // MARK: - Offering

    private func offer(_ info: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "\(info.title) is available"
        var text = "You have Tide \(Self.currentVersion). Tide will download the update, replace itself and relaunch."
        let notes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text += "\n\n" + String(notes.prefix(1200)) }
        alert.informativeText = text
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(info)
        case .alertThirdButtonReturn: UserDefaults.standard.set(info.version, forKey: Self.skipKey)
        default: break
        }
    }

    private func alert(_ title: String, _ message: String) {
        if quiet { print("\(title): \(message)"); return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - Installing

    /// Downloads, unpacks, verifies and (unless `dryRun`) swaps the running bundle and relaunches.
    func install(_ info: ReleaseInfo, dryRun: Bool = false, completion: ((Result<URL, Error>) -> Void)? = nil) {
        if !dryRun, !quiet, NSDocumentController.shared.hasEditedDocuments {
            alert("Save your documents first", "Tide needs to quit and relaunch to update. Save your open documents, then choose Check for Updates again.")
            completion?(.failure(UpdateError.unsaved))
            return
        }
        showProgress("Downloading \(info.assetName)…")
        download(info.assetURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.hideProgress()
                self.alert("Update failed", error.localizedDescription)
                completion?(.failure(error))
            case .success(let zip):
                self.setProgress("Unpacking…")
                do {
                    let app = try self.extract(zip)
                    try self.verify(app)
                    try? FileManager.default.removeItem(at: zip)
                    if dryRun {
                        self.hideProgress()
                        completion?(.success(app))
                        return
                    }
                    self.setProgress("Installing…")
                    let installed = try self.swap(newApp: app)
                    self.hideProgress()
                    completion?(.success(installed))
                    self.relaunch(installed)
                } catch {
                    self.hideProgress()
                    self.alert("Update failed", error.localizedDescription)
                    completion?(.failure(error))
                }
            }
        }
    }

    private func download(_ url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        var req = URLRequest(url: url)
        req.setValue("Tide/\(Self.currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120
        let task = URLSession.shared.downloadTask(with: req) { tmp, response, error in
            let moved: Result<URL, Error>
            if let error {
                moved = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                moved = .failure(UpdateError.download("HTTP \(http.statusCode)"))
            } else if let tmp {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("TideUpdate-\(UUID().uuidString).zip")
                do { try FileManager.default.moveItem(at: tmp, to: dest); moved = .success(dest) } catch { moved = .failure(error) }
            } else {
                moved = .failure(UpdateError.download("no data"))
            }
            DispatchQueue.main.async { completion(moved) }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.progressBar?.isIndeterminate = false
                self?.progressBar?.doubleValue = p.fractionCompleted * 100
            }
        }
        task.resume()
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func extract(_ zip: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TideUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) == 0 else { throw UpdateError.extract }
        func findApp(in d: URL, depth: Int) -> URL? {
            guard depth >= 0, let items = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return nil }
            if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
            for sub in items where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let app = findApp(in: sub, depth: depth - 1) { return app }
            }
            return nil
        }
        guard let app = findApp(in: dir, depth: 2) else { throw UpdateError.extract }
        // Gatekeeper would refuse an ad-hoc signed app that carries the quarantine flag.
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    private func verify(_ app: URL) throws {
        guard let bundle = Bundle(url: app) else { throw UpdateError.verify("not a bundle") }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.verify("bundle id \(bundle.bundleIdentifier ?? "?")") }
        guard let exe = bundle.executableURL, FileManager.default.isExecutableFile(atPath: exe.path) else { throw UpdateError.verify("no executable") }
        guard run("/usr/bin/codesign", ["--verify", "--deep", app.path]) == 0 else { throw UpdateError.verify("signature") }
    }

    /// Moves the current bundle aside and puts the new one in its place. The running process keeps working
    /// from its mapped binary until it relaunches.
    private func swap(newApp: URL) throws -> URL {
        let current = Bundle.main.bundleURL
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("Tide-previous-\(Self.currentVersion)-\(UUID().uuidString.prefix(6)).app")
        do { try FileManager.default.moveItem(at: current, to: backup) } catch { throw UpdateError.install(error.localizedDescription) }
        do {
            try FileManager.default.moveItem(at: newApp, to: current)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: current)
            throw UpdateError.install(error.localizedDescription)
        }
        return current
    }

    private func relaunch(_ app: URL) {
        let extra = quiet ? " --args --quit-after-launch" : ""
        let script = "sleep 0.8; /usr/bin/open \"\(app.path)\"\(extra)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        if quiet { exit(0) }
        NSApp.terminate(nil)
    }

    // MARK: - Progress window

    private func showProgress(_ text: String) {
        if quiet { print(text); return }
        if progressWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 92), styleMask: [.titled], backing: .buffered, defer: false)
            w.title = "Updating Tide"
            w.isReleasedWhenClosed = false
            let content = NSView(frame: w.contentView!.bounds)
            let label = NSTextField(labelWithString: text)
            label.frame = NSRect(x: 20, y: 54, width: 340, height: 20)
            let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 24, width: 340, height: 20))
            bar.style = .bar
            bar.isIndeterminate = true
            bar.minValue = 0
            bar.maxValue = 100
            bar.startAnimation(nil)
            content.addSubview(label)
            content.addSubview(bar)
            w.contentView = content
            w.center()
            progressWindow = w
            progressBar = bar
            progressLabel = label
        }
        progressLabel?.stringValue = text
        progressWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setProgress(_ text: String) {
        if quiet { print(text); return }
        progressLabel?.stringValue = text
        progressBar?.isIndeterminate = true
        progressBar?.startAnimation(nil)
    }

    private func hideProgress() {
        progressObservation = nil
        progressWindow?.orderOut(nil)
    }

    // MARK: - Command-line helpers (`--update-check`, `--update-dryrun`, `--update-now`)

    static func runCommandLine(mode: String, feed: String) -> Never {
        let updater = Updater.shared
        updater.quiet = true
        guard let url = URL(string: feed) else { print("bad feed URL"); exit(2) }
        print("Tide \(currentVersion) at \(Bundle.main.bundleURL.path)")
        print("feed: \(url)")
        updater.fetchLatest(from: url) { result in
            switch result {
            case .failure(let error):
                print("check failed: \(error.localizedDescription)")
                exit(1)
            case .success(let info):
                let newer = isNewer(info.version, than: currentVersion)
                print("latest: \(info.version) (\(info.assetName), \(info.size.map { "\($0) bytes" } ?? "size unknown")) — \(newer ? "newer" : "not newer")")
                print("asset: \(info.assetURL)")
                if mode == "--update-check" { exit(0) }
                guard newer || mode == "--update-dryrun" else { print("nothing to install"); exit(0) }
                updater.install(info, dryRun: mode == "--update-dryrun") { r in
                    switch r {
                    case .success(let url): print("\(mode == "--update-dryrun" ? "verified" : "installed"): \(url.path)"); if mode == "--update-dryrun" { exit(0) }
                    case .failure(let error): print("install failed: \(error.localizedDescription)"); exit(1)
                    }
                }
            }
        }
        RunLoop.main.run()
        exit(0)
    }
}
