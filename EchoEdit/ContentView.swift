//  ContentView.swift
//  TextTune
//  Prompts cycle; Nicola is always 5th.
//  Created by Steven Strange on 6/13/25.

import SwiftUI
import Foundation
import UIKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

// No need for custom module imports - they're part of the same target

struct ContentView: View {
    // MARK: - State
    @State private var text = ""
    @State private var animatedPrompt = ""
    @State private var index = 0
    @State private var shown = 0           // prompts shown so far
    @State private var nicolaInjected = false
    @State private var selectedImage: UIImage?
    @State private var generatedImage: UIImage?
    @State private var isLoading = false
    @State private var isKeyboardVisible = false
    @State private var showImagePicker = false
    @State private var useProService = true
    @State private var showSettings = false
    @State private var showInfoPopup = false
    @State private var showErrorPopup = false
    @State private var showPlans = false
    @State private var errorMessage = ""
    @State private var useHighQuality = false
    @StateObject private var appAttestService = AppAttestService()
    @StateObject private var storeKitService: StoreKitService
    
    // Blur effect transition states
    @State private var blurRadius: CGFloat = 20.0
    @State private var transitionActive = false
    @State private var transitionOpacity: Double = 0.0
    
    // Blur transition states only
    
    // Tracks which image is displayed
    @State private var displayedImage: UIImage?
    
    // Image history
    @State private var imageHistory: [UIImage] = []
    @State private var currentHistoryIndex: Int = -1
    
    // We're removing crop/aspect ratio functionality
    
    // MARK: - Dependencies
    @State private var secureProService: SecureFluxProService?
    @State private var secureMaxService: SecureFluxMaxService?
    @State private var contentFilter = ContentFilter()
    
    init() {
        let appAttest = AppAttestService()
        _appAttestService = StateObject(wrappedValue: appAttest)
        _storeKitService = StateObject(wrappedValue: StoreKitService(appAttestService: appAttest))
    }
    
    private var activeSecureService: any SecureFluxService {
        if useHighQuality {
            if secureMaxService == nil {
                secureMaxService = SecureFluxMaxService(workerURL: AppConfig.workerURL, appAttestService: appAttestService)
            }
            return secureMaxService!
        } else {
            if secureProService == nil {
                secureProService = SecureFluxProService(workerURL: AppConfig.workerURL, appAttestService: appAttestService)
            }
            return secureProService!
        }
    }

    // MARK: - Constants
    private let promptDelay: UInt64 = 3_000_000_000 // 3 s
    private let charDelay:   UInt64 =   30_000_000 // 30 ms

    // MARK: - UI Components
    
    // Background 
    private var backgroundGradient: some View {
        Color(.systemBackground)
            .edgesIgnoringSafeArea(.all)
    }
    
    // Displayed image view - simplified
    private func displayedImageView(image: UIImage) -> some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                // Container with consistent padding
                ZStack {
                    // Container with consistent border
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white, lineWidth: 1)
                        .background(Color.clear)
                    
                    // Calculate aspect ratio to determine padding
                    let imageAspect = image.size.width / image.size.height
                    let frameWidth = geo.size.width * 0.9
                    let frameHeight = isKeyboardVisible ? geo.size.width * 0.85 : geo.size.height * 0.8
                    let contentPadding: CGFloat = 16
                    
                    // The image with consistent padding
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 4, y: 4)
                        .padding(contentPadding)
                }
                .frame(
                    width: geo.size.width * 0.9, // 90% of width to match containers
                    height: isKeyboardVisible ? geo.size.width * 0.85 : geo.size.height * 0.8 // Larger when keyboard is hidden
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isKeyboardVisible)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // Empty state view
    private func emptyStateView(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            // Safe container that respects screen bounds
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white, lineWidth: 1)
                    .background(Color.clear)
                
                // Use consistent padding
                let contentPadding: CGFloat = 16
                
                VStack {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text("Add a photo to get started")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(contentPadding)
            }
            // Responsive container that adjusts to keyboard visibility
            .frame(
                width: geometry.size.width * 0.9,
                height: isKeyboardVisible ? geometry.size.width * 0.85 : geometry.size.height * 0.8 // Larger when keyboard is hidden
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isKeyboardVisible)
            .contentShape(Rectangle())
            .onTapGesture {
                showImagePicker = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Transition effect view - simplified without distortion and background blur
    private func transitionEffectView(image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                // Centered content
                VStack {
                    Spacer()
                    // Simple blur effect container
                    ZStack {
                        // Container with consistent border
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white, lineWidth: 1)
                            .background(Color.clear)
                        
                        // Calculate consistent padding
                        let contentPadding: CGFloat = 16
                        
                        // Simple layers with standard blur
                        ZStack {
                            ForEach(0..<5, id: \.self) { _ in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit() // Important: ensures image fits container
                                    .blur(radius: blurRadius)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(contentPadding) // Add padding inside container
                    }
                    // Matching responsive size constraints to the display view
                    .frame(
                        width: geo.size.width * 0.9, // 90% width (same as display view)
                        height: isKeyboardVisible ? geo.size.width * 0.85 : geo.size.height * 0.8 // Larger when keyboard is hidden
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isKeyboardVisible)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(transitionOpacity)
        }
    }
    
    // Loading indicator
    private var loadingIndicator: some View {
        ProgressView()
            .scaleEffect(1.5)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
    }
    
    // Keyboard area
    private var keyboardArea: some View {
        VStack(spacing: 8) {
            controlRow
            textInputRow
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color(.systemBackground))
        .edgesIgnoringSafeArea(.bottom)
    }
    
    // Control row
    private var controlRow: some View {
        HStack(spacing: 8) {
            imageHistoryView
            if !imageHistory.isEmpty {
                photoButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .padding(.vertical, 4)
    }
    
    // Settings panel overlay
    private var settingsPanel: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showSettings = false
                }
            
            // Settings panel
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showSettings = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Settings content
                VStack(spacing: 20) {
                    // Higher quality output toggle
                    HStack {
                        Text("Higher quality output")
                            .foregroundColor(.white)
                            .font(.body)
                        
                        Button(action: { showInfoPopup = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 16))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $useHighQuality)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding(.horizontal, 20)
                    
                    // Plans button
                    Button(action: { 
                        showSettings = false
                        showPlans = true 
                    }) {
                        HStack {
                            Image(systemName: "creditcard")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                            
                            Text("View Plans")
                                .foregroundColor(.white)
                                .font(.body)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 20)
            }
            .frame(width: 300, height: 250)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // Information popup
    private var infoPopup: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showInfoPopup = false
                }
            
            // Info popup
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Spacer()
                    
                    Button(action: { showInfoPopup = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Info text
                Text("When enabled the system will try harder to achieve your edit but use double the tokens")
                    .foregroundColor(.white)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(width: 250)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // Error popup
    private var errorPopup: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showErrorPopup = false
                }
            
            // Error popup
            VStack(spacing: 0) {
                // Header with error icon and close button
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.system(size: 18, weight: .medium))
                    
                    Text("Error")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: { showErrorPopup = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Error message
                Text(errorMessage)
                    .foregroundColor(.white)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(width: 300)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // Plans/Pricing view components
    private var plansHeader: some View {
        HStack {
            Text("Choose Your Plan")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: { showPlans = false }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 18, weight: .medium))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    private var monthlySubscriptionPlan: some View {
        VStack(spacing: 12) {
            // Plan header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Subscription")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Best value for regular users")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(storeKitService.getSubscriptionPrice())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("per month")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            subscriptionFeatures
            
            // Subscribe button
            Button(action: {
                Task {
                    await storeKitService.purchaseSubscription()
                }
            }) {
                Text("Subscribe Now")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var subscriptionFeatures: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                
                Text("100 standard quality edits")
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                
                Text("Full access to all editing features")
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                
                Text("Cancel anytime")
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
        }
        .padding(.horizontal, 8)
    }
    
    private var topUpPlan: some View {
        VStack(spacing: 12) {
            // Plan header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top-up Credits")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Need more edits?")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(storeKitService.getCreditsPrice())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("one-time")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Features
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                
                Text("25 additional edits")
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            
            // Purchase button
            Button(action: {
                Task {
                    await storeKitService.purchaseCredits()
                }
            }) {
                Text("Buy Credits")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // Plans/Pricing view
    private var plansView: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.6)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showPlans = false
                }
            
            // Plans panel
            VStack(spacing: 0) {
                plansHeader
                
                // Plans content
                VStack(spacing: 16) {
                    monthlySubscriptionPlan
                    topUpPlan
                    
                    // Restore purchases button
                    Button(action: {
                        Task {
                            await storeKitService.restorePurchases()
                        }
                    }) {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .underline()
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 350)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // Image history view
    private var imageHistoryView: some View {
        Group {
            if !imageHistory.isEmpty {
                imageHistoryScrollView
                    .frame(height: 50)
            } else {
                Spacer() // If no history, just use a spacer
                    .frame(width: 0, height: 50)
            }
        }
    }
    
    // Helper view to break up the complex expression
    private var imageHistoryScrollView: some View {
        ScrollViewReader { scrollView in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<imageHistory.count, id: \.self) { index in
                        imageHistoryItem(for: index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: currentHistoryIndex) { _, newIndex in
                if newIndex >= 0 {
                    withAnimation {
                        scrollView.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .onChange(of: imageHistory.count) { _, _ in
                if currentHistoryIndex >= 0 {
                    withAnimation {
                        scrollView.scrollTo(currentHistoryIndex, anchor: .center)
                    }
                }
            }
        }
    }
    
    // Helper view for each history item
    private func imageHistoryItem(for index: Int) -> some View {
        // Container for consistent positioning and sizing
        Image(uiImage: imageHistory[index])
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        index == currentHistoryIndex ? Color.white : Color.white.opacity(0.5),
                        lineWidth: 1
                    )
            )
            .frame(width: 50, height: 50)
            .id(index)
            .onTapGesture {
                currentHistoryIndex = index
                displayedImage = imageHistory[index]
            }
    }
    
    // Photo button
    private var photoButton: some View {
        Button(action: { showImagePicker = true }) {
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .padding(15)
                .foregroundColor(.white)
                .background(Circle().fill(Color.clear))
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
        .frame(width: 50, height: 50)
    }
    
    // Text input row
    private var textInputRow: some View {
        HStack(spacing: 16) {
            promptTextField
            magicButton
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
    
    // Prompt text field
    private var promptTextField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 25)
                .strokeBorder(Color.white, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 25).fill(Color.clear))
                .frame(height: 50)
            
            if text.isEmpty {
                Text(animatedPrompt)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }
            
            TextField("", text: $text)
                .keyboardType(.alphabet)
                .disableAutocorrection(true)
                .padding(.horizontal, 16)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isKeyboardVisible = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isKeyboardVisible = false
                    }
                }
        }
    }
    
    // Magic button
    private var magicButton: some View {
        Button(action: generateImage) {
            Image(systemName: "wand.and.stars")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .padding(15)
                .foregroundColor(.white)
                .background(Circle().fill(Color.clear))
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
        .frame(width: 50, height: 50)
        .accessibilityLabel("Generate Image")
        .disabled(isLoading || (text.isEmpty && displayedImage == nil))
    }
    
    // MARK: - UI
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Neumorphic Dark Gradient Background
                backgroundGradient
                
                VStack(spacing: 0) {
                    // Top button row
                    HStack {
                        Spacer()
                        .frame(width: geometry.size.width * 0.05)
                        
                        // Settings button (left)
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .foregroundColor(.white)
                                .background(Capsule().fill(Color.clear))
                                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                        }
                        .frame(height: 30)
                        
                        // Credits display (center)
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 12))
                            Text("\(storeKitService.credits)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.3)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                        
                        Spacer()
                        
                        // Save button (right)
                        Button(action: {
                            // Save functionality will be added later
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .foregroundColor(.white)
                                .background(Capsule().fill(Color.clear))
                                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                        }
                        .frame(height: 30)
                        
                        Spacer()
                        .frame(width: geometry.size.width * 0.05)
                    }
                    .padding(.top, 6)
                    
                    // Image Display Area - flexibly fills all available space
                    ZStack {
                        if let image = displayedImage {
                            displayedImageView(image: image)
                        
                        } else {
                            emptyStateView(geometry: geometry)
                        }
                        
                        // Newly generated image with blur transition effect
                        if let image = generatedImage, isLoading || transitionActive {
                            transitionEffectView(image: image)
                        }
                        
                        if isLoading {
                            loadingIndicator
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                keyboardArea
            }
            
            // Settings panel overlay
            if showSettings {
                settingsPanel
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            // Info popup overlay
            if showInfoPopup {
                infoPopup
                    .transition(.opacity)
                    .zIndex(2)
            }
            
            // Error popup overlay
            if showErrorPopup {
                errorPopup
                    .transition(.opacity)
                    .zIndex(3)
            }
            
            // Plans view overlay
            if showPlans {
                plansView
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .task {
            // Initialize app attestation on first launch
            if !appAttestService.isAttested {
                do {
                    try await appAttestService.performInitialAttestation()
                } catch {
                    print("Initial attestation failed: \(error)")
                    errorMessage = "Device security setup failed. Please restart the app."
                    showErrorPopup = true
                }
            }
            
            index = Int.random(in: 0..<DemoPrompts.prompts.count)
            await cyclePrompts()
        }
        .onChange(of: storeKitService.errorMessage) { errorMessage in
            if let errorMessage = errorMessage, !errorMessage.isEmpty {
                self.errorMessage = errorMessage
                showErrorPopup = true
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage, onDismiss: {
                if let image = selectedImage {
                    // First, ensure the image is not too large by scaling it down if needed
                    let processedImage = scaleImageIfNeeded(image)
                    
                    // Use the processed image
                    displayedImage = processedImage
                    
                    // Add to history
                    imageHistory = [processedImage]
                    currentHistoryIndex = 0
                }
            })
        }
    }

    // MARK: - Prompt cycle
    func cyclePrompts() async {
        while true {
            let next: String
            if shown == 4 && !nicolaInjected {
                next = DemoPrompts.nicola
                nicolaInjected = true
            } else {
                next = DemoPrompts.prompts[index]
                index = (index + 1) % DemoPrompts.prompts.count
            }

            // erase current
            for _ in animatedPrompt.indices.reversed() {
                await MainActor.run { _ = animatedPrompt.popLast() }
                try? await Task.sleep(nanoseconds: charDelay)
            }
            // type next
            for ch in next {
                await MainActor.run { animatedPrompt.append(ch) }
                try? await Task.sleep(nanoseconds: charDelay)
            }

            shown += 1
            try? await Task.sleep(nanoseconds: promptDelay)
        }
    }

    // MARK: - Actions
    func generateImage() {
        guard !text.isEmpty || displayedImage != nil else { return }
        
        // Check if user has subscription OR sufficient credits
        let requiredCredits = useHighQuality ? 5 : 2
        let hasSubscription = storeKitService.subscriptionStatus == .subscribed
        let hasCredits = storeKitService.credits >= requiredCredits
        
        if !hasSubscription && !hasCredits {
            if storeKitService.credits == 0 {
                errorMessage = "You need a subscription or credits to generate images. Please subscribe or purchase credits."
            } else {
                errorMessage = "Insufficient credits. You need \(requiredCredits) credits for this generation."
            }
            showErrorPopup = true
            showPlans = true
            return
        }
        
        // Check for banned words before sending to API
        if !text.isEmpty && contentFilter.containsBannedWords(text) {
            errorMessage = "Your prompt contains content that violates our content policy. Please modify your prompt and try again."
            showErrorPopup = true
            return
        }
        
        isLoading = true
        
        // Initialize transition - start with no blur but make it visible
        transitionActive = true
        blurRadius = 0
        
        // No distortion animation anymore
        
        // Make a copy of the current displayed image for the transition
        if let currentImage = displayedImage {
            generatedImage = currentImage
            
            // Animate blur increasing
            withAnimation(.easeIn(duration: 0.5)) {
                blurRadius = 20.0
                transitionOpacity = 1.0
            }
        }
        
        // Convert displayed image (current selection from history) to base64 if available
        var base64Image: String?
        if let image = displayedImage {
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                base64Image = imageData.base64EncodedString()
            }
        }
        
        Task {
            do {
                // Try using the real API first
                // No aspect ratio needed
                
                print("===== STARTING API REQUEST =====")
                print("Text prompt: \(text)")
                print("Has input image: \(base64Image != nil)")
                print("Device model: \(UIDevice.current.model)")
                print("iOS version: \(UIDevice.current.systemVersion)")
                
                let serviceName = useHighQuality ? "Flux Kontext Max" : "Flux Kontext Pro"
                print("Using service: \(serviceName)")
                
                // Debug info about which service is being used
                if let service = activeSecureService as? SecureFluxProService {
                    print("Service instance is SecureFluxProService")
                    print("Service info: \(service.getServiceInfo())")
                } else if let service = activeSecureService as? SecureFluxMaxService {
                    print("Service instance is SecureFluxMaxService")
                    print("Service info: \(service.getServiceInfo())")
                } else {
                    print("Unknown service type: \(type(of: activeSecureService))")
                }
                
                let apiResult = try await activeSecureService.generateImage(
                    prompt: text,
                    inputImage: base64Image,
                    seed: nil as Int?,
                    aspectRatio: nil
                )
                
                print("API request successful, polling URL: \(apiResult.polling_url)")
                
                // Poll for result
                let finalImage = try await activeSecureService.pollForResult(pollingURL: apiResult.polling_url)
                
                print("Successfully retrieved image from API")
                
                // Deduct credits if user doesn't have an active subscription
                if storeKitService.subscriptionStatus != .subscribed {
                    await MainActor.run {
                        storeKitService.credits -= requiredCredits
                        print("💰 Deducted \(requiredCredits) credits. Remaining: \(storeKitService.credits)")
                    }
                }
                
                await MainActor.run {
                    // Create cross-fade between old and new image while blurred
                    let originalImage = self.generatedImage
                    
                    // Hide the loading indicator
                    self.isLoading = false
                    
                    // Animate cross-fade under blur over 1.5 seconds
                    withAnimation(.easeInOut(duration: 1.5)) {
                        self.generatedImage = finalImage
                    }
                    
                    // After cross-fade completes, start reducing blur
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        // Now gradually reduce blur to reveal the image
                        withAnimation(.easeOut(duration: 3.0)) {
                            self.blurRadius = 0
                        }
                    }
                    
                    // When blur animation completes, update the displayed image and finish transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                        self.displayedImage = finalImage
                        
                        // Fade out the transition layer
                        withAnimation(.easeOut(duration: 0.3)) {
                            self.transitionOpacity = 0
                        }
                        
                        // After fade out, deactivate transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.transitionActive = false
                            // No distortion animation to stop
                            
                            // Add to history right after the current selected image
                            if self.currentHistoryIndex >= 0 {
                                // Insert right after the current index
                                let insertIndex = self.currentHistoryIndex + 1
                                
                                // Insert the new image at the right position (without removing later images)
                                self.imageHistory.insert(finalImage, at: insertIndex)
                                self.currentHistoryIndex = insertIndex
                            } else if !self.imageHistory.isEmpty {
                                // If somehow no index is selected but history exists, append to end
                                self.imageHistory.append(finalImage)
                                self.currentHistoryIndex = self.imageHistory.count - 1
                            } else {
                                // First image in history
                                self.imageHistory = [finalImage]
                                self.currentHistoryIndex = 0
                            }
                        }
                    }
                }
            } catch let fluxError as SecureFluxError {
                // If API fails with a specific flux error, show error popup
                print("⚠️ FLUX API ERROR: \(fluxError)")
                
                await MainActor.run {
                    self.isLoading = false
                    self.transitionActive = false
                    
                    // Set error message based on error type
                    switch fluxError {
                    case .invalidURL:
                        self.errorMessage = "Invalid API endpoint. Please check your configuration."
                    case .invalidResponse:
                        self.errorMessage = "Invalid response from server. Please try again."
                    case .encodingError:
                        self.errorMessage = "Failed to encode request. Please try again."
                    case .decodingError:
                        self.errorMessage = "Failed to decode server response. Please try again."
                    case .networkError(let error):
                        self.errorMessage = "Network error: \(error.localizedDescription)"
                    case .apiError(let message):
                        self.errorMessage = "API error: \(message)"
                    case .imageDecodingError:
                        self.errorMessage = "Failed to decode generated image. Please try again."
                    case .pollingTimeout:
                        self.errorMessage = "Request timed out. Please modify your prompt or image, or try again later."
                    case .unauthorized:
                        self.errorMessage = "Unauthorized access. Please check your API token."
                    case .rateLimited:
                        self.errorMessage = "Too many requests. Please wait and try again."
                    case .attestationRequired:
                        self.errorMessage = "Device authentication required. Please restart the app."
                    case .attestationFailed:
                        self.errorMessage = "Device authentication failed. Please restart the app."
                    }
                    
                    self.showErrorPopup = true
                }
            } catch {
                // If API fails with a generic error, show error popup
                print("⚠️ GENERAL API ERROR: \(error)")
                
                await MainActor.run {
                    self.isLoading = false
                    self.transitionActive = false
                    
                    self.errorMessage = "Image generation failed: \(error.localizedDescription)"
                    self.showErrorPopup = true
                }
            }
        }
    }
    
    // Save photo functionality removed
    
    // Helper function to scale and preserve aspect ratio
    func scaleImageIfNeeded(_ image: UIImage) -> UIImage {
        // Define maximum dimensions we want to allow - reduced to ensure better fit on screen
        let maxWidth: CGFloat = 1600
        let maxHeight: CGFloat = 1600
        
        // Get current image dimensions
        let currentWidth = image.size.width
        let currentHeight = image.size.height
        
        // Check if image needs scaling
        if currentWidth <= maxWidth && currentHeight <= maxHeight {
            return image // No scaling needed
        }
        
        // Calculate scale factor to fit within max dimensions
        let widthScale = maxWidth / currentWidth
        let heightScale = maxHeight / currentHeight
        let scale = min(widthScale, heightScale)
        
        // Calculate new size, preserving aspect ratio
        let newWidth = currentWidth * scale
        let newHeight = currentHeight * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        // Render image at new size
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return scaledImage
    }
    
    // Distortion effects removed
}

// Distortion View Modifier removed

#Preview {
    ContentView()
}
