// supabase/functions/send-hazard-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const WEBHOOK_SECRET_HEADER = "x-riskradar-webhook-secret";

// Load Firebase credentials from environment variable.
function parseFirebaseServiceAccount(): Record<string, string> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT is not configured.");
  }

  const trimmed = raw.trim();
  const unwrapped =
    (trimmed.startsWith("'") && trimmed.endsWith("'")) ||
    (trimmed.startsWith('"') && trimmed.endsWith('"'))
      ? trimmed.slice(1, -1)
      : trimmed;

  return JSON.parse(unwrapped);
}

const firebaseConfig = parseFirebaseServiceAccount();

interface HazardPayload {
  type: 'INSERT'
  table: string
  record: {
    id: string
    officer_uid?: string
    assigned_to?: string
    description: string
    severity: string
    image_url?: string
    hazard_type: string
  }
  old_record: null
}

// ✅ Helper: Convert PEM → ArrayBuffer (DER)
function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
    status,
  });
}

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

// Convert PEM to ArrayBuffer (DER).
function pemToArrayBuffer(pem: string): ArrayBuffer {
  // Remove all whitespace first, then remove the PEM headers/footers
  const b64 = pem
    .replace(/\s+/g, "")  // Remove ALL whitespace first
    .replace(/-----BEGIN[A-Z ]+-----/g, "")
    .replace(/-----END[A-Z ]+-----/g, "");

  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// ✅ Base64URL encode for JWT
function base64url(input: string): string {
  return btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function sanitizeText(value: unknown, maxLength = 300): string {
  return String(value ?? "")
    .replace(/<[^>]*>/g, "")
    .replace(/\b(?:javascript|vbscript|data)\s*:/gi, "")
    .replace(/\b(?:select|insert|update|delete|drop|alter|truncate|union|exec|execute)\b/gi, "")
    .replace(/(--|\/\*|\*\/|;)/g, "")
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

// ✅ Create OAuth2 token with proper key handling
async function createAccessToken(sa: any): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  // Convert PEM to DER
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const keyBuffer = pemToArrayBuffer(pem);

  // Import key
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  // Create JWT
  const encoder = new TextEncoder();
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const toSign = `${headerB64}.${payloadB64}`;

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(toSign),
  );

  const signatureB64 = base64url(
    String.fromCharCode(...new Uint8Array(signature))
  );

  const jwt = `${toSign}.${signatureB64}`;

  // Exchange for access token
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const json = await res.json();
  if (!json.access_token) {
    throw new Error(`Token error: ${JSON.stringify(json)}`);
  }

  return json.access_token;
}

async function sendNotification(
  token: string,
  hazardId: string,
  title: string,
  body: string,
  severity: string,
  sourceTable: string,
  imageUrl?: string
) {
  const url = `https://fcm.googleapis.com/v1/projects/${firebaseConfig.project_id}/messages:send`;
  const jwt = await createAccessToken(firebaseConfig);

  const message = {
    message: {
      token,
      notification: {
        title,
        body
      },
      data: {
        hazard_id: hazardId,
        title,
        body,
        severity,
        image_url: imageUrl || '',
        source_table: sourceTable,
        notification_type: 'assignment',
        priority: 'high',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'HIGH',
        notification: {
          title,
          body,
          channelId: 'Hazards Details',
          notificationPriority: 'PRIORITY_HIGH',
          defaultSound: true,
          defaultVibrateTimings: true,
          image: imageUrl || undefined,
        },
      },
      apns: { headers: { 'apns-priority': '10' } },
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });

  return await res.json();
}

serve(async (req) => {
  try {
    const unauthorized = requireWebhookSecret(req);
    if (unauthorized) return unauthorized;

    const payload: HazardPayload = await req.json();

    // Contractor/officer receives only SOS and 10m proximity alerts.
    // Assignment inserts are pushed only to the assigned HSE/safety officer.
    if (payload.type !== 'INSERT' || payload.table !== 'assign_hazards') {
      return jsonResponse({
        ignored: true,
        reason: 'Only assigned HSE hazard notifications are enabled here.',
        table: payload.table,
        type: payload.type,
      });
    }

    const hazard = payload.record;
    if (!hazard?.id || !hazard.assigned_to) {
      return jsonResponse({ error: 'Invalid assignment webhook payload.' }, 400);
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: recipient, error } = await supabaseClient
      .from('hse_workers')
      .select('fcm_token, first_name, last_name')
      .eq('id', hazard.assigned_to)
      .maybeSingle();

    if (error || !recipient?.fcm_token) {
      console.log(`No HSE FCM token found for ${hazard.assigned_to}`);
      return jsonResponse({ success: true, sent: 0 });
    }

    const description = sanitizeText(
      hazard.description || 'No description provided',
      300,
    );
    const hazardType = sanitizeText(hazard.hazard_type || 'Hazard', 80);
    const body = `${hazardType}: ${description.substring(0, 100)}`;

    const fcmResponse = await sendNotification(
      recipient.fcm_token,
      hazard.id,
      'Assigned Hazard',
      body,
      hazard.severity,
      payload.table,
      hazard.image_url
    );

    console.log('FCM Response:', JSON.stringify(fcmResponse, null, 2));

    if (fcmResponse.name) {
      console.log(`Assigned hazard notification sent to ${recipient.first_name} ${recipient.last_name}`);
      return jsonResponse({ success: true, fcmResponse });
    }

    console.error('FCM Error:', JSON.stringify(fcmResponse, null, 2));
    return jsonResponse({ success: false, error: 'Notification dispatch failed.' }, 500);

  } catch (error: any) {
    console.error('Error:', error);
    return jsonResponse({ success: false, error: 'Notification dispatch failed.' }, 500);
  }
});
