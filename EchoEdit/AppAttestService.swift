//
//  AppAttestService.swift
//  EchoEdit
//
//  Created by Claude on 7/4/25.
//

import Foundation
import DeviceCheck
import CryptoKit

@MainActor
class AppAttestService: ObservableObject {
    @Published var isAttested = false
    @Published var isInitializing = false
    @Published var errorMessage: String?
    
    private let keyID = "EchoEdit_Device_Key"
    private let attestationKey = "app_attest_keyid"
    private let attestationStatusKey = "app_attest_status"
    
    // MARK: - Initialization
    
    init() {
        checkAttestationStatus()
    }
    
    private func checkAttestationStatus() {
        // Check if we have a stored keyID and attestation status
        if let storedKeyID = UserDefaults.standard.string(forKey: attestationKey),
           UserDefaults.standard.bool(forKey: attestationStatusKey) {
            isAttested = true
            print("✅ App Attest: Device already attested with keyID: \(storedKeyID)")
        } else {
            print("⚠️ App Attest: Device not yet attested")
        }
    }
    
    // MARK: - App Attest Flow
    
    func performInitialAttestation() async throws {
        guard DCAppAttestService.shared.isSupported else {
            throw AppAttestError.notSupported
        }
        
        isInitializing = true
        errorMessage = nil
        
        defer {
            isInitializing = false
        }
        
        do {
            // Step 1: Generate key
            let keyID = try await DCAppAttestService.shared.generateKey()
            print("🔑 App Attest: Generated keyID: \(keyID)")
            
            // Step 2: Get nonce from backend
            let nonce = try await getNonceFromBackend()
            print("🎲 App Attest: Received nonce from backend")
            
            // Step 3: Create client data hash
            let clientDataHash = createClientDataHash(nonce: nonce)
            
            // Step 4: Generate attestation
            let attestation = try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
            print("📄 App Attest: Generated attestation")
            
            // Step 5: Send to backend for verification
            try await sendAttestationToBackend(
                keyID: keyID,
                attestation: attestation,
                clientDataHash: clientDataHash
            )
            
            // Step 6: Store successful attestation
            UserDefaults.standard.set(keyID, forKey: attestationKey)
            UserDefaults.standard.set(true, forKey: attestationStatusKey)
            
            isAttested = true
            print("✅ App Attest: Device successfully attested")
            
        } catch {
            print("❌ App Attest: Attestation failed: \(error)")
            errorMessage = "Device attestation failed: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Request Signing
    
    func generateAssertion(for requestData: Data) async throws -> (keyID: String, assertion: Data, clientDataHash: Data) {
        guard let keyID = UserDefaults.standard.string(forKey: attestationKey),
              isAttested else {
            throw AppAttestError.notAttested
        }
        
        // Create client data hash from request data
        let clientDataHash = SHA256.hash(data: requestData)
        let clientDataHashData = Data(clientDataHash)
        
        // Generate assertion
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHashData)
        
        return (keyID: keyID, assertion: assertion, clientDataHash: clientDataHashData)
    }
    
    // MARK: - Helper Methods
    
    private func createClientDataHash(nonce: String) -> Data {
        let clientData = [
            "nonce": nonce,
            "bundleID": Bundle.main.bundleIdentifier ?? "stevenstrange.EchoEdit",
            "timestamp": String(Int(Date().timeIntervalSince1970))
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: clientData) else {
            return Data()
        }
        
        let hash = SHA256.hash(data: jsonData)
        return Data(hash)
    }
    
    private func getNonceFromBackend() async throws -> String {
        guard let url = URL(string: "\(AppConfig.workerURL)/attest/nonce") else {
            throw AppAttestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Add the required app token header
        request.setValue(AppConfig.appToken, forHTTPHeaderField: "X-App-Token")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppAttestError.backendError
        }
        
        if httpResponse.statusCode != 200 {
            print("❌ App Attest: Nonce request failed with status: \(httpResponse.statusCode)")
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? String {
                print("❌ App Attest: Backend error: \(error)")
            }
            throw AppAttestError.backendError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nonce = json["nonce"] as? String else {
            throw AppAttestError.invalidResponse
        }
        
        return nonce
    }
    
    private func sendAttestationToBackend(keyID: String, attestation: Data, clientDataHash: Data) async throws {
        guard let url = URL(string: "\(AppConfig.workerURL)/attest/verify") else {
            throw AppAttestError.invalidURL
        }
        
        let requestBody = [
            "keyID": keyID,
            "attestation": attestation.base64EncodedString(),
            "clientDataHash": clientDataHash.base64EncodedString()
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Add the required app token header
        request.setValue(AppConfig.appToken, forHTTPHeaderField: "X-App-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppAttestError.attestationFailed
        }
        
        if httpResponse.statusCode != 200 {
            print("❌ App Attest: Verify request failed with status: \(httpResponse.statusCode)")
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? String {
                print("❌ App Attest: Backend error: \(error)")
            }
            throw AppAttestError.attestationFailed
        }
    }
    
    // MARK: - Public Interface
    
    func ensureAttested() async throws {
        if !isAttested {
            try await performInitialAttestation()
        }
    }
    
    func getStoredKeyID() -> String? {
        return UserDefaults.standard.string(forKey: attestationKey)
    }
    
    func reset() {
        UserDefaults.standard.removeObject(forKey: attestationKey)
        UserDefaults.standard.removeObject(forKey: attestationStatusKey)
        isAttested = false
        print("🔄 App Attest: Reset attestation status")
    }
}

// MARK: - Error Types

enum AppAttestError: LocalizedError {
    case notSupported
    case notAttested
    case invalidURL
    case backendError
    case invalidResponse
    case attestationFailed
    
    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "App Attest is not supported on this device"
        case .notAttested:
            return "Device is not attested"
        case .invalidURL:
            return "Invalid backend URL"
        case .backendError:
            return "Backend communication error"
        case .invalidResponse:
            return "Invalid response from backend"
        case .attestationFailed:
            return "Attestation verification failed"
        }
    }
}