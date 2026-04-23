import Foundation

struct SearchService {
    /// Generic Smart Search (AND-logic for includes, boolean exclusion)
    static func smartFilter<T>(_ items: [T], query: String, valueProvider: (T) -> String) -> [T] {
        guard !query.isEmpty else { return items }
        
        let terms = query.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let excludeTerms = terms.filter { $0.hasPrefix("-") && $0.count > 1 }.map { String($0.dropFirst()) }
        let includeTerms = terms.filter { !$0.hasPrefix("-") || $0.count == 1 }
        
        if includeTerms.isEmpty && excludeTerms.isEmpty { return items }
        
        return items.filter { item in
            let content = valueProvider(item).lowercased()
            
            if !includeTerms.isEmpty {
                let matchesAll = includeTerms.allSatisfy { content.contains($0) }
                if !matchesAll { return false }
            }
            
            if !excludeTerms.isEmpty {
                let matchesExclude = excludeTerms.contains { content.contains($0) }
                if matchesExclude { return false }
            }
            
            return true
        }
    }
}