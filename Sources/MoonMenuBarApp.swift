import Cocoa
import CoreLocation
import Darwin

private enum DisplayMode: String {
    case iconOnly
    case iconAndBrightness
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
        surfaceStyle: MoonSurfaceStyle
    ) {
        self.phase = phase
        self.displayMode = displayMode
        self.iconColor = iconColor
        self.surfaceStyle = surfaceStyle
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
        drawMoon(in: iconRect, phase: phase)

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

final class MoonMenuBarApp: NSObject, NSApplicationDelegate {
    private let displayModeKey = "displayMode"
    private let iconColorKey = "iconColor"
    private let surfaceStyleKey = "surfaceStyle"
    private let loginAgentLabel = "com.local.moonmenubar.login"
    private let loginAgentFileName = "com.local.moonmenubar.login.plist"

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
            let raw = UserDefaults.standard.string(forKey: displayModeKey)
            return DisplayMode(rawValue: raw ?? "") ?? .iconAndBrightness
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: displayModeKey)
        }
    }

    private var iconColor: MoonIconColor {
        get {
            let raw = UserDefaults.standard.string(forKey: iconColorKey)
            return MoonIconColor(rawValue: raw ?? "") ?? .white
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: iconColorKey)
        }
    }

    private var surfaceStyle: MoonSurfaceStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: surfaceStyleKey)
            return MoonSurfaceStyle(rawValue: raw ?? "") ?? .none
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: surfaceStyleKey)
        }
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

        let tz = currentLocation?.timeZone ?? .current
        let phase = MoonPhaseCalculator.phase(for: Date(), timeZone: tz)
        let illuminationText = String(format: "%.1f%%", phase.illumination * 100.0)
        let brightnessText = String(format: "%.1f%%", phase.relativeBrightness * 100.0)

        if let statusView {
            statusView.configure(
                phase: phase,
                displayMode: displayMode,
                iconColor: iconColor,
                surfaceStyle: surfaceStyle
            )
            statusView.toolTip = "Moon phase: \(phase.phaseName) / Relative brightness: \(brightnessText)"
            statusView.frame.size = NSSize(width: statusView.preferredWidth, height: NSStatusBar.system.thickness)
            item.length = statusView.preferredWidth
        }

        item.menu = makeMenu(
            phase: phase,
            illuminationText: illuminationText,
            brightnessText: brightnessText
        )
    }

    private func makeMenu(
        phase: MoonPhaseInfo,
        illuminationText: String,
        brightnessText: String
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        addDisabledItem("Current time: \(dateFormatter.string(from: Date()))", to: menu)

        if let loc = currentLocation {
            addDisabledItem(
                String(format: "Location: %.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude),
                to: menu
            )
            let position = MoonPhaseCalculator.position(
                for: Date(),
                latitudeDeg: loc.coordinate.latitude,
                longitudeDeg: loc.coordinate.longitude
            )
            let visibility = position.isAboveHorizon ? "visible" : "below horizon"
            addDisabledItem(String(format: "Current altitude: %+.1f° (%@)", position.altitudeDeg, visibility), to: menu)
            addDisabledItem(
                String(format: "Current direction: %@ (%.1f°)", position.compassDirection, position.azimuthDeg),
                to: menu
            )
        } else {
            addDisabledItem("Location: Waiting...", to: menu)
            addDisabledItem("Current altitude: Waiting for location...", to: menu)
            addDisabledItem("Current direction: Waiting for location...", to: menu)
        }

        addDisabledItem("Phase: \(phase.phaseName)", to: menu)
        addDisabledItem("Illumination: \(illuminationText)", to: menu)
        addDisabledItem("Relative brightness: \(brightnessText) (Full Moon=100%)", to: menu)

        menu.addItem(NSMenuItem.separator())

        let iconOnlyItem = NSMenuItem(title: "Show icon only", action: #selector(setIconOnlyMode), keyEquivalent: "")
        iconOnlyItem.target = self
        iconOnlyItem.state = displayMode == .iconOnly ? .on : .off
        menu.addItem(iconOnlyItem)

        let iconBrightnessItem = NSMenuItem(title: "Show icon + brightness %", action: #selector(setIconAndBrightnessMode), keyEquivalent: "")
        iconBrightnessItem.target = self
        iconBrightnessItem.state = displayMode == .iconAndBrightness ? .on : .off
        menu.addItem(iconBrightnessItem)

        menu.addItem(NSMenuItem.separator())
        addIconColorMenu(to: menu)
        addSurfaceStyleMenu(to: menu)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

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

    @objc private func setIconOnlyMode() {
        displayMode = .iconOnly
        updateStatus()
    }

    @objc private func setIconAndBrightnessMode() {
        displayMode = .iconAndBrightness
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

    @objc private func toggleLoginItem() {
        if isLoginItemEnabled() {
            disableLoginItem()
        } else {
            enableLoginItem()
        }
        updateStatus()
    }

    private func enableLoginItem() {
        let appPath = Bundle.main.bundlePath
        if appPath.hasPrefix("/Volumes/") {
            showAlert(
                title: "Move to Applications first",
                message: "Apps launched from inside a DMG may not be available at the next login.\nMove MoonMenuBar.app to the Applications folder, then reopen it."
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
    }

    private func isLoginItemEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: loginAgentURL),
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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
