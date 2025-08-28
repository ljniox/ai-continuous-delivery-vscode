#!/usr/bin/env python3
"""
Gmail Push Permissions Fix Script
Diagnoses and fixes Pub/Sub permissions for Gmail Push notifications
"""

import json
import os
import sys
import subprocess

def run_gcloud_command(cmd):
    """Run a gcloud command and return the result"""
    try:
        result = subprocess.run(
            ['gcloud'] + cmd, 
            capture_output=True, 
            text=True, 
            check=True
        )
        return result.stdout.strip(), None
    except subprocess.CalledProcessError as e:
        return None, e.stderr.strip()
    except FileNotFoundError:
        return None, "Google Cloud CLI (gcloud) not found. Please install it first."

def check_gcloud_auth():
    """Check if user is authenticated with gcloud"""
    output, error = run_gcloud_command(['auth', 'list', '--format=value(account)'])
    if error:
        return False, error
    if not output:
        return False, "No authenticated accounts found"
    return True, output.split('\n')

def get_current_project():
    """Get the current gcloud project"""
    output, error = run_gcloud_command(['config', 'get-value', 'project'])
    if error:
        return None, error
    return output if output else None, None

def check_topic_exists(project_id, topic_name):
    """Check if the Pub/Sub topic exists"""
    full_topic = f"projects/{project_id}/topics/{topic_name}"
    output, error = run_gcloud_command(['pubsub', 'topics', 'describe', topic_name, '--project', project_id])
    return output is not None, error

def create_topic(project_id, topic_name):
    """Create the Pub/Sub topic"""
    output, error = run_gcloud_command(['pubsub', 'topics', 'create', topic_name, '--project', project_id])
    return output is not None, error

def check_gmail_permissions(project_id, topic_name):
    """Check if Gmail service account has publisher permissions"""
    output, error = run_gcloud_command([
        'pubsub', 'topics', 'get-iam-policy', topic_name, 
        '--project', project_id, '--format=json'
    ])
    
    if error:
        return False, error
    
    try:
        policy = json.loads(output)
        bindings = policy.get('bindings', [])
        
        # Look for Gmail service account with Publisher role
        for binding in bindings:
            if binding.get('role') == 'roles/pubsub.publisher':
                members = binding.get('members', [])
                gmail_sa = 'serviceAccount:gmail-api-push@system.gserviceaccount.com'
                if gmail_sa in members:
                    return True, None
        
        return False, "Gmail service account not found in publisher role"
        
    except json.JSONDecodeError:
        return False, "Failed to parse IAM policy JSON"

def add_gmail_permissions(project_id, topic_name):
    """Add Gmail service account to topic with Publisher role"""
    output, error = run_gcloud_command([
        'pubsub', 'topics', 'add-iam-policy-binding', topic_name,
        '--project', project_id,
        '--member=serviceAccount:gmail-api-push@system.gserviceaccount.com',
        '--role=roles/pubsub.publisher'
    ])
    return output is not None, error

def main():
    """Main diagnostic and fix process"""
    
    print("🔧 Gmail Push Permissions Fix")
    print("=============================")
    print()
    
    # Configuration
    project_id = os.getenv('GOOGLE_CLOUD_PROJECT', 'ai-contiuous-delivery')
    topic_name = 'gmail-notifications'
    
    print(f"Project ID: {project_id}")
    print(f"Topic Name: {topic_name}")
    print()
    
    # Step 1: Check gcloud authentication
    print("1️⃣ Checking gcloud authentication...")
    is_auth, result = check_gcloud_auth()
    if not is_auth:
        print(f"❌ Not authenticated: {result}")
        print("Run: gcloud auth login")
        return 1
    else:
        print(f"✅ Authenticated as: {', '.join(result)}")
    
    # Step 2: Set/check project
    print("\n2️⃣ Checking project configuration...")
    current_project, error = get_current_project()
    if error:
        print(f"❌ Error getting project: {error}")
        return 1
    
    if current_project != project_id:
        print(f"⚠️  Current project: {current_project}, Expected: {project_id}")
        print(f"Setting project to {project_id}...")
        _, error = run_gcloud_command(['config', 'set', 'project', project_id])
        if error:
            print(f"❌ Failed to set project: {error}")
            return 1
        print(f"✅ Project set to {project_id}")
    else:
        print(f"✅ Project correctly set to {project_id}")
    
    # Step 3: Check if topic exists
    print(f"\n3️⃣ Checking if topic exists...")
    topic_exists, error = check_topic_exists(project_id, topic_name)
    if not topic_exists:
        print(f"❌ Topic doesn't exist: {error}")
        print(f"Creating topic {topic_name}...")
        
        success, error = create_topic(project_id, topic_name)
        if not success:
            print(f"❌ Failed to create topic: {error}")
            return 1
        print(f"✅ Topic {topic_name} created")
    else:
        print(f"✅ Topic {topic_name} exists")
    
    # Step 4: Check Gmail service account permissions
    print(f"\n4️⃣ Checking Gmail service account permissions...")
    has_permission, error = check_gmail_permissions(project_id, topic_name)
    if not has_permission:
        print(f"❌ Gmail service account missing permissions: {error}")
        print("Adding Gmail service account to topic...")
        
        success, error = add_gmail_permissions(project_id, topic_name)
        if not success:
            print(f"❌ Failed to add permissions: {error}")
            return 1
        print("✅ Gmail service account granted Publisher role")
    else:
        print("✅ Gmail service account has correct permissions")
    
    # Step 5: Final verification
    print(f"\n5️⃣ Final verification...")
    has_permission, error = check_gmail_permissions(project_id, topic_name)
    if has_permission:
        print("🎉 Gmail Push permissions are correctly configured!")
        print()
        print("You can now run the OAuth setup:")
        print("  ./scripts/gmail-oauth-setup.py")
        return 0
    else:
        print(f"❌ Permissions still not working: {error}")
        return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n⏹️  Fix cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)