//
//  ContentFilter.swift
//  TextTune
//
//  Created by Claude on 7/2/25.
//

import Foundation

class ContentFilter {
    private var bannedWords: Set<String> = []
    
    // List of language codes for banned word files
    private let languageCodes = ["ar", "cs", "da", "en", "eo", "es", "fa", "fi", "fil", "fr", "hi", "hu", "it", "ja", "kab", "ko", "nl", "no", "pl", "pt", "ru", "sv", "th", "tlh", "tr", "zh"]
    
    init() {
        loadBannedWords()
    }
    
    private func loadBannedWords() {
        var loadedFiles = 0
        
        // Try to load each language file from the bundle
        for languageCode in languageCodes {
            if let filePath = Bundle.main.path(forResource: languageCode, ofType: nil, inDirectory: "Banned") {
                loadWordsFromFile(filePath)
                loadedFiles += 1
            } else if let filePath = Bundle.main.path(forResource: languageCode, ofType: "") {
                // Fallback: try to find the file without specifying directory
                loadWordsFromFile(filePath)
                loadedFiles += 1
            }
        }
        
        // If no files were loaded from bundle, try loading from project directory
        if loadedFiles == 0 {
            loadFromProjectDirectory()
        }
        
        print("ContentFilter: Loaded \(bannedWords.count) banned words from \(loadedFiles) language files")
    }
    
    private func loadFromProjectDirectory() {
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let bannedWordsDirectory = currentDirectory + "/Banned"
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: bannedWordsDirectory)
            
            for file in files {
                // Skip hidden files and directories
                if file.hasPrefix(".") { continue }
                
                let filePath = bannedWordsDirectory + "/" + file
                
                // Check if it's a file (not a directory)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory), !isDirectory.boolValue {
                    loadWordsFromFile(filePath)
                }
            }
        } catch {
            print("ContentFilter Error: Failed to load banned words from project directory: \(error)")
            // As a final fallback, load some common banned words
            loadFallbackWords()
        }
    }
    
    private func loadWordsFromFile(_ filePath: String) {
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty {
                    // Convert to lowercase for case-insensitive matching
                    bannedWords.insert(trimmedLine.lowercased())
                }
            }
        } catch {
            print("ContentFilter Error: Failed to load file \(filePath): \(error)")
        }
    }
    
    private func loadFallbackWords() {
        // Load a basic set of common banned words as fallback
        let fallbackWords = [
            "explicit", "nsfw", "nude", "naked", "porn", "sex", "sexual", "adult",
            "offensive", "inappropriate", "violence", "gore", "bloody"
        ]
        
        for word in fallbackWords {
            bannedWords.insert(word.lowercased())
        }
        
        print("ContentFilter: Loaded \(fallbackWords.count) fallback banned words")
    }
    
    /// Check if the given text contains any banned words
    /// - Parameter text: The text to check
    /// - Returns: true if banned words are found, false otherwise
    func containsBannedWords(_ text: String) -> Bool {
        let lowercaseText = text.lowercased()
        
        // Check for exact word matches and partial matches
        for bannedWord in bannedWords {
            if lowercaseText.contains(bannedWord) {
                print("ContentFilter: Found banned word '\(bannedWord)' in text")
                return true
            }
        }
        
        return false
    }
    
    /// Get a list of banned words found in the text
    /// - Parameter text: The text to check
    /// - Returns: Array of banned words found
    func findBannedWords(in text: String) -> [String] {
        let lowercaseText = text.lowercased()
        var foundWords: [String] = []
        
        for bannedWord in bannedWords {
            if lowercaseText.contains(bannedWord) {
                foundWords.append(bannedWord)
            }
        }
        
        return foundWords
    }
}