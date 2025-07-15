//
//  SecureFluxService.swift
//  EchoEdit
//
//  Secure API service using Cloudflare Worker proxy
//  Created by Steven Strange on 6/26/25.
//

import Foundation
import UIKit
import StoreKit

// MARK: - Secure API Models
struct SecureFluxRequest: Codable {
    let prompt: String
    let inputImage: String?
    let seed: Int?
    let aspectRatio: String?
}

struct SecureFluxResponse: Codable {
    let id: String
    let polling_url: String
}

struct SecureFluxResult: Codable {
    let status: String
    let result: SecureResultData?
}

struct SecureResultData: Codable {
    let sample: String?
}

// MARK: - Secure Service Errors
enum SecureFluxError: Error {
    case invalidURL
    case invalidResponse
    case encodingError
    case decodingError
    case networkError(Error)
    case apiError(String)
    case imageDecodingError
    case pollingTimeout
    case unauthorized
    case rateLimited
    case attestationRequired
    case attestationFailed
}

// MARK: - Secure Service Protocol
protocol SecureFluxService {
    func generateImage(
        prompt: String,
        inputImage: String?,
        seed: Int?,
        aspectRatio: String?
    ) async throws -> SecureFluxResponse
    
    func pollForResult(pollingURL: String) async throws -> UIImage
}

// MARK: - Secure Flux Pro Service
class SecureFluxProService: SecureFluxService {
    private let workerBaseURL: String
    private let session: URLSession
    private let maxPollingAttempts = 9
    private let appAttestService: AppAttestService
    
    init(workerURL: String, appAttestService: AppAttestService) {
        self.workerBaseURL = workerURL
        self.appAttestService = appAttestService
        self.session = NetworkHelper.createSession()
    }
    
    func generateImage(
        prompt: String,
        inputImage: String? = nil,
        seed: Int? = nil,
        aspectRatio: String? = nil
    ) async throws -> SecureFluxResponse {
        
        // Ensure device is attested
        try await appAttestService.ensureAttested()
        
        guard let url = URL(string: "\(workerBaseURL)/generate-pro") else {
            throw SecureFluxError.invalidURL
        }
        
        let requestBody = SecureFluxRequest(
            prompt: prompt,
            inputImage: inputImage,
            seed: seed,
            aspectRatio: aspectRatio
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add current transaction data for subscription verification
        if let transactionData = await getCurrentTransactionData() {
            print("📄 SecureFlux: Adding transaction data to request")
            request.addValue(transactionData, forHTTPHeaderField: "X-Transaction-Data")
        } else {
            print("⚠️ SecureFlux: No valid transaction data available - this may cause authentication issues")
        }
        
        // Add App Attest headers
        try await addAppAttestHeaders(to: &request, requestBody: requestBody)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw SecureFluxError.encodingError
        }
        
        return try await NetworkHelper.makeRequestWithRetry(
            session: session,
            request: request,
            responseType: SecureFluxResponse.self
        )
    }
    
    func pollForResult(pollingURL: String) async throws -> UIImage {
        let encodedURL = pollingURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pollingURL
        
        guard let url = URL(string: "\(workerBaseURL)/poll/\(encodedURL)") else {
            throw SecureFluxError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add App Attest headers for polling
        try await addAppAttestHeaders(to: &request, requestBody: nil)
        
        var attemptCount = 0
        
        while attemptCount < maxPollingAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SecureFluxError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String {
                        
                        if status == "Ready",
                           let result = json["result"] as? [String: Any],
                           let sampleURL = result["sample"] as? String {
                            
                            return try await downloadImage(from: sampleURL)
                        }
                        else if status == "failed" {
                            throw SecureFluxError.apiError("Image generation failed")
                        }
                        else {
                            // Still processing, wait and retry
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                            attemptCount += 1
                        }
                    } else {
                        throw SecureFluxError.decodingError
                    }
                case 401:
                    throw SecureFluxError.unauthorized
                case 429:
                    throw SecureFluxError.rateLimited
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw SecureFluxError.apiError(errorMessage)
                }
            } catch let error as SecureFluxError {
                throw error
            } catch {
                throw SecureFluxError.networkError(error)
            }
        }
        
        throw SecureFluxError.pollingTimeout
    }
    
    private func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw SecureFluxError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SecureFluxError.networkError(NSError(domain: "Image download failed", code: 0))
        }
        
        guard let image = UIImage(data: data) else {
            throw SecureFluxError.imageDecodingError
        }
        
        return image
    }
    
    func getServiceInfo() -> String {
        return "SecureFluxProService - Worker URL: \(workerBaseURL)"
    }
    
    private func addAppAttestHeaders(to request: inout URLRequest, requestBody: SecureFluxRequest?) async throws {
        // Create request data for signing
        var requestData = Data()
        if let body = requestBody {
            requestData = try JSONEncoder().encode(body)
        } else {
            requestData = request.url?.absoluteString.data(using: .utf8) ?? Data()
        }
        
        // Generate assertion
        let (keyID, assertion, clientDataHash) = try await appAttestService.generateAssertion(for: requestData)
        
        // Add headers
        request.addValue(keyID, forHTTPHeaderField: "X-Key-ID")
        request.addValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Assertion")
        request.addValue(clientDataHash.base64EncodedString(), forHTTPHeaderField: "X-Client-Data-Hash")
    }
}

// MARK: - Secure Flux Max Service
class SecureFluxMaxService: SecureFluxService {
    private let workerBaseURL: String
    private let session: URLSession
    private let maxPollingAttempts = 9
    private let appAttestService: AppAttestService
    
    init(workerURL: String, appAttestService: AppAttestService) {
        self.workerBaseURL = workerURL
        self.appAttestService = appAttestService
        self.session = NetworkHelper.createSession()
    }
    
    func generateImage(
        prompt: String,
        inputImage: String? = nil,
        seed: Int? = nil,
        aspectRatio: String? = nil
    ) async throws -> SecureFluxResponse {
        
        // Ensure device is attested
        try await appAttestService.ensureAttested()
        
        guard let url = URL(string: "\(workerBaseURL)/generate-max") else {
            throw SecureFluxError.invalidURL
        }
        
        let requestBody = SecureFluxRequest(
            prompt: prompt,
            inputImage: inputImage,
            seed: seed,
            aspectRatio: aspectRatio
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add current transaction data for subscription verification
        if let transactionData = await getCurrentTransactionData() {
            print("📄 SecureFlux: Adding transaction data to request")
            request.addValue(transactionData, forHTTPHeaderField: "X-Transaction-Data")
        } else {
            print("⚠️ SecureFlux: No valid transaction data available - this may cause authentication issues")
        }
        
        // Add App Attest headers
        try await addAppAttestHeaders(to: &request, requestBody: requestBody)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw SecureFluxError.encodingError
        }
        
        return try await NetworkHelper.makeRequestWithRetry(
            session: session,
            request: request,
            responseType: SecureFluxResponse.self
        )
    }
    
    func pollForResult(pollingURL: String) async throws -> UIImage {
        let encodedURL = pollingURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pollingURL
        
        guard let url = URL(string: "\(workerBaseURL)/poll/\(encodedURL)") else {
            throw SecureFluxError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add App Attest headers for polling
        try await addAppAttestHeaders(to: &request, requestBody: nil)
        
        var attemptCount = 0
        
        while attemptCount < maxPollingAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SecureFluxError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String {
                        
                        if status == "Ready",
                           let result = json["result"] as? [String: Any],
                           let sampleURL = result["sample"] as? String {
                            
                            return try await downloadImage(from: sampleURL)
                        }
                        else if status == "failed" {
                            throw SecureFluxError.apiError("Image generation failed")
                        }
                        else {
                            // Still processing, wait and retry
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                            attemptCount += 1
                        }
                    } else {
                        throw SecureFluxError.decodingError
                    }
                case 401:
                    throw SecureFluxError.unauthorized
                case 429:
                    throw SecureFluxError.rateLimited
                default:
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw SecureFluxError.apiError(errorMessage)
                }
            } catch let error as SecureFluxError {
                throw error
            } catch {
                throw SecureFluxError.networkError(error)
            }
        }
        
        throw SecureFluxError.pollingTimeout
    }
    
    private func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw SecureFluxError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SecureFluxError.networkError(NSError(domain: "Image download failed", code: 0))
        }
        
        guard let image = UIImage(data: data) else {
            throw SecureFluxError.imageDecodingError
        }
        
        return image
    }
    
    func getServiceInfo() -> String {
        return "SecureFluxMaxService - Worker URL: \(workerBaseURL)"
    }
    
    private func addAppAttestHeaders(to request: inout URLRequest, requestBody: SecureFluxRequest?) async throws {
        // Create request data for signing
        var requestData = Data()
        if let body = requestBody {
            requestData = try JSONEncoder().encode(body)
        } else {
            requestData = request.url?.absoluteString.data(using: .utf8) ?? Data()
        }
        
        // Generate assertion
        let (keyID, assertion, clientDataHash) = try await appAttestService.generateAssertion(for: requestData)
        
        // Add headers
        request.addValue(keyID, forHTTPHeaderField: "X-Key-ID")
        request.addValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Assertion")
        request.addValue(clientDataHash.base64EncodedString(), forHTTPHeaderField: "X-Client-Data-Hash")
    }
}

// MARK: - Helper Functions
private func getCurrentTransactionData() async -> String? {
    do {
        print("🔍 SecureFlux: Starting transaction data collection...")
        var activeTransactions: [String] = []
        
        // Check all current entitlements
        var entitlementCount = 0
        for await result in Transaction.currentEntitlements {
            entitlementCount += 1
            print("🔍 SecureFlux: Processing entitlement #\(entitlementCount)")
            
            do {
                let transaction = try await checkVerified(result)
                print("🔍 SecureFlux: Transaction - ID: \(transaction.productID), Type: \(transaction.productType)")
                
                let transactionData: [String: Any] = [
                    "productId": transaction.productID,
                    "transactionId": String(transaction.id),
                    "originalTransactionId": String(transaction.originalID),
                    "purchaseDate": transaction.purchaseDate.timeIntervalSince1970,
                    "expirationDate": transaction.expirationDate?.timeIntervalSince1970 ?? 0,
                    "productType": transaction.productType == .autoRenewable ? "autoRenewable" : 
                                  transaction.productType == .nonConsumable ? "nonConsumable" : "other",
                    "isActive": !transaction.isUpgraded
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: transactionData),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    activeTransactions.append(jsonString)
                    print("✅ SecureFlux: Added transaction: \(transaction.productID)")
                }
            } catch {
                print("❌ SecureFlux: Failed to verify transaction: \(error)")
            }
        }
        
        print("🔍 SecureFlux: Found \(entitlementCount) total entitlements, \(activeTransactions.count) valid transactions")
        
        if !activeTransactions.isEmpty {
            let combinedData = ["transactions": activeTransactions]
            if let jsonData = try? JSONSerialization.data(withJSONObject: combinedData) {
                print("✅ SecureFlux: Successfully gathered transaction data (\(activeTransactions.count) transactions)")
                return jsonData.base64EncodedString()
            }
        }
        
        print("⚠️ SecureFlux: No active transactions found")
        return nil
        
    } catch {
        print("❌ SecureFlux: Failed to get transaction data: \(error)")
        return nil
    }
}

private func checkVerified<T>(_ result: VerificationResult<T>) async throws -> T {
    switch result {
    case .unverified:
        throw SecureFluxError.unauthorized
    case .verified(let safe):
        return safe
    }
}