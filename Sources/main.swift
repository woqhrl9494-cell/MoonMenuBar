import Cocoa

let app = NSApplication.shared
let delegate = ClairDeLuneApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
