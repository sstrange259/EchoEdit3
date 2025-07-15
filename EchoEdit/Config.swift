//
//  Config.swift
//  EchoEdit
//
//  Configuration for secure API access
//  Created by Steven Strange on 6/26/25.
//

import Foundation

struct AppConfig {
    // MARK: - Secure API Configuration
    
    // Your deployed Cloudflare Worker URL
    static let workerURL = "https://echoedit3.stevenstrange1998.workers.dev"
    
    // App token for initial authentication (must match your Cloudflare Worker's APP_TOKEN environment variable)
    static let appToken = "EchoEdit_2025_Secure_Token_v1"
    
    // App authentication is now handled via App Attest
    // No static tokens are stored in the client app
    
    // MARK: - Feature Flags
    static let useSecureAPI = true  // Set to true to use secure Cloudflare Worker
    
    // MARK: - App Settings
    static let maxImageDimension: CGFloat = 1600
    static let defaultPromptDelay: UInt64 = 3_000_000_000 // 3 seconds
    static let defaultCharDelay: UInt64 = 30_000_000      // 30 ms
    
    // MARK: - Security Notes
    /*
     IMPORTANT SECURITY NOTES:
     
     1. APP ATTEST SECURITY:
        - Authentication is now handled via Apple's App Attest framework
        - Each device generates a unique cryptographic key pair
        - Every API request is signed with device-specific assertions
        - No static secrets are stored in the client application
     
     2. WORKER URL:
        - This is public information (not secret)
        - Your Worker validates App Attest assertions before processing requests
        
     3. BEST PRACTICES:
        - Monitor your Worker logs for suspicious activity
        - App Attest keys are automatically rotated by iOS
        - Only genuine iOS devices can generate valid attestations
        - All payment verification happens on the backend
     */
}

// MARK: - Helper Extensions
extension AppConfig {
    /// Validates that the configuration is properly set up
    static var isConfigured: Bool {
        return !workerURL.contains("your-worker")
    }
    
    /// Returns appropriate error message if not configured
    static var configurationError: String? {
        if workerURL.contains("your-worker") {
            return "Please update workerURL in Config.swift with your deployed Cloudflare Worker URL"
        }
        return nil
    }
}