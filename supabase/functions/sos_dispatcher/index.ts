// supabase/functions/sos_dispatcher/index.ts

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { initializeApp, cert, getApps } from "npm:firebase-admin@11.11.0/app";
import { getMessaging } from "npm:firebase-admin@11.11.0/messaging";

const WEBHOOK_SECRET_HEADER = "x-riskradar-webhook-secret";

function requireWebhookSecret(req: Request): Response | null {
  const expectedSecret = Deno.env.get("WEBHOOK_SHARED_SECRET");
  if (!expectedSecret) {
    console.error("WEBHOOK_SHARED_SECRET is not configured.");
    return jsonResponse({ error: "Function secret is not configured." }, 500);
  }

  const receivedSecret = req.headers.get(WEBHOOK_SECRET_HEADER);
  if (receivedSecret !== expectedSecret) {
    return jsonResponse({ error: "Unauthorized webhook request." }, 401);
  }

  return null;
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
    status,
  });
}

// 1. Initialize Firebase Admin
// This reads the Firebase JSON credentials we will securely store in Supabase later.
const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
if (serviceAccountStr && getApps().length === 0) {
  try {
    const serviceAccount = JSON.parse(serviceAccountStr);
    initializeApp({ credential: cert(serviceAccount) });
  } catch (err) {
    console.error("Firebase initialization failed:", err);
  }
}

Deno.serve(async (req) => {
  try {
    const unauthorized = requireWebhookSecret(req);
    if (unauthorized) return unauthorized;

    // 2. Parse the Webhook Payload from Supabase
    // This gives us the new row that was just inserted into 'site_alerts'
    const payload = await req.json();
    const newAlert = payload.record;

    // Only process SOS alerts
    if (!newAlert || newAlert.alert_type !== 'SOS') {
      return jsonResponse({ ignored: true, reason: "Not an SOS alert." });
    }

    const reporterId = newAlert.reporter_uid;
    const alertMessage = newAlert.message || "EMERGENCY SOS Triggered!";

    // 3. Initialize Supabase Client with Admin rights
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 4. Fetch all FCM tokens EXCEPT the person who pressed the button
    const { data: tokensData, error } = await supabaseAdmin
      .from('user_fcm_tokens')
      .select('fcm_token')
      .neq('user_id', reporterId);

    if (error || !tokensData || tokensData.length === 0) {
      console.log("No target devices found.");
      return jsonResponse({ success: true, sent: 0 });
    }

    // Extract just the string tokens into an array
    const tokens = tokensData.map((t: any) => t.fcm_token);

    // 5. Construct the Firebase Payload
    // 🚨 We use a strict "data-only" payload so your Flutter background handler catches it
    const message = {
      data: {
        type: 'SOS',
        message: alertMessage,
        alert_id: newAlert.id
      },
      android: {
        priority: 'high', // Critical for waking up the OS network radio
      },
      tokens: tokens,
    };

    // 6. Send the Push Notification Multicast (Send to all tokens at once)
    const response = await getMessaging().sendMulticast(message);

    console.log(`SOS Sent. Success: ${response.successCount}, Failed: ${response.failureCount}`);

    return jsonResponse({ success: true, sent: response.successCount });

  } catch (error: any) {
    console.error("Error dispatching SOS:", error.message);
    return jsonResponse({ error: error.message }, 500);
  }
});
