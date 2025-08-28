# Gmail Push Notifications Setup Guide

This guide walks you through setting up Gmail Push notifications to automatically trigger AI continuous delivery workflows when specifications are received via email.

## Architecture Overview

```
Gmail → Google Cloud Pub/Sub → Supabase Edge Function → GitHub Actions Workflow
```

The system monitors a Gmail inbox for emails containing project specifications (YAML attachments) and automatically triggers the CI/CD pipeline.

## Prerequisites

### Required Accounts & Services
- Google Cloud Project with billing enabled
- Gmail account to monitor
- Supabase project (Project B) 
- GitHub repository with Actions enabled

### Required Tools
- Google Cloud CLI (`gcloud`)
- Python 3.7+ with `requests` library
- Access to Supabase dashboard
- GitHub personal access token

## Setup Process

### Step 1: Google Cloud Project Setup

1. **Create or select a Google Cloud Project**
   ```bash
   gcloud projects create ai-continuous-delivery
   gcloud config set project ai-continuous-delivery
   ```

2. **Enable required APIs**
   ```bash
   gcloud services enable pubsub.googleapis.com
   gcloud services enable gmail.googleapis.com
   ```

3. **Run the automated setup script**
   ```bash
   cd /path/to/ai-continuous-delivery
   ./scripts/setup-gmail-push.sh
   ```

This script will:
- Create Pub/Sub topic `gmail-notifications`
- Grant Gmail permission to publish to the topic
- Create push subscription with webhook endpoint
- Display configuration details

### Step 2: OAuth 2.0 Credentials Setup

1. **Go to Google Cloud Console**
   - Navigate to [APIs & Services > Credentials](https://console.cloud.google.com/apis/credentials)
   - Click "Create Credentials" > "OAuth 2.0 Client IDs"
   - Choose "Desktop Application" as application type
   - Download the credentials JSON file

2. **Run the OAuth setup script**
   ```bash
   python3 scripts/gmail-oauth-setup.py
   ```

This script will:
- Guide you through OAuth 2.0 authorization
- Generate refresh token for Gmail API access
- Set up Gmail watch on your inbox
- Provide environment variables for Supabase

### Step 3: Supabase Configuration

1. **Deploy the Edge Function**
   ```bash
   cd supabase-b/
   supabase functions deploy gmail-webhook
   ```

2. **Set Environment Variables**
   In your Supabase dashboard, go to Edge Functions settings and add:
   ```
   GMAIL_CLIENT_ID=your-oauth-client-id
   GMAIL_CLIENT_SECRET=your-oauth-client-secret
   GMAIL_REFRESH_TOKEN=your-refresh-token
   GITHUB_TOKEN=your-github-personal-access-token
   ```

3. **Create Storage Bucket**
   Create a storage bucket named `specifications` for storing email attachments.

### Step 4: Test the Integration

1. **Test the webhook endpoint**
   ```bash
   ./test-gmail-webhook.sh
   ```

2. **Send a test email**
   - Send an email to your monitored Gmail account
   - Subject should contain keywords like "project specification", "spec", or "ai delivery"
   - Attach a YAML file with your project specification
   - Mark the email as unread if needed

3. **Monitor the workflow**
   - Check Supabase Edge Function logs
   - Verify GitHub Actions workflow is triggered
   - Monitor the database for new records

## Configuration Details

### Gmail Search Query
The system searches for emails matching:
```
is:unread subject:"project specification" OR subject:"spec" OR subject:"ai delivery"
```

You can modify this query in the Edge Function code to match your needs.

### Specification Format
Email attachments should be YAML files containing project specifications. The system looks for files with extensions:
- `.yaml`
- `.yml`
- Files containing "spec" in the name

### Watch Expiration
Gmail watch expires after 7 days and must be renewed. You can:
- Set up a cron job to renew automatically
- Monitor expiration and renew manually
- Check expiration status in the setup script output

## Troubleshooting

### Common Issues

#### 1. "Topic not found" Error
**Solution**: Ensure the Pub/Sub topic exists and has correct permissions:
```bash
gcloud pubsub topics list
gcloud pubsub topics get-iam-policy gmail-notifications
```

#### 2. "Invalid credentials" Error
**Solution**: Refresh OAuth credentials:
```bash
python3 scripts/gmail-oauth-setup.py
```

#### 3. Webhook not receiving messages
**Checklist**:
- [ ] Pub/Sub subscription created with correct endpoint
- [ ] Supabase Edge Function deployed and running
- [ ] Gmail watch is active (check expiration)
- [ ] Email matches search criteria

#### 4. GitHub workflow not triggering
**Checklist**:
- [ ] GITHUB_TOKEN environment variable set correctly
- [ ] Token has `repo` and `workflow` permissions
- [ ] Repository dispatch event configured in workflow

### Debug Commands

```bash
# Check Pub/Sub setup
gcloud pubsub topics list
gcloud pubsub subscriptions list

# Test webhook manually
curl -X POST https://your-project.supabase.co/functions/v1/gmail-webhook \
  -H "Content-Type: application/json" \
  -d '{"message":{"data":"eyJlbWFpbEFkZHJlc3MiOiJ0ZXN0QGV4YW1wbGUuY29tIiwiaGlzdG9yeUlkIjoiMTIzNDU2In0="}}'

# Check Gmail watch status
curl -H "Authorization: Bearer $ACCESS_TOKEN" \
  https://gmail.googleapis.com/gmail/v1/users/me/profile
```

## Security Considerations

### OAuth Token Security
- Store refresh tokens securely in environment variables
- Never commit credentials to version control
- Regularly rotate tokens if compromised
- Use minimal required scopes

### Webhook Security
- Verify requests come from Google Cloud Pub/Sub
- Implement request validation and rate limiting
- Monitor for suspicious activity
- Use HTTPS for all endpoints

### Email Processing
- Validate all email attachments before processing
- Sanitize file names and content
- Limit file sizes and types
- Scan for malicious content

## Maintenance

### Regular Tasks
- **Weekly**: Check Gmail watch expiration status
- **Monthly**: Review and rotate OAuth credentials
- **Quarterly**: Update Edge Function dependencies

### Monitoring
- Set up alerts for Edge Function errors
- Monitor Pub/Sub message delivery metrics
- Track GitHub workflow trigger success rates
- Review storage bucket usage

### Backup
- Export OAuth credentials securely
- Backup Pub/Sub configuration
- Document any custom search queries or filters

## Advanced Configuration

### Custom Email Filters
Modify the Gmail search query in the Edge Function:
```typescript
const query = 'is:unread from:trusted@domain.com has:attachment filename:spec.yaml'
```

### Multiple Gmail Accounts
Set up separate Pub/Sub topics and subscriptions for different accounts:
```bash
# Account 1
gcloud pubsub topics create gmail-notifications-account1
# Account 2  
gcloud pubsub topics create gmail-notifications-account2
```

### Batch Processing
Configure batch processing for high-volume scenarios:
```typescript
// Process multiple messages in batches
const batchSize = 10
const messages = await getUnreadMessages(batchSize)
```

## Cost Optimization

### Pub/Sub Costs
- Messages: $0.40 per million messages
- Storage: $0.27 per GB-month
- Typical cost: < $1/month for normal usage

### Gmail API Costs
- Free quota: 1 billion quota units/day
- Paid usage: $0.01 per 1,000 quota units
- Watch operations use minimal quota

### Optimization Tips
- Use efficient Gmail search queries
- Process only necessary attachments  
- Clean up old Pub/Sub messages
- Monitor quota usage regularly

---

## Quick Reference

### Essential Commands
```bash
# Setup
./scripts/setup-gmail-push.sh
python3 scripts/gmail-oauth-setup.py

# Test
./test-gmail-webhook.sh

# Deploy
supabase functions deploy gmail-webhook

# Monitor
gcloud pubsub topics list-subscriptions gmail-notifications
```

### Important URLs
- [Gmail Push API Docs](https://developers.google.com/workspace/gmail/api/guides/push)
- [Google Cloud Pub/Sub](https://console.cloud.google.com/cloudpubsub/topic/list)
- [OAuth 2.0 Credentials](https://console.cloud.google.com/apis/credentials)
- [Supabase Dashboard](https://supabase.com/dashboard/projects)