<<<<<<< HEAD
# Yojana Wala - Farmer Welfare App

> "Something for the one who gives us food"

A Flutter application designed to connect farmers with government welfare schemes using OTP-based authentication.

## Features

- 🌱 **Farmer Login** - OTP-based phone authentication via Twilio (configured in Supabase)
- 👨‍💼 **Admin Login** - Email/password authentication for administrators
- 🔐 **Secure Authentication** - Powered by Supabase Auth
- 📱 **Beautiful UI** - Clean, modern design with green theme

## Getting Started

### Prerequisites

- Flutter SDK (3.5.0 or later)
- Dart SDK
- Android Studio / VS Code with Flutter extensions
- A device or emulator to run the app

### Installation

1. **Install dependencies:**
=======
# AgriSarthi Mobile App (Flutter)

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)](https://flutter.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-Auth-green)](https://supabase.com/)

AgriSarthi ("Agricultural Companion") is a state-of-the-art Flutter application empowering farmers to access government welfare schemes using just their voice. Designed with a focus on accessibility, language localization, and ease of use.

## 🌟 Key Features

### 🗣️ Smart Voice Assistant
- **Voice Navigation**: Navigate the entire app using voice commands in Hindi, Marathi, or English.
- **Conversational Apply**: "Apply for PM Kisan" triggers a guided application flow.
- **Status Enquiry**: "Check my application status" fetches real-time updates.

### 📱 User-Centric Design
- **One-Tap Login**: Simple OTP-based authentication via mobile number.
- **Document Locker**: Securely upload and manage documents (Aadhaar, Pan, Land Records) once and reuse them for multiple schemes.
- **Eligibility Check**: Automatically filters schemes based on the farmer's profile data.
- **Application Dashboard**: Track the progress of all submitted applications in one place.

### 👨‍💼 Admin Features
- **Scheme Management**: Add, update, or remove government schemes.
- **Application Review**: Review farmer applications and documents.
- **User Management**: Oversee farmer registrations.

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.10+)
- Dart SDK
- Android Studio / VS Code with Flutter extensions
- Android Device/Emulator

### Installation

1. **Navigate to Frontend Directory**
   ```bash
   cd FrontEnd2.0
   ```

2. **Install Dependencies**
>>>>>>> new
   ```bash
   flutter pub get
   ```

<<<<<<< HEAD
2. **Run the app:**
=======
3. **Configure Environment**
   Ensure `lib/core/config/supabase_config.dart` (or similar config file) contains your Supabase credentials.

4. **Run the App**
>>>>>>> new
   ```bash
   flutter run
   ```

<<<<<<< HEAD
### Project Structure

```
lib/
├── main.dart                     # App entry point
├── core/
│   ├── config/
│   │   └── supabase_config.dart  # Supabase credentials
│   ├── router/
│   │   └── app_router.dart       # Navigation routes
│   └── theme/
│       └── app_theme.dart        # App theme and colors
└── features/
    ├── auth/
    │   ├── providers/
    │   │   └── auth_provider.dart    # Auth state management
    │   ├── screens/
    │   │   ├── splash_screen.dart
    │   │   ├── welcome_screen.dart
    │   │   ├── farmer_login_screen.dart
    │   │   └── admin_login_screen.dart
    │   └── widgets/
    │       └── leaf_logo.dart
    └── home/
        └── screens/
            ├── farmer_home_screen.dart
            └── admin_home_screen.dart
```

## Authentication Flow

### Farmer (OTP Login)
1. User enters 10-digit phone number
2. Clicks "Get OTP" - sends SMS via Supabase + Twilio
3. Enters 4-digit OTP code
4. Clicks "Verify OTP" - verifies and logs in
5. Redirected to Farmer Dashboard

### Admin (Email/Password Login)
1. Clicks "Login as Admin"
2. Enters email and password
3. Clicks "Login" - authenticates via Supabase
4. Redirected to Admin Dashboard

## Supabase Configuration

The app is configured to use Supabase for authentication:

- **Supabase URL:** `https://djnhdraoijkxsrxgatht.supabase.co`
- **Auth Provider:** Supabase Auth with Twilio SMS integration

### Setting up Twilio in Supabase

Twilio is already configured in your Supabase project for OTP delivery.

## Tech Stack

- **Flutter** - UI Framework
- **Supabase Flutter** - Backend & Authentication
- **Provider** - State Management
- **Go Router** - Navigation
- **Pinput** - OTP Input Widget
- **Google Fonts** - Typography

## Next Steps

- [ ] Profile form screen for farmers
- [ ] Document upload functionality
- [ ] Admin scheme management
- [ ] Notifications system
- [ ] Document verification workflow

## License

This project is private and proprietary.
=======
## 🏗️ Project Structure

```
lib/
├── main.dart                  # App Entry Point
├── core/                      # Core configs (Theme, Router, API clients)
├── features/
│   ├── auth/                  # Login & OTP Logic
│   ├── home/                  # Dashboard Screens
│   ├── profile/               # Farmer Profile Management
│   ├── documents/             # Document Upload & Gallery
│   ├── schemes/               # Scheme Listing & Details
│   ├── applications/          # Tracking & Status
│   └── voice/                 # Voice Assistant Implementation
└── shared/                    # Reusable Widgets
```

## 🎤 Voice Commands Guide

| Command (English) | Hindi Example | Action |
|-------------------|---------------|--------|
| "Show Schemes" | "योजनाएं दिखाओ" | Lists eligible schemes |
| "Apply for [Scheme]" | "[Scheme] के लिए आवेदन करें" | Starts application process |
| "Check Status" | "स्थिति चेक करें" | Shows application status |
| "View Profile" | "प्रोफाइल दिखाओ" | Opens profile page |

## 🛠 Tech Stack
- **Frontend**: Flutter (Dart)
- **State Management**: Provider
- **Backend Service**: Supabase (Auth, Storage, Database)
- **Voice/Audio**: `speech_to_text`, `flutter_tts` (or custom integration)

## 🤝 Contributing
1. Fork the repo
2. Create feature branch (`git checkout -b feature/NewFeature`)
3. Commit changes
4. Push to branch
5. Create Pull Request

## 📄 License
MIT License.
>>>>>>> new
