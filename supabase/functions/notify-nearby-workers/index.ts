import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const WEBHOOK_SECRET_HEADER = "x-riskradar-webhook-secret";
const PROXIMITY_RADIUS_METERS = 25;
const LOCATION_MAX_AGE_MINUTES = 10;

function logDispatchResult(summary: Record<string, unknown>): void {
  console.log("Worker proximity dispatch result:", JSON.stringify(summary));
}

interface HazardInsertPayload {
  type: "INSERT";
  table: string;
  record: {
    id: string;
    worker_id?: string;
    officer_uid?: string;
    current_site_id?: string;
    hazard_type?: string;
    description?: string;
    severity?: string;
    image_url?: string;
    latitude: number;
    longitude: number;
  };
  old_record: null;
}

interface FirebaseServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function requireWebhookSecret(req: Request): Response | null {
  const expectedSecret = Deno.env.get("WEBHOOK_SHARED_SECRET");
  if (!expectedSecret) {
    console.error("WEBHOOK_SHARED_SECRET is not configured.");
    return jsonResponse({ error: "Function secret is not configured." }, 500);
  }

  if (req.headers.get(WEBHOOK_SECRET_HEADER) !== expectedSecret) {
    return jsonResponse({ error: "Unauthorized webhook request." }, 401);
  }

  return null;
}

function parseFirebaseServiceAccount(): FirebaseServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT is not configured.");
  }

  const trimmed = raw.trim();
  const unwrapped =
    ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
      (trimmed.startsWith('"') && trimmed.endsWith('"')))
      ? trimmed.slice(1, -1)
      : trimmed;

  return JSON.parse(unwrapped);
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/\s+/g, "")
    .replace(/-----BEGIN[A-Z ]+-----/g, "")
    .replace(/-----END[A-Z ]+-----/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function base64url(input: string): string {
  return btoa(input)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function createAccessToken(
  serviceAccount: FirebaseServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsignedToken = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key.replace(/\\n/g, "\n")),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken),
  );
  const encodedSignature = base64url(
    String.fromCharCode(...new Uint8Array(signature)),
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsignedToken}.${encodedSignature}`,
    }),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token) {
    throw new Error(`Firebase access token failed: ${JSON.stringify(result)}`);
  }
  return result.access_token;
}

function sanitizeText(value: unknown, maxLength: number): string {
  return String(value ?? "")
    .replace(/<[^>]*>/g, "")
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

function toRadians(degrees: number): number {
  return degrees * Math.PI / 180;
}

function distanceMeters(
  fromLatitude: number,
  fromLongitude: number,
  toLatitude: number,
  toLongitude: number,
): number {
  const earthRadiusMeters = 6371000;
  const latitudeDelta = toRadians(toLatitude - fromLatitude);
  const longitudeDelta = toRadians(toLongitude - fromLongitude);
  const startLatitude = toRadians(fromLatitude);
  const endLatitude = toRadians(toLatitude);
  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(startLatitude) *
      Math.cos(endLatitude) *
      Math.sin(longitudeDelta / 2) ** 2;
  return 2 * earthRadiusMeters *
    Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
}

function proximityLabel(distance: number): string {
  const roundedDistance = Math.max(1, Math.round(distance));
  if (roundedDistance <= PROXIMITY_RADIUS_METERS) {
    return `within ${PROXIMITY_RADIUS_METERS} m`;
  }
  return `${roundedDistance} m away`;
}

async function sendProximityNotification(params: {
  accessToken: string;
  serviceAccount: FirebaseServiceAccount;
  token: string;
  hazard: HazardInsertPayload["record"];
  distance: number;
}): Promise<{ ok: boolean; response: unknown }> {
  const title = sanitizeText(
    params.hazard.hazard_type || "Nearby Hazard",
    80,
  );
  const description = sanitizeText(
    params.hazard.description || "A hazard was reported near you. Stay safe!",
    180,
  );
  const roundedDistance = Math.max(1, Math.round(params.distance));
  const body = `${description} (${proximityLabel(params.distance)})`;
  const url =
    `https://fcm.googleapis.com/v1/projects/${params.serviceAccount.project_id}/messages:send`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${params.accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token: params.token,
        data: {
          type: "NEARBY_HAZARD",
          notification_type: "worker_proximity",
          hazard_id: params.hazard.id,
          source_table: "hazards",
          title,
          body,
          severity: String(params.hazard.severity || "low"),
          image_url: String(params.hazard.image_url || ""),
          distance_meters: String(roundedDistance),
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: { priority: "HIGH" },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { "content-available": 1 } },
        },
      },
    }),
  });

  return { ok: response.ok, response: await response.json() };
}

serve(async (req) => {
  try {
    const unauthorized = requireWebhookSecret(req);
    if (unauthorized) return unauthorized;

    const payload: HazardInsertPayload = await req.json();
    if (payload.type !== "INSERT" || payload.table !== "hazards") {
      return jsonResponse({
        ignored: true,
        reason: "Only new worker hazard reports are processed.",
      });
    }

    const hazard = payload.record;
    const latitude = Number(hazard?.latitude);
    const longitude = Number(hazard?.longitude);
    if (
      !hazard?.id ||
      !hazard.current_site_id ||
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude)
    ) {
      return jsonResponse({ error: "Invalid hazard webhook payload." }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    let workersQuery = supabase
      .from("workers")
      .select("id")
      .eq("current_site_id", hazard.current_site_id)
      .eq("is_active", true);
    if (hazard.officer_uid) {
      workersQuery = workersQuery.eq("officer_uid", hazard.officer_uid);
    }
    if (hazard.worker_id) {
      workersQuery = workersQuery.neq("id", hazard.worker_id);
    }

    const { data: workers, error: workersError } = await workersQuery;
    if (workersError) throw workersError;

    const workerIds = (workers ?? []).map((worker) => String(worker.id));
    if (workerIds.length === 0) {
      const resultSummary = { success: true, eligible: 0, nearby: 0, sent: 0 };
      logDispatchResult(resultSummary);
      return jsonResponse(resultSummary);
    }

    const locationCutoff = new Date(
      Date.now() - LOCATION_MAX_AGE_MINUTES * 60 * 1000,
    ).toISOString();
    const locationFutureLimit = new Date(Date.now() + 60 * 1000).toISOString();
    const [{ data: locations, error: locationsError }, {
      data: tokenRows,
      error: tokensError,
    }] = await Promise.all([
      supabase
        .from("user_locations")
        .select("user_id, latitude, longitude, updated_at")
        .in("user_id", workerIds)
        .gte("updated_at", locationCutoff)
        .lte("updated_at", locationFutureLimit),
      supabase
        .from("user_fcm_tokens")
        .select("user_id, fcm_token")
        .in("user_id", workerIds),
    ]);
    if (locationsError) throw locationsError;
    if (tokensError) throw tokensError;

    const tokenByUser = new Map(
      (tokenRows ?? []).map((row) => [
        String(row.user_id),
        String(row.fcm_token || "").trim(),
      ]),
    );
    const candidateRecipients = (locations ?? [])
      .map((location) => {
        const userId = String(location.user_id);
        const distance = distanceMeters(
          latitude,
          longitude,
          Number(location.latitude),
          Number(location.longitude),
        );
        return {
          userId,
          distance,
          rounded_distance: Math.round(distance),
          has_token: (tokenByUser.get(userId)?.length ?? 0) > 0,
          updated_at: String(location.updated_at || ""),
        };
      })
      .sort((a, b) => a.distance - b.distance);

    const nearbyRecipients = candidateRecipients
      .map((recipient) => ({
        userId: recipient.userId,
        distance: recipient.distance,
      }))
      .filter((recipient) =>
        recipient.distance <= PROXIMITY_RADIUS_METERS &&
        (tokenByUser.get(recipient.userId)?.length ?? 0) > 0
      );

    if (nearbyRecipients.length === 0) {
      const resultSummary = {
        success: true,
        eligible: workerIds.length,
        fresh_locations: locations?.length ?? 0,
        token_rows: tokenRows?.length ?? 0,
        candidates: candidateRecipients.slice(0, 5).map((candidate) => ({
          user_id: candidate.userId,
          distance_meters: candidate.rounded_distance,
          has_token: candidate.has_token,
          updated_at: candidate.updated_at,
        })),
        nearby: 0,
        sent: 0,
      };
      logDispatchResult(resultSummary);
      return jsonResponse(resultSummary);
    }

    const serviceAccount = parseFirebaseServiceAccount();
    const accessToken = await createAccessToken(serviceAccount);
    let sent = 0;
    let duplicates = 0;
    const failures: Array<Record<string, unknown>> = [];

    for (const recipient of nearbyRecipients) {
      const { error: claimError } = await supabase
        .from("hazard_notification_deliveries")
        .insert({
          hazard_id: hazard.id,
          recipient_id: recipient.userId,
          notification_type: "worker_proximity",
        });

      if (claimError?.code === "23505") {
        duplicates++;
        continue;
      }
      if (claimError) {
        failures.push({
          user_id: recipient.userId,
          stage: "deduplication",
          error: claimError.message,
        });
        continue;
      }

      const result = await sendProximityNotification({
        accessToken,
        serviceAccount,
        token: tokenByUser.get(recipient.userId)!,
        hazard,
        distance: recipient.distance,
      });

      if (result.ok) {
        sent++;
        continue;
      }

      const fcmErrorCode = (
        result.response as {
          error?: {
            details?: Array<{ errorCode?: string }>;
          };
        }
      )?.error?.details?.find((detail) => detail.errorCode)?.errorCode;
      if (fcmErrorCode === "UNREGISTERED") {
        await Promise.all([
          supabase
            .from("user_fcm_tokens")
            .delete()
            .eq("user_id", recipient.userId),
          supabase
            .from("workers")
            .update({ fcm_token: null })
            .eq("id", recipient.userId),
        ]);
      }

      await supabase
        .from("hazard_notification_deliveries")
        .delete()
        .eq("hazard_id", hazard.id)
        .eq("recipient_id", recipient.userId)
        .eq("notification_type", "worker_proximity");
      failures.push({
        user_id: recipient.userId,
        stage: "fcm",
        response: result.response,
      });
    }

    const resultSummary = {
      success: failures.length === 0,
      eligible: workerIds.length,
      nearby: nearbyRecipients.length,
      sent,
      duplicates,
      failures,
    };
    logDispatchResult(resultSummary);
    return jsonResponse(resultSummary, failures.length === 0 ? 200 : 207);
  } catch (error) {
    console.error("notify-nearby-workers failed:", error);
    return jsonResponse({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
