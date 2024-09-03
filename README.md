# Fun Home Screen

Fun Home Screen is an iOS application that allows users to create custom app icons for their iPhone home screen.

## Features

- Upload screenshots of your iPhone home screen
- Extracts app names from the screenshots
- Generates custom app icons based on an input theme
- Can Save generated icons to your photo library

## How It Works

1. Upload up to 5 screenshots of your iPhone home screen
2. The app extracts app names from the screenshots using OpenAI's GPT-4 model
3. You enter a desired theme for your custom icons
4. The app generates custom icons using OpenAI's DALL-E 3 model
5. You can save the generated icons to your photo library

## Note

This app uses OpenAI's API and includes rate limiting to comply with the basic tier limit of 5 requests per minute. As a result, generating icons may take 5-10 minutes per home screen screenshot. Costs are at ~90 cents per home screen image (30 dalle generations). 

## Setup

To use this app, you need to insert your OpenAI API key in the `APIKeys.swift` file.
