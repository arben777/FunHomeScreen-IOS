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
    
    func extractAppNames(from images: [UIImage], completion: @escaping (Result<[String], OpenAIServiceError>) -> Void) {
        let endpoint = baseURL + "chat/completions"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: Any]] = [
            ["role": "system", "content": "You are an AI assistant that extracts app names from iPhone home screen images."],
            ["role": "user", "content": [
                ["type": "text", "text": "Please list the names of all the apps you can see in these iPhone home screen images. Only list the app names, separated by commas."]
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
            "model": "gpt-4-turbo",  // Changed back to vision-specific model
            "messages": messages,
            "max_tokens": 300
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Implement exponential backoff with a maximum retry count
        func makeRequest(attempt: Int = 0) {
            print("Attempting request, attempt number: \(attempt)")
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    print("API Response Status Code: \(httpResponse.statusCode)")
                }
                
                if let error = error {
                    completion(.failure(.networkError(error)))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(.noData))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                            print("API Error: \(message)")
                            if (response as? HTTPURLResponse)?.statusCode == 429 {
                                if attempt < 5 {  // Increased max attempts
                                    let delay = Double(pow(2, Double(attempt))) * 2  // Increased delay
                                    print("Rate limited. Retrying in \(delay) seconds.")
                                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                        makeRequest(attempt: attempt + 1)
                                    }
                                    return
                                } else {
                                    completion(.failure(.apiError("Rate limit exceeded. Please try again later.")))
                                    return
                                }
                            }
                            completion(.failure(.apiError(message)))
                            return
                        }
                        
                        if let choices = json["choices"] as? [[String: Any]],
                           let message = choices.first?["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            let appNames = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            completion(.success(appNames))
                        } else {
                            completion(.failure(.apiError("Unexpected response structure")))
                        }
                    } else {
                        completion(.failure(.decodingError(NSError(domain: "JSONSerialization", code: 0, userInfo: nil))))
                    }
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            }.resume()
        }
        
        makeRequest()
    }
    
    func generateIcons(appNames: [String], theme: String, completion: @escaping (Result<[UIImage], OpenAIServiceError>) -> Void) {
        let endpoint = baseURL + "images/generations"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompts = appNames.map { "Create an app icon for '\($0)' in a \(theme) style" }
        let body: [String: Any] = [
            "model": "dall-e-3",
            "prompt": prompts.joined(separator: ". "),
            "n": 1,
            "size": "1024x1024",
            "quality": "standard"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                        completion(.failure(.apiError(message)))
                        return
                    }
                    
                    if let imageData = json["data"] as? [[String: String]] {
                        let imageURLs = imageData.compactMap { $0["url"] }
                        self.downloadImages(from: imageURLs, completion: completion)
                    } else {
                        completion(.failure(.apiError("Unexpected response structure")))
                    }
                } else {
                    completion(.failure(.decodingError(NSError(domain: "JSONSerialization", code: 0, userInfo: nil))))
                }
            } catch {
                completion(.failure(.decodingError(error)))
            }
        }.resume()
    }
    
    private func downloadImages(from urls: [String], completion: @escaping (Result<[UIImage], OpenAIServiceError>) -> Void) {
        let group = DispatchGroup()
        var images: [UIImage] = []
        var downloadError: OpenAIServiceError?
        
        for urlString in urls {
            group.enter()
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                
                if let error = error {
                    downloadError = .networkError(error)
                    return
                }
                
                guard let data = data else {
                    downloadError = .noData
                    return
                }
                
                if let image = UIImage(data: data) {
                    images.append(image)
                } else {
                    downloadError = .imageDownloadError
                }
            }.resume()
        }
        
        group.notify(queue: .main) {
            if let error = downloadError {
                completion(.failure(error))
            } else if images.isEmpty {
                completion(.failure(.imageDownloadError))
            } else {
                completion(.success(images))
            }
        }
    }
}
