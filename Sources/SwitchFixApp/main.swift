import AppKit
import UI

// SwitchFix - Menu bar app, no Dock icon
// LSUIElement behavior is set via Info.plist in the final .app bundle.
// For swift run, we set the activation policy programmatically.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
