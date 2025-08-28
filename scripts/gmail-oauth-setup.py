#!/usr/bin/env python3
"""
Gmail OAuth 2.0 Setup Script
Helps generate the required OAuth credentials for Gmail API access
"""

import json
import os
import sys
import webbrowser
from urllib.parse import urlencode, parse_qs
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time

try:
    import requests
except ImportError:
    print("❌ 'requests' library required. Install with: pip install requests")
    sys.exit(1)

class OAuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/oauth/callback'):
            # Parse the authorization code from the callback
            query = self.path.split('?')[1] if '?' in self.path else ''
            params = parse_qs(query)
            
            if 'code' in params:
                self.server.auth_code = params['code'][0]
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(b'''
                <html>
                <body>
                <h1>Authorization Successful!</h1>
                <p>You can now close this window and return to the terminal.</p>
                <script>setTimeout(() => window.close(), 3000);</script>
                </body>
                </html>
                ''')
            else:
                error = params.get('error', ['Unknown error'])[0]
                self.send_response(400)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                html_content = f'''
                <html>
                <body>
                <h1>Authorization Failed</h1>
                <p>Error: {error}</p>
                </body>
                </html>
                '''
                self.wfile.write(html_content.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress HTTP server logs
        pass

def get_oauth_credentials():
    """Guide user through OAuth 2.0 setup process"""
    
    print("🔐 Gmail OAuth 2.0 Setup")
    print("========================")
    print()
    
    # Check if we already have credentials
    if os.path.exists('.gmail-credentials.json'):
        print("📋 Found existing credentials file: .gmail-credentials.json")
        choice = input("Do you want to use existing credentials? (y/N): ").lower()
        if choice == 'y':
            with open('.gmail-credentials.json', 'r') as f:
                creds = json.load(f)
                return creds
    
    print("To set up Gmail OAuth, you need to:")
    print("1. Go to Google Cloud Console: https://console.cloud.google.com/")
    print("2. Select your project (or create one)")
    print("3. Enable Gmail API: https://console.cloud.google.com/apis/library/gmail.googleapis.com")
    print("4. Go to Credentials: https://console.cloud.google.com/apis/credentials")
    print("5. Create OAuth 2.0 Client IDs for 'Desktop Application'")
    print("6. Download the JSON credentials file")
    print()
    
    # Get client credentials
    client_id = input("Enter your OAuth 2.0 Client ID: ").strip()
    if not client_id:
        print("❌ Client ID is required")
        return None
        
    client_secret = input("Enter your OAuth 2.0 Client Secret: ").strip()
    if not client_secret:
        print("❌ Client Secret is required")
        return None
    
    # OAuth 2.0 flow
    redirect_uri = "http://localhost:8080/oauth/callback"
    
    # Start local server to handle OAuth callback
    print("\n🚀 Starting OAuth flow...")
    print("A browser window will open for authorization.")
    
    server = HTTPServer(('localhost', 8080), OAuthHandler)
    server.auth_code = None
    
    # Start server in background
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    
    # Build authorization URL
    auth_params = {
        'client_id': client_id,
        'redirect_uri': redirect_uri,
        'scope': 'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.modify',
        'response_type': 'code',
        'access_type': 'offline',  # Important for refresh token
        'prompt': 'consent'  # Force consent screen to ensure refresh token
    }
    
    auth_url = f"https://accounts.google.com/o/oauth2/v2/auth?{urlencode(auth_params)}"
    
    print(f"Opening browser to: {auth_url}")
    webbrowser.open(auth_url)
    
    # Wait for authorization code
    print("⏳ Waiting for authorization...")
    timeout = 120  # 2 minutes
    start_time = time.time()
    
    while server.auth_code is None and (time.time() - start_time) < timeout:
        time.sleep(1)
    
    server.shutdown()
    
    if server.auth_code is None:
        print("❌ Authorization timeout or failed")
        return None
    
    print("✅ Authorization code received")
    
    # Exchange code for tokens
    token_data = {
        'client_id': client_id,
        'client_secret': client_secret,
        'code': server.auth_code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect_uri
    }
    
    print("🔄 Exchanging code for tokens...")
    
    response = requests.post('https://oauth2.googleapis.com/token', data=token_data)
    
    if not response.ok:
        print(f"❌ Token exchange failed: {response.text}")
        return None
    
    tokens = response.json()
    
    if 'refresh_token' not in tokens:
        print("❌ No refresh token received. Make sure to revoke any existing permissions and try again.")
        print("   Go to: https://myaccount.google.com/permissions")
        return None
    
    credentials = {
        'client_id': client_id,
        'client_secret': client_secret,
        'refresh_token': tokens['refresh_token'],
        'access_token': tokens['access_token']
    }
    
    # Save credentials
    with open('.gmail-credentials.json', 'w') as f:
        json.dump(credentials, f, indent=2)
    
    print("✅ Credentials saved to .gmail-credentials.json")
    
    return credentials

def setup_gmail_watch(credentials, topic_name):
    """Set up Gmail watch using the credentials"""
    
    print(f"\n📧 Setting up Gmail watch for topic: {topic_name}")
    
    # Get fresh access token
    token_data = {
        'client_id': credentials['client_id'],
        'client_secret': credentials['client_secret'],
        'refresh_token': credentials['refresh_token'],
        'grant_type': 'refresh_token'
    }
    
    token_response = requests.post('https://oauth2.googleapis.com/token', data=token_data)
    
    if not token_response.ok:
        print(f"❌ Failed to refresh token: {token_response.text}")
        return False
    
    access_token = token_response.json()['access_token']
    
    # Set up Gmail watch
    watch_data = {
        'topicName': topic_name,
        'labelIds': ['INBOX']  # Watch for changes in inbox
    }
    
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }
    
    watch_response = requests.post(
        'https://gmail.googleapis.com/gmail/v1/users/me/watch',
        headers=headers,
        json=watch_data
    )
    
    if not watch_response.ok:
        print(f"❌ Failed to set up watch: {watch_response.text}")
        return False
    
    watch_result = watch_response.json()
    print(f"✅ Gmail watch set up successfully!")
    print(f"   History ID: {watch_result.get('historyId')}")
    print(f"   Expiration: {watch_result.get('expiration')}")
    
    # Calculate expiration date
    if 'expiration' in watch_result:
        exp_timestamp = int(watch_result['expiration']) / 1000
        exp_date = time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime(exp_timestamp))
        print(f"   Expires at: {exp_date}")
        print("   ⚠️  Remember to renew the watch before it expires!")
    
    return True

def main():
    """Main setup process"""
    
    # Get project and topic info
    project_id = os.getenv('GOOGLE_CLOUD_PROJECT', 'ai-continuous-delivery')
    topic_name = f"projects/{project_id}/topics/gmail-notifications"
    
    print(f"Setting up Gmail Push for:")
    print(f"  Project: {project_id}")
    print(f"  Topic: {topic_name}")
    print()
    
    # Get OAuth credentials
    credentials = get_oauth_credentials()
    if not credentials:
        print("❌ Failed to get OAuth credentials")
        return 1
    
    # Set up Gmail watch
    if not setup_gmail_watch(credentials, topic_name):
        print("❌ Failed to set up Gmail watch")
        return 1
    
    # Display environment variables for Supabase
    print("\n🔧 Supabase Environment Variables:")
    print("==================================")
    print("Add these to your Supabase Edge Function environment:")
    print()
    print(f"GMAIL_CLIENT_ID={credentials['client_id']}")
    print(f"GMAIL_CLIENT_SECRET={credentials['client_secret']}")
    print(f"GMAIL_REFRESH_TOKEN={credentials['refresh_token']}")
    print("GITHUB_TOKEN=<your-github-token>")
    print()
    print("📝 Don't forget to also add GITHUB_TOKEN for workflow triggering!")
    
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n⏹️  Setup cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)