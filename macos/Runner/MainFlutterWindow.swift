import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // iPad 2세대 논리 해상도 (1024 × 768)
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let screenFrame = screen.visibleFrame
    let windowWidth: CGFloat = 1024
    let windowHeight: CGFloat = 768
    let originX = screenFrame.midX - windowWidth / 2
    let originY = screenFrame.midY - windowHeight / 2
    let windowFrame = NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 800, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
