import AppKit
import Core
import UI
import Utils

// SwitchFix - Menu bar app (LSUIElement = true, no Dock icon)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
