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
3.  Run the application locally (TMDB requests are proxied through the backend, so a local API key is not required on the client):
    ```bash
    flutter run \
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

---

## 📝 Commit Messages (Conventional Commits)

We use [Conventional Commits](https://www.conventionalcommits.org/) so history stays readable and changelogs can be generated later.

```
<type>(<scope>): <short summary>    ← imperative mood, ≤50 chars

Optional body: why the change was made, breaking changes, etc.
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | New user-facing feature |
| `fix` | Bug fix |
| `refactor` | Code restructure without behavior change |
| `perf` | Performance improvement |
| `test` | Adding or updating tests only |
| `docs` | Documentation only |
| `chore` | Tooling, deps, housekeeping |
| `ci` | CI/CD workflow changes |

### Examples

```
feat(social): add pending request count badge on tab
fix(sync): preserve local delete in last-write-wins conflict
refactor(match): extract couch mode into match/together_body.dart
test(widget): smoke test for ProfileScreen library header
ci(android): add release APK/AAB workflow on tag dispatch
```

### Scope hints

Use the area you touched: `social`, `sync`, `browse`, `match`, `profile`, `backend`, `notifications`, `ci`, etc.

> Past commits may use informal messages; apply this rule **from now on** — no need to rewrite history.

---

## Branch protection (`main`)

If you maintain the repo on GitHub, enable protection on `main` so CI must pass before merge:

### With GitHub CLI (recommended)

```bash
gh auth login
gh api repos/mehmetbukum35/cinema-/branches/main/protection \
  --method PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["CI"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

Adjust the `contexts` array if your workflow job name differs (check the green check name on a recent PR).

### Manual (GitHub web UI)

1. Open **Settings → Branches → Add branch protection rule**
2. Branch name pattern: `main`
3. Enable **Require status checks to pass before merging** and select the **CI** workflow
4. Enable **Require branches to be up to date before merging**
5. Disable force pushes and branch deletion (recommended)

If `gh` is not authenticated locally, use the web UI steps above — no CLI is required.
