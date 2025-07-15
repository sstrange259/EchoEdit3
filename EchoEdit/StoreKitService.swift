import Foundation
import StoreKit
import SwiftUI

@MainActor
class StoreKitService: ObservableObject {
    @Published var subscriptionStatus: SubscriptionStatus = .unknown
    @Published var credits: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var subscriptionProduct: Product?
    private var creditsProduct: Product?
    private var updateListenerTask: Task<Void, Error>?
    private let appAttestService: AppAttestService
    
    enum SubscriptionStatus {
        case unknown
        case notSubscribed
        case subscribed
        case expired
    }
    
    let subscriptionProductID = "echoedit.monthly.subscription"
    let creditsProductID = "echoedit.credits.25pack"
    
    init(appAttestService: AppAttestService) {
        self.appAttestService = appAttestService
        updateListenerTask = listenForTransactions()
        Task {
            await requestProducts()
            await updateSubscriptionStatus()
            // Skip backend update for now since App Attest is failing
            // await updateCreditsFromBackend()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try await self?.checkVerified(result)
                    guard let transaction = transaction else { continue }
                    
                    // Update on main actor
                    await MainActor.run {
                        guard let self = self else { return }
                        Task {
                            await self.updateSubscriptionStatus()
                            await self.updateCreditsFromBackend()
                        }
                    }
                    
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    private func requestProducts() async {
        do {
            print("🛍️ StoreKit: Requesting products for IDs: \([subscriptionProductID, creditsProductID])")
            print("🛍️ StoreKit: StoreKit.canMakePayments = \(StoreKit.AppStore.canMakePayments)")
            
            let products = try await Product.products(for: [subscriptionProductID, creditsProductID])
            print("🛍️ StoreKit: Retrieved \(products.count) products")
            
            if products.isEmpty {
                print("❌ StoreKit: No products returned! Check if StoreKit configuration is properly set in scheme")
            }
            
            for product in products {
                print("🛍️ StoreKit: Found product - ID: \(product.id), Name: \(product.displayName), Price: \(product.displayPrice)")
                switch product.id {
                case subscriptionProductID:
                    self.subscriptionProduct = product
                case creditsProductID:
                    self.creditsProduct = product
                default:
                    break
                }
            }
            
            if subscriptionProduct == nil {
                print("❌ StoreKit: Subscription product not found!")
            }
            if creditsProduct == nil {
                print("❌ StoreKit: Credits product not found!")
            }
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("❌ StoreKit: Failed to request products: \(error)")
        }
    }
    
    func purchaseSubscription() async {
        print("🛍️ StoreKit: Purchase subscription requested")
        guard let product = subscriptionProduct else {
            errorMessage = "Subscription product not available"
            print("❌ StoreKit: No subscription product available")
            return
        }
        
        print("🛍️ StoreKit: Starting purchase for product: \(product.id)")
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            print("🛍️ StoreKit: Purchase result received")
            
            switch result {
            case .success(let verification):
                print("✅ StoreKit: Purchase successful")
                let transaction = try await checkVerified(verification)
                await updateSubscriptionStatus()
                
                // Award credits for subscription (100 credits per month)
                if transaction.productID == subscriptionProductID {
                    print("🎉 StoreKit: Awarding 100 credits for subscription")
                    self.credits += 100
                }
                
                await transaction.finish()
                
            case .userCancelled:
                print("🛍️ StoreKit: Purchase cancelled by user")
                break
                
            case .pending:
                print("⏳ StoreKit: Purchase pending approval")
                errorMessage = "Purchase is pending approval"
                
            @unknown default:
                print("❌ StoreKit: Unknown purchase result")
                errorMessage = "Unknown purchase result"
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("❌ StoreKit: Purchase failed: \(error)")
        }
        
        isLoading = false
    }
    
    func purchaseCredits() async {
        guard let product = creditsProduct else {
            errorMessage = "Credits product not available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try await checkVerified(verification)
                
                // Award credits for one-time purchase (25 credits)
                if transaction.productID == creditsProductID {
                    print("🎉 StoreKit: Awarding 25 credits for one-time purchase")
                    self.credits += 25
                }
                
                await transaction.finish()
                
            case .userCancelled:
                break
                
            case .pending:
                errorMessage = "Purchase is pending approval"
                
            @unknown default:
                errorMessage = "Unknown purchase result"
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("Purchase failed: \(error)")
        }
        
        isLoading = false
    }
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            await updateCreditsFromBackend()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            print("Failed to restore purchases: \(error)")
        }
        
        isLoading = false
    }
    
    private func updateSubscriptionStatus() async {
        guard let subscriptionProduct = subscriptionProduct else { return }
        
        do {
            let statuses = try await subscriptionProduct.subscription?.status ?? []
            
            for status in statuses {
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    subscriptionStatus = .subscribed
                    return
                case .expired, .revoked:
                    subscriptionStatus = .expired
                    return
                default:
                    break
                }
            }
            
            subscriptionStatus = .notSubscribed
        } catch {
            print("Failed to check subscription status: \(error)")
            subscriptionStatus = .unknown
        }
    }
    
    private func updateCreditsFromBackend() async {
        do {
            // Ensure device is attested before making credits request
            try await appAttestService.ensureAttested()
            
            guard let receiptData = await getAppStoreReceiptData() else {
                print("No receipt data available")
                return
            }
            
            let url = URL(string: "\(AppConfig.workerURL)/credits")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(receiptData, forHTTPHeaderField: "X-Receipt-Data")
            
            // Add App Attest headers for credits request
            try await addAppAttestHeaders(to: &request)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let result = try? JSONDecoder().decode(CreditsResponse.self, from: data) {
                self.credits = result.credits
            }
        } catch {
            print("Failed to update credits from backend: \(error)")
        }
    }
    
    private func addAppAttestHeaders(to request: inout URLRequest) async throws {
        // Create request data for signing
        let requestData = request.url?.absoluteString.data(using: .utf8) ?? Data()
        
        // Generate assertion
        let (keyID, assertion, clientDataHash) = try await appAttestService.generateAssertion(for: requestData)
        
        // Add headers
        request.addValue(keyID, forHTTPHeaderField: "X-Key-ID")
        request.addValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Assertion")
        request.addValue(clientDataHash.base64EncodedString(), forHTTPHeaderField: "X-Client-Data-Hash")
    }
    
    private func getAppStoreReceiptData() async -> String? {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: appStoreReceiptURL.path) else {
            return nil
        }
        
        do {
            let receiptData = try Data(contentsOf: appStoreReceiptURL)
            return receiptData.base64EncodedString()
        } catch {
            print("Failed to read receipt data: \(error)")
            return nil
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) async throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    func getSubscriptionPrice() -> String {
        return subscriptionProduct?.displayPrice ?? "$7.99"
    }
    
    func getCreditsPrice() -> String {
        return creditsProduct?.displayPrice ?? "$1.99"
    }
}

struct CreditsResponse: Codable {
    let credits: Int
}

enum StoreError: Error {
    case failedVerification
}