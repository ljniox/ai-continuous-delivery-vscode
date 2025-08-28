#!/usr/bin/env python3
"""
Multi-Project Webhook Client
Simple tool to trigger AI continuous delivery for any repository
"""

import json
import sys
import os
import requests
import argparse
from typing import Optional

def trigger_project(
    webhook_url: str,
    repo: str,
    spec_file: str,
    branch: str = "main",
    project_name: Optional[str] = None,
    requester_email: Optional[str] = None
) -> bool:
    """
    Trigger AI continuous delivery for a project
    
    Args:
        webhook_url: URL of the simple webhook endpoint
        repo: Target repository (e.g., "user/project-name")  
        spec_file: Path to YAML specification file
        branch: Target branch (default: main)
        project_name: Human-readable project name
        requester_email: Who requested this
    
    Returns:
        True if successful, False otherwise
    """
    
    try:
        # Read specification file
        with open(spec_file, 'r', encoding='utf-8') as f:
            spec_yaml = f.read()
    except FileNotFoundError:
        print(f"❌ Specification file not found: {spec_file}")
        return False
    except Exception as e:
        print(f"❌ Error reading specification file: {e}")
        return False
    
    # Prepare webhook payload
    payload = {
        "repo": repo,
        "branch": branch,
        "spec_yaml": spec_yaml,
    }
    
    if project_name:
        payload["project_name"] = project_name
    if requester_email:
        payload["requester_email"] = requester_email
    
    print(f"🚀 Triggering AI continuous delivery...")
    print(f"   Repository: {repo}")
    print(f"   Branch: {branch}")
    print(f"   Spec file: {spec_file} ({len(spec_yaml)} chars)")
    if project_name:
        print(f"   Project: {project_name}")
    
    try:
        # Send webhook request
        response = requests.post(
            webhook_url,
            json=payload,
            headers={'Content-Type': 'application/json'},
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Success!")
            print(f"   Spec ID: {result.get('spec_id')}")
            print(f"   Workflow triggered: {result.get('workflow_triggered', False)}")
            return True
        elif response.status_code == 207:
            result = response.json()
            print(f"⚠️  Partial success!")
            print(f"   Spec ID: {result.get('spec_id')}")
            print(f"   Issue: {result.get('error', 'Unknown')}")
            return True
        else:
            error_detail = response.text
            print(f"❌ Failed with status {response.status_code}")
            print(f"   Error: {error_detail}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error: {e}")
        return False

def main():
    """Main CLI interface"""
    
    parser = argparse.ArgumentParser(
        description='Trigger AI continuous delivery for any project',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Trigger for a new project
  %(prog)s user/my-new-app spec.yaml --project "My New App"
  
  # Trigger for existing project with feature branch
  %(prog)s user/existing-project feature-spec.yaml --branch feature/new-feature
  
  # Include requester email
  %(prog)s user/project spec.yaml --email developer@company.com
        """
    )
    
    parser.add_argument(
        'repo',
        help='Target repository (e.g., user/project-name)'
    )
    
    parser.add_argument(
        'spec_file',
        help='Path to YAML specification file'
    )
    
    parser.add_argument(
        '--webhook-url',
        default=os.getenv('AI_CD_WEBHOOK_URL', 'https://your-project.supabase.co/functions/v1/simple-webhook'),
        help='Webhook URL (default: from AI_CD_WEBHOOK_URL env var)'
    )
    
    parser.add_argument(
        '--branch',
        default='main',
        help='Target branch (default: main)'
    )
    
    parser.add_argument(
        '--project',
        help='Human-readable project name'
    )
    
    parser.add_argument(
        '--email',
        help='Requester email address'
    )
    
    args = parser.parse_args()
    
    # Validate repository format
    if '/' not in args.repo or len(args.repo.split('/')) != 2:
        print("❌ Repository must be in format 'owner/name'")
        return 1
    
    # Check if spec file exists
    if not os.path.exists(args.spec_file):
        print(f"❌ Specification file does not exist: {args.spec_file}")
        return 1
    
    # Trigger the workflow
    success = trigger_project(
        webhook_url=args.webhook_url,
        repo=args.repo,
        spec_file=args.spec_file,
        branch=args.branch,
        project_name=args.project,
        requester_email=args.email
    )
    
    if success:
        print("\n🎉 AI continuous delivery triggered successfully!")
        print("   Check the target repository's Actions tab for progress.")
        return 0
    else:
        print("\n💥 Failed to trigger AI continuous delivery")
        return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n⏹️  Cancelled by user")
        sys.exit(1)