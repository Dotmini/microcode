//
//  BillingService.swift
//  CodeTunner
//
//  Handles Subscription, Pay-as-you-go tokens, and Compute Engine billing.
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

enum BillingTier {
    case free
    case pro
    case enterprise
}

class BillingService: ObservableObject {
    static let shared = BillingService()
    
    // MARK: - Stripe Backend Configuration
    private let backendBaseURL = "https://api.dotmini.net/v1/billing"
    private var authToken: String? // User's JWT or session token
    
    @Published var tokenBalance: Int = 0 // Will be fetched from backend
    @Published var currentTier: BillingTier = .free
    @Published var isLoading: Bool = false
    
    private var computeTimer: Timer?
    private var tokensPerMinute: Int = 10
    
    private init() {
        // Automatically fetch initial balance if token exists
        Task {
            await fetchBalance()
        }
    }
    
    // MARK: - Auth Management
    
    func setAuthToken(_ token: String) {
        self.authToken = token
        Task {
            await fetchBalance()
        }
    }
    
    // MARK: - Compute Pricing
    
    /// Returns the cost per minute of execution for a specific compute target
    func getCostPerMinute(for target: ComputeTarget) -> Int {
        switch target {
        case .localCPU, .localMLX, .localNvidia, .customHPC:
            return 0 // Free / Bring your own compute
        case .cloudPremium:
            return 50 // 50 Tokens per minute
        }
    }
    
    // MARK: - Execution Tracking
    
    func startComputeSession(for target: ComputeTarget, onInsufficientBalance: @escaping () -> Void) {
        let cost = getCostPerMinute(for: target)
        guard cost > 0 else { return }
        
        if tokenBalance < cost {
            onInsufficientBalance()
            return
        }
        
        // Setup timer to deduct tokens every minute and sync with Stripe Backend
        computeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                do {
                    try await self.chargeTokensViaStripe(amount: cost)
                    
                    if self.tokenBalance < cost {
                        self.stopComputeSession()
                        onInsufficientBalance()
                    }
                } catch {
                    print("⚠️ Failed to charge tokens: \(error)")
                }
            }
        }
    }
    
    func stopComputeSession() {
        computeTimer?.invalidate()
        computeTimer = nil
    }
    
    // MARK: - Stripe API Integration
    
    struct BalanceResponse: Codable {
        let tokens: Int
        let tier: String
    }
    
    /// Fetches the user's token balance and subscription tier from the Stripe Backend
    func fetchBalance() async throws {
        guard let token = authToken else { throw URLError(.userAuthenticationRequired) }
        
        DispatchQueue.main.async { self.isLoading = true }
        defer { DispatchQueue.main.async { self.isLoading = false } }
        
        guard let url = URL(string: "\(backendBaseURL)/balance") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(BalanceResponse.self, from: data)
        
        DispatchQueue.main.async {
            self.tokenBalance = result.tokens
            self.currentTier = result.tier == "pro" ? .pro : .free
        }
    }
    
    /// Sends a charge request to the Stripe Backend
    func chargeTokensViaStripe(amount: Int) async throws {
        guard let token = authToken else { throw URLError(.userAuthenticationRequired) }
        
        guard let url = URL(string: "\(backendBaseURL)/charge") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["amount": amount, "description": "Cloud GPU Usage"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(BalanceResponse.self, from: data)
        
        DispatchQueue.main.async {
            self.tokenBalance = result.tokens
        }
    }
    
    /// Triggers a Stripe Checkout Session for purchasing tokens
    func buyTokens(packageId: String) async throws -> URL {
        guard let token = authToken else { throw URLError(.userAuthenticationRequired) }
        
        guard let url = URL(string: "\(backendBaseURL)/create-checkout-session") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["package_id": packageId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sessionUrlString = json["url"] as? String,
           let sessionUrl = URL(string: sessionUrlString) {
            return sessionUrl
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    /// Triggers a Stripe Checkout Session for Pro Subscription
    func upgradeToProViaStripe() async throws -> URL {
        return try await buyTokens(packageId: "sub_pro_monthly")
    }
}
