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

def create_github_repo(repo: str, description: str, github_token: str, private: bool = False) -> bool:
    """
    Create a new GitHub repository
    
    Args:
        repo: Repository name (e.g., "user/project-name")
        description: Repository description
        github_token: GitHub personal access token
        private: Whether to create private repository
    
    Returns:
        True if successful, False otherwise
    """
    
    try:
        username, repo_name = repo.split('/')
    except ValueError:
        print(f"❌ Invalid repository format: {repo}. Use 'username/repo-name'")
        return False
    
    # GitHub API endpoint
    api_url = "https://api.github.com/user/repos"
    
    headers = {
        "Authorization": f"token {github_token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }
    
    payload = {
        "name": repo_name,
        "description": description,
        "private": private,
        "auto_init": True,  # Initialize with README
        "gitignore_template": "Python",  # Default template
        "license_template": "mit"
    }
    
    try:
        print(f"🔧 Creating GitHub repository: {repo}...")
        response = requests.post(api_url, headers=headers, json=payload)
        
        if response.status_code == 201:
            repo_data = response.json()
            print(f"✅ Repository created successfully!")
            print(f"   URL: {repo_data['html_url']}")
            print(f"   Clone: {repo_data['clone_url']}")
            return True
        elif response.status_code == 422:
            error_data = response.json()
            if "already exists" in str(error_data):
                print(f"ℹ️  Repository {repo} already exists, continuing...")
                return True
            else:
                print(f"❌ Repository creation failed: {error_data}")
                return False
        else:
            print(f"❌ GitHub API error: {response.status_code} - {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error creating repository: {e}")
        return False

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
        # Prepare headers with Supabase authentication
        headers = {'Content-Type': 'application/json'}
        
        # Add Supabase authentication if URL contains supabase.co
        if 'supabase.co' in webhook_url:
            # Get Supabase anon key from arguments or environment
            supabase_key = os.getenv('SUPABASE_ANON_KEY')
            if supabase_key:
                # Clean the key of any whitespace or newlines
                supabase_key = supabase_key.strip()
                headers['Authorization'] = f'Bearer {supabase_key}'
                print(f"🔑 Using Supabase authentication")
            else:
                print("⚠️  No SUPABASE_ANON_KEY found in environment")
                print("   Set SUPABASE_ANON_KEY for proper authentication")
        
        # Send webhook request
        response = requests.post(
            webhook_url,
            json=payload,
            headers=headers,
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
        '--project-name',
        help='Human-readable project name'
    )
    
    parser.add_argument(
        '--email',
        help='Requester email address'
    )
    
    parser.add_argument(
        '--create-repo',
        action='store_true',
        help='Create GitHub repository if it doesn\'t exist'
    )
    
    parser.add_argument(
        '--github-token',
        default=os.getenv('GITHUB_TOKEN'),
        help='GitHub personal access token (default: from GITHUB_TOKEN env var)'
    )
    
    parser.add_argument(
        '--private',
        action='store_true',
        help='Create private repository'
    )
    
    parser.add_argument(
        '--repo-description',
        help='Repository description for new repositories'
    )
    
    parser.add_argument(
        '--supabase-key',
        default=os.getenv('SUPABASE_ANON_KEY'),
        help='Supabase anon key for webhook authentication (default: from SUPABASE_ANON_KEY env var)'
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
    
    # Handle repository creation if requested
    if args.create_repo:
        if not args.github_token:
            print("❌ GitHub token required for repository creation")
            print("   Set GITHUB_TOKEN env var or use --github-token")
            return 1
        
        # Use project name or repo description for repo description
        repo_desc = args.repo_description or args.project_name or f"AI-generated project: {args.repo}"
        
        print(f"🔧 Repository creation requested...")
        if not create_github_repo(args.repo, repo_desc, args.github_token, args.private):
            print("❌ Failed to create repository")
            return 1
        print()  # Add spacing
    
    # Trigger the workflow
    success = trigger_project(
        webhook_url=args.webhook_url,
        repo=args.repo,
        spec_file=args.spec_file,
        branch=args.branch,
        project_name=args.project_name,
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