# RiskRadar — Codebase Audit & Agent Gap-Fill Instruction Manual
### Version 1.0 | Generated: May 2026
### Purpose: Hand this document to an autonomous coding agent to complete all missing parts of the existing RiskRadar Flutter app.

---

> ⚠️ **AGENT DIRECTIVE — READ BEFORE TOUCHING ANY FILE**
>
> This document is a **gap-fill mission**, NOT a greenfield build. The app already exists at `https://github.com/Imad-ullah/risk_radar`. Your job is to:
> 1. Clone the repo
> 2. Audit against this document
> 3. Implement ONLY what is listed as MISSING or INCOMPLETE
> 4. **Never rewrite working code** — extend, fix, or add only
> 5. After each numbered STEP, output `✅ STEP [N] COMPLETE — AWAITING APPROVAL` and halt until the human approves

---

## SECTION 1 — WHAT ALREADY EXISTS (DO NOT TOUCH UNLESS TOLD)

The following is fully or substantially built. The agent must read these files to understand patterns before writing any new code.

### ✅ Authentication System
- `lib/auth/auth_wrapper.dart` — Complete offline-first boot sequence with cache-first loading, background refresh, role determination from 3 Supabase tables (`officers`, `workers`, `hse_workers`), FCM token save/clear on login/logout, deep link handling.
- `lib/auth/login_screen.dart` — Email + Google sign-in with rate limiting (3 attempts, 30s cooldown).
- `lib/auth/signup_screen.dart` — User signup flow.
- `lib/shared/screens/profile_setup_screen.dart` — First-time profile setup.

### ✅ Data Models
- `lib/shared/models/hazard.dart` — `Hazard` class with full column sets, `fromMap`, `toMap`, column whitelist constants.
- `lib/shared/models/user_models.dart` — `AppUser` interface, `Worker`, `HseWorker`, `Officer` concrete classes with `fromMap`/`toMap`.

### ✅ Offline-First Sync Engine
- `lib/services/sync_service.dart` — Queue-based sync with online check, insert/update/delete/RPC dispatch, S3 file upload on sync.
- `lib/services/sync_policy.dart` — Role-based column whitelisting and ownership validation for all sync operations.
- `lib/services/repositories/sync_repository.dart` — SQLite pending actions queue.
- `lib/services/repositories/sqlite_cache_store.dart` — SQLite-backed JSON cache store.

### ✅ Repository Layer
- `lib/services/repositories/auth_repository.dart` — Role/profile cache with per-role save/get methods.
- `lib/services/repositories/officer_repository.dart` — Officer profile + analytics cache.
- `lib/services/repositories/hazard_repository.dart` — Hazard data access layer.
- `lib/services/repositories/hse_repository.dart` — HSE worker data access layer.

### ✅ Core Services
- `lib/services/app_config.dart` — `--dart-define` based config (no `.env` in Flutter).
- `lib/services/app_initializer.dart` — Two-phase init: critical (Supabase + Firebase) and deferred (notifications + FCM).
- `lib/services/supabase_service.dart` — Profile image upload to Supabase Storage.
- `lib/services/hazard_service.dart` — AI hazard image analysis via Supabase Edge Function.
- `lib/services/local_storage_service.dart` — `SharedPreferences`-backed key-value store.
- `lib/services/logger_service.dart` — Structured logging.
- `lib/services/firebase_messaging_service.dart` — FCM initialization.

### ✅ Navigation
- `lib/shared/navigation/app_router.dart` — Named routes: `/`, `/login`, `/signup`, `/profile-setup`, `/officer-profile-setup`, `/officer-view-profile`, `/worker-view-profile`, `/hazard-scanner`.
- `lib/shared/navigation/app_navigator.dart` — Global navigator key.

### ✅ Notification System
- `lib/services/notifications/notification_handlers.dart` — Background FCM handler, notification action handlers.
- `lib/shared/hazards/hazard_notifier.dart` — Polling-based hazard notification with geolocation proximity.
- `lib/officers/notifications/officer_hazard_notifier.dart` — Officer-specific hazard polling.
- `lib/workers/settings/worker_hazard_notifier.dart` — Worker-specific hazard polling.

### ✅ Supabase Edge Functions (All Deployed)
- `supabase/functions/analyze-hazard-image/` — Gemini 2.5 Flash AI hazard detection from photo.
- `supabase/functions/send-hazard-notification/` — Firebase FCM push on hazard insert (webhook-triggered).
- `supabase/functions/sos_dispatcher/` — SOS multicast to all site users (webhook-triggered).

### ✅ Database
- `supabase/migrations/202605060001_atomic_hazard_assignment.sql` — Atomic `assign_hazard_to_hse` RPC with `FOR UPDATE` row lock.
- Tables confirmed in use: `hazards`, `assign_hazards`, `resolved_hazards`, `sites`, `officers`, `workers`, `hse_workers`, `user_fcm_tokens`, `officer_emergency_contacts`.

### ✅ Officer Screens (Partial)
- `lib/officers/screens/officer_home_screen.dart` — Officer dashboard with bottom nav.
- `lib/officers/screens/officer_analytics_screen.dart` — Analytics with fl_chart, time filters, site filters, cache-first loading.
- `lib/officers/screens/active_task.dart` — Active hazard task management.
- `lib/officers/screens/resolved_hazards_screen.dart` — Resolved hazards list.
- `lib/officers/screens/team_overview.dart` — Team member overview.
- `lib/officers/screens/hazard_report_generation_screen.dart` — PDF report generation.
- `lib/officers/sites/officer_sites_screen.dart` — Sites management.
- `lib/officers/sites/site_personnel_screen.dart` — Personnel per site.
- `lib/officers/labours/manage_workers_screen.dart` — Worker management.

### ✅ Worker Screens (Partial)
- `lib/workers/screens/worker_home_screen.dart` — Worker dashboard.
- `lib/workers/screens/worker_hazard_report_screen.dart` — Hazard reporting form.
- `lib/workers/screens/worker_ongoing_hazards_screen.dart` — Active hazards list.
- `lib/workers/screens/worker_resolved_hazards_screen.dart` — Resolved hazards.
- `lib/workers/tabs/ai_image.dart` — AI hazard image scanner (Gemini-powered).
- `lib/workers/tabs/my_hazards_screen.dart` — Worker's own hazards.

### ✅ HSE Worker Screens (Partial)
- `lib/hse_worker/screens/hse_worker_dashboard.dart` — HSE dashboard.
- `lib/hse_worker/screens/AssignedTasksScreen.dart` — Tasks assigned to HSE.
- `lib/hse_worker/screens/HSEWorkerResolvedHazardsScreen.dart` — HSE resolved view.
- `lib/hse_worker/screens/hazard_resolution_verification_screen.dart` — Resolution verification.

### ✅ Shared Components
- `lib/shared/hazards/hazard_details_screen.dart` — Full hazard detail view.
- `lib/shared/hazards/hazard_notifier.dart` — Base hazard notification logic.
- `lib/shared/hazards/orphaned_hazards_screen.dart` — Unassigned hazards.
- `lib/shared/hazards/resolved_hazard_report_screen.dart` — Resolution report view.
- `lib/shared/hazards/select_hazard_type_screen.dart` — Hazard type selector with SVG icons (14 types).
- `lib/shared/hazards/voice_note_recorder.dart` — Voice note recording.
- `lib/shared/screens/shared_emergency_sos_screen.dart` — SOS trigger screen.
- `lib/shared/widgets/` — `emergency_permission_dialog`, `full_image_viewer`, `liquid_loader`, `risk_radar_loader`, `voice_note_player`.
- `lib/shared/theme/app_colors.dart` — Brand color constants.

### ✅ Assets
- `assets/hazards/` — 14 SVG hazard icons.
- `assets/lottie/` — 3 Lottie animation files (crane, electrical, fire).
- `assets/audio/sos_alarm.wav`
- `assets/logo.png`, `assets/default_user.png`, `assets/google_logo.svg`

---

## SECTION 2 — COMPLETE AUDIT: WHAT IS MISSING OR INCOMPLETE

The following are the confirmed gaps identified by comparing the existing codebase against production requirements. These are your **only targets**.

---

### 🔴 GAP 1 — State Management: No Riverpod / Provider (Critical Architecture Gap)

**What exists:** Raw `StatefulWidget` + `setState` everywhere. Screens fetch data directly from Supabase inside `initState`. No shared reactive state.

**Problems this causes:**
- Data re-fetched on every screen push/pop — wasteful and slow
- No shared loading/error state across screens
- No reactive updates when Supabase data changes
- Impossible to unit test business logic cleanly

**What to build:**
- Add `flutter_riverpod` to `pubspec.yaml`
- Create providers for the three core data domains:
  - `hazardProvider` — streams the active hazards list (Supabase realtime subscription)
  - `userProfileProvider` — exposes cached user profile (reads from `AuthRepository`)
  - `notificationCountProvider` — streams unread notification count
- Wrap `MyApp` in `ProviderScope`
- **DO NOT refactor all screens** — only wire providers into the 3 highest-traffic screens:
  - `OfficerHomeScreen`
  - `WorkerHomeScreen`
  - `HSEWorkerHomeScreen`
- Keep `StateNotifier` pattern: `HazardNotifier extends StateNotifier<AsyncValue<List<Hazard>>>`

---

### 🔴 GAP 2 — Missing Supabase Realtime Subscriptions (Critical UX Gap)

**What exists:** All data loading is one-shot `await supabase.from(...).select()` in `initState`. No realtime.

**What to build:**
- Add Supabase Realtime channel subscriptions for:
  - `hazards` table — `INSERT`, `UPDATE` events → update `hazardProvider` state
  - `assign_hazards` table — `INSERT`, `UPDATE` events → update HSE worker task list
- Subscribe in the Riverpod notifier's constructor. Dispose on `ref.onDispose`.
- Channel filter: always filter by `officer_uid` or `assigned_to` = current user ID to avoid receiving all rows
- Show a small animated indicator (green dot) in the app bar when realtime is connected
- Handle reconnection: on `AppLifecycleState.resumed`, call `supabase.realtime.reconnect()` if channel is in disconnected state

---

### 🔴 GAP 3 — No Error Boundary or Global Error Handling (Critical Stability Gap)

**What exists:** Scattered `try/catch` blocks with `debugPrint`. No user-visible error feedback on network failures. Silent failures everywhere.

**What to build:**
- Create `lib/shared/widgets/error_boundary.dart` — a `StatefulWidget` that wraps children and catches Flutter rendering errors via `ErrorWidget.builder`
- Create `lib/shared/widgets/async_value_widget.dart` — a generic widget that handles `AsyncValue` loading/error/data states with consistent UI:
  ```dart
  class AsyncValueWidget<T> extends StatelessWidget {
    // Shows RiskRadarLoader on loading
    // Shows ErrorRetryWidget on error
    // Shows data widget on success
  }
  ```
- Create `lib/shared/widgets/error_retry_widget.dart` — consistent error UI with retry button
- Create `lib/services/error_service.dart` — centralized error reporting:
  - In debug: `debugPrint` with full stack trace
  - In release: send to Supabase `error_logs` table (non-blocking, fire-and-forget)
  - Never crash the app on non-fatal errors
- Add `FlutterError.onError` and `PlatformDispatcher.instance.onError` handlers in `main()` before `runApp()`

---

### 🔴 GAP 4 — Missing Complete HSE Worker Flow (Feature Gap)

**What exists:** `hse_worker_dashboard.dart`, `AssignedTasksScreen.dart`, `HSEWorkerResolvedHazardsScreen.dart`, `hazard_resolution_verification_screen.dart` exist as screens but the resolution flow is incomplete.

**What is missing:**
- **Resolution submission**: HSE worker must be able to mark a task as `in_progress` → `resolved` with:
  - Resolution notes (text field, required)
  - Resolution photo (image_picker, required — at least 1 photo)
  - Resolution voice note (optional, uses existing `voice_note_recorder.dart`)
- **Offline resolution**: if offline, queue the resolution in SQLite via `SyncService` with `action: 'update'` on `assign_hazards` table
- **`lib/hse_worker/screens/hse_worker_resolution_form_screen.dart`** — NEW FILE: Full resolution form screen
  - Takes `Hazard` as constructor argument
  - Fields: resolution notes, photo picker (min 1, max 3), voice note recorder (optional)
  - Submit button: validates → calls `SyncService` queue → shows success snackbar → pops screen
- Wire the form into `AssignedTasksScreen` — tapping a task card opens `hse_worker_resolution_form_screen`
- Add `report_number` auto-generation: `RR-{year}-{5-digit-sequential-number}` — fetch next number from a Supabase sequence or use `uuid` short form

---

### 🔴 GAP 5 — Missing Worker Hazard Detail Screen (Feature Gap)

**What exists:** `lib/workers/details/worker_hazard_details_screen.dart` file exists but is referenced without confirmation of completeness.

**What is missing:**
- Full hazard detail view for workers showing:
  - Hazard type + severity badge (color-coded: Critical=red, High=orange, Medium=yellow, Low=green)
  - Description
  - Photo viewer (uses existing `full_image_viewer.dart`)
  - Voice note player (uses existing `voice_note_player.dart`)
  - Location map thumbnail (static Google Maps image or `geolocator` coordinates display)
  - Status timeline: `reported → assigned → in_progress → resolved`
  - If status is `resolved`: show resolution notes + resolution photo

---

### 🔴 GAP 6 — Missing Offline Indicator UI (UX Gap)

**What exists:** `connectivity_plus` package is in `pubspec.yaml`. There is no visible offline indicator anywhere in the UI.

**What to build:**
- Create `lib/shared/widgets/offline_banner.dart` — an animated banner that:
  - Slides down from the top when connectivity is lost
  - Shows: `📡 You're offline. Changes will sync when reconnected.`
  - Background: `Colors.orange.shade700`
  - Slides back up automatically when reconnected
  - Uses `connectivity_plus` `onConnectivityChanged` stream
- Create `lib/services/connectivity_service.dart` — singleton that wraps `connectivity_plus` and exposes:
  - `Stream<bool> get isOnlineStream`
  - `bool get isOnline` (synchronous getter)
- Add `OfflineBanner` as the topmost widget in all three home screens (`OfficerHomeScreen`, `WorkerHomeScreen`, `HSEWorkerHomeScreen`) wrapped in a `Column` above the current body

---

### 🔴 GAP 7 — Missing Pull-to-Refresh on All List Screens (UX Gap)

**What exists:** Data loads once in `initState`. No refresh mechanism.

**What to build:**
- Wrap the list content in ALL the following screens with `RefreshIndicator`:
  - `worker_ongoing_hazards_screen.dart`
  - `worker_resolved_hazards_screen.dart`
  - `workers/tabs/my_hazards_screen.dart`
  - `hse_worker/screens/AssignedTasksScreen.dart`
  - `hse_worker/screens/HSEWorkerResolvedHazardsScreen.dart`
  - `officers/screens/resolved_hazards_screen.dart`
  - `officers/screens/active_task.dart`
- `RefreshIndicator.onRefresh` must: clear local cache for that screen → re-fetch from Supabase → update state
- Color the refresh indicator with brand teal `Color(0xFF1B3D3D)`

---

### 🔴 GAP 8 — No Pagination on Hazard Lists (Performance Gap)

**What exists:** All list screens fetch all rows with no `limit` or `range`. On a large site this will OOM the device.

**What to build:**
- Implement cursor-based pagination on all hazard list screens:
  - Page size: 20 rows per fetch
  - Fetch strategy: `supabase.from(...).select().order('created_at', ascending: false).range(offset, offset + 19)`
  - Add a `ScrollController` to each list — detect when user scrolls to 80% of list height → load next page
  - Show a `CircularProgressIndicator` at the bottom of the list while loading more
  - Stop fetching when returned rows < 20 (last page reached)
- Apply to all screens listed in GAP 7 plus `orphaned_hazards_screen.dart`

---

### 🔴 GAP 9 — Missing Officer Profile Edit (Feature Gap)

**What exists:** `lib/officers/settings/edit_officer_profile_screen.dart` exists and is registered as a named route (`/officer-profile-setup`).

**What is missing (verify by reading the file first):**
- If the screen exists but doesn't save: add save logic that queues an `update` on `officers` table via `SyncService`
- Profile fields required: `first_name`, `last_name`, `dob` (date picker), `profile_image_url` (image_picker + upload)
- On save: validate non-empty `first_name` and `last_name` → queue sync → show success snackbar
- Profile image upload: use existing `SupabaseService.uploadProfileImage()` — pass local file path in `image_paths` field of sync payload so `SyncService._preparePayload` handles the upload

---

### 🔴 GAP 10 — Missing Worker Profile View/Edit (Feature Gap)

**What exists:** `lib/workers/settings/worker_view_profile_screen.dart` exists and is registered as `/worker-view-profile`.

**What is missing:**
- Worker must be able to update their `profile_image_url` only (workers cannot edit name/email — only officer can)
- Add an edit photo button (camera icon overlay on avatar)
- On tap: `image_picker` → crop via `image_cropper` → pass local path to sync queue as `image_paths` for the `workers` table `update` action

---

### 🔴 GAP 11 — No Input Validation on Hazard Report Form (Security Gap)

**What exists:** `worker_hazard_report_screen.dart` collects hazard data but validation state is unclear.

**What to build / verify:**
- Read `worker_hazard_report_screen.dart` fully. Then enforce:
  - `hazard_type` — required, must be one of the 14 allowed types from `select_hazard_type_screen.dart`
  - `description` — required, min 10 characters, max 500 characters
  - `severity` — required, must be one of: `Critical`, `High`, `Medium`, `Low`
  - `latitude` / `longitude` — required, auto-populated from `Geolocator.getCurrentPosition()` — show error if location permission denied
  - `image_url` — at least 1 photo required
- Show inline field errors below each field using `TextFormField` validator pattern
- Disable submit button while any field is invalid

---

### 🔴 GAP 12 — Missing Integration Tests (Quality Gap)

**What exists:** `integration_test/offline_storage_integration_test.dart` (partial), `test/sync_policy_test.dart` (partial), `test/widget_test.dart` (default empty test).

**What to build:**
- `test/sync_policy_test.dart` — Expand to cover ALL `SyncPolicy` paths:
  - `validateSyncAction` for each table + action + role combination
  - Verify `SyncValidationException` is thrown for disallowed role+table+action combos
  - Verify column whitelist enforcement (unknown column → exception)
  - Verify `_requirePayloadOwner` rejects mismatched user IDs
- `test/hazard_model_test.dart` — NEW: Test `Hazard.fromMap` round-trips correctly for all fields
- `integration_test/offline_storage_integration_test.dart` — Complete: test that a hazard queued offline appears in `sync_queue` SQLite table and is removed after successful sync mock

---

### 🔴 GAP 13 — Missing Supabase Database Migrations (Backend Gap)

**What exists:** Only one migration file: `202605060001_atomic_hazard_assignment.sql`.

**What is missing:** The full schema has never been committed to `supabase/migrations/`. This means a fresh Supabase project cannot be bootstrapped from the repo alone.

**What to build:**
- Create `supabase/migrations/202605050000_initial_schema.sql` (dated before the existing migration) containing:
  - Full `CREATE TABLE` statements for all tables with correct columns matching what `SyncPolicy` and models expect:
    - `officers` (id uuid PK, first_name, last_name, email, role, officer_uid, profile_image_url, fcm_token, dob, created_at)
    - `workers` (id uuid PK, first_name, last_name, email, role, officer_uid, work_type, profile_image_url, is_active, default_site_id, current_site_id, fcm_token, created_at)
    - `hse_workers` (id uuid PK, first_name, last_name, email, role, officer_uid, designation, profile_image_url, is_active, is_available, current_site_id, fcm_token, created_at)
    - `sites` (id uuid PK, name, description, officer_uid, created_at)
    - `hazards` (id uuid PK, worker_id, hazard_type, description, severity, latitude, longitude, status, created_at, image_url, voice_note_url, officer_uid, current_site_id, orphaned bool, resolved_at, ranking_score, assigned_to)
    - `assign_hazards` (same as hazards + assigned_at, started_at, resolution_notes, resolution_image_url, resolution_voice_note_url, report_number)
    - `resolved_hazards` (same as assign_hazards)
    - `user_fcm_tokens` (id uuid PK, user_id uuid UNIQUE, fcm_token text, created_at)
    - `officer_emergency_contacts` (id uuid PK, officer_id, officer_uid, contact_name, relationship, personal, blood_type, chronic_conditions, ambulance, fire_brigade, supervisor, emergency_contact_name, emergency_contact_phone, emergency_contact_relation, blood_group, medical_conditions, allergies, medications, home_address)
    - `site_alerts` (id uuid PK, reporter_uid, alert_type, message, created_at)
    - `error_logs` (id uuid PK, user_id, error_message, stack_trace, created_at) — for GAP 3
  - All `uuid_generate_v4()` defaults
  - All FK constraints
  - RLS policies: `authenticated` users can only read/write their own rows (based on `auth.uid()`)
  - Supabase Storage buckets: `hazard-images` (public), `voice_notes` (public), `profile-images` (public), `resolutions` (public)

---

### 🔴 GAP 14 — Missing `README.md` Update (Documentation Gap)

**What exists:** `README.md` is the default Flutter README with no project-specific content.

**What to build:**
- Complete `README.md` with:
  - Project description and purpose
  - Three user roles explained (Officer, Worker, HSE Worker)
  - Local setup instructions: `flutter pub get`, `--dart-define` build commands from `BUILD_CONFIG.md`
  - Supabase setup: required tables, storage buckets, edge function deployment commands
  - Edge function secrets: `GEMINI_API_KEY`, `FIREBASE_SERVICE_ACCOUNT`, `WEBHOOK_SHARED_SECRET`
  - How to run integration tests
  - Architecture overview: offline-first sync, role-based auth, realtime subscriptions

---

### 🟡 GAP 15 — Code Quality: `dynamic` Types in Models (Minor but Important)

**What exists:** All model fields in `user_models.dart` and `hazard.dart` use `dynamic` type for every field. This bypasses Dart's type system entirely.

**What to build:**
- Refactor `Hazard` model — replace `dynamic` with proper types:
  - `id: String?`, `workerId: String?`, `hazardType: String?`, `description: String?`
  - `severity: String?`, `latitude: double?`, `longitude: double?`, `status: String?`
  - `imageUrl: String?`, `orphaned: bool?`, `rankingScore: double?`
- Refactor `Worker`, `HseWorker`, `Officer` models similarly
- Update all `fromMap` factories to use safe casting: `row['id'] as String?` instead of `row['id']`
- **Do NOT change field names or map keys** — only the Dart types
- Run `flutter analyze` after — zero warnings allowed

---

### 🟡 GAP 16 — Missing `fcm_token` Column Handling in `SyncPolicy` (Minor Security Gap)

**What exists:** `SyncPolicy.allowedColumnsFor('officers', 'update')` returns `{'id', 'first_name', 'last_name', 'email', 'dob', 'profile_image_url', ...localUploadColumns}`. The `fcm_token` column is NOT whitelisted.

**Problem:** FCM token updates are done directly in `auth_wrapper.dart` bypassing the sync queue (online-only). This is actually correct behaviour for tokens — but `hse_workers` update whitelist is missing `is_available` which is needed for the availability toggle.

**What to build:**
- Add `'is_available'` to `hse_workers` update allowed columns in `SyncPolicy.allowedColumnsFor`
- Add a test in `sync_policy_test.dart` verifying `hse_worker` role can update `is_available` on `hse_workers`
- Add HSE Worker availability toggle (ON/OFF switch) to `hse_worker_app_settings_screen.dart` that queues a sync update

---

## SECTION 3 — TECHNOLOGY RULES (CARRY OVER FROM EXISTING CODE)

The agent must match the existing technology choices exactly:

| Layer | Technology | Version (from pubspec.yaml) |
|---|---|---|
| Framework | Flutter | SDK ^3.8.1 |
| Backend | Supabase | supabase_flutter: 2.12.0 |
| Auth | Supabase Auth + Google Sign-In | google_sign_in: 7.2.0 |
| Local DB | SQLite | sqflite: 2.4.2 |
| Notifications | Awesome Notifications + FCM | awesome_notifications: 0.10.1, firebase_messaging: 16.1.1 |
| Charts | fl_chart | 1.2.0 |
| State (to add) | Riverpod | Latest stable |
| Maps | geolocator | 14.0.2 |
| Images | image_picker + cached_network_image + image_cropper | As in pubspec |
| Audio | record + audioplayers + audio_waveforms | As in pubspec |
| PDF | pdf + printing | As in pubspec |
| Connectivity | connectivity_plus | 7.1.1 |
| Config | `--dart-define` only | Never use `.env` in Flutter |

### Prohibited in this project:
- `Provider` package (use Riverpod only)
- `GetX` (not in stack)
- `http` package for Supabase calls (use `supabase_flutter` client)
- Hardcoded Supabase URL or anon key in source code
- `var` or `dynamic` for new code (except where absolutely necessary with a comment explaining why)
- `debugPrint` for error reporting in new code (use `LoggerService`)

---

## SECTION 4 — FILE NAMING & CODE CONVENTIONS (MATCH EXISTING PATTERNS)

- **File names:** `snake_case.dart`
- **Class names:** `PascalCase`
- **Brand colors:** Always use `Color(0xFF1B3D3D)` for primary teal and `Color(0xFFE6A050)` for accent gold. Never hardcode other colors inline — use `AppColors`.
- **Supabase calls:** Always in repository classes (`lib/services/repositories/`), never directly in screen `build()` methods
- **Error handling:** Always `try/catch` around Supabase calls. On error, call `LoggerService.error(...)`. Show user-facing `SnackBar` with red background
- **Offline writes:** Always queue through `SyncService` — never call `supabase.from(...).insert/update/delete()` directly from screens
- **Comments:** Use the existing comment style — section separators with `// ══════` for major sections, `// ──────` for subsections

---

## SECTION 5 — AGENT EXECUTION PLAN

> ⚠️ STOP after each step. Output `✅ STEP [N] COMPLETE — AWAITING APPROVAL`. Do not proceed until explicitly told.

---

### STEP 1 — Clone & Audit
```
git clone https://github.com/Imad-ullah/risk_radar.git
cd risk_radar
flutter pub get
flutter analyze
```
- Read every file listed in SECTION 1 before writing a single line of code
- Output a brief confirmation of what you found matches this document
- Report any discrepancies between this document and the actual file contents

---

### STEP 2 — Database Migration (GAP 13)
- Create `supabase/migrations/202605050000_initial_schema.sql` with full schema as specified in GAP 13
- Validate all column names against `SyncPolicy.allowedColumnsFor()` and model `fromMap` factories
- Verify it is ordered before `202605060001_atomic_hazard_assignment.sql`

---

### STEP 3 — Type Safety Refactor (GAP 15)
- Refactor `Hazard`, `Worker`, `HseWorker`, `Officer` models: replace `dynamic` with proper Dart types
- Run `flutter analyze` — zero errors or warnings before proceeding

---

### STEP 4 — SyncPolicy Fix + HSE Availability (GAP 16)
- Add `is_available` to HSE worker allowed columns in `SyncPolicy`
- Add availability toggle to `hse_worker_app_settings_screen.dart`
- Add test cases in `sync_policy_test.dart` for GAP 16

---

### STEP 5 — Connectivity Service + Offline Banner (GAP 6)
- Build `lib/services/connectivity_service.dart`
- Build `lib/shared/widgets/offline_banner.dart`
- Integrate into `OfficerHomeScreen`, `WorkerHomeScreen`, `HSEWorkerHomeScreen`

---

### STEP 6 — Error Handling Infrastructure (GAP 3)
- Build `lib/services/error_service.dart`
- Build `lib/shared/widgets/error_boundary.dart`
- Build `lib/shared/widgets/async_value_widget.dart`
- Build `lib/shared/widgets/error_retry_widget.dart`
- Wire `FlutterError.onError` and `PlatformDispatcher.instance.onError` in `main()`

---

### STEP 7 — Riverpod State Management (GAP 1)
- Add `flutter_riverpod` to `pubspec.yaml`, run `flutter pub get`
- Wrap `MyApp` in `ProviderScope`
- Create `lib/services/providers/hazard_provider.dart`
- Create `lib/services/providers/user_profile_provider.dart`
- Create `lib/services/providers/notification_count_provider.dart`
- Wire into the 3 home screens only

---

### STEP 8 — Supabase Realtime Subscriptions (GAP 2)
- Add realtime subscriptions to `hazardProvider` and HSE task provider
- Add realtime connection indicator to app bars
- Handle reconnection on `AppLifecycleState.resumed`

---

### STEP 9 — Pull-to-Refresh + Pagination (GAPs 7 & 8)
- Add `RefreshIndicator` to all 8 list screens
- Implement cursor-based pagination (page size 20) on all hazard list screens
- Add scroll-based load-more trigger and bottom loading indicator

---

### STEP 10 — Hazard Report Form Validation (GAP 11)
- Read `worker_hazard_report_screen.dart` in full
- Add/enforce all input validation rules as specified in GAP 11
- Add location permission handling with user-facing error if denied

---

### STEP 11 — HSE Resolution Form (GAP 4)
- Create `lib/hse_worker/screens/hse_worker_resolution_form_screen.dart`
- Implement resolution notes + photo + optional voice note
- Wire into `AssignedTasksScreen` task card tap
- Add offline queue support via `SyncService`
- Add `report_number` generation

---

### STEP 12 — Worker & Officer Profile Edits (GAPs 9 & 10)
- Verify and complete `edit_officer_profile_screen.dart` save flow
- Add worker profile photo update in `worker_view_profile_screen.dart`
- Both must route through `SyncService` queue

---

### STEP 13 — Worker Hazard Detail Screen (GAP 5)
- Verify `worker_hazard_details_screen.dart` completeness
- Add any missing fields: severity badge, status timeline, resolution section

---

### STEP 14 — Tests (GAP 12)
- Expand `sync_policy_test.dart` to full coverage
- Create `test/hazard_model_test.dart`
- Complete `integration_test/offline_storage_integration_test.dart`
- Run all tests — 100% pass rate required before this step is complete

---

### STEP 15 — README Update (GAP 14)
- Rewrite `README.md` with full project documentation as specified in GAP 14

---

### STEP 16 — Final QA
Before declaring the project complete, verify every item:
- [ ] `flutter analyze` — zero warnings or errors
- [ ] `flutter test` — all tests pass
- [ ] Offline mode: disconnect wifi → create hazard → reconnect → verify sync completes
- [ ] Realtime: insert hazard in Supabase dashboard → verify it appears in officer screen without refresh
- [ ] SOS button → verify all users receive FCM notification
- [ ] AI scanner: upload a photo with safety violations → verify Gemini returns hazards
- [ ] Officer approves worker → worker sees assignment in HSE tasks
- [ ] HSE resolves task offline → reconnect → verify `resolved_hazards` row in Supabase
- [ ] Pull-to-refresh works on all 8 list screens
- [ ] Offline banner appears immediately when wifi disconnected
- [ ] No `dynamic` types in new code — `flutter analyze` confirms
- [ ] All secret keys only via `--dart-define`, never in source files

---

## SECTION 6 — QUICK REFERENCE: KEY FILE LOCATIONS

```
lib/
├── auth/
│   ├── auth_wrapper.dart          ← Boot sequence, DO NOT rewrite
│   ├── login_screen.dart          ← Email + Google auth
│   └── signup_screen.dart
├── services/
│   ├── app_config.dart            ← --dart-define config
│   ├── app_initializer.dart       ← Two-phase init
│   ├── sync_service.dart          ← Offline queue engine ← READ BEFORE WRITING ANYTHING
│   ├── sync_policy.dart           ← Column whitelist + RBAC ← READ BEFORE WRITING ANYTHING
│   ├── connectivity_service.dart  ← TO BUILD (GAP 6)
│   ├── error_service.dart         ← TO BUILD (GAP 3)
│   ├── repositories/
│   │   ├── auth_repository.dart   ← Profile cache
│   │   ├── sync_repository.dart   ← SQLite queue
│   │   ├── hazard_repository.dart
│   │   ├── hse_repository.dart
│   │   └── officer_repository.dart
│   └── providers/                 ← TO BUILD (GAP 1)
│       ├── hazard_provider.dart
│       ├── user_profile_provider.dart
│       └── notification_count_provider.dart
├── shared/
│   ├── models/
│   │   ├── hazard.dart            ← Refactor types (GAP 15)
│   │   └── user_models.dart       ← Refactor types (GAP 15)
│   ├── widgets/
│   │   ├── offline_banner.dart    ← TO BUILD (GAP 6)
│   │   ├── error_boundary.dart    ← TO BUILD (GAP 3)
│   │   ├── async_value_widget.dart← TO BUILD (GAP 3)
│   │   └── error_retry_widget.dart← TO BUILD (GAP 3)
│   └── hazards/
│       └── select_hazard_type_screen.dart ← 14 hazard types source of truth
├── hse_worker/screens/
│   └── hse_worker_resolution_form_screen.dart ← TO BUILD (GAP 4)
supabase/
├── migrations/
│   ├── 202605050000_initial_schema.sql      ← TO BUILD (GAP 13)
│   └── 202605060001_atomic_hazard_assignment.sql ← EXISTS
└── functions/
    ├── analyze-hazard-image/      ← EXISTS, DO NOT TOUCH
    ├── send-hazard-notification/  ← EXISTS, DO NOT TOUCH
    └── sos_dispatcher/            ← EXISTS, DO NOT TOUCH
```

---

*Document Version: 1.0 | Audit Date: May 2026*
*This document supersedes all verbal instructions. The agent must not deviate from it.*
