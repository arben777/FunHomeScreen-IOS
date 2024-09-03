//
//  ContentView.swift
//  FunHomeScreen
//
//  Created by Arben Gutierrez-Bujari on 9/2/24.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var theme: String = ""
    @State private var appNames: [String] = []
    @State private var generatedIcons: [UIImage] = []
    @State private var isProcessing = false
    @State private var currentStep = 0
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showThemeInput = false
    @State private var detailedErrorMessage: String = ""

    var body: some View {
        NavigationView {
            VStack {
                switch currentStep {
                case 0:
                    welcomeView
                case 1:
                    uploadView
                case 2:
                    generatedIconsView
                case 3:
                    instructionsView
                default:
                    Text("Unexpected state")
                }
            }
            .navigationTitle("Fun Home Screen")
            .alert(isPresented: $showError) {
                Alert(title: Text("Error"), message: Text(detailedErrorMessage), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $showThemeInput) {
                themeInputView
            }
        }
    }
    
    var welcomeView: some View {
        VStack {
            Text("Welcome to Fun Home Screen")
                .font(.title)
            Text("Create unique icons for your iPhone")
                .font(.subheadline)
            Button("Get Started") {
                currentStep = 1
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
    
    var uploadView: some View {
            VStack {
                Text("Upload Screenshots")
                    .font(.title2)
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 5, matching: .images) {
                    Text("Select Images")
                }
                .onChange(of: selectedItems) { _, newItems in
                    loadTransferable(from: newItems)
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                if !selectedImages.isEmpty {
                    Text("\(selectedImages.count) images selected")
                    Button("Process Images") {
                        extractAppNames()
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                if isProcessing {
                    ProgressView()
                        .padding()
                }
            }
        }

    
    var themeInputView: some View {
        VStack {
            Text("Enter Theme")
                .font(.title2)
            TextField("e.g., minimalist, retro", text: $theme)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            Button("Generate Icons") {
                showThemeInput = false
                generateIcons()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(theme.isEmpty)
            
            if isProcessing {
                ProgressView()
                    .padding()
            }
        }
        .padding()
    }
    
    var generatedIconsView: some View {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    ForEach(Array(zip(appNames, generatedIcons)), id: \.0) { appName, icon in
                        VStack {
                            Image(uiImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .cornerRadius(16)
                            Text(appName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding()
                
                Button("Save Icons") {
                    saveIcons()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Create More Icons") {
                    showThemeInput = true
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Finish") {
                    currentStep = 3
                }
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    
    var instructionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("How to Set Custom Icons")
                    .font(.title2)
                Text("1. Open the Shortcuts app on your iPhone")
                Text("2. Tap the + button to create a new shortcut")
                Text("3. Add the 'Open App' action")
                Text("4. Choose the app you want to customize")
                Text("5. Tap the share button and 'Add to Home Screen'")
                Text("6. Tap the icon next to the shortcut name")
                Text("7. Choose 'Select Photo' and pick your custom icon")
                Text("8. Name the shortcut the same as the original app and tap 'Add'")
            }
            .padding()
        }
    }
    
    private func loadTransferable(from items: [PhotosPickerItem]) {
        selectedImages.removeAll()
        
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    if let data = data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self.selectedImages.append(image)
                        }
                    }
                case .failure(let error):
                    print("Error loading image: \(error)")
                }
            }
        }
    }


    func extractAppNames() {
        isProcessing = true
        OpenAIService.shared.extractAppNames(from: selectedImages) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success(let names):
                    self.appNames = names
                    self.showThemeInput = true
                case .failure(let error):
                    switch error {
                    case .apiError(let message):
                        if message.contains("Rate limit exceeded") {
                            self.detailedErrorMessage = "The service is currently busy. Please wait a few minutes and try again."
                        } else {
                            self.detailedErrorMessage = "API Error: \(message)"
                        }
                    case .networkError(_):
                        self.detailedErrorMessage = "Network error. Please check your internet connection and try again."
                    case .noData:
                        self.detailedErrorMessage = "No data received from the server. Please try again."
                    case .decodingError(_):
                        self.detailedErrorMessage = "Error processing the response. Please try again."
                    case .unknownError:
                        self.detailedErrorMessage = "An unknown error occurred. Please try again."
                    case .imageDownloadError:
                        self.detailedErrorMessage = "Error downloading images. Please try again."
                    }
                    self.showError = true
                }
            }
        }
    }
    
    func generateIcons() {
        isProcessing = true
        OpenAIService.shared.generateIcons(appNames: appNames, theme: theme) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success(let icons):
                    self.generatedIcons = icons
                    self.currentStep = 2
                case .failure(let error):
                    self.handleError(error)
                }
            }
        }
    }
    
    private func handleError(_ error: OpenAIServiceError) {
        switch error {
        case .networkError(let underlyingError):
            detailedErrorMessage = "Network error: \(underlyingError.localizedDescription)"
        case .noData:
            detailedErrorMessage = "No data received from the server."
        case .decodingError(let underlyingError):
            detailedErrorMessage = "Error decoding response: \(underlyingError.localizedDescription)"
        case .apiError(let message):
            detailedErrorMessage = "API error: \(message)"
        case .unknownError:
            detailedErrorMessage = "An unknown error occurred."
        case .imageDownloadError:
            detailedErrorMessage = "Error downloading generated images."
        }
        showError = true
    }
    
    func saveIcons() {
        for icon in generatedIcons {
            UIImageWriteToSavedPhotosAlbum(icon, nil, nil, nil)
        }
        self.detailedErrorMessage = "Icons saved successfully!"
        self.showError = true
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
