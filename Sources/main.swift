import Cocoa

let app = NSApplication.shared
let delegate = MoonMenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
