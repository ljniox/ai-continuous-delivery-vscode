import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PubSubMessage {
  message: {
    data: string
    messageId: string
    publishTime: string
  }
  subscription: string
}

interface GmailNotification {
  emailAddress: string
  historyId: string
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('Gmail webhook triggered:', req.method, req.url)

    // Verify this is a POST request from Google Cloud Pub/Sub
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse the Pub/Sub message
    const pubsubMessage: PubSubMessage = await req.json()
    console.log('Pub/Sub message received:', pubsubMessage)

    if (!pubsubMessage.message || !pubsubMessage.message.data) {
      console.error('Invalid Pub/Sub message format')
      return new Response('OK', { status: 200, headers: corsHeaders })
    }

    // Decode the base64 message data
    const messageData = atob(pubsubMessage.message.data)
    const gmailNotification: GmailNotification = JSON.parse(messageData)
    
    console.log('Gmail notification:', gmailNotification)

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get Gmail API credentials from environment
    const gmailClientId = Deno.env.get('GMAIL_CLIENT_ID')
    const gmailClientSecret = Deno.env.get('GMAIL_CLIENT_SECRET')
    const gmailRefreshToken = Deno.env.get('GMAIL_REFRESH_TOKEN')

    if (!gmailClientId || !gmailClientSecret || !gmailRefreshToken) {
      console.error('Gmail API credentials missing')
      return new Response('OK', { status: 200, headers: corsHeaders })
    }

    // Get access token for Gmail API
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        client_id: gmailClientId,
        client_secret: gmailClientSecret,
        refresh_token: gmailRefreshToken,
        grant_type: 'refresh_token',
      }),
    })

    if (!tokenResponse.ok) {
      console.error('Failed to get Gmail access token:', await tokenResponse.text())
      return new Response('OK', { status: 200, headers: corsHeaders })
    }

    const tokenData = await tokenResponse.json()
    const accessToken = tokenData.access_token

    // Get the latest messages from Gmail
    const messagesResponse = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/${gmailNotification.emailAddress}/messages?q=is:unread subject:"project specification" OR subject:"spec" OR subject:"ai delivery"&maxResults=10`,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
        },
      }
    )

    if (!messagesResponse.ok) {
      console.error('Failed to fetch Gmail messages:', await messagesResponse.text())
      return new Response('OK', { status: 200, headers: corsHeaders })
    }

    const messagesData = await messagesResponse.json()
    console.log('Found messages:', messagesData.messages?.length || 0)

    if (!messagesData.messages || messagesData.messages.length === 0) {
      console.log('No relevant unread messages found')
      return new Response('OK', { status: 200, headers: corsHeaders })
    }

    // Process each message
    for (const message of messagesData.messages) {
      try {
        await processGmailMessage(supabase, accessToken, gmailNotification.emailAddress, message.id)
      } catch (error) {
        console.error('Error processing message:', message.id, error)
      }
    }

    return new Response('OK', { status: 200, headers: corsHeaders })

  } catch (error) {
    console.error('Error in gmail-webhook:', error)
    return new Response('OK', { status: 200, headers: corsHeaders })
  }
})

async function processGmailMessage(supabase: any, accessToken: string, emailAddress: string, messageId: string) {
  console.log('Processing message:', messageId)

  // Get full message details
  const messageResponse = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/${emailAddress}/messages/${messageId}`,
    {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    }
  )

  if (!messageResponse.ok) {
    console.error('Failed to fetch message details:', await messageResponse.text())
    return
  }

  const messageData = await messageResponse.json()
  
  // Extract message metadata
  const headers = messageData.payload.headers
  const subject = headers.find((h: any) => h.name === 'Subject')?.value || ''
  const from = headers.find((h: any) => h.name === 'From')?.value || ''
  const date = headers.find((h: any) => h.name === 'Date')?.value || ''

  console.log('Message details:', { subject, from, date })

  // Look for attachments (specifications)
  const attachments = await extractAttachments(accessToken, emailAddress, messageData)
  
  if (attachments.length === 0) {
    console.log('No attachments found in message:', messageId)
    return
  }

  // Process each YAML/YML attachment
  for (const attachment of attachments) {
    if (attachment.filename.toLowerCase().endsWith('.yaml') || 
        attachment.filename.toLowerCase().endsWith('.yml') ||
        attachment.filename.toLowerCase().includes('spec')) {
      
      await processSpecificationAttachment(supabase, attachment, from, subject)
    }
  }

  // Mark message as read
  await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/${emailAddress}/messages/${messageId}/modify`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        removeLabelIds: ['UNREAD']
      }),
    }
  )
}

async function extractAttachments(accessToken: string, emailAddress: string, messageData: any) {
  const attachments = []
  
  if (messageData.payload.parts) {
    for (const part of messageData.payload.parts) {
      if (part.filename && part.body && part.body.attachmentId) {
        // Download attachment
        const attachmentResponse = await fetch(
          `https://gmail.googleapis.com/gmail/v1/users/${emailAddress}/messages/${messageData.id}/attachments/${part.body.attachmentId}`,
          {
            headers: {
              'Authorization': `Bearer ${accessToken}`,
            },
          }
        )

        if (attachmentResponse.ok) {
          const attachmentData = await attachmentResponse.json()
          const content = atob(attachmentData.data.replace(/-/g, '+').replace(/_/g, '/'))
          
          attachments.push({
            filename: part.filename,
            content: content,
            mimeType: part.mimeType
          })
        }
      }
    }
  }

  return attachments
}

async function processSpecificationAttachment(supabase: any, attachment: any, from: string, subject: string) {
  console.log('Processing specification:', attachment.filename)

  try {
    // Create spec record in database
    const specData = {
      repo: 'ljniox/ai-continuous-delivery', // Default repo, could be parsed from email
      branch: 'main',
      storage_path: `specs/email-${Date.now()}-${attachment.filename}`,
      created_by: from,
    }

    const { data: spec, error: specError } = await supabase
      .table('specs')
      .insert(specData)
      .select()
      .single()

    if (specError) {
      console.error('Error creating spec record:', specError)
      return
    }

    console.log('Spec record created:', spec.id)

    // Store specification content in Supabase Storage
    const { error: uploadError } = await supabase.storage
      .from('specifications')
      .upload(specData.storage_path, attachment.content, {
        contentType: 'text/yaml',
        upsert: false
      })

    if (uploadError) {
      console.error('Error uploading spec to storage:', uploadError)
      return
    }

    // Create signed URL for the specification
    const { data: signedUrlData, error: urlError } = await supabase.storage
      .from('specifications')
      .createSignedUrl(specData.storage_path, 3600) // 1 hour expiry

    if (urlError) {
      console.error('Error creating signed URL:', urlError)
      return
    }

    console.log('Signed URL created:', signedUrlData.signedUrl)

    // Trigger GitHub workflow
    const githubToken = Deno.env.get('GITHUB_TOKEN')
    if (!githubToken) {
      console.error('GitHub token not configured')
      return
    }

    const workflowPayload = {
      event_type: 'spec_ingested',
      client_payload: {
        spec_url: signedUrlData.signedUrl,
        spec_id: spec.id,
        triggered_by: from,
        subject: subject
      }
    }

    const workflowResponse = await fetch(
      'https://api.github.com/repos/ljniox/ai-continuous-delivery/dispatches',
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
      console.log('GitHub workflow triggered successfully for spec:', spec.id)
      
      // Log status event
      await supabase
        .table('status_events')
        .insert({
          phase: 'SPEC_RECEIVED',
          message: `Specification received via email from ${from}`,
          metadata: {
            spec_id: spec.id,
            filename: attachment.filename,
            subject: subject,
            trigger_method: 'email'
          }
        })
    } else {
      console.error('Failed to trigger GitHub workflow:', await workflowResponse.text())
    }

  } catch (error) {
    console.error('Error processing specification attachment:', error)
  }
}