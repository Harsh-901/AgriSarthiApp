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
   ```bash
   flutter pub get
   ```

2. **Run the app:**
   ```bash
   flutter run
   ```

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
