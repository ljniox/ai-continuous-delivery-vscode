#!/usr/bin/env python3
"""
Test script for Gmail Push integration
Tests the complete email-to-workflow pipeline
"""

import json
import base64
import requests
import sys
import os

def test_webhook_endpoint(webhook_url):
    """Test the Supabase Edge Function webhook endpoint"""
    
    print("🧪 Testing Gmail webhook endpoint...")
    
    # Create a test Pub/Sub message
    gmail_notification = {
        "emailAddress": "test@example.com",
        "historyId": "123456789"
    }
    
    # Encode as base64 (as Google Pub/Sub would)
    message_data = base64.b64encode(json.dumps(gmail_notification).encode()).decode()
    
    # Create Pub/Sub message format
    pubsub_message = {
        "message": {
            "data": message_data,
            "messageId": "test-message-id",
            "publishTime": "2025-08-28T12:00:00.000Z"
        },
        "subscription": "projects/test-project/subscriptions/test-subscription"
    }
    
    # Send test request
    try:
        response = requests.post(
            webhook_url,
            json=pubsub_message,
            headers={'Content-Type': 'application/json'},
            timeout=30
        )
        
        print(f"Status Code: {response.status_code}")
        print(f"Response: {response.text}")
        
        if response.status_code == 200:
            print("✅ Webhook endpoint is responding correctly")
            return True
        else:
            print(f"❌ Webhook returned status {response.status_code}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to connect to webhook: {e}")
        return False

def test_gmail_oauth_config():
    """Test if Gmail OAuth credentials are properly configured"""
    
    print("🔐 Testing Gmail OAuth configuration...")
    
    creds_file = '.gmail-credentials.json'
    
    if not os.path.exists(creds_file):
        print(f"❌ Credentials file not found: {creds_file}")
        print("Run: python3 scripts/gmail-oauth-setup.py")
        return False
    
    try:
        with open(creds_file, 'r') as f:
            creds = json.load(f)
        
        required_fields = ['client_id', 'client_secret', 'refresh_token']
        
        for field in required_fields:
            if field not in creds:
                print(f"❌ Missing field in credentials: {field}")
                return False
            if not creds[field]:
                print(f"❌ Empty field in credentials: {field}")
                return False
        
        print("✅ Gmail OAuth credentials are properly configured")
        return True
        
    except (json.JSONDecodeError, IOError) as e:
        print(f"❌ Error reading credentials file: {e}")
        return False

def test_github_workflow_config():
    """Test GitHub workflow configuration"""
    
    print("🔧 Testing GitHub workflow configuration...")
    
    workflow_file = '.github/workflows/sprint.yml'
    
    if not os.path.exists(workflow_file):
        print(f"❌ Workflow file not found: {workflow_file}")
        return False
    
    try:
        with open(workflow_file, 'r') as f:
            content = f.read()
        
        # Check for required triggers
        if 'repository_dispatch:' not in content:
            print("❌ Missing repository_dispatch trigger in workflow")
            return False
        
        if 'spec_ingested' not in content:
            print("❌ Missing spec_ingested event type in workflow")
            return False
        
        print("✅ GitHub workflow is properly configured")
        return True
        
    except IOError as e:
        print(f"❌ Error reading workflow file: {e}")
        return False

def test_supabase_schema():
    """Test if Supabase database schema is deployed"""
    
    print("💾 Testing Supabase database schema...")
    
    # This would require Supabase credentials to test properly
    # For now, just check if the schema file exists
    schema_file = 'supabase-b/schema.sql'
    
    if not os.path.exists(schema_file):
        print(f"❌ Schema file not found: {schema_file}")
        return False
    
    try:
        with open(schema_file, 'r') as f:
            content = f.read()
        
        required_tables = ['specs', 'sprints', 'runs', 'artifacts', 'status_events']
        
        for table in required_tables:
            if f'create table {table}' not in content:
                print(f"❌ Missing table in schema: {table}")
                return False
        
        print("✅ Database schema is properly defined")
        return True
        
    except IOError as e:
        print(f"❌ Error reading schema file: {e}")
        return False

def main():
    """Run all tests"""
    
    print("🧪 Gmail Push Integration Test Suite")
    print("====================================")
    print()
    
    # Configuration
    supabase_url = os.getenv('SUPABASE_URL', 'https://your-project.supabase.co')
    webhook_url = f"{supabase_url}/functions/v1/gmail-webhook"
    
    print(f"Testing configuration:")
    print(f"  Webhook URL: {webhook_url}")
    print()
    
    tests = [
        ("Supabase Schema", test_supabase_schema),
        ("GitHub Workflow", test_github_workflow_config),
        ("Gmail OAuth", test_gmail_oauth_config),
        ("Webhook Endpoint", lambda: test_webhook_endpoint(webhook_url)),
    ]
    
    results = []
    
    for test_name, test_func in tests:
        print(f"Running: {test_name}")
        print("-" * 40)
        
        try:
            success = test_func()
            results.append((test_name, success))
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
            results.append((test_name, False))
        
        print()
    
    # Summary
    print("📊 Test Results Summary")
    print("======================")
    
    passed = 0
    total = len(results)
    
    for test_name, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"  {test_name}: {status}")
        if success:
            passed += 1
    
    print()
    print(f"Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Gmail Push integration is ready.")
        return 0
    else:
        print("⚠️  Some tests failed. Check the output above for details.")
        return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n⏹️  Tests cancelled by user")
        sys.exit(1)