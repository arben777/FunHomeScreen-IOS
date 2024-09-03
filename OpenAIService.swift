//
//  OpenAIService.swift
//  FunHomeScreen
//
//  Created by Arben Gutierrez-Bujari on 9/2/24.
//

import Foundation
import UIKit

enum OpenAIServiceError: Error {
    case networkError(Error)
    case noData
    case decodingError(Error)
    case apiError(String)
    case unknownError
    case imageDownloadError
    case rateLimitExceeded
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

class OpenAIService {
    static let shared = OpenAIService()
    private init() {}
    
    private let apiKey = APIKeys.openAI
    private let baseURL = "https://api.openai.com/v1/"
    private let requestQueue = DispatchQueue(label: "com.openai.requestQueue", attributes: .concurrent)
    private let rateLimitSemaphore = DispatchSemaphore(value: 1)
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 12 // 5 requests per minute = 12 seconds between requests
    
    func extractAppNames(from images: [UIImage], completion: @escaping (Result<[String], OpenAIServiceError>) -> Void) {
        let endpoint = baseURL + "chat/completions"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: Any]] = [
            ["role": "system", "content": "You are an AI assistant that extracts app names from iPhone home screen images."],
            ["role": "user", "content": [
                ["type": "text", "text": "Please list all the app names you can see in these iPhone home screen images. Provide the names in a comma-separated list, without any additional text or explanation."]
            ] as [Any]]
        ]
        
        // Optimize and add image content to the user message
        for image in images {
            if let optimizedImage = image.resized(to: CGSize(width: 800, height: 800)),
               let base64String = optimizedImage.jpegData(compressionQuality: 0.5)?.base64EncodedString() {
                let imageContent: [String: Any] = [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64String)"
                    ]
                ]
                if var content = messages[1]["content"] as? [[String: Any]] {
                    content.append(imageContent)
                    messages[1]["content"] = content
                }
            }
        }
        
        let body: [String: Any] = [
            "model": "gpt-4-turbo",
            "messages": messages,
            "max_tokens": 300
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "Unable to print request body")")
        } catch {
            print("Error creating request body: \(error)")
            completion(.failure(.unknownError))
            return
        }
        
        print("Sending request to OpenAI API...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error)")
                completion(.failure(.networkError(error)))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("API Response Status Code: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("No data received from API")
                completion(.failure(.noData))
                return
            }
            
            print("Received data from API. Attempting to parse...")
            do {
                if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("API Response: \(jsonResult)")
                    
                    if let errorInfo = jsonResult["error"] as? [String: Any],
                       let errorMessage = errorInfo["message"] as? String {
                        print("API Error: \(errorMessage)")
                        completion(.failure(.apiError(errorMessage)))
                        return
                    }
                    
                    if let choices = jsonResult["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        print("Extracted content: \(content)")
                        let appNames = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        print("Parsed app names: \(appNames)")
                        completion(.success(appNames))
                    } else {
                        print("Unexpected response structure")
                        completion(.failure(.apiError("Unexpected response structure")))
                    }
                } else {
                    print("Failed to parse JSON")
                    completion(.failure(.decodingError(NSError(domain: "JSONParsing", code: 0, userInfo: nil))))
                }
            } catch {
                print("JSON parsing error: \(error)")
                completion(.failure(.decodingError(error)))
            }
        }.resume()
    }
    
    func generateIcon(for appName: String, theme: String, completion: @escaping (Result<UIImage, OpenAIServiceError>) -> Void) {
        rateLimitSemaphore.wait()
        
        let currentTime = Date()
        let timeIntervalSinceLastRequest = currentTime.timeIntervalSince(lastRequestTime)
        
        if timeIntervalSinceLastRequest < minimumRequestInterval {
            let delay = minimumRequestInterval - timeIntervalSinceLastRequest
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                self.rateLimitSemaphore.signal()
                self.generateSingleIcon(appName: appName, theme: theme, completion: completion)
            }
        } else {
            rateLimitSemaphore.signal()
            generateSingleIcon(appName: appName, theme: theme, completion: completion)
        }
    }
    
    private func generateSingleIcon(appName: String, theme: String, completion: @escaping (Result<UIImage, OpenAIServiceError>) -> Void) {
        let endpoint = baseURL + "images/generations"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = "Create a \(theme) style app icon for '\(appName)'. The icon should be simple, clear, and suitable for an iOS app. Do not include any text in the icon."
        let body: [String: Any] = [
            "model": "dall-e-3",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "quality": "standard"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("Sending request to generate icon for \(appName)")
        } catch {
            print("Error creating request body for \(appName): \(error)")
            completion(.failure(.unknownError))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            self.lastRequestTime = Date()
            
            if let error = error {
                print("Network error for \(appName): \(error)")
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                print("No data received for \(appName)")
                completion(.failure(.noData))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("Full API response for \(appName): \(json)")
                    
                    if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                        print("API error for \(appName): \(message)")
                        if message.contains("Rate limit exceeded") {
                            completion(.failure(.rateLimitExceeded))
                        } else {
                            completion(.failure(.apiError(message)))
                        }
                        return
                    }
                    
                    if let imageData = json["data"] as? [[String: String]],
                       let imageURLString = imageData.first?["url"],
                       let imageURL = URL(string: imageURLString) {
                        print("Successfully received image URL for \(appName)")
                        self.downloadImage(from: imageURL) { result in
                            switch result {
                            case .success(let image):
                                print("Successfully downloaded image for \(appName)")
                                completion(.success(image))
                            case .failure(let error):
                                print("Failed to download image for \(appName): \(error)")
                                completion(.failure(error))
                            }
                        }
                    } else {
                        print("Unexpected response structure for \(appName)")
                        completion(.failure(.apiError("Unexpected response structure")))
                    }
                } else {
                    print("Failed to parse JSON for \(appName)")
                    completion(.failure(.decodingError(NSError(domain: "JSONParsing", code: 0, userInfo: nil))))
                }
            } catch {
                print("JSON parsing error for \(appName): \(error)")
                completion(.failure(.decodingError(error)))
            }
        }.resume()
    }
    
    private func downloadImage(from url: URL, completion: @escaping (Result<UIImage, OpenAIServiceError>) -> Void) {
        print("Downloading image from URL: \(url)")
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Network error while downloading image: \(error)")
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                print("Failed to create image from downloaded data")
                completion(.failure(.imageDownloadError))
                return
            }
            
            print("Successfully downloaded and created image")
            completion(.success(image))
        }.resume()
    }
}
