import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface WebhookPayload {
  repo: string              // Target repository (e.g., "user/project-name")
  branch?: string           // Target branch (default: "main") 
  spec_yaml: string         // YAML specification content
  requester_email?: string  // Who requested this (optional)
  project_name?: string     // Human-readable project name
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('Simple webhook triggered:', req.method, req.url)

    // Only accept POST requests
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse the webhook payload
    const payload: WebhookPayload = await req.json()
    console.log('Webhook payload received:', {
      repo: payload.repo,
      branch: payload.branch || 'main',
      project_name: payload.project_name,
      spec_size: payload.spec_yaml?.length || 0
    })

    // Validate required fields
    if (!payload.repo || !payload.spec_yaml) {
      return new Response(
        JSON.stringify({ 
          error: 'Missing required fields', 
          required: ['repo', 'spec_yaml'] 
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Create spec record in database
    const specData = {
      repo: payload.repo,
      branch: payload.branch || 'main',
      storage_path: `specs/webhook-${Date.now()}-${crypto.randomUUID()}.yaml`,
      created_by: payload.requester_email || 'webhook-trigger',
    }

    const { data: spec, error: specError } = await supabase
      .from('specs')
      .insert(specData)
      .select()
      .single()

    if (specError) {
      console.error('Error creating spec record:', specError)
      return new Response(
        JSON.stringify({ error: 'Failed to create spec record', details: specError }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('Spec record created:', spec.id)

    // Store specification content in Supabase Storage
    const { error: uploadError } = await supabase.storage
      .from('specifications')
      .upload(specData.storage_path, payload.spec_yaml, {
        contentType: 'text/yaml',
        upsert: false
      })

    if (uploadError) {
      console.error('Error uploading spec to storage:', uploadError)
      return new Response(
        JSON.stringify({ error: 'Failed to store specification', details: uploadError }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create signed URL for the specification
    const { data: signedUrlData, error: urlError } = await supabase.storage
      .from('specifications')
      .createSignedUrl(specData.storage_path, 3600) // 1 hour expiry

    if (urlError) {
      console.error('Error creating signed URL:', urlError)
      return new Response(
        JSON.stringify({ error: 'Failed to create signed URL', details: urlError }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('Signed URL created:', signedUrlData.signedUrl)

    // Log status event
    await supabase
      .from('status_events')
      .insert({
        phase: 'SPEC_RECEIVED',
        message: `Specification received via webhook for ${payload.repo}`,
        metadata: {
          spec_id: spec.id,
          repo: payload.repo,
          branch: payload.branch || 'main',
          project_name: payload.project_name,
          trigger_method: 'webhook'
        }
      })

    // Trigger GitHub workflow
    const githubToken = Deno.env.get('GITHUB_TOKEN')
    if (!githubToken) {
      console.error('GitHub token not configured')
      return new Response(
        JSON.stringify({ error: 'GitHub integration not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const workflowPayload = {
      event_type: 'spec_ingested',
      client_payload: {
        spec_url: signedUrlData.signedUrl,
        spec_id: spec.id,
        repo: payload.repo,
        branch: payload.branch || 'main',
        project_name: payload.project_name,
        triggered_by: 'webhook'
      }
    }

    // Trigger workflow on the control-plane repository (ai-continuous-delivery)
    const controlPlaneRepo = 'ljniox/ai-continuous-delivery'
    const workflowResponse = await fetch(
      `https://api.github.com/repos/${controlPlaneRepo}/dispatches`,
      {
        method: 'POST',
        headers: {
          'Authorization': `token ${githubToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(workflowPayload),
      }
    )

    if (workflowResponse.ok) {
      console.log('GitHub workflow triggered successfully for control-plane repo:', controlPlaneRepo)
      console.log('Target repository for development:', payload.repo)
      
      return new Response(
        JSON.stringify({
          success: true,
          spec_id: spec.id,
          repo: payload.repo,
          branch: payload.branch || 'main',
          workflow_triggered: true,
          message: 'Specification processed and workflow triggered'
        }),
        { 
          status: 200, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    } else {
      const error = await workflowResponse.text()
      console.error('Failed to trigger GitHub workflow:', error)
      
      return new Response(
        JSON.stringify({
          success: true,
          spec_id: spec.id,
          repo: payload.repo,
          workflow_triggered: false,
          error: 'Failed to trigger workflow',
          details: error,
          message: 'Specification stored but workflow trigger failed'
        }),
        { 
          status: 207, // Partial success
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

  } catch (error) {
    console.error('Error in simple-webhook:', error)
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        details: error.message 
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})