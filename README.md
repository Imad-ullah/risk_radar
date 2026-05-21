# RiskRadar

RiskRadar is a Flutter workplace hazard reporting and response app for industrial, construction, and other high-risk environments. It helps workers report hazards quickly, lets officers triage and assign hazards, and gives HSE workers a focused task flow for resolving assigned safety issues.

The app is built around three production priorities:

- Offline-first reporting so safety events are not lost when connectivity is poor.
- Role-based workflows for Workers, Officers, and HSE Workers.
- Real-time updates, push notifications, and auditable sync behavior for safety-critical actions.

## User Roles

### Worker

Workers use RiskRadar to:

- Report hazards with type, severity, description, location, photos, and optional voice notes.
- View reported, ongoing, and resolved hazards.
- Receive status updates as hazards are assigned and resolved.
- Update their profile photo through the sync queue.
- Use emergency/SOS flows when immediate help is needed.

### Officer

Officers use RiskRadar to:

- Monitor active and resolved hazards across sites.
- Manage workers, HSE workers, sites, assignments, and emergency details.
- Assign hazards to HSE workers through the `assign_hazard_to_hse` RPC.
- Review resolution evidence and generate hazard reports.
- Receive real-time hazard notifications and site alerts.

### HSE Worker

HSE workers use RiskRadar to:

- See assigned tasks and active hazard work.
- Mark tasks in progress.
- Submit resolution notes, photos, and voice evidence.
- Maintain availability and current site state.
- Receive real-time task updates.

## Architecture Overview

RiskRadar follows a layered Flutter architecture:

```text
Screen / Widget
  -> Repository / Provider
  -> SyncRepository / Local SQLite cache
  -> SyncService / Supabase
```

Important paths:

- `lib/main.dart` initializes app-level error handling, local storage, Supabase, Firebase, notifications, and connectivity sync triggers.
- `lib/services/app_config.dart` reads Supabase client config from `--dart-define` values.
- `lib/services/sync_service.dart` drains queued writes and sends validated operations to Supabase.
- `lib/services/sync_policy.dart` enforces role, table, action, owner, required-field, status, and column-whitelist rules before sync.
- `lib/services/repositories/sync_repository.dart` stores pending writes in SQLite.
- `lib/services/database/database_helper.dart` owns local SQLite tables for hazards, sync queue, sites, and generic cache entries.
- `lib/services/providers/hazard_provider.dart` and `lib/services/providers/hse_task_provider.dart` provide Riverpod state with Supabase realtime subscriptions.
- `lib/shared/widgets/offline_banner.dart` and `lib/shared/widgets/realtime_connection_indicator.dart` surface offline and realtime status in the UI.

## Offline-First Sync

Writes are queued locally first and synced later by `SyncService`.

Current queued write examples include:

- Worker hazard reports.
- Officer site and personnel updates.
- HSE task status and resolution submissions.
- Profile image updates.
- Emergency contact updates.

The sync queue is persisted in SQLite table `sync_queue`. Each queued item stores:

- `id`
- `table_name`
- `action`
- `payload_json`
- `created_at`

Before any queued action reaches Supabase, `SyncPolicy` validates:

- The role can perform that table/action combination.
- The payload owner matches the signed-in user where required.
- Required fields are present.
- Status values are supported.
- No unknown columns are sent.

When connectivity returns, `main.dart` listens through `connectivity_plus` and triggers `SyncService.instance.run()`.

## Realtime and Notifications

RiskRadar uses Supabase realtime channels for hazard and task changes, plus Firebase Cloud Messaging and Awesome Notifications for push/local notifications.

Notification-related Edge Functions:

- `send-hazard-notification`
- `sos_dispatcher`

AI/image analysis Edge Function:

- `analyze-hazard-image`

Realtime connection state is surfaced in the app through `RealtimeConnectionIndicator`.

## Local Setup

### Prerequisites

Install:

- Flutter SDK compatible with Dart `^3.8.1`
- Android Studio or another Flutter-capable IDE
- Supabase CLI for backend migrations/functions
- Firebase CLI if updating Firebase project configuration

### Install Dependencies

```powershell
flutter pub get
```

### Run the App

RiskRadar does not use a Flutter `.env` file. Pass Supabase client config through Dart defines:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

For release builds, pass the same values:

```powershell
flutter build apk `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

See `BUILD_CONFIG.md` for the canonical build/config notes.

## Supabase Setup

### Migrations

Apply the migrations in order:

```text
supabase/migrations/202605050000_initial_schema.sql
supabase/migrations/202605060001_atomic_hazard_assignment.sql
```

The initial schema creates the main app tables, RLS policies, and storage buckets. The atomic assignment migration creates the `assign_hazard_to_hse` RPC used by the officer assignment flow.

Core tables include:

- `officers`
- `workers`
- `hse_workers`
- `sites`
- `hazards`
- `assign_hazards`
- `resolved_hazards`
- `user_fcm_tokens`
- `officer_emergency_contacts`
- `site_alerts`
- `error_logs`

Storage buckets:

- `hazard-images`
- `voice_notes`
- `profile-images`
- `resolutions`

Keep mobile validation, `SyncPolicy`, and database check constraints aligned when changing statuses, severities, or allowed columns.

### Edge Function Secrets

Set secrets in Supabase, not in Flutter code:

```powershell
supabase secrets set GEMINI_API_KEY=your-gemini-key
supabase secrets set FIREBASE_SERVICE_ACCOUNT=path-or-json-service-account
supabase secrets set WEBHOOK_SHARED_SECRET=your-long-random-secret
```

The notification functions also use Supabase-provided runtime values such as `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

### Deploy Edge Functions

```powershell
supabase functions deploy analyze-hazard-image
supabase functions deploy send-hazard-notification
supabase functions deploy sos_dispatcher
```

For webhook-protected functions, configure callers to send:

```text
x-riskradar-webhook-secret: your-long-random-secret
```

## Firebase Setup

Firebase is used for Cloud Messaging and initialized through `lib/firebase_options.dart`.

If Firebase project settings change, regenerate platform options with FlutterFire tooling and keep Android/iOS Firebase files in sync with the Firebase project.

## Tests and Analysis

Run static analysis:

```powershell
flutter analyze
```

Run unit/widget tests:

```powershell
flutter test test/sync_policy_test.dart test/hazard_model_test.dart test/widget_test.dart
```

Run the offline SQLite integration test:

```powershell
flutter test integration_test/offline_storage_integration_test.dart
```

Expected current result after the gap-fill work:

- Unit/widget tests pass.
- Offline SQLite integration tests pass.
- `flutter analyze` reports no issues.

## Development Rules

When adding features, preserve the layered architecture:

- Do not call Supabase directly from screens for writes.
- Queue writes through `SyncRepository` / `SyncService`.
- Keep validation in `SyncPolicy` strict and covered by tests.
- Use repositories/providers for reads and state management.
- Use `LoggerService` / `ErrorService` for error reporting.
- Keep secrets out of source code and pass Flutter client config with `--dart-define`.

## Useful Commands

```powershell
flutter pub get
flutter analyze
flutter test test/sync_policy_test.dart test/hazard_model_test.dart test/widget_test.dart
flutter test integration_test/offline_storage_integration_test.dart
```

```powershell
supabase functions deploy analyze-hazard-image
supabase functions deploy send-hazard-notification
supabase functions deploy sos_dispatcher
```
