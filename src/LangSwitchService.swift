import Cocoa
import Carbon

class LangSwitchService {
    static let shared = LangSwitchService()
    
    func switchKeyboardLanguage() {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else {
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: [LangSwitch] Failed to copy current keyboard language.")
            }
            return
        }
        
        let inputSources = getInputSources()
        guard !inputSources.isEmpty else {
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: [LangSwitch] No input sources found.")
            }
            return
        }
        
        guard let currentIndex = inputSources.firstIndex(where: { $0 == currentSource }) else {
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: [LangSwitch] Current source not found in input sources list.")
            }
            return
        }
        
        let nextIndex = (currentIndex + 1) % inputSources.count
        let nextSource = inputSources[nextIndex]
        
        TISSelectInputSource(nextSource)
        
        if UserDefaults.standard.bool(forKey: "debugMode") {
            if let prop = TISGetInputSourceProperty(nextSource, kTISPropertyLocalizedName) {
                let newSourceName = Unmanaged<CFString>.fromOpaque(prop).takeUnretainedValue() as String
                print("DEBUG: [LangSwitch] Switched to: \(newSourceName)")
            }
        }
    }
    
    private func getInputSources() -> [TISInputSource] {
        guard let inputSourceNSArray = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? NSArray else {
            return[]
        }
        var inputSourceList = inputSourceNSArray as! [TISInputSource]
        
        inputSourceList = inputSourceList.filter({
            $0.category == TISInputSource.Category.keyboardInputSource
        })
        
        let inputSources = inputSourceList.filter({
            $0.isSelectable
        })
        
        return inputSources
    }
}

extension TISInputSource {
    enum Category {
        static var keyboardInputSource: String {
            return kTISCategoryKeyboardInputSource as String
        }
    }
    
    private func getProperty(_ key: CFString) -> AnyObject? {
        let cfType = TISGetInputSourceProperty(self, key)
        if (cfType != nil) {
            return Unmanaged<AnyObject>.fromOpaque(cfType!)
                .takeUnretainedValue()
        } else {
            return nil
        }
    }
    
    var category: String {
        return getProperty(kTISPropertyInputSourceCategory) as? String ?? ""
    }
    
    var isSelectable: Bool {
        return getProperty(kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false
    }
}