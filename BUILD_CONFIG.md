# Build Configuration

RiskRadar no longer ships a `.env` file inside the app.

Run or build the Flutter app with Dart defines:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

For release builds, pass the same values to `flutter build apk`,
`flutter build appbundle`, or `flutter build ios`.

Do not put provider secrets such as Gemini API keys or Supabase service-role
keys in Flutter code, assets, or `.env` files. Those belong only in backend
services such as Supabase Edge Function secrets.

## AI Hazard Scanner

The AI scanner calls the Supabase Edge Function:

```text
analyze-hazard-image
```

Set the Gemini key as a Supabase secret, not in Flutter:

```powershell
supabase secrets set GEMINI_API_KEY=your-new-gemini-key
```

Then deploy the function:

```powershell
supabase functions deploy analyze-hazard-image
```

The function uses the logged-in user's Supabase JWT, so the app must be signed
in before using AI scanning.

## Notification Webhooks

The SOS and hazard notification Edge Functions require a shared webhook secret:

```powershell
supabase secrets set WEBHOOK_SHARED_SECRET=your-long-random-secret
```

Use the same value in the Supabase webhook request headers:

```text
x-riskradar-webhook-secret: your-long-random-secret
```

This stops random callers from triggering push notifications.

## Atomic Hazard Assignment

Run this SQL in the Supabase SQL Editor before using the new assignment flow:

```text
supabase/migrations/202605060001_atomic_hazard_assignment.sql
```

It creates the `assign_hazard_to_hse` RPC. The app uses that RPC so assigning a
hazard moves it from `hazards` to `assign_hazards` in one database transaction.
