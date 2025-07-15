//
//  NetworkHelper.swift
//  EchoEdit
//
//  Network utilities for handling QUIC/HTTP3 issues
//  Created by Steven Strange on 6/26/25.
//

import Foundation

class NetworkHelper {
    static func createSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 120.0
        config.waitsForConnectivity = true
        
        // Force HTTP/2 instead of HTTP/3 to avoid QUIC packet size issues with large payloads
        config.httpAdditionalHeaders = [
            "Connection": "keep-alive",
            "Accept": "application/json",
            "Alt-Svc": ""  // Disable HTTP/3 alternative service discovery
        ]
        config.networkServiceType = .default
        config.allowsCellularAccess = true
        config.httpShouldUsePipelining = false
        config.httpMaximumConnectionsPerHost = 1  // Force single connection to avoid QUIC
        
        // Use HTTP/1.1 by default to avoid any HTTP/3 issues
        config.httpCookieAcceptPolicy = .always
        
        return URLSession(configuration: config)
    }
    
    static func makeRequestWithRetry<T: Codable>(
        session: URLSession,
        request: URLRequest,
        responseType: T.Type,
        maxRetries: Int = 3
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                print("🌐 Making request to: \(request.url?.absoluteString ?? "unknown") (attempt \(attempt))")
                print("📱 Request headers: \(request.allHTTPHeaderFields ?? [:])")
                
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response")
                    throw SecureFluxError.invalidResponse
                }
                
                print("📡 Response status: \(httpResponse.statusCode)")
                
                switch httpResponse.statusCode {
                case 200:
                    do {
                        return try JSONDecoder().decode(T.self, from: data)
                    } catch {
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
                print("🚨 SecureFluxError: \(error)")
                throw error
            } catch {
                lastError = error
                print("🌐 Network error on attempt \(attempt): \(error)")
                if let urlError = error as? URLError {
                    print("🌐 URLError code: \(urlError.code.rawValue)")
                    // Only retry on connection lost errors (-1005)
                    if urlError.code.rawValue == -1005 && attempt < maxRetries {
                        print("🔄 Retrying in 2 seconds...")
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                }
                throw SecureFluxError.networkError(error)
            }
        }
        
        // If we get here, all retries failed
        if let lastError = lastError {
            throw SecureFluxError.networkError(lastError)
        } else {
            throw SecureFluxError.networkError(NSError(domain: "Unknown", code: 0))
        }
    }
}