//
//  FluxKontextService.swift
//  TextTune
//
//  Created by Steven Strange on 6/13/25.
//

import Foundation
import UIKit

// MARK: - API Models
struct FluxKontextRequest: Codable {
    let prompt: String
    let inputImage: String?
    let seed: Int?
    let aspectRatio: String?
    let outputFormat: String
    let promptUpsampling: Bool
    let safetyTolerance: Int
    
    enum CodingKeys: String, CodingKey {
        case prompt
        case inputImage = "input_image"
        case seed
        case aspectRatio = "aspect_ratio"
        case outputFormat = "output_format"
        case promptUpsampling = "prompt_upsampling"
        case safetyTolerance = "safety_tolerance"
    }
}

struct FluxKontextResponse: Codable {
    let id: String
    let pollingURL: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case pollingURL = "polling_url"
    }
}

struct FluxKontextResultResponse: Codable {
    let status: String
    let imageBase64: String?
    let result: ResultData?
    let id: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case imageBase64 = "image_base64"
        case result
        case id
    }
}

struct ResultData: Codable {
    let sample: String?
    let prompt: String?
    let seed: Int?
    let startTime: Double?
    let endTime: Double?
    let duration: Double?
    
    enum CodingKeys: String, CodingKey {
        case sample
        case prompt
        case seed
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
    }
}

// MARK: - API Service Errors
enum FluxKontextError: Error {
    case invalidURL
    case invalidResponse
    case encodingError
    case decodingError
    case networkError(Error)
    case apiError(String)
    case imageDecodingError
    case pollingTimeout
}

// MARK: - API Service Protocol
protocol FluxKontextService {
    func generateImage(
        prompt: String,
        inputImage: String?,
        seed: Int?,
        aspectRatio: String?
    ) async throws -> FluxKontextResponse
    
    func pollForResult(pollingURL: String) async throws -> UIImage
}

// MARK: - Flux Kontext Max Service
class FluxKontextMaxService: FluxKontextService {
    // MARK: - Properties
    private let baseURL = "https://api.bfl.ai/v1/flux-kontext-max"
    private let apiKey = "562db9a5-e02d-4a27-a73f-71843216a1a7" // Replace with actual API key
    private let session = URLSession.shared
    private let maxPollingAttempts = 30 // ~5 minutes with 10-second intervals
    
    // MARK: - Public Methods
    
    /// Generate an image using the Flux Kontext Max API
    /// - Parameters:
    ///   - prompt: Text prompt for image generation
    ///   - inputImage: Optional base64-encoded image for image-to-image generation
    ///   - seed: Optional seed for reproducibility
    ///   - aspectRatio: Optional aspect ratio (e.g., "16:9")
    /// - Returns: Response with polling URL
    func generateImage(
        prompt: String,
        inputImage: String? = nil,
        seed: Int? = nil,
        aspectRatio: String? = nil
    ) async throws -> FluxKontextResponse {
        
        // Create the request body
        let requestBody = FluxKontextRequest(
            prompt: prompt,
            inputImage: inputImage,
            seed: seed,
            aspectRatio: aspectRatio,
            outputFormat: "jpeg",
            promptUpsampling: false,
            safetyTolerance: 2
        )
        
        // Create the request
        guard let url = URL(string: baseURL) else {
            throw FluxKontextError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-key")
        
        // Encode and set the request body
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw FluxKontextError.encodingError
        }
        
        // Make the request
        do {
            let (data, response) = try await session.data(for: request)
            
            // Verify response code
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FluxKontextError.invalidResponse
            }
            
            // Check for successful response
            if httpResponse.statusCode == 200 {
                do {
                    return try JSONDecoder().decode(FluxKontextResponse.self, from: data)
                } catch {
                    throw FluxKontextError.decodingError
                }
            } else {
                // Handle API error
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw FluxKontextError.apiError(errorMessage)
            }
        } catch let error as FluxKontextError {
            throw error
        } catch {
            throw FluxKontextError.networkError(error)
        }
    }
    
    /// Poll the API for the result of an image generation request
    /// - Parameter pollingURL: URL to poll for results
    /// - Returns: The generated UIImage
    func pollForResult(pollingURL: String) async throws -> UIImage {
        guard let url = URL(string: pollingURL) else {
            print("❌ Invalid polling URL: \(pollingURL)")
            throw FluxKontextError.invalidURL
        }
        
        print("🔄 Starting to poll URL: \(pollingURL)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-key")
        
        var attemptCount = 0
        
        while attemptCount < maxPollingAttempts {
            do {
                print("🔄 Poll attempt #\(attemptCount+1)...")
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response")
                    throw FluxKontextError.invalidResponse
                }
                
                print("📡 HTTP Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Print raw response for debugging
                    if let responseStr = String(data: data, encoding: .utf8) {
                        print("📄 Response data: \(responseStr)")
                    }
                    
                    // Parse the response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String {
                        
                        print("✅ Status: \(status)")
                        
                        // Check for "Ready" status with sample URL
                        if status == "Ready",
                           let result = json["result"] as? [String: Any],
                           let sampleURL = result["sample"] as? String {
                            
                            print("🎉 Image ready! Downloading from URL: \(sampleURL)")
                            
                            // Download the image from the sample URL
                            guard let imageURL = URL(string: sampleURL) else {
                                print("❌ Invalid sample URL")
                                throw FluxKontextError.invalidURL
                            }
                            
                            var imageRequest = URLRequest(url: imageURL)
                            imageRequest.httpMethod = "GET"
                            
                            let (imageData, imageResponse) = try await session.data(for: imageRequest)
                            guard let httpImageResponse = imageResponse as? HTTPURLResponse, 
                                  httpImageResponse.statusCode == 200 else {
                                print("❌ Failed to download image: HTTP \((imageResponse as? HTTPURLResponse)?.statusCode ?? 0)")
                                throw FluxKontextError.networkError(NSError(domain: "Image download failed", code: 0))
                            }
                            
                            guard let image = UIImage(data: imageData) else {
                                print("❌ Failed to create image from downloaded data")
                                throw FluxKontextError.imageDecodingError
                            }
                            
                            print("✅ Successfully downloaded image: \(image.size.width)x\(image.size.height)")
                            return image
                        }
                        // Fall back to original "completed" status with base64 data
                        else if status == "completed",
                                let imageBase64 = json["image_base64"] as? String {
                            
                            print("🎉 Image generation completed with base64 data!")
                            guard let imageData = Data(base64Encoded: imageBase64) else {
                                print("❌ Failed to decode base64 image data")
                                throw FluxKontextError.imageDecodingError
                            }
                            
                            guard let image = UIImage(data: imageData) else {
                                print("❌ Failed to create UIImage from data")
                                throw FluxKontextError.imageDecodingError
                            }
                            
                            print("✅ Successfully created image: \(image.size.width)x\(image.size.height)")
                            return image
                        }
                        else if status == "failed" {
                            print("❌ API reported generation failed")
                            throw FluxKontextError.apiError("Image generation failed")
                        }
                        else {
                            // Status is still processing, wait and try again
                            print("⏳ Status: \(status) - waiting 10 seconds before next poll...")
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                            attemptCount += 1
                        }
                    } else {
                        print("❌ Failed to parse JSON response")
                        throw FluxKontextError.decodingError
                    }
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ API error (HTTP \(httpResponse.statusCode)): \(errorMessage)")
                    throw FluxKontextError.apiError(errorMessage)
                }
            } catch let error as FluxKontextError {
                print("❌ Flux error during polling: \(error)")
                throw error
            } catch {
                print("❌ Network error during polling: \(error)")
                throw FluxKontextError.networkError(error)
            }
        }
        
        print("❌ MaxService: Polling timeout after \(maxPollingAttempts) attempts")
        throw FluxKontextError.pollingTimeout
    }
    
    // Debug information method
    func getServiceInfo() -> String {
        return "FluxKontextMaxService - URL: \(baseURL)"
    }
}

// MARK: - Flux Kontext Pro Service
class FluxKontextProService: FluxKontextService {
    // MARK: - Properties
    private let baseURL = "https://api.bfl.ai/v1/flux-kontext-pro"
    private let apiKey = "562db9a5-e02d-4a27-a73f-71843216a1a7" // Using same API key for now
    private let session = URLSession.shared
    private let maxPollingAttempts = 30 // ~5 minutes with 10-second intervals
    
    // MARK: - Public Methods
    
    /// Generate an image using the Flux Kontext Pro API
    /// - Parameters:
    ///   - prompt: Text prompt for image generation
    ///   - inputImage: Optional base64-encoded image for image-to-image generation
    ///   - seed: Optional seed for reproducibility
    ///   - aspectRatio: Optional aspect ratio (e.g., "16:9")
    /// - Returns: Response with polling URL
    func generateImage(
        prompt: String,
        inputImage: String? = nil,
        seed: Int? = nil,
        aspectRatio: String? = nil
    ) async throws -> FluxKontextResponse {
        
        // Create the request body
        let requestBody = FluxKontextRequest(
            prompt: prompt,
            inputImage: inputImage,
            seed: seed,
            aspectRatio: aspectRatio,
            outputFormat: "jpeg",
            promptUpsampling: false,
            safetyTolerance: 2
        )
        
        // Create the request
        guard let url = URL(string: baseURL) else {
            throw FluxKontextError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-key")
        
        // Encode and set the request body
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw FluxKontextError.encodingError
        }
        
        // Make the request
        do {
            let (data, response) = try await session.data(for: request)
            
            // Verify response code
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FluxKontextError.invalidResponse
            }
            
            // Check for successful response
            if httpResponse.statusCode == 200 {
                do {
                    return try JSONDecoder().decode(FluxKontextResponse.self, from: data)
                } catch {
                    throw FluxKontextError.decodingError
                }
            } else {
                // Handle API error
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw FluxKontextError.apiError(errorMessage)
            }
        } catch let error as FluxKontextError {
            throw error
        } catch {
            throw FluxKontextError.networkError(error)
        }
    }
    
    /// Poll the API for the result of an image generation request
    /// - Parameter pollingURL: URL to poll for results
    /// - Returns: The generated UIImage
    func pollForResult(pollingURL: String) async throws -> UIImage {
        guard let url = URL(string: pollingURL) else {
            print("❌ Invalid polling URL: \(pollingURL)")
            throw FluxKontextError.invalidURL
        }
        
        print("🔄 Starting to poll URL: \(pollingURL)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-key")
        
        var attemptCount = 0
        
        while attemptCount < maxPollingAttempts {
            do {
                print("🔄 Poll attempt #\(attemptCount+1)...")
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response")
                    throw FluxKontextError.invalidResponse
                }
                
                print("📡 HTTP Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Print raw response for debugging
                    if let responseStr = String(data: data, encoding: .utf8) {
                        print("📄 Response data: \(responseStr)")
                    }
                    
                    // Parse the response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String {
                        
                        print("✅ Status: \(status)")
                        
                        // Check for "Ready" status with sample URL
                        if status == "Ready",
                           let result = json["result"] as? [String: Any],
                           let sampleURL = result["sample"] as? String {
                            
                            print("🎉 Image ready! Downloading from URL: \(sampleURL)")
                            
                            // Download the image from the sample URL
                            guard let imageURL = URL(string: sampleURL) else {
                                print("❌ Invalid sample URL")
                                throw FluxKontextError.invalidURL
                            }
                            
                            var imageRequest = URLRequest(url: imageURL)
                            imageRequest.httpMethod = "GET"
                            
                            let (imageData, imageResponse) = try await session.data(for: imageRequest)
                            guard let httpImageResponse = imageResponse as? HTTPURLResponse, 
                                  httpImageResponse.statusCode == 200 else {
                                print("❌ Failed to download image: HTTP \((imageResponse as? HTTPURLResponse)?.statusCode ?? 0)")
                                throw FluxKontextError.networkError(NSError(domain: "Image download failed", code: 0))
                            }
                            
                            guard let image = UIImage(data: imageData) else {
                                print("❌ Failed to create image from downloaded data")
                                throw FluxKontextError.imageDecodingError
                            }
                            
                            print("✅ Successfully downloaded image: \(image.size.width)x\(image.size.height)")
                            return image
                        }
                        // Fall back to original "completed" status with base64 data
                        else if status == "completed",
                                let imageBase64 = json["image_base64"] as? String {
                            
                            print("🎉 Image generation completed with base64 data!")
                            guard let imageData = Data(base64Encoded: imageBase64) else {
                                print("❌ Failed to decode base64 image data")
                                throw FluxKontextError.imageDecodingError
                            }
                            
                            guard let image = UIImage(data: imageData) else {
                                print("❌ Failed to create UIImage from data")
                                throw FluxKontextError.imageDecodingError
                            }
                            
                            print("✅ Successfully created image: \(image.size.width)x\(image.size.height)")
                            return image
                        }
                        else if status == "failed" {
                            print("❌ API reported generation failed")
                            throw FluxKontextError.apiError("Image generation failed")
                        }
                        else {
                            // Status is still processing, wait and try again
                            print("⏳ Status: \(status) - waiting 10 seconds before next poll...")
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                            attemptCount += 1
                        }
                    } else {
                        print("❌ Failed to parse JSON response")
                        throw FluxKontextError.decodingError
                    }
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ API error (HTTP \(httpResponse.statusCode)): \(errorMessage)")
                    throw FluxKontextError.apiError(errorMessage)
                }
            } catch let error as FluxKontextError {
                print("❌ Flux error during polling: \(error)")
                throw error
            } catch {
                print("❌ Network error during polling: \(error)")
                throw FluxKontextError.networkError(error)
            }
        }
        
        print("❌ ProService: Polling timeout after \(maxPollingAttempts) attempts")
        throw FluxKontextError.pollingTimeout
    }
    
    // Debug information method
    func getServiceInfo() -> String {
        return "FluxKontextProService - URL: \(baseURL)"
    }
}
