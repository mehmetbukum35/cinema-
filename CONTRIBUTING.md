# Contributing to cinema+

Thank you for your interest in contributing to **cinema+**! This document provides guidelines and instructions on how to set up the development environment, follow style standards, and run tests.

---

## 📂 Project Structure

The project is structured as a monorepo containing both the Flutter frontend application and the PHP backend API:

*   `lib/` - Flutter application source code.
    *   `models/` - Data models.
    *   `providers/` - Riverpod state managers (Business logic).
    *   `screens/` - UI screens/pages.
    *   `services/` - Services for network calls, database helper, etc.
    *   `theme/` - Visual theme configurations.
    *   `widgets/` - Reusable UI widgets.
*   `test/` - Frontend unit and widget tests.
*   `backend/` - PHP backend codebase.
    *   `src/` - PHP controllers, middleware, and core API logic.
    *   `tests/` - Backend unit and integration tests (PHPUnit).

---

## ⚙️ Local Development Setup

### Frontend (Flutter)
1.  Ensure you have the Flutter SDK installed (stable channel).
2.  Install dependencies:
    ```bash
    flutter pub get
    ```
3.  Run the application locally:
    ```bash
    flutter run \
      --dart-define=TMDB_API_KEY=YOUR_TMDB_API_KEY \
      --dart-define=API_BASE_URL=http://localhost:8000 \
      --dart-define=WEB_PROFILE_BASE_URL=http://localhost:8000/profile
    ```

### Backend (PHP)
1.  Ensure you have PHP 8.4+ and Composer installed.
2.  Install composer dependencies:
    ```bash
    cd backend
    composer install
    ```
3.  Run a local development server:
    ```bash
    php -S localhost:8000 -t api
    ```

---

## 🧪 Running Tests

Always ensure all tests are passing before submitting any changes.

### Frontend Tests
Run all unit and widget tests:
```bash
flutter test
```

### Backend Tests
Run all PHPUnit tests:
```bash
cd backend
composer test
```

---

## 🎨 Code Style Guides

### Dart (Flutter)
*   Format your code using the official Dart formatter:
    ```bash
    dart format .
    ```
*   Ensure there are no analyzer warnings or errors:
    ```bash
    flutter analyze
    ```
*   Use Riverpod's `StateNotifier` or `Provider` architecture for state management.
*   Follow clean coding principles and write unit tests for any new provider/service logic.

### PHP (Backend)
*   Ensure compatibility with PHP 8.4+.
*   Write modular controller logic and unit tests using PHPUnit.
