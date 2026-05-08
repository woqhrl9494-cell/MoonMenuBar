import Cocoa
import CoreLocation
import Darwin

private enum DisplayMode: String, CaseIterable {
    case iconOnly
    case iconAndBrightness

    var menuTitle: String {
        switch self {
        case .iconOnly:
            return "Show icon only"
        case .iconAndBrightness:
            return "Show icon + brightness %"
        }
    }
}

private enum AltitudeIconMode: String, CaseIterable {
    case disabled
    case hideBelowHorizon
    case peekBelowHorizon

    var menuTitle: String {
        switch self {
        case .disabled:
            return "Ignore moon altitude"
        case .hideBelowHorizon:
            return "Use altitude, hide below horizon"
        case .peekBelowHorizon:
            return "Use altitude, peek below horizon"
        }
    }

    var usesAltitude: Bool {
        self != .disabled
    }
}

private final class MenuInfoItemView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        let font = NSFont.menuFont(ofSize: 0.0)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        super.init(frame: NSRect(x: 0.0, y: 0.0, width: ceil(textSize.width) + 28.0, height: 22.0))

        label.stringValue = title
        label.font = font
        label.textColor = NSColor.labelColor.withAlphaComponent(0.78)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14.0),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14.0),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class MoonStatusView: NSView {
    weak var statusItem: NSStatusItem?

    private var phase: MoonPhaseInfo?
    private var displayMode: DisplayMode = .iconAndBrightness
    private var iconColor: MoonIconColor = .white
    private var surfaceStyle: MoonSurfaceStyle = .none
    private var altitudeTrack: MoonAltitudeTrackInfo?
    private var altitudeIconMode: AltitudeIconMode = .disabled
    private var isPressed = false

    private let iconSize: CGFloat = 18.0
    private let sidePadding: CGFloat = 0.5
    private let textGap: CGFloat = 6.0

    private var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .semibold),
            .foregroundColor: NSColor.white,
            .shadow: textShadow
        ]
    }

    private var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 1.0
        shadow.shadowOffset = NSSize(width: 0.0, height: -1.0)
        return shadow
    }

    private var brightnessLabel: String {
        guard let phase else { return "" }
        return String(format: "%.0f%%", phase.relativeBrightness * 100.0)
    }

    var preferredWidth: CGFloat {
        if displayMode == .iconOnly {
            return sidePadding * 2.0 + iconSize
        }

        let textWidth = (brightnessLabel as NSString).size(withAttributes: textAttributes).width
        return sidePadding * 2.0 + iconSize + textGap + ceil(textWidth)
    }

    func configure(
        phase: MoonPhaseInfo,
        displayMode: DisplayMode,
        iconColor: MoonIconColor,
        surfaceStyle: MoonSurfaceStyle,
        altitudeTrack: MoonAltitudeTrackInfo?,
        altitudeIconMode: AltitudeIconMode
    ) {
        self.phase = phase
        self.displayMode = displayMode
        self.iconColor = iconColor
        self.surfaceStyle = surfaceStyle
        self.altitudeTrack = altitudeTrack
        self.altitudeIconMode = altitudeIconMode
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isPressed {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: 4.0, yRadius: 4.0).fill()
        }

        guard let phase else { return }

        let iconRect = NSRect(
            x: sidePadding,
            y: floor((bounds.height - iconSize) * 0.5),
            width: iconSize,
            height: iconSize
        )
        if let resolvedIconRect = resolvedMoonRect(from: iconRect) {
            drawMoon(in: resolvedIconRect, phase: phase)
        }

        if displayMode == .iconAndBrightness {
            let text = brightnessLabel as NSString
            let textSize = text.size(withAttributes: textAttributes)
            let textOrigin = NSPoint(
                x: iconRect.maxX + textGap,
                y: floor((bounds.height - textSize.height) * 0.5) + 1.0
            )
            text.draw(at: textOrigin, withAttributes: textAttributes)
        }
    }

    private func resolvedMoonRect(from centeredRect: NSRect) -> NSRect? {
        guard altitudeIconMode.usesAltitude else {
            return centeredRect
        }

        guard let altitudeTrack else {
            return centeredRect
        }

        guard altitudeTrack.isAboveHorizon || altitudeIconMode == .peekBelowHorizon else {
            return nil
        }

        // Altitude mode maps the horizon to a 20%-visible icon and the current
        // 20 deg altitude threshold to the same centered placement as normal mode.
        let fraction = CGFloat(max(0.0, min(1.0, altitudeTrack.altitudeFraction)))
        let minimumVisibleFraction = CGFloat(MoonPhaseCalculator.minimumAltitudeIconVisibleFraction)
        let lowestY = -iconSize * (1.0 - minimumVisibleFraction)
        let peakY = floor((bounds.height - iconSize) * 0.5)
        let y = lowestY + (peakY - lowestY) * fraction

        return NSRect(
            x: centeredRect.origin.x,
            y: y,
            width: centeredRect.width,
            height: centeredRect.height
        )
    }

    private func drawMoon(in rect: NSRect, phase: MoonPhaseInfo) {
        let image = MoonIconRenderer.image(
            pointSize: iconSize,
            illumination: phase.illumination,
            relativeBrightness: phase.relativeBrightness,
            waxing: phase.waxing,
            color: iconColor,
            surfaceStyle: surfaceStyle
        )
        image.draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true

        if let statusItem, let menu = statusItem.menu {
            statusItem.popUpMenu(menu)
        }

        isPressed = false
        needsDisplay = true
    }
}

final class ClairDeLuneApp: NSObject, NSApplicationDelegate {
    private let legacyDefaultsSuiteName = "com.local.moonmenubar"
    private let displayModeKey = "displayMode"
    private let iconColorKey = "iconColor"
    private let surfaceStyleKey = "surfaceStyle"
    private let altitudeIconModeKey = "altitudeIconMode"
    private let legacyBelowHorizonIconPolicyKey = "belowHorizonIconPolicy"
    private let loginAgentLabel = "com.local.clairdelune.login"
    private let loginAgentFileName = "com.local.clairdelune.login.plist"
    private let legacyLoginAgentFileName = "com.local.moonmenubar.login.plist"

    private var statusItem: NSStatusItem?
    private var statusView: MoonStatusView?
    private var timer: Timer?
    private let locationService = LocationService()
    private var currentLocation: LocationState?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var displayMode: DisplayMode {
        get {
            let raw = storedString(forKey: displayModeKey)
            if raw == "altitudeIcon" {
                return .iconOnly
            }
            return DisplayMode(rawValue: raw ?? "") ?? .iconAndBrightness
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: displayModeKey)
        }
    }

    private var iconColor: MoonIconColor {
        get {
            let raw = storedString(forKey: iconColorKey)
            return MoonIconColor(rawValue: raw ?? "") ?? .white
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: iconColorKey)
        }
    }

    private var surfaceStyle: MoonSurfaceStyle {
        get {
            let raw = storedString(forKey: surfaceStyleKey)
            if raw == "realCrater" {
                return .craters
            }
            return MoonSurfaceStyle(rawValue: raw ?? "") ?? .none
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: surfaceStyleKey)
        }
    }

    private var altitudeIconMode: AltitudeIconMode {
        get {
            let raw = storedString(forKey: altitudeIconModeKey)
            if let mode = AltitudeIconMode(rawValue: raw ?? "") {
                return mode
            }

            let legacyDisplayMode = storedString(forKey: displayModeKey)
            guard legacyDisplayMode == "altitudeIcon" else {
                return .disabled
            }

            let legacyPolicy = storedString(forKey: legacyBelowHorizonIconPolicyKey)
            let migratedMode: AltitudeIconMode = legacyPolicy == "peek" ? .peekBelowHorizon : .hideBelowHorizon
            UserDefaults.standard.set(DisplayMode.iconOnly.rawValue, forKey: displayModeKey)
            UserDefaults.standard.set(migratedMode.rawValue, forKey: altitudeIconModeKey)
            return migratedMode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: altitudeIconModeKey)
        }
    }

    private var legacyDefaults: UserDefaults? {
        UserDefaults(suiteName: legacyDefaultsSuiteName)
    }

    private func storedString(forKey key: String) -> String? {
        if let value = UserDefaults.standard.string(forKey: key) {
            return value
        }

        guard let value = legacyDefaults?.string(forKey: key) else {
            return nil
        }

        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let view = MoonStatusView(frame: NSRect(x: 0.0, y: 0.0, width: 68.0, height: NSStatusBar.system.thickness))
        view.statusItem = item
        view.toolTip = "Loading Moon phase..."
        statusView = view
        item.view = view
        item.isVisible = true

        locationService.start { [weak self] state in
            guard let self else { return }
            self.currentLocation = state
            self.updateStatus()
        }

        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        locationService.stop()
    }

    @objc private func updateStatus() {
        guard let item = statusItem else { return }

        let now = Date()
        let tz = currentLocation?.timeZone ?? .current
        let phase = MoonPhaseCalculator.phase(for: now, timeZone: tz)
        let illuminationText = String(format: "%.1f%%", phase.illumination * 100.0)
        let brightnessText = String(format: "%.1f%%", phase.relativeBrightness * 100.0)
        var position: MoonPositionInfo?
        var altitudeTrack: MoonAltitudeTrackInfo?

        if let loc = currentLocation {
            position = MoonPhaseCalculator.position(
                for: now,
                latitudeDeg: loc.coordinate.latitude,
                longitudeDeg: loc.coordinate.longitude
            )
            altitudeTrack = MoonPhaseCalculator.altitudeTrack(
                for: now,
                latitudeDeg: loc.coordinate.latitude,
                longitudeDeg: loc.coordinate.longitude
            )
        }

        if let statusView {
            statusView.configure(
                phase: phase,
                displayMode: displayMode,
                iconColor: iconColor,
                surfaceStyle: surfaceStyle,
                altitudeTrack: altitudeTrack,
                altitudeIconMode: altitudeIconMode
            )
            statusView.toolTip = statusToolTip(
                phase: phase,
                brightnessText: brightnessText,
                altitudeTrack: altitudeTrack
            )
            statusView.frame.size = NSSize(width: statusView.preferredWidth, height: NSStatusBar.system.thickness)
            item.length = statusView.preferredWidth
        }

        item.menu = makeMenu(
            phase: phase,
            illuminationText: illuminationText,
            brightnessText: brightnessText,
            now: now,
            position: position,
            altitudeTrack: altitudeTrack
        )
    }

    private func makeMenu(
        phase: MoonPhaseInfo,
        illuminationText: String,
        brightnessText: String,
        now: Date,
        position: MoonPositionInfo?,
        altitudeTrack: MoonAltitudeTrackInfo?
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        addDisabledItem("Current time: \(dateFormatter.string(from: now))", to: menu)

        if let loc = currentLocation {
            addDisabledItem(
                String(format: "Location: %.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude),
                to: menu
            )
            if let position {
                let visibility = position.isAboveHorizon ? "visible" : "below horizon"
                addDisabledItem(String(format: "Current altitude: %+.1f° (%@)", position.altitudeDeg, visibility), to: menu)
                addDisabledItem(
                    String(format: "Current direction: %@ (%.1f°)", position.compassDirection, position.azimuthDeg),
                    to: menu
                )
            }

            if altitudeIconMode == .disabled {
                addDisabledItem("Altitude icon mode: ignored", to: menu)
            } else if let altitudeTrack {
                if altitudeTrack.isAboveHorizon, let peakDate = altitudeTrack.peakDate {
                    let altitudeFractionText = String(format: "%.0f%%", altitudeTrack.altitudeFraction * 100.0)
                    let visibleFractionText = String(format: "%.0f%%", altitudeTrack.visibleFraction * 100.0)
                    addDisabledItem(
                        String(format: "Current pass peak: %+.1f° at %@", altitudeTrack.peakAltitudeDeg, dateFormatter.string(from: peakDate)),
                        to: menu
                    )
                    addDisabledItem(String(format: "Altitude icon center threshold: %.0f°", MoonPhaseCalculator.altitudeIconCenterAltitudeDeg), to: menu)
                    addDisabledItem("Altitude progress: \(altitudeFractionText) toward center", to: menu)
                    addDisabledItem("Altitude icon height: \(visibleFractionText) (min 20%)", to: menu)
                } else {
                    let visibleFractionText = String(format: "%.0f%%", altitudeTrack.visibleFraction * 100.0)
                    addDisabledItem("Altitude progress: below horizon", to: menu)
                    if altitudeIconMode == .peekBelowHorizon {
                        addDisabledItem("Altitude icon height: \(visibleFractionText) (peek below horizon)", to: menu)
                    } else {
                        addDisabledItem("Altitude icon height: hidden below horizon", to: menu)
                    }
                }
            } else {
                addDisabledItem("Altitude icon height: Waiting for location...", to: menu)
            }
        } else {
            addDisabledItem("Location: Waiting...", to: menu)
            addDisabledItem("Current altitude: Waiting for location...", to: menu)
            addDisabledItem("Current direction: Waiting for location...", to: menu)
            addDisabledItem("Altitude icon height: Waiting for location...", to: menu)
        }

        addDisabledItem("Phase: \(phase.phaseName)", to: menu)
        addDisabledItem("Illumination: \(illuminationText)", to: menu)
        addDisabledItem("Relative brightness: \(brightnessText) (Full Moon=100%)", to: menu)

        menu.addItem(NSMenuItem.separator())

        addMenuBarContentMenu(to: menu)
        addAltitudeIconModeMenu(to: menu)

        menu.addItem(NSMenuItem.separator())
        addIconColorMenu(to: menu)
        addSurfaceStyleMenu(to: menu)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Clair de Lune", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(updateStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addDisabledItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = MenuInfoItemView(title: title)
        item.isEnabled = false
        menu.addItem(item)
    }

    private func statusToolTip(
        phase: MoonPhaseInfo,
        brightnessText: String,
        altitudeTrack: MoonAltitudeTrackInfo?
    ) -> String {
        var parts = [
            "Moon phase: \(phase.phaseName)",
            "Relative brightness: \(brightnessText)"
        ]

        if altitudeIconMode == .disabled {
            parts.append("Altitude icon: ignored")
        } else if let altitudeTrack {
            if altitudeTrack.isAboveHorizon {
                let altitudeFractionText = String(format: "%.0f%%", altitudeTrack.altitudeFraction * 100.0)
                let visibleFractionText = String(format: "%.0f%%", altitudeTrack.visibleFraction * 100.0)
                parts.append(String(format: "Altitude: %+.1f° / center %.0f° (progress %@, icon %@)", altitudeTrack.currentAltitudeDeg, MoonPhaseCalculator.altitudeIconCenterAltitudeDeg, altitudeFractionText, visibleFractionText))
            } else {
                let visibleFractionText = String(format: "%.0f%%", altitudeTrack.visibleFraction * 100.0)
                if altitudeIconMode == .peekBelowHorizon {
                    parts.append(String(format: "Altitude: %+.1f° (below horizon, icon %@)", altitudeTrack.currentAltitudeDeg, visibleFractionText))
                } else {
                    parts.append(String(format: "Altitude: %+.1f° (below horizon, icon hidden)", altitudeTrack.currentAltitudeDeg))
                }
            }
        } else if altitudeIconMode.usesAltitude {
            parts.append("Altitude: waiting for location")
        }

        return parts.joined(separator: " / ")
    }

    private func addIconColorMenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Moon color", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for color in MoonIconColor.allCases {
            let item = NSMenuItem(title: color.menuTitle, action: #selector(setIconColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color.rawValue
            item.state = iconColor == color ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addMenuBarContentMenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Menu bar content", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = displayMode == mode ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addAltitudeIconModeMenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Moon altitude", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for mode in AltitudeIconMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(setAltitudeIconMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = altitudeIconMode == mode ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addSurfaceStyleMenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Moon shape", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for style in MoonSurfaceStyle.allCases {
            let item = NSMenuItem(title: style.menuTitle, action: #selector(setSurfaceStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = surfaceStyle == style ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = DisplayMode(rawValue: rawValue)
        else {
            return
        }

        displayMode = mode
        updateStatus()
    }

    @objc private func setIconColor(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let color = MoonIconColor(rawValue: rawValue)
        else {
            return
        }

        iconColor = color
        updateStatus()
    }

    @objc private func setSurfaceStyle(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = MoonSurfaceStyle(rawValue: rawValue)
        else {
            return
        }

        surfaceStyle = style
        updateStatus()
    }

    @objc private func setAltitudeIconMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = AltitudeIconMode(rawValue: rawValue)
        else {
            return
        }

        altitudeIconMode = mode
        updateStatus()
    }

    @objc private func toggleLoginItem() {
        if isLoginItemEnabled() {
            disableLoginItem()
        } else {
            enableLoginItem()
        }
        updateStatus()
    }

    private func enableLoginItem() {
        removeLegacyLoginItem()

        let appPath = Bundle.main.bundlePath
        if appPath.hasPrefix("/Volumes/") {
            showAlert(
                title: "Move to Applications first",
                message: "Apps launched from inside a DMG may not be available at the next login.\nMove Clair de Lune.app to the Applications folder, then reopen it."
            )
            return
        }

        let agentURL = loginAgentURL
        try? FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload: [String: Any] = [
            "Label": loginAgentLabel,
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
        } catch {
            showAlert(title: "Failed to configure launch at login", message: error.localizedDescription)
        }
    }

    private func disableLoginItem() {
        unloadLaunchAgent()
        try? FileManager.default.removeItem(at: loginAgentURL)
        removeLegacyLoginItem()
    }

    private func isLoginItemEnabled() -> Bool {
        if isLoginItemEnabled(at: loginAgentURL) {
            return true
        }
        return isLoginItemEnabled(at: legacyLoginAgentURL)
    }

    private func isLoginItemEnabled(at agentURL: URL) -> Bool {
        guard
            let data = try? Data(contentsOf: agentURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any],
            let args = dict["ProgramArguments"] as? [String],
            args.count >= 2
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: args[1])
    }

    private var loginAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(loginAgentFileName)
    }

    private var legacyLoginAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(legacyLoginAgentFileName)
    }

    private func removeLegacyLoginItem() {
        runLaunchctl(["bootout", "gui/\(getuid())", legacyLoginAgentURL.path])
        runLaunchctl(["unload", legacyLoginAgentURL.path])
        try? FileManager.default.removeItem(at: legacyLoginAgentURL)
    }

    private func unloadLaunchAgent() {
        runLaunchctl(["bootout", "gui/\(getuid())", loginAgentURL.path])
        runLaunchctl(["unload", loginAgentURL.path])
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func showAlert(title: String, message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return "Version unavailable"
        }
    }

    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clair de Lune"
        alert.informativeText = "\(appVersionText)\nCreated by Jaebok Lee\nok7393@hanyang.ac.kr"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
