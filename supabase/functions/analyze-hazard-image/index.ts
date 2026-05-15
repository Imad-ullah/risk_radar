import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const modelName = "gemini-2.5-flash";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return jsonResponse(
        { error: "GEMINI_API_KEY is not configured on the Edge Function." },
        500,
      );
    }

    const body = await req.json();
    const imageBase64 = body?.imageBase64;
    const mimeType = body?.mimeType || "image/jpeg";

    if (typeof imageBase64 !== "string" || imageBase64.length === 0) {
      return jsonResponse({ error: "imageBase64 is required." }, 400);
    }

    if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
      return jsonResponse({ error: "Unsupported image type." }, 400);
    }

    // Keep requests small enough for Edge Function and Gemini payload limits.
    if (imageBase64.length > 7_000_000) {
      return jsonResponse({ error: "Image is too large. Use a smaller photo." }, 413);
    }

    const prompt = `
You are a Senior HSE Risk Assessor for the "RiskRadar" safety platform.
Analyze the provided worksite image and identify safety violations strictly according to OSHA/ISO safety standards.

Return ONLY valid JSON. No markdown, no conversational text.

Required JSON Schema:
{
  "hazards": [
    {
      "category": "string (e.g., PPE Violation, Fall Hazard, Electrical, Housekeeping)",
      "description": "string (Max 15 words. Technical and direct.)",
      "severity": "string (Critical|High|Medium|Low)",
      "action": "string (Immediate corrective action. Max 10 words.)"
    }
  ],
  "summary": "string (One professional sentence summarizing the site safety status)"
}

Guidelines:
1. Be strict. If a hazard exists, report it.
2. Descriptions must be to-the-point and technical. No fluff.
3. Do not invent hazards. If the image is safe, return an empty hazards array.
4. Focus strictly on PPE, Working at Heights, Electrical, Fire Safety, Heavy Machinery, and Housekeeping.
`;

    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: prompt },
                {
                  inlineData: {
                    mimeType,
                    data: imageBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            temperature: 0.2,
            topK: 32,
            topP: 1,
            maxOutputTokens: 2048,
          },
        }),
      },
    );

    const geminiJson = await geminiResponse.json();
    if (!geminiResponse.ok) {
      return jsonResponse(
        {
          error: "Gemini request failed.",
          detail: geminiJson?.error?.message ?? geminiJson,
        },
        502,
      );
    }

    const text = geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== "string" || text.trim().length === 0) {
      return jsonResponse({ error: "Gemini returned an empty response." }, 502);
    }

    const result = JSON.parse(
      text.replaceAll("```json", "").replaceAll("```", "").trim(),
    );
    validateResult(result);

    return jsonResponse(result, 200);
  } catch (error) {
    return jsonResponse(
      { error: "Hazard analysis failed.", detail: String(error?.message ?? error) },
      500,
    );
  }
});

function validateResult(result: unknown) {
  if (!result || typeof result !== "object") {
    throw new Error("Invalid AI response.");
  }
  const data = result as Record<string, unknown>;
  if (!Array.isArray(data.hazards)) {
    throw new Error("AI response is missing hazards array.");
  }
  if (typeof data.summary !== "string") {
    throw new Error("AI response is missing summary.");
  }
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
