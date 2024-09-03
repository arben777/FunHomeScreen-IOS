//
//  APIKeys.swift
//  FunHomeScreen
//
//  Created by Arben Gutierrez-Bujari on 9/2/24.
//

import Foundation


struct APIKeys {
    static let openAI = "INSERT OPENAI KEY HERE"
}
// Can be tier 1 as this application was made with rate limiting to be compliant with the maximum of 5 requests / min
// Note that this does make the image generation take 5 to 10 minutes for 1 homepage screenshot. Obviously not ideal at all
// Hoewever the tradeoff is again it works with the most basic OpenAI API tier. Can modify if you have higher rate avaible.
