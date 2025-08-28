#!/bin/bash

# Gmail Push Notifications Setup Script
# This script helps configure Gmail Push API with Google Cloud Pub/Sub

set -e

echo "🚀 Gmail Push Notifications Setup"
echo "================================="

# Check if required tools are installed
command -v gcloud >/dev/null 2>&1 || { 
    echo "❌ Google Cloud CLI (gcloud) is required but not installed."
    echo "Install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
}

# Configuration variables
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"ai-contiuous-delivery"}
TOPIC_NAME="gmail-notifications"
SUBSCRIPTION_NAME="gmail-webhook-subscription"
WEBHOOK_URL=${SUPABASE_URL}/functions/v1/gmail-webhook

echo "Configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Topic Name: $TOPIC_NAME"
echo "  Subscription Name: $SUBSCRIPTION_NAME"  
echo "  Webhook URL: $WEBHOOK_URL"
echo ""

# Step 1: Set the project
echo "📋 Step 1: Setting up Google Cloud Project..."
gcloud config set project $PROJECT_ID

# Step 2: Enable required APIs
echo "🔧 Step 2: Enabling required APIs..."
gcloud services enable pubsub.googleapis.com
gcloud services enable gmail.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Step 3: Create Pub/Sub topic
echo "📢 Step 3: Creating Pub/Sub topic..."
if gcloud pubsub topics describe $TOPIC_NAME >/dev/null 2>&1; then
    echo "  ✅ Topic '$TOPIC_NAME' already exists"
else
    gcloud pubsub topics create $TOPIC_NAME
    echo "  ✅ Topic '$TOPIC_NAME' created"
fi

# Step 4: Grant Gmail permission to publish to the topic
echo "🔐 Step 4: Granting Gmail permissions..."
gcloud pubsub topics add-iam-policy-binding $TOPIC_NAME \
    --member=serviceAccount:gmail-api-push@system.gserviceaccount.com \
    --role=roles/pubsub.publisher

echo "  ✅ Gmail service account granted publisher role"

# Step 5: Create push subscription to webhook
echo "🔗 Step 5: Creating push subscription..."
if gcloud pubsub subscriptions describe $SUBSCRIPTION_NAME >/dev/null 2>&1; then
    echo "  ⚠️  Subscription '$SUBSCRIPTION_NAME' already exists, deleting..."
    gcloud pubsub subscriptions delete $SUBSCRIPTION_NAME
fi

gcloud pubsub subscriptions create $SUBSCRIPTION_NAME \
    --topic=$TOPIC_NAME \
    --push-endpoint=$WEBHOOK_URL \
    --ack-deadline=600

echo "  ✅ Push subscription created with webhook endpoint"

# Step 6: Create service account for Gmail API access (optional)
SERVICE_ACCOUNT_NAME="gmail-push-service"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "👤 Step 6: Creating service account..."
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL >/dev/null 2>&1; then
    echo "  ✅ Service account already exists"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Gmail Push Notifications Service Account"
    echo "  ✅ Service account created"
fi

# Step 7: Generate and display the topic name for Gmail watch
FULL_TOPIC_NAME="projects/$PROJECT_ID/topics/$TOPIC_NAME"

echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "Next steps:"
echo "1. Configure these environment variables in your Supabase Edge Function:"
echo "   - GMAIL_CLIENT_ID: Your OAuth 2.0 client ID"
echo "   - GMAIL_CLIENT_SECRET: Your OAuth 2.0 client secret"  
echo "   - GMAIL_REFRESH_TOKEN: OAuth 2.0 refresh token for your Gmail account"
echo "   - GITHUB_TOKEN: GitHub personal access token"
echo ""
echo "2. Use this topic name to set up Gmail watch:"
echo "   Topic: $FULL_TOPIC_NAME"
echo ""
echo "3. Test the webhook endpoint:"
echo "   curl -X POST $WEBHOOK_URL"
echo ""
echo "📚 Documentation:"
echo "   - Gmail Push API: https://developers.google.com/workspace/gmail/api/guides/push"
echo "   - OAuth 2.0 Setup: https://developers.google.com/identity/protocols/oauth2"

# Optional: Create a test script
cat > test-gmail-webhook.sh << EOF
#!/bin/bash
# Test script for Gmail webhook

echo "Testing Gmail webhook endpoint..."

curl -X POST $WEBHOOK_URL \\
  -H "Content-Type: application/json" \\
  -d '{
    "message": {
      "data": "$(echo '{"emailAddress": "test@example.com", "historyId": "123456"}' | base64 -w 0)",
      "messageId": "test-message-id",
      "publishTime": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
    },
    "subscription": "projects/$PROJECT_ID/subscriptions/$SUBSCRIPTION_NAME"
  }'

echo ""
echo "Check Supabase Edge Function logs for webhook processing results."
EOF

chmod +x test-gmail-webhook.sh
echo "📝 Test script created: ./test-gmail-webhook.sh"