import CoreGraphics

struct ParsedToAction {
    let keyCode: CGKeyCode
    let coreFlags: CGEventFlags
}

struct ParsedKeyMap {
    let original: KeyMap
    let fromKeyCode: CGKeyCode
    let fromCoreFlags: CGEventFlags
    let fromStrictFlags: [String]
    let isShell: Bool
    let shellCommand: String?
    let isFunc: Bool
    let funcCommand: String?
    let toActions: [ParsedToAction]
}

struct ParsedPCModeRule {
    let rule: PCModeRule
    let mappings: [ParsedKeyMap]
}