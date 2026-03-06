import Foundation
import SwiftData

@Model
final class TranscriptionEntry {
    var timestamp: Date
    var rawText: String
    var filteredText: String?
    var dictionaryCorrectedText: String?
    var cleanedText: String?
    var appName: String?
    var appBundleIdentifier: String?
    var windowTitle: String?
    var surroundingText: String?
    var filterRan: Bool
    var dictionaryRan: Bool
    var llmRan: Bool

    var displayText: String {
        cleanedText ?? dictionaryCorrectedText ?? filteredText ?? rawText
    }

    init(timestamp: Date, rawText: String, filteredText: String? = nil,
         dictionaryCorrectedText: String? = nil, cleanedText: String? = nil,
         appName: String? = nil, appBundleIdentifier: String? = nil,
         windowTitle: String? = nil, surroundingText: String? = nil,
         filterRan: Bool = false, dictionaryRan: Bool = false, llmRan: Bool = false) {
        self.timestamp = timestamp
        self.rawText = rawText
        self.filteredText = filteredText
        self.dictionaryCorrectedText = dictionaryCorrectedText
        self.cleanedText = cleanedText
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.windowTitle = windowTitle
        self.surroundingText = surroundingText
        self.filterRan = filterRan
        self.dictionaryRan = dictionaryRan
        self.llmRan = llmRan
    }
}

@Model
final class DictionaryWord {
    @Attribute(.unique) var word: String
    var source: String
    var dateAdded: Date

    init(word: String, source: DictionarySource = .manual, dateAdded: Date = .now) {
        self.word = word
        self.source = source.rawValue
        self.dateAdded = dateAdded
    }

    var sourceType: DictionarySource {
        DictionarySource(rawValue: source) ?? .manual
    }
}

enum DictionarySource: String, Codable {
    case manual
    case learned
}
