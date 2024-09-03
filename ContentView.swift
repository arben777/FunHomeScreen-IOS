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
    @State private var generatedIcons: [String: UIImage] = [:]  // Changed to empty dictionary literal
    @State private var isProcessing = false
    @State private var currentStep = 0
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showThemeInput = false
    @State private var detailedErrorMessage: String = ""
    @State private var currentAppIndex = 0
    @State private var showSuccess = false
    @State private var successMessage: String = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
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
                            .font(.headline)
                    }
                }
                .padding()
            }
            .navigationTitle("Fun Home Screen")
            .alert(isPresented: $showError) {
                Alert(title: Text("Error"), message: Text(detailedErrorMessage), dismissButton: .default(Text("OK")))
            }
            .alert(isPresented: $showSuccess) {
                Alert(title: Text("Success"), message: Text(successMessage), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $showThemeInput) {
                themeInputView
            }
        }
    }
    
    var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Welcome to Fun Home Screen")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Create unique icons for your iPhone")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                withAnimation {
                    currentStep = 1
                }
            }) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }
    
    var uploadView: some View {
        VStack(spacing: 20) {
            Text("Upload Screenshots")
                .font(.title2)
                .fontWeight(.semibold)
            
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 5, matching: .images) {
                Label("Select Images", systemImage: "photo.on.rectangle.angled")
            }
            .onChange(of: selectedItems) { _, newItems in
                loadTransferable(from: newItems)
            }
            .buttonStyle(.borderedProminent)
            
            if !selectedImages.isEmpty {
                Text("\(selectedImages.count) images selected")
                    .foregroundColor(.secondary)
                
                Button(action: {
                    extractAppNames()
                }) {
                    Label("Process Images", systemImage: "arrow.right.circle")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            
            if isProcessing {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
    }
    
    var themeInputView: some View {
            VStack(spacing: 20) {
                Text("Enter Theme")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                TextField("e.g., minimalist, retro", text: $theme)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button(action: {
                    showThemeInput = false
                    startIconGeneration()
                }) {
                    Text("Start Generating Icons")
                        .fontWeight(.semibold)
                        .frame(minWidth: 200)
                        .padding()
                        .background(theme.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(theme.isEmpty)
            }
            .padding()
        }
    
    var generatedIconsView: some View {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
                    ForEach(appNames, id: \.self) { appName in
                        VStack {
                            if let icon = generatedIcons[appName] {
                                Image(uiImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(16)
                                    .shadow(radius: 5)
                            } else {
                                ProgressView()
                                    .frame(width: 80, height: 80)
                            }
                            Text(appName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding()
                
                if currentAppIndex < appNames.count {
                    ProgressView("Generating \(appNames[currentAppIndex])")
                } else {
                    Button(action: {
                        saveIcons()
                    }) {
                        Text("Save Icons")
                            .fontWeight(.semibold)
                            .frame(minWidth: 200)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        }

    private func startIconGeneration() {
        currentAppIndex = 0
        generateNextIcon()
    }

    private func generateNextIcon() {
        guard currentAppIndex < appNames.count else {
            currentStep = 2
            return
        }
        
        let appName = appNames[currentAppIndex]
        OpenAIService.shared.generateIcon(for: appName, theme: theme) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let icon):
                    self.generatedIcons[appName] = icon
                    self.currentAppIndex += 1
                    self.generateNextIcon()
                case .failure(let error):
                    if case .rateLimitExceeded = error {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                            self.generateNextIcon()
                        }
                    } else {
                        self.handleError(error)
                    }
                }
            }
        }
    }

    private func saveIcons() {
        for (_, icon) in generatedIcons {
            UIImageWriteToSavedPhotosAlbum(icon, nil, nil, nil)
        }
        self.successMessage = "Icons saved successfully!"
        self.showSuccess = true
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
        case .rateLimitExceeded:
            detailedErrorMessage = "Rate limit exceeded. Please try again later."
        }
        print("Error occurred: \(detailedErrorMessage)")
        showError = true
    }
    
    var instructionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("How to Set Custom Icons")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom)
                
                ForEach(instructionSteps, id: \.self) { step in
                    HStack(alignment: .top) {
                        Text("•")
                            .font(.title3)
                            .foregroundColor(.blue)
                        Text(step)
                    }
                }
                
                Button(action: {
                    withAnimation {
                        currentStep = 0
                        selectedItems = []
                        selectedImages = []
                        theme = ""
                        appNames = []
                        generatedIcons = [:]
                    }
                }) {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .padding()
        }
    }
    
    private let instructionSteps = [
        "Open the Shortcuts app on your iPhone",
        "Tap the + button to create a new shortcut",
        "Add the 'Open App' action",
        "Choose the app you want to customize",
        "Tap the share button and 'Add to Home Screen'",
        "Tap the icon next to the shortcut name",
        "Choose 'Select Photo' and pick your custom icon",
        "Name the shortcut the same as the original app",
        "Tap 'Add' to create the custom icon on your home screen"
    ]
    
    private func loadTransferable(from items: [PhotosPickerItem]) {
            print("Loading transferable items...")
            selectedImages.removeAll()
            
            for (index, item) in items.enumerated() {
                item.loadTransferable(type: Data.self) { result in
                    switch result {
                    case .success(let data):
                        if let data = data, let image = UIImage(data: data) {
                            print("Successfully loaded image \(index + 1)")
                            DispatchQueue.main.async {
                                self.selectedImages.append(image)
                            }
                        } else {
                            print("Failed to create UIImage from data for item \(index + 1)")
                        }
                    case .failure(let error):
                        print("Error loading image \(index + 1): \(error)")
                    }
                }
            }
        }

        private func extractAppNames() {
            print("Starting app name extraction...")
            isProcessing = true
            OpenAIService.shared.extractAppNames(from: selectedImages) { result in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    switch result {
                    case .success(let names):
                        print("Successfully extracted app names: \(names)")
                        self.appNames = names
                        self.showThemeInput = true
                    case .failure(let error):
                        print("Failed to extract app names: \(error)")
                        self.handleError(error)
                    }
                }
            }
        }
        
        // Removed the generateIcons function as it's no longer used
    }

    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }

