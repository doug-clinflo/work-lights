import AppKit
import CoreGraphics
import Darwin

struct Bulb: Codable { var ip: String; var mac: String; var roomID: UUID? = nil }
struct Room: Codable { let id: UUID; var name: String }
struct Configuration: Codable {
    var rooms: [Room] = []
    var bulbs: [Bulb] = []
    var selectedRoom: UUID? = nil
    var paused = true
    func targets() -> [Bulb] {
        guard let id = selectedRoom, rooms.contains(where: { $0.id == id }) else { return [] }
        return bulbs.filter { $0.roomID == id }
    }
    func validate() throws {
        guard Set(rooms.map(\.id)).count == rooms.count,
              Set(bulbs.map(\.mac)).count == bulbs.count,
              rooms.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              selectedRoom == nil || rooms.contains(where: { $0.id == selectedRoom }),
              bulbs.allSatisfy({ b in b.mac.count == 12 && b.mac.allSatisfy({ $0.isHexDigit }) && (b.roomID == nil || rooms.contains { $0.id == b.roomID }) }) else {
            throw NSError(domain: "Invalid local configuration", code: 1)
        }
    }
}
struct Reply { let ip: String; let mac: String; let state: Bool; var dimming: Int? = nil; var scene: Int? = nil }
func parse(_ data: Data, ip: String) -> Reply? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
          obj["method"] as? String == "getPilot", let r = obj["result"] as? [String:Any],
          let raw = r["mac"] as? String, let state = r["state"] as? Bool else { return nil }
    let mac = raw.lowercased().replacingOccurrences(of: ":", with: "")
    guard mac.count == 12, mac.allSatisfy({ $0.isHexDigit }) else { return nil }
    return Reply(ip: ip, mac: mac, state: state, dimming: (r["dimming"] as? Int).flatMap { (0...100).contains($0) ? $0 : nil }, scene: r["sceneId"] as? Int)
}
// Each request gets its own socket; replies must match the requested IP and method.
func request(_ ips: [String], broadcast: Bool = false, params: [String:Any]? = nil) -> [Reply] {
    guard !ips.isEmpty else { return [] }
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return [] }; defer { close(fd) }
    var timeout = timeval(tv_sec: 0, tv_usec: 200000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    var yes: Int32 = 1
    if broadcast { setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, 4) }
    let command: [String:Any] = ["method": params == nil ? "getPilot" : "setPilot", "params": params ?? [:]]
    guard let data = try? JSONSerialization.data(withJSONObject: command) else { return [] }
    for ip in ips {
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(38899).bigEndian
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { continue }
        _ = data.withUnsafeBytes { bytes in withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }}
    }
    if params != nil { return [] }
    let deadline = Date().addingTimeInterval(broadcast ? 2 : 1)
    var results: [String:Reply] = [:]
    while Date() < deadline {
        var buffer = [UInt8](repeating: 0, count: 4096); var addr = sockaddr_in()
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            recvfrom(fd, &buffer, buffer.count, 0, $0, &size)
        }}
        if n <= 0 { continue }
        let ip = String(cString: inet_ntoa(addr.sin_addr))
        guard addr.sin_port == UInt16(38899).bigEndian, broadcast || ips.contains(ip) else { continue }
        if let reply = parse(Data(buffer.prefix(n)), ip: ip) { results[reply.mac] = reply }
        if !broadcast && results.count == Set(ips).count { break }
    }
    return Array(results.values)
}
func broadcasts() -> [String] {
    var result = Set(["255.255.255.255"]); var head: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&head) == 0 {
        defer { freeifaddrs(head) }; var cursor = head
        while let p = cursor {
            let a = p.pointee; cursor = a.ifa_next
            guard a.ifa_flags & UInt32(IFF_UP) != 0, a.ifa_flags & UInt32(IFF_BROADCAST) != 0,
                  let dst = a.ifa_dstaddr, dst.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let v = UnsafeRawPointer(dst).assumingMemoryBound(to: sockaddr_in.self).pointee
            result.insert(String(cString: inet_ntoa(v.sin_addr)))
        }
    }
    return Array(result)
}
func shouldRestore(_ r: Reply, bulbs: [Bulb], active: Bool) -> Bool {
    active && !r.state && bulbs.contains { $0.mac == r.mac && $0.ip == r.ip }
}

struct Look {
    let title: String
    let scene: Int
}
let looks = [
    Look(title: "🎯 Deep work · Focus", scene: 15),
    Look(title: "☀️ Fresh start · Daylight", scene: 12),
    Look(title: "☕ Coffee break · Cozy", scene: 6),
    Look(title: "🌅 Golden hour · Sunset", scene: 3),
    Look(title: "🌊 Ocean drift · Ocean", scene: 1),
    Look(title: "🔥 Fireside · Fireplace", scene: 5),
    Look(title: "🌙 Wind down · Relax", scene: 16),
    Look(title: "🕯 Candlelit · Candlelight", scene: 29)
]
enum Adjustment {
    case scene(Int), delta(Int), level(Int)
    func parameters(for reply: Reply) -> [String:Any]? {
        switch self {
        case .scene(let id): return ["state":true, "sceneId":id]
        case .delta(let amount):
            guard let current = reply.dimming else { return nil }
            let next = min(100, max(10, current + amount))
            guard next != current || !reply.state else { return nil }
            return ["state":true, "dimming":next]
        case .level(let value): return ["state":true, "dimming":min(100, max(10, value))]
        }
    }
    func matches(_ reply: Reply, params: [String:Any]) -> Bool {
        guard reply.state else { return false }
        if let scene = params["sceneId"] as? Int { return reply.scene == scene }
        return reply.dimming == params["dimming"] as? Int
    }
}
final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!; var timer: Timer?
    var menuOpen = false; var feedback = "Choose a room to control its lights"
    var observed: [Reply] = []
    let worker = DispatchQueue(label: "WorkLights.network")
    let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WorkLightsCommunity")
    var config = Configuration()
    var configurationError: String? = nil
    var bulbs: [Bulb] {
        get { config.bulbs }
        set { config.bulbs = newValue }
    }
    var selectedBulbs: [Bulb] { config.targets() }
    var roomName: String { config.rooms.first { $0.id == config.selectedRoom }?.name ?? "No room selected" }
    var candidates: [Reply] = []
    var busy = false; var sleeping = false; var screenSleeping = false; var sessionInactive = false
    var paused: Bool {
        get { config.paused }
        set { config.paused = newValue }
    }
    var holdUntil = Date.distantPast; var nextCheck = Date.distantPast; var nextDiscovery = Date.distantPast
    var failures = 0; var status = "Checking saved addresses…"; var lastSent: [String:Date] = [:]
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "org.worklights.app").count > 1 { NSApp.terminate(nil); return }
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let file = base.appendingPathComponent("configuration.json")
            if FileManager.default.fileExists(atPath: file.path) {
                config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
                try config.validate()
            } else {
                try JSONEncoder().encode(config).write(to: file, options: .atomic)
            }
        } catch {
            configurationError = "Configuration could not be loaded. Open local settings to inspect it."
            config = Configuration()
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "💡"; rebuild()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        check(discover: true)
    }
    @objc func workspaceChanged(_ n: Notification) {
        switch n.name {
        case NSWorkspace.willSleepNotification: sleeping = true; holdUntil = .distantPast
        case NSWorkspace.didWakeNotification: sleeping = false
        case NSWorkspace.screensDidSleepNotification: screenSleeping = true; holdUntil = .distantPast
        case NSWorkspace.screensDidWakeNotification: screenSleeping = false
        case NSWorkspace.sessionDidResignActiveNotification: sessionInactive = true; holdUntil = .distantPast
        default: sessionInactive = false
        }
        nextCheck = .distantPast; nextDiscovery = .distantPast; rebuild()
    }
    var sessionAvailable: Bool {
        guard !sleeping, !screenSleeping, !sessionInactive,
              let session = CGSessionCopyCurrentDictionary() as? [String:Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true else { return false }
        return true
    }
    var active: Bool {
        guard configurationError == nil, !selectedBulbs.isEmpty, !paused, sessionAvailable else { return false }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return Date() < holdUntil || (idle.isFinite && idle >= 0 && idle < 900)
    }
    func save() {
        guard configurationError == nil else { return }
        do {
            try config.validate()
            try JSONEncoder().encode(config).write(to: base.appendingPathComponent("configuration.json"), options: .atomic)
        } catch { paused = true; configurationError = "Could not save local settings; control disabled" }

    }
    func tick() {
        rebuild()
        guard active, !busy, Date() >= nextCheck else { return }
        check(discover: Date() >= nextDiscovery)
    }
    func check(discover: Bool) {
        guard !busy, configurationError == nil else { return }; busy = true
        let targets = selectedBulbs.map(\.ip)
        worker.async {
            let direct = request(targets)
            let found = discover ? request(broadcasts(), broadcast: true) : []
            DispatchQueue.main.async {
                self.busy = false
                // Rediscovery only updates previously assigned identities.
                for r in direct + found {
                    if let index = self.bulbs.firstIndex(where: { $0.mac == r.mac }) { self.bulbs[index].ip = r.ip }
                }
                if discover {
                    self.candidates = (direct + found).reduce(into: [String:Reply]()) { $0[$1.mac] = $1 }.values.filter { r in !self.bulbs.contains { $0.mac == r.mac } }.sorted { $0.ip < $1.ip }
                    self.nextDiscovery = Date().addingTimeInterval(300)
                }
                self.save()
                var replies: [String:Reply] = [:]
                for r in direct + found { replies[r.mac] = r }
                self.observed = replies.values.filter { r in self.selectedBulbs.contains { $0.mac == r.mac && $0.ip == r.ip } }
                let reachable = replies.values.filter { r in self.selectedBulbs.contains { $0.mac == r.mac } }.count
                self.failures = reachable == 0 ? min(self.failures + 1, 5) : 0
                self.nextCheck = Date().addingTimeInterval(reachable == 0 ? min(300, 15 * pow(2, Double(self.failures))) : 15)
                self.status = "\(self.roomName) · \(reachable)/\(self.selectedBulbs.count) reachable"
                // Check activity again after network work, preventing stale wake/lock actions.
                for r in replies.values where shouldRestore(r, bulbs: self.selectedBulbs, active: self.active) {
                    guard Date().timeIntervalSince(self.lastSent[r.mac] ?? .distantPast) >= 30 else { continue }
                    self.lastSent[r.mac] = Date()
                    _ = request([r.ip], params: ["state": true])
                }
                self.rebuild()
            }
        }
    }
    func entry(_ title: String, _ selector: Selector?, into menu: NSMenu) {
        let m = NSMenuItem(title: title, action: selector, keyEquivalent: ""); m.target = self; menu.addItem(m)
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
    func rebuild() {
        guard !menuOpen else { return }
        let menu = NSMenu(); menu.delegate = self
        entry(paused ? "Paused" : (active ? "Keeping work lights on" : "Waiting for activity"), nil, into: menu)
        entry(configurationError ?? status, nil, into: menu)
        let rooms = NSMenu()
        for room in config.rooms {
            let m = NSMenuItem(title:room.name, action:#selector(selectRoom(_:)), keyEquivalent:"")
            m.target = self; m.representedObject = room.id.uuidString
            m.state = config.selectedRoom == room.id ? .on : .off; rooms.addItem(m)
        }
        rooms.addItem(.separator())
        entry("New room…", #selector(newRoom), into: rooms)
        entry("Rename selected room…", #selector(renameRoom), into: rooms)
        entry("Delete selected room…", #selector(deleteRoom), into: rooms)
        let roomParent = NSMenuItem(title:"Room · \(roomName)", action:nil, keyEquivalent:"")
        roomParent.submenu = rooms; menu.addItem(roomParent)
        menu.addItem(.separator())
        entry("SET THE MOOD", nil, into: menu)
        entry("Controls apply to \(roomName)", nil, into: menu)
        entry(feedback, nil, into: menu)
        let sceneMenu = NSMenu()
        for look in looks {
            let m = NSMenuItem(title: look.title, action: #selector(selectScene(_:)), keyEquivalent: "")
            m.target = self; m.tag = look.scene
            if !observed.isEmpty && observed.allSatisfy({ $0.state && $0.scene == look.scene }) { m.state = .on }
            sceneMenu.addItem(m)
        }
        sceneMenu.addItem(.separator())
        entry("Availability varies by bulb model", nil, into: sceneMenu)
        let sceneParent = NSMenuItem(title: "Scenes", action: nil, keyEquivalent: "")
        sceneParent.submenu = sceneMenu; menu.addItem(sceneParent)
        let levels = observed.compactMap(\.dimming)
        if let low = levels.min(), let high = levels.max() {
            entry(low == high ? "Brightness · \(low)%" : "Brightness · \(low)–\(high)% across lights", nil, into: menu)
        }
        entry("−  Dim down 10%", #selector(dimDown), into: menu)
        entry("+  Brighten up 10%", #selector(dimUp), into: menu)
        let brightness = NSMenu()
        for (label, level) in [("Low glow · 10%",10),("Easy evening · 30%",30),("Half light · 50%",50),("Bright ideas · 75%",75),("Full beam · 100%",100)] {
            let m = NSMenuItem(title:label, action:#selector(selectLevel(_:)), keyEquivalent:"")
            m.target = self; m.tag = level; brightness.addItem(m)
        }
        let levelParent = NSMenuItem(title:"Set brightness", action:nil, keyEquivalent:"")
        levelParent.submenu = brightness; menu.addItem(levelParent)
        menu.addItem(.separator())
        entry(paused ? "Resume automatic control" : "Pause automatic control", #selector(toggle), into: menu)
        entry("Keep on for 1 hour", #selector(hold), into: menu)
        entry("Return to activity detection", #selector(clearHold), into: menu)
        entry("Check addresses / discover", #selector(rediscover), into: menu)
        if !candidates.isEmpty && config.selectedRoom != nil {
            let parent = NSMenuItem(title: "Add discovered lights to \(roomName)", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for r in candidates {
                let m = NSMenuItem(title: "\(r.ip) · \(r.mac)", action: #selector(enrol(_:)), keyEquivalent: "")
                m.target = self; m.representedObject = r.mac; sub.addItem(m)
            }
            parent.submenu = sub; menu.addItem(parent)
        }
        let devices = NSMenuItem(title: "Manage assigned lights", action: nil, keyEquivalent: ""); let list = NSMenu()
        for b in bulbs {
            let assigned = config.rooms.first { $0.id == b.roomID }?.name ?? "Unassigned"
            let parent = NSMenuItem(title:"\(assigned) · \(b.ip) · \(b.mac)", action:nil, keyEquivalent:"")
            let actions = NSMenu()
            for room in config.rooms {
                let m = NSMenuItem(title:"Move to \(room.name)", action:#selector(moveBulb(_:)), keyEquivalent:"")
                m.target = self; m.representedObject = [b.mac,room.id.uuidString]; actions.addItem(m)
            }
            let remove = NSMenuItem(title:"Forget this light", action:#selector(forgetBulb(_:)), keyEquivalent:"")
            remove.target = self; remove.representedObject = b.mac; actions.addItem(remove)
            parent.submenu = actions; list.addItem(parent)
        }; devices.submenu = list; menu.addItem(devices)
        entry("Open local settings folder", #selector(openSettings), into: menu)
        menu.addItem(.separator())
        entry("Enable start at login", #selector(installLogin), into: menu)
        entry("Disable start at login", #selector(removeLogin), into: menu)
        entry("Quit", #selector(quit), into: menu)
        item.menu = menu; item.button?.title = paused ? "💡Ⅱ" : "💡"
    }
    @objc func selectScene(_ sender: NSMenuItem) { adjust(.scene(sender.tag), label: sender.title) }
    @objc func selectLevel(_ sender: NSMenuItem) { adjust(.level(sender.tag), label: sender.title) }
    @objc func dimDown() { adjust(.delta(-10), label: "Dim down") }
    @objc func dimUp() { adjust(.delta(10), label: "Brighten up") }
    func adjust(_ adjustment: Adjustment, label: String) {
        guard !busy else { feedback = "Checking lights — try again in a moment"; rebuild(); return }
        guard configurationError == nil, !selectedBulbs.isEmpty, sessionAvailable else { feedback = "No lights available in this session"; rebuild(); return }
        busy = true; feedback = "Applying \(label)…"; rebuild()
        let targets = selectedBulbs
        let roomID = config.selectedRoom
        worker.async {
            // Fresh preflight validates identity and reads each bulb's own brightness.
            let before = request(targets.map(\.ip)).filter { r in targets.contains { $0.ip == r.ip && $0.mac == r.mac } }
            var expected: [String:[String:Any]] = [:]
            var skipped = 0
            DispatchQueue.main.sync {
                guard self.sessionAvailable, self.config.selectedRoom == roomID else { return }
                for r in before {
                    guard let params = adjustment.parameters(for:r) else { skipped += 1; continue }
                    if adjustment.matches(r, params:params) { skipped += 1; continue }
                    expected[r.mac] = params
                    _ = request([r.ip], params:params)
                }
            }
            // Verify what the bulbs report, rather than treating a UDP send as success.
            if !expected.isEmpty { Thread.sleep(forTimeInterval:0.4) }
            let after = expected.isEmpty ? before : request(before.map(\.ip)).filter { r in targets.contains { $0.ip == r.ip && $0.mac == r.mac } }
            let confirmed = after.filter { r in expected[r.mac].map { adjustment.matches(r, params:$0) } ?? false }.count
            let sent = expected.count; let skippedCount = skipped
            DispatchQueue.main.async {
                self.busy = false; self.observed = self.config.selectedRoom == roomID ? after : []
                let unavailable = targets.count - before.count
                self.feedback = "\(confirmed)/\(sent) changes confirmed · \(skippedCount) unchanged"
                if unavailable > 0 { self.feedback += " · \(unavailable) offline"; self.nextDiscovery = .distantPast }
                if confirmed < sent { self.feedback += " · some unconfirmed/unsupported" }
                if !self.sessionAvailable || self.config.selectedRoom != roomID { self.feedback = "Cancelled — session or room changed" }
                self.nextCheck = Date().addingTimeInterval(15); self.rebuild()
            }
        }
    }
    @objc func toggle() { paused.toggle(); save(); nextCheck = .distantPast; rebuild() }
    @objc func hold() { paused = false; save(); holdUntil = Date().addingTimeInterval(3600); nextCheck = .distantPast; tick() }
    @objc func clearHold() { holdUntil = .distantPast; rebuild() }
    @objc func rediscover() { check(discover: true) }
    @objc func enrol(_ sender: NSMenuItem) {
        guard !busy, configurationError == nil, let room = config.selectedRoom, let mac = sender.representedObject as? String, let r = candidates.first(where: { $0.mac == mac }), !bulbs.contains(where: { $0.mac == mac }) else { return }
        bulbs.append(Bulb(ip: r.ip, mac: r.mac, roomID: room)); candidates.removeAll { $0.mac == mac }; save(); nextCheck = .distantPast; rebuild()
    }
    func canEdit() -> Bool {
        if busy { feedback = "Wait for the current check to finish"; rebuild(); return false }
        return configurationError == nil
    }
    func promptName(_ title: String, current: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = title
        alert.informativeText = "Rooms are stored on this Mac and do not change rooms in the WiZ app."
        let input = NSTextField(string:current); input.frame = NSRect(x:0,y:0,width:280,height:24)
        input.placeholderString = "e.g. Office"; alert.accessoryView = input
        alert.addButton(withTitle:"Save"); alert.addButton(withTitle:"Cancel")
        NSApp.activate(ignoringOtherApps:true); alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { feedback = "Use a room name of 1–60 characters"; return nil }
        return name
    }
    func roomChanged() {
        holdUntil = .distantPast; observed = []; nextCheck = .distantPast
        feedback = "Controls apply to \(roomName)"; save(); rebuild()
    }
    @objc func selectRoom(_ sender: NSMenuItem) {
        guard canEdit(), let value = sender.representedObject as? String, let id = UUID(uuidString:value), config.rooms.contains(where: { $0.id == id }) else { return }
        config.selectedRoom = id; roomChanged()
    }
    @objc func newRoom() {
        guard canEdit(), let name = promptName("Create a room") else { return }
        let room = Room(id:UUID(), name:name); config.rooms.append(room); config.selectedRoom = room.id; roomChanged()
    }
    @objc func renameRoom() {
        guard canEdit(), let index = config.rooms.firstIndex(where: { $0.id == config.selectedRoom }), let name = promptName("Rename room", current:config.rooms[index].name) else { return }
        config.rooms[index].name = name; roomChanged()
    }
    @objc func deleteRoom() {
        guard canEdit(), let id = config.selectedRoom else { return }
        let alert = NSAlert(); alert.messageText = "Delete \(roomName)?"
        alert.informativeText = "Its lights will be unassigned. Their power state and WiZ settings will not change."
        alert.addButton(withTitle:"Delete room"); alert.addButton(withTitle:"Cancel")
        NSApp.activate(ignoringOtherApps:true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        config.rooms.removeAll { $0.id == id }
        for index in bulbs.indices where bulbs[index].roomID == id { bulbs[index].roomID = nil }
        config.selectedRoom = nil; paused = true; roomChanged()
    }
    @objc func moveBulb(_ sender: NSMenuItem) {
        guard canEdit(), let values = sender.representedObject as? [String], values.count == 2,
              let index = bulbs.firstIndex(where: { $0.mac == values[0] }), let id = UUID(uuidString:values[1]), config.rooms.contains(where: { $0.id == id }) else { return }
        bulbs[index].roomID = id; roomChanged()
    }
    @objc func forgetBulb(_ sender: NSMenuItem) {
        guard canEdit(), let mac = sender.representedObject as? String else { return }
        bulbs.removeAll { $0.mac == mac }; roomChanged()
    }
    @objc func openSettings() { NSWorkspace.shared.open(base) }
    var loginURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/org.worklights.app.plist") }
    @objc func installLogin() {
        do {
            let plist: [String:Any] = ["Label":"org.worklights.app", "ProgramArguments":[Bundle.main.executablePath!], "RunAtLoad":true, "LimitLoadToSessionType":"Aqua", "ProcessType":"Interactive"]
            try FileManager.default.createDirectory(at: loginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: loginURL, options: .atomic)
            status = "Start at login enabled for next login"
        } catch { status = "Login setup failed: \(error.localizedDescription)" }; rebuild()
    }
    @objc func removeLogin() {
        do { if FileManager.default.fileExists(atPath: loginURL.path) { try FileManager.default.removeItem(at: loginURL) }; status = "Start at login disabled" }
        catch { status = error.localizedDescription }; rebuild()
    }
    @objc func quit() { NSApp.terminate(nil) }
}
if CommandLine.arguments.contains("--self-test") {
    let data = Data(#"{"method":"getPilot","result":{"mac":"AA:BB:CC:DD:EE:FF","state":false}}"#.utf8)
    let r = parse(data, ip: "192.0.2.2")!
    let known = [Bulb(ip:r.ip, mac:r.mac)]
    assert(shouldRestore(r, bulbs: known, active:true))
    assert(!shouldRestore(r, bulbs: known, active:false))
    assert(!shouldRestore(Reply(ip:r.ip, mac:r.mac, state:true), bulbs:known, active:true))
    assert(!shouldRestore(Reply(ip:r.ip, mac:"111111111111", state:false), bulbs:known, active:true))
    assert(!shouldRestore(Reply(ip:"192.0.2.3", mac:r.mac, state:false), bulbs:known, active:true))
    assert(parse(Data(#"{"method":"getPilot","result":{"mac":"bad","state":false}}"#.utf8), ip:r.ip) == nil)
    assert(parse(Data(#"{"method":"setPilot","result":{"success":true}}"#.utf8), ip:r.ip) == nil)
    let lit = Reply(ip:r.ip, mac:r.mac, state:true, dimming:95, scene:15)
    assert(Adjustment.delta(10).parameters(for:lit)?["dimming"] as? Int == 100)
    assert(Adjustment.delta(-10).parameters(for:Reply(ip:r.ip, mac:r.mac, state:true, dimming:12))?["dimming"] as? Int == 10)
    assert(Adjustment.delta(10).parameters(for:r) == nil)
    assert(Adjustment.delta(10).parameters(for:Reply(ip:r.ip, mac:r.mac, state:true, dimming:100)) == nil)
    assert(Adjustment.scene(1).parameters(for:lit)?["dimming"] == nil)
    assert(Adjustment.delta(-10).parameters(for:lit)?["sceneId"] == nil)
    assert(Adjustment.scene(15).matches(lit, params:["sceneId":15]))
    assert(!Adjustment.scene(1).matches(lit, params:["sceneId":1]))
    let office = Room(id:UUID(), name:"Office"), lounge = Room(id:UUID(), name:"Lounge")
    var configuration = Configuration(rooms:[office,lounge], bulbs:[Bulb(ip:r.ip,mac:r.mac,roomID:office.id), Bulb(ip:"192.0.2.3",mac:"001122334455",roomID:lounge.id)], selectedRoom:office.id)
    assert(configuration.targets().count == 1 && configuration.targets()[0].mac == r.mac)
    configuration.selectedRoom = lounge.id
    assert(!shouldRestore(r, bulbs:configuration.targets(), active:true))
    configuration.selectedRoom = nil; assert(configuration.targets().isEmpty)
    assert(Configuration().targets().isEmpty && Configuration().paused)
    let roundTrip = try! JSONDecoder().decode(Configuration.self, from:JSONEncoder().encode(configuration))
    assert(roundTrip.rooms.count == 2 && roundTrip.bulbs.count == 2)
    try! roundTrip.validate()
    configuration.bulbs.append(configuration.bulbs[0])
    do { try configuration.validate(); assertionFailure("Duplicate identity accepted") } catch { }
    print("PASS: room isolation, empty setup, persistence, duplicate validation; scene/brightness isolation, bounds, missing brightness, verification; restoration gates, identity/address matching, malformed replies, already-on suppression")
} else {
    let app = NSApplication.shared; let controller = Controller()
    app.setActivationPolicy(.accessory); app.delegate = controller; app.run()
}
