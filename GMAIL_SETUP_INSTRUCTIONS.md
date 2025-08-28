# Gmail OAuth Setup Instructions

## Current Issue & Solution

The Gmail OAuth setup failed because of a project ID mismatch. The error shows the actual Google Cloud project ID is `ai-contiuous-delivery` (note: missing 'n' in "continuous").

## Steps to Complete Setup

### 1. Run the OAuth Setup Script Interactively

```bash
./scripts/gmail-oauth-setup.py
```

When prompted:
- **Use existing credentials?** Type `y` and press Enter
- The script should now work with the corrected project ID: `ai-contiuous-delivery`

### 2. Alternative: Manual Project ID Override

If you want to use a different project ID, set the environment variable:

```bash
export GOOGLE_CLOUD_PROJECT="your-actual-project-id"
./scripts/gmail-oauth-setup.py
```

### 3. Check Your Google Cloud Project

To verify the correct project ID:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Check the project selector at the top
3. Note the exact project ID (shown in parentheses)

### 4. Expected Success Output

When the script succeeds, you should see:

```
✅ Gmail watch set up successfully!
   History ID: [some-number]
   Expiration: [timestamp]
   Expires at: [date]
   ⚠️  Remember to renew the watch before it expires!

🔧 Supabase Environment Variables:
==================================
Add these to your Supabase Edge Function environment:

GMAIL_CLIENT_ID=your-oauth-client-id
GMAIL_CLIENT_SECRET=your-oauth-client-secret
GMAIL_REFRESH_TOKEN=your-refresh-token
GITHUB_TOKEN=<your-github-token>
```

### 5. Next Steps After Success

1. **Copy the environment variables** shown in the output
2. **Add them to Supabase Edge Functions**:
   - Go to your Supabase dashboard
   - Navigate to Edge Functions
   - Add the environment variables
3. **Deploy the Gmail webhook function**:
   ```bash
   cd supabase-b/
   supabase functions deploy gmail-webhook
   ```
4. **Test the integration**:
   ```bash
   python3 test-gmail-integration.py
   ```

## Troubleshooting

### If OAuth Setup Still Fails

1. **Check topic exists in Google Cloud**:
   - Go to [Pub/Sub console](https://console.cloud.google.com/cloudpubsub/topic/list)
   - Verify `gmail-notifications` topic exists
   - Check project ID matches exactly

2. **Verify Gmail API permissions**:
   - Check that `gmail-api-push@system.gserviceaccount.com` has Publisher role on the topic

3. **Check OAuth credentials**:
   - Ensure OAuth 2.0 client is configured for "Desktop Application"
   - Verify redirect URI includes `http://localhost:8080/oauth/callback`

### Common Project ID Issues

- **Typos**: `ai-continuous-delivery` vs `ai-contiuous-delivery`
- **Environment variables**: Check `GOOGLE_CLOUD_PROJECT` if set
- **Multiple projects**: Ensure you're using the right project in Google Cloud Console

## Files Updated

- `scripts/gmail-oauth-setup.py` - Fixed project ID to `ai-contiuous-delivery`
- `scripts/setup-gmail-push.sh` - Fixed project ID to `ai-contiuous-delivery`

The scripts now use the correct project ID that matches your Google Cloud setup.