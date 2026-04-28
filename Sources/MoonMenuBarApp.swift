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
    private var isPressed = false

    private let iconSize: CGFloat = 17.0
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

    func configure(phase: MoonPhaseInfo, displayMode: DisplayMode) {
        self.phase = phase
        self.displayMode = displayMode
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
        let illumination = max(0.0, min(1.0, phase.illumination))
        let brightness = max(0.0, min(1.0, phase.relativeBrightness))
        let diskPath = NSBezierPath(ovalIn: rect)

        NSColor.white.withAlphaComponent(0.30).setFill()
        diskPath.fill()

        let sunObserverAngle = acos(max(-1.0, min(1.0, 2.0 * illumination - 1.0)))
        let side = phase.waxing ? 1.0 : -1.0
        let sunX = side * sin(sunObserverAngle)
        let sunZ = cos(sunObserverAngle)
        let litAlpha = CGFloat(0.42 + 0.58 * pow(brightness, 0.45))

        NSColor.white.withAlphaComponent(litAlpha).setFill()

        if abs(sunX) < 1.0e-8 {
            if sunZ > 0.0 {
                diskPath.fill()
            }
        } else {
            let steps = 96
            let halfWidth = rect.width * 0.5
            let halfHeight = rect.height * 0.5

            for row in 0..<steps {
                let y0 = -1.0 + 2.0 * CGFloat(row) / CGFloat(steps)
                let y1 = -1.0 + 2.0 * CGFloat(row + 1) / CGFloat(steps)
                let yMid = (y0 + y1) * 0.5
                let xEdge = sqrt(max(0.0, 1.0 - Double(yMid * yMid)))
                let boundarySign = -copysign(1.0, sunZ / sunX)
                let xBoundary = CGFloat(boundarySign * abs(sunZ) * xEdge)

                let xStartNorm: CGFloat
                let xEndNorm: CGFloat
                if sunX > 0.0 {
                    xStartNorm = max(xBoundary, -CGFloat(xEdge))
                    xEndNorm = CGFloat(xEdge)
                } else {
                    xStartNorm = -CGFloat(xEdge)
                    xEndNorm = min(xBoundary, CGFloat(xEdge))
                }

                guard xEndNorm > xStartNorm else { continue }

                let strip = NSRect(
                    x: rect.midX + xStartNorm * halfWidth,
                    y: rect.midY + y0 * halfHeight,
                    width: (xEndNorm - xStartNorm) * halfWidth,
                    height: (y1 - y0) * halfHeight + 0.5
                )
                NSBezierPath(rect: strip).fill()
            }
        }

        NSColor.white.withAlphaComponent(0.88).setStroke()
        diskPath.lineWidth = 1.0
        diskPath.stroke()
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
    private let loginAgentLabel = "com.local.moonmenubar.login"
    private let loginAgentFileName = "com.local.moonmenubar.login.plist"

    private var statusItem: NSStatusItem?
    private var statusView: MoonStatusView?
    private var timer: Timer?
    private let locationService = LocationService()
    private var currentLocation: LocationState?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let view = MoonStatusView(frame: NSRect(x: 0.0, y: 0.0, width: 68.0, height: NSStatusBar.system.thickness))
        view.statusItem = item
        view.toolTip = "달 위상 로딩 중..."
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
            statusView.configure(phase: phase, displayMode: displayMode)
            statusView.toolTip = "달 위상: \(phase.phaseName) / 상대 밝기: \(brightnessText)"
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

        addDisabledItem("현재 시각: \(dateFormatter.string(from: Date()))", to: menu)

        if let loc = currentLocation {
            addDisabledItem(
                String(format: "위치: %.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude),
                to: menu
            )
            let position = MoonPhaseCalculator.position(
                for: Date(),
                latitudeDeg: loc.coordinate.latitude,
                longitudeDeg: loc.coordinate.longitude
            )
            let visibility = position.isAboveHorizon ? "보임" : "지평선 아래"
            addDisabledItem(String(format: "현재 고도: %+.1f° (%@)", position.altitudeDeg, visibility), to: menu)
            addDisabledItem(
                String(format: "현재 방향: %@ (%.1f°)", position.compassDirection, position.azimuthDeg),
                to: menu
            )
        } else {
            addDisabledItem("위치: 확인 중...", to: menu)
            addDisabledItem("현재 고도: 위치 확인 중...", to: menu)
            addDisabledItem("현재 방향: 위치 확인 중...", to: menu)
        }

        addDisabledItem("위상: \(phase.phaseName)", to: menu)
        addDisabledItem("조명률: \(illuminationText)", to: menu)
        addDisabledItem("상대 밝기: \(brightnessText) (보름달=100%)", to: menu)

        menu.addItem(NSMenuItem.separator())

        let iconOnlyItem = NSMenuItem(title: "아이콘만 표시", action: #selector(setIconOnlyMode), keyEquivalent: "")
        iconOnlyItem.target = self
        iconOnlyItem.state = displayMode == .iconOnly ? .on : .off
        menu.addItem(iconOnlyItem)

        let iconBrightnessItem = NSMenuItem(title: "아이콘 + 밝기% 표시", action: #selector(setIconAndBrightnessMode), keyEquivalent: "")
        iconBrightnessItem.target = self
        iconBrightnessItem.state = displayMode == .iconAndBrightness ? .on : .off
        menu.addItem(iconBrightnessItem)

        let loginItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "새로고침", action: #selector(updateStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "종료", action: #selector(quitApp), keyEquivalent: "q")
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

    @objc private func setIconOnlyMode() {
        displayMode = .iconOnly
        updateStatus()
    }

    @objc private func setIconAndBrightnessMode() {
        displayMode = .iconAndBrightness
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
                title: "먼저 Applications로 옮기세요",
                message: "DMG 안에서 실행한 앱은 다음 로그인 때 사라질 수 있습니다.\nMoonMenuBar.app을 Applications 폴더로 옮긴 뒤 다시 켜세요."
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
            showAlert(title: "자동 실행 설정 실패", message: error.localizedDescription)
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
