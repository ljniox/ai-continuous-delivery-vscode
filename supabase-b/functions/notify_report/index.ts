import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ReportSummary {
  run_id?: string;
  sprint?: string;
  result: "PASSED" | "FAILED";
  coverage?: number;
  unit_pass?: boolean;
  e2e_pass?: boolean;
  lighthouse?: number;
  notes?: string;
  requester_email?: string;
  artifacts?: Array<{
    kind: string;
    storage_path: string;
    signed_url: string;
  }>;
}

function renderHtml(summary: ReportSummary): string {
  const status = summary.result === "PASSED" ? "✅ SUCCÈS" : "❌ ÉCHEC";
  const statusColor = summary.result === "PASSED" ? "#28a745" : "#dc3545";

  let artifactsList = "";
  if (summary.artifacts) {
    artifactsList = summary.artifacts.map(artifact => 
      `<li><a href="${artifact.signed_url}" style="color: #007bff;">${artifact.kind.toUpperCase()}</a></li>`
    ).join("");
  }

  return `
    <html>
      <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: ${statusColor};">${status} - Sprint ${summary.sprint || "N/A"}</h2>
        
        <div style="background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
          <h3>Résumé de l'exécution</h3>
          <ul>
            <li><strong>Coverage:</strong> ${summary.coverage ? (summary.coverage * 100).toFixed(1) + "%" : "N/A"}</li>
            <li><strong>Tests unitaires:</strong> ${summary.unit_pass ? "✅ Passés" : "❌ Échecs"}</li>
            <li><strong>Tests E2E:</strong> ${summary.e2e_pass ? "✅ Passés" : "❌ Échecs"}</li>
            <li><strong>Lighthouse Score:</strong> ${summary.lighthouse || "N/A"}</li>
          </ul>
          ${summary.notes ? `<p><strong>Notes:</strong> ${summary.notes}</p>` : ""}
        </div>

        ${artifactsList ? `
          <div style="background-color: #e9ecef; padding: 15px; border-radius: 5px; margin: 20px 0;">
            <h3>Artefacts générés</h3>
            <ul>${artifactsList}</ul>
            <p style="font-size: 0.9em; color: #6c757d;">
              <em>Les liens expirent dans 24h</em>
            </p>
          </div>
        ` : ""}

        <hr style="margin: 30px 0;">
        <p style="color: #6c757d; font-size: 0.9em;">
          Généré automatiquement par le système de livraison continue IA
        </p>
      </body>
    </html>
  `;
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const smtpEndpoint = Deno.env.get("SMTP_ENDPOINT"); // Ex: SendGrid, Resend, etc.
    const smtpToken = Deno.env.get("SMTP_TOKEN");

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response("Missing Supabase environment variables", { status: 500 });
    }

    const supa = createClient(supabaseUrl, supabaseServiceKey);
    const summary: ReportSummary = await req.json();

    console.log("Notification summary:", summary);

    // Si un run_id est fourni, récupérer les artefacts
    if (summary.run_id) {
      const { data: artifacts } = await supa
        .from("artifacts")
        .select("*")
        .eq("run_id", summary.run_id);

      if (artifacts) {
        // Générer des URLs signées pour chaque artefact
        summary.artifacts = [];
        for (const artifact of artifacts) {
          const { data: urlData } = await supa.storage
            .from("automation")
            .createSignedUrl(artifact.storage_path, 86400);
          
          if (urlData?.signedUrl) {
            summary.artifacts.push({
              kind: artifact.kind,
              storage_path: artifact.storage_path,
              signed_url: urlData.signedUrl
            });
          }
        }
      }
    }

    // Générer l'email HTML
    const emailHtml = renderHtml(summary);
    
    // Envoyer l'email (simulation - à adapter selon votre provider SMTP)
    if (smtpEndpoint && smtpToken) {
      const emailResponse = await fetch(smtpEndpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${smtpToken}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          to: summary.requester_email || "default@example.com",
          subject: `Sprint ${summary.sprint} — ${summary.result}`,
          html: emailHtml
        })
      });

      if (!emailResponse.ok) {
        console.error("Email sending failed:", await emailResponse.text());
        return new Response("Email sending failed", { status: 500 });
      }
    } else {
      // Fallback: juste logger l'HTML de l'email
      console.log("Email HTML (SMTP not configured):", emailHtml);
    }

    return new Response(JSON.stringify({ 
      success: true, 
      artifacts_count: summary.artifacts?.length || 0 
    }));

  } catch (error) {
    console.error("Error in notify_report:", error);
    return new Response("Internal server error", { status: 500 });
  }
});