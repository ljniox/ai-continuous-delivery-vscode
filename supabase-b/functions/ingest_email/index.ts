import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface GmailPushMessage {
  message: {
    data: string;
    messageId: string;
  };
}

function parseGmailPush(payload: any) {
  // Simulation parsing - à adapter selon le format réel Gmail Push
  return {
    subject: payload.subject || "Ordre de mission",
    body: payload.body || "spec content",
    attachments: payload.attachments || []
  };
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const githubToken = Deno.env.get("GITHUB_TOKEN");
    const targetRepo = Deno.env.get("TARGET_REPO") || "ljniox/ai-continuous-delivery";

    if (!supabaseUrl || !supabaseServiceKey || !githubToken) {
      return new Response("Missing environment variables", { status: 500 });
    }

    const supa = createClient(supabaseUrl, supabaseServiceKey);
    
    const payload = await req.json();
    console.log("Gmail push payload:", payload);
    
    const { subject, body, attachments } = parseGmailPush(payload);

    // Générer un nom de fichier unique pour la spec
    const specId = crypto.randomUUID();
    const path = `specs/${specId}.yaml`;
    
    // Stocker la spec dans Supabase Storage
    const { error: uploadError } = await supa.storage
      .from("automation")
      .upload(path, new Blob([body], { type: "text/yaml" }));

    if (uploadError) {
      console.error("Upload error:", uploadError);
      return new Response("Storage upload failed", { status: 500 });
    }

    // Insérer en base de données
    const { data: spec, error: insertError } = await supa
      .from("specs")
      .insert({
        repo: targetRepo,
        branch: "spec/auto",
        storage_path: path,
        created_by: "gmail-push"
      })
      .select()
      .single();

    if (insertError) {
      console.error("Insert error:", insertError);
      return new Response("Database insert failed", { status: 500 });
    }

    // Générer URL signée pour la spec
    const { data: urlData, error: urlError } = await supa.storage
      .from("automation")
      .createSignedUrl(path, 86400); // 24h

    if (urlError) {
      console.error("Signed URL error:", urlError);
      return new Response("Signed URL creation failed", { status: 500 });
    }

    // Enregistrer événement de statut
    await supa
      .from("status_events")
      .insert({
        run_id: null,
        phase: "SPEC_RECEIVED",
        message: `Spec ${spec?.id} déposée`
      });

    // Déclencher le workflow GitHub
    const githubResponse = await fetch(`https://api.github.com/repos/${targetRepo}/dispatches`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${githubToken}`,
        "Accept": "application/vnd.github+json"
      },
      body: JSON.stringify({
        event_type: "spec_ingested",
        client_payload: {
          spec_url: urlData?.signedUrl,
          spec_id: spec?.id
        }
      })
    });

    if (!githubResponse.ok) {
      console.error("GitHub dispatch failed:", await githubResponse.text());
      return new Response("GitHub dispatch failed", { status: 500 });
    }

    console.log("Spec ingested successfully:", spec?.id);
    return new Response(JSON.stringify({ 
      success: true, 
      spec_id: spec?.id,
      spec_url: urlData?.signedUrl 
    }));

  } catch (error) {
    console.error("Error in ingest_email:", error);
    return new Response("Internal server error", { status: 500 });
  }
});