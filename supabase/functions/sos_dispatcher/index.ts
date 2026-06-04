// supabase/functions/sos_dispatcher/index.ts

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const WEBHOOK_SECRET_HEADER = "x-riskradar-webhook-secret";

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

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/\s+/g, "")
    .replace(/-----BEGIN[A-Z ]+-----/g, "")
    .replace(/-----END[A-Z ]+-----/g, "");

  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

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

type ReporterScope = {
  contractorId: unknown;
  siteId: string;
};

type ProfileRow = {
  id: string;
  officer_uid?: string | null;
  current_site_id?: string | null;
};

type ReporterInfo = {
  name: string;
  role: string;
};

function isUuid(value: unknown): value is string {
  return typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function addRecipientId(
  recipients: Set<string>,
  value: unknown,
  reporterId: string,
) {
  if (isUuid(value) && value !== reporterId) {
    recipients.add(value);
  }
}

async function maybeSingleProfile(
  supabaseAdmin: ReturnType<typeof createClient>,
  table: string,
  userId: string,
): Promise<ProfileRow | null> {
  const { data, error } = await supabaseAdmin
    .from(table)
    .select('id, officer_uid, current_site_id')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    if (error.message?.includes('current_site_id')) {
      const fallback = await supabaseAdmin
        .from(table)
        .select('id, officer_uid')
        .eq('id', userId)
        .maybeSingle();
      if (fallback.error) {
        console.error(`Could not resolve SOS reporter from ${table}:`, fallback.error.message);
        return null;
      }
      return fallback.data as ProfileRow | null;
    }

    console.error(`Could not resolve SOS reporter from ${table}:`, error.message);
    return null;
  }

  return data as ProfileRow | null;
}

async function resolveReporterScope(
  supabaseAdmin: ReturnType<typeof createClient>,
  reporterId: string,
  alertSiteId?: string | null,
): Promise<ReporterScope | null> {
  const worker = await maybeSingleProfile(supabaseAdmin, 'workers', reporterId);
  if (worker?.officer_uid && (alertSiteId || worker.current_site_id)) {
    return {
      contractorId: worker.officer_uid,
      siteId: alertSiteId || worker.current_site_id!,
    };
  }

  const hseWorker = await maybeSingleProfile(supabaseAdmin, 'hse_workers', reporterId);
  if (hseWorker?.officer_uid && (alertSiteId || hseWorker.current_site_id)) {
    return {
      contractorId: hseWorker.officer_uid,
      siteId: alertSiteId || hseWorker.current_site_id!,
    };
  }

  const officer = await maybeSingleProfile(supabaseAdmin, 'officers', reporterId);
  if (officer && (alertSiteId || officer.current_site_id)) {
    return {
      contractorId: officer.officer_uid || officer.id,
      siteId: alertSiteId || officer.current_site_id!,
    };
  }

  return null;
}

async function fetchScopedRecipientIds(
  supabaseAdmin: ReturnType<typeof createClient>,
  scope: ReporterScope,
  reporterId: string,
): Promise<string[]> {
  const [workersResult, hseWorkersResult, siteOwnerResult, officerResult] = await Promise.all([
    supabaseAdmin
      .from('workers')
      .select('id')
      .eq('officer_uid', scope.contractorId)
      .eq('current_site_id', scope.siteId)
      .neq('id', reporterId),
    supabaseAdmin
      .from('hse_workers')
      .select('id')
      .eq('officer_uid', scope.contractorId)
      .eq('current_site_id', scope.siteId)
      .neq('id', reporterId),
    supabaseAdmin
      .from('sites')
      .select('officer_uid')
      .eq('id', scope.siteId)
      .maybeSingle(),
    supabaseAdmin
      .from('officers')
      .select('id')
      .eq('officer_uid', scope.contractorId)
      .maybeSingle(),
  ]);

  if (workersResult.error) {
    console.error('Could not fetch SOS worker recipients:', workersResult.error.message);
  }
  if (hseWorkersResult.error) {
    console.error('Could not fetch SOS HSE recipients:', hseWorkersResult.error.message);
  }
  if (siteOwnerResult.error) {
    console.error('Could not fetch SOS site owner:', siteOwnerResult.error.message);
  }
  if (officerResult.error) {
    console.error('Could not fetch SOS officer recipient:', officerResult.error.message);
  }

  const recipientIds = new Set<string>();
  for (const row of workersResult.data ?? []) {
    addRecipientId(recipientIds, row.id, reporterId);
  }
  for (const row of hseWorkersResult.data ?? []) {
    addRecipientId(recipientIds, row.id, reporterId);
  }

  const siteOwnerUid = siteOwnerResult.data?.officer_uid;
  if (isUuid(siteOwnerUid)) {
    addRecipientId(recipientIds, siteOwnerUid, reporterId);
  } else if (siteOwnerUid != null) {
    const { data: siteOfficer, error: siteOfficerError } = await supabaseAdmin
      .from('officers')
      .select('id')
      .eq('officer_uid', siteOwnerUid)
      .maybeSingle();
    if (siteOfficerError) {
      console.error('Could not resolve SOS site officer UUID:', siteOfficerError.message);
    }
    addRecipientId(recipientIds, siteOfficer?.id, reporterId);
  }
  addRecipientId(recipientIds, officerResult.data?.id, reporterId);

  console.log(
    `SOS scoped recipients: workers=${workersResult.data?.length ?? 0}, ` +
      `hse=${hseWorkersResult.data?.length ?? 0}, ` +
      `siteOwner=${siteOwnerUid ?? 'none'}, totalRecipientIds=${recipientIds.size}`,
  );

  return [...recipientIds];
}

async function fetchReporterInfo(
  supabaseAdmin: ReturnType<typeof createClient>,
  reporterId: string,
): Promise<ReporterInfo> {
  const lookups = [
    { table: 'workers', role: 'Site Worker' },
    { table: 'hse_workers', role: 'Safety Supervisor' },
    { table: 'officers', role: 'Contractor' },
  ];

  for (const lookup of lookups) {
    const { data, error } = await supabaseAdmin
      .from(lookup.table)
      .select('first_name, last_name')
      .eq('id', reporterId)
      .maybeSingle();
    if (error) {
      console.error(`Could not fetch SOS reporter info from ${lookup.table}:`, error.message);
      continue;
    }
    if (data) {
      const name = sanitizeText(
        `${data.first_name ?? ''} ${data.last_name ?? ''}`.trim(),
        80,
      );
      return {
        name: name || lookup.role,
        role: lookup.role,
      };
    }
  }

  return { name: 'Site Personnel', role: 'Site Personnel' };
}

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

  const pem = sa.private_key.replace(/\\n/g, "\n");
  const keyBuffer = pemToArrayBuffer(pem);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

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
    String.fromCharCode(...new Uint8Array(signature)),
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${toSign}.${signatureB64}`,
    }),
  });

  const json = await res.json();
  if (!json.access_token) {
    throw new Error(`Token error: ${JSON.stringify(json)}`);
  }

  return json.access_token;
}

async function sendSosNotification(
  token: string,
  jwt: string,
  alertId: string,
  title: string,
  body: string,
  reporterInfo: ReporterInfo,
) {
  const url = `https://fcm.googleapis.com/v1/projects/${firebaseConfig.project_id}/messages:send`;

  const message = {
    message: {
      token,
      notification: {
        title,
        body,
      },
      data: {
        type: 'SOS',
        title,
        body,
        message: body,
        alert_id: alertId,
        reporter_name: reporterInfo.name,
        reporter_role: reporterInfo.role,
        priority: 'high',
      },
      android: {
        priority: 'HIGH',
        notification: {
          title,
          body,
          channelId: 'sos_alerts_critical',
          notificationPriority: 'PRIORITY_MAX',
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default',
          },
        },
      },
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

  const json = await res.json();
  return { ok: res.ok, json };
}

function isUnregisteredFcmResponse(response: unknown): boolean {
  const details = (response as any)?.error?.details;
  if (!Array.isArray(details)) {
    return false;
  }

  return details.some((detail: any) =>
    detail?.errorCode === 'UNREGISTERED' ||
    detail?.errorCode === 'INVALID_ARGUMENT'
  );
}

async function deleteInvalidFcmToken(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  token: string,
) {
  if (!isUuid(userId) || token.trim().length === 0) {
    return;
  }

  const { error } = await supabaseAdmin
    .from('user_fcm_tokens')
    .delete()
    .eq('user_id', userId)
    .eq('fcm_token', token);
  if (error) {
    console.error(`Could not delete invalid FCM token for ${userId}:`, error.message);
  } else {
    console.log(`Deleted invalid FCM token for ${userId}.`);
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
    const alertSiteId = typeof newAlert.site_id === 'string'
      ? newAlert.site_id
      : null;
    const alertMessage = sanitizeText(
      newAlert.message || "EMERGENCY SOS Triggered!",
      160,
    );

    // 3. Initialize Supabase Client with Admin rights
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const scope = await resolveReporterScope(supabaseAdmin, reporterId, alertSiteId);
    if (!scope) {
      console.log(`SOS ignored: reporter ${reporterId} is not assigned to a contractor/site.`);
      return jsonResponse({ success: true, sent: 0, reason: 'No contractor/site scope.' });
    }
    const reporterInfo = await fetchReporterInfo(supabaseAdmin, reporterId);

    const recipientIds = await fetchScopedRecipientIds(
      supabaseAdmin,
      scope,
      reporterId,
    );

    console.log(
      `SOS scope resolved: reporter=${reporterId}, contractor=${scope.contractorId}, ` +
        `site=${scope.siteId}, recipientIds=${recipientIds.length}`,
    );

    if (recipientIds.length === 0) {
      console.log("No scoped SOS recipients found.");
      return jsonResponse({ success: true, sent: 0 });
    }

    const { data: reporterTokenRows, error: reporterTokenError } = await supabaseAdmin
      .from('user_fcm_tokens')
      .select('fcm_token')
      .eq('user_id', reporterId);
    if (reporterTokenError) {
      console.error("Could not fetch SOS reporter tokens:", reporterTokenError.message);
    }
    const reporterTokens = new Set(
      (reporterTokenRows ?? [])
        .map((row: any) => row.fcm_token?.toString().trim() ?? '')
        .filter((token: string) => token.length > 0),
    );

    // 4. Fetch FCM tokens only for same-contractor, same-site recipients.
    const { data: tokensData, error } = await supabaseAdmin
      .from('user_fcm_tokens')
      .select('user_id, fcm_token')
      .in('user_id', recipientIds);

    if (error || !tokensData || tokensData.length === 0) {
      if (error) {
        console.error("Could not fetch SOS target devices:", error.message);
      }
      console.log(
        `No target devices found. recipientIds=${recipientIds.length}, ` +
          `sample=${recipientIds.slice(0, 3).join(',')}`,
      );
      return jsonResponse({ success: true, sent: 0 });
    }

    const tokenTargetsByToken = new Map<string, { userId: string; token: string }>();
    for (const row of tokensData) {
      const token = row.fcm_token?.toString().trim() ?? '';
      if (token.length === 0) {
        continue;
      }
      if (reporterTokens.has(token)) {
        continue;
      }
      if (!tokenTargetsByToken.has(token)) {
        tokenTargetsByToken.set(token, {
          userId: row.user_id?.toString() ?? '',
          token,
        });
      }
    }
    const tokenTargets = [...tokenTargetsByToken.values()];
    const duplicateTokenCount = tokensData
      .map((row: any) => ({
        userId: row.user_id?.toString() ?? '',
        token: row.fcm_token?.toString() ?? '',
      }))
      .filter((target: { userId: string; token: string }) =>
        target.token.trim().length > 0
      ).length - tokenTargets.length;

    console.log(
      `SOS target devices found: tokenRows=${tokensData.length}, ` +
        `usableTokens=${tokenTargets.length}, duplicateTokens=${duplicateTokenCount}, ` +
        `reporterTokensExcluded=${reporterTokens.size}`,
    );

    if (tokenTargets.length === 0) {
      return jsonResponse({ success: true, sent: 0, reason: 'No usable FCM tokens.' });
    }

    const title = 'Emergency SOS';
    const body = sanitizeText(
      `${reporterInfo.role} ${reporterInfo.name} triggered an emergency alert.`,
      220,
    );
    const jwt = await createAccessToken(firebaseConfig);
    const results = await Promise.allSettled(
      tokenTargets.map((target) =>
        sendSosNotification(
          target.token,
          jwt,
          newAlert.id?.toString() ?? '',
          title,
          body,
          reporterInfo,
        )
      ),
    );

    const successCount = results.filter(
      (result) => result.status === 'fulfilled' && result.value.ok,
    ).length;
    const failureCount = results.length - successCount;
    if (failureCount > 0) {
      const failures: Record<string, unknown>[] = [];
      const cleanupPromises: Promise<void>[] = [];
      results.forEach((result, index) => {
        const target = tokenTargets[index];
        if (result.status === 'rejected') {
          failures.push({ index, userId: target?.userId, error: String(result.reason) });
        } else if (!result.value.ok) {
          failures.push({ index, userId: target?.userId, response: result.value.json });
          if (target && isUnregisteredFcmResponse(result.value.json)) {
            cleanupPromises.push(
              deleteInvalidFcmToken(supabaseAdmin, target.userId, target.token),
            );
          }
        }
      });
      console.error('SOS FCM failures:', JSON.stringify(failures));
      await Promise.allSettled(cleanupPromises);
    }

    console.log(`SOS Sent. Success: ${successCount}, Failed: ${failureCount}`);

    return jsonResponse({ success: true, sent: successCount, failed: failureCount });

  } catch (error: any) {
    console.error("Error dispatching SOS:", error.message);
    return jsonResponse({ error: "SOS dispatch failed." }, 500);
  }
});
