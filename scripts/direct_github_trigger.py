#!/usr/bin/env python3
"""
Direct GitHub Actions Trigger
Bypasses webhook and triggers GitHub Actions directly
"""

import json
import sys
import os
import requests
import argparse
from typing import Optional

def trigger_github_workflow_directly(
    repo: str,
    spec_file: str,
    github_token: str,
    branch: str = "main",
    project_name: Optional[str] = None,
    requester_email: Optional[str] = None
) -> bool:
    """
    Trigger GitHub Actions workflow directly on target repository
    
    Args:
        repo: Target repository (e.g., "user/project-name")
        spec_file: Path to YAML specification file
        github_token: GitHub personal access token
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
    
    # Create a temporary URL for the spec (using GitHub Gist)
    print("🔧 Creating temporary specification storage...")
    
    # Create a private gist to store the spec temporarily
    gist_payload = {
        "description": f"Temporary spec for {repo}",
        "public": False,
        "files": {
            "spec.yaml": {
                "content": spec_yaml
            }
        }
    }
    
    gist_response = requests.post(
        "https://api.github.com/gists",
        headers={
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json"
        },
        json=gist_payload
    )
    
    if gist_response.status_code != 201:
        print(f"❌ Failed to create temporary storage: {gist_response.status_code}")
        return False
    
    gist_data = gist_response.json()
    spec_url = gist_data["files"]["spec.yaml"]["raw_url"]
    print(f"✅ Temporary spec URL: {spec_url}")
    
    # Prepare workflow dispatch payload
    workflow_payload = {
        "ref": branch,
        "inputs": {
            "spec_url": spec_url,
            "spec_id": f"direct-{int(requests.get('https://httpbin.org/uuid').json()['uuid'].split('-')[0], 16)}",
            "target_repo": repo,
            "target_branch": branch,
            "project_name": project_name or repo.split('/')[-1],
            "triggered_by": "direct-trigger"
        }
    }
    
    print(f"🚀 Triggering GitHub Actions workflow...")
    print(f"   Repository: {repo}")
    print(f"   Branch: {branch}")
    print(f"   Project: {project_name or repo}")
    
    # Trigger workflow on AI continuous delivery repository
    workflow_response = requests.post(
        f"https://api.github.com/repos/ljniox/ai-continuous-delivery/actions/workflows/sprint.yml/dispatches",
        headers={
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json"
        },
        json=workflow_payload
    )
    
    if workflow_response.status_code == 204:
        print("✅ GitHub Actions workflow triggered successfully!")
        print(f"   Check: https://github.com/ljniox/ai-continuous-delivery/actions")
        print(f"   Target repo: https://github.com/{repo}")
        
        # Schedule gist cleanup (optional)
        print(f"💡 Cleanup: Delete gist {gist_data['id']} after workflow completes")
        
        return True
    else:
        error_text = workflow_response.text
        print(f"❌ Failed to trigger workflow: {workflow_response.status_code}")
        print(f"   Error: {error_text}")
        
        # Cleanup gist on failure
        requests.delete(
            f"https://api.github.com/gists/{gist_data['id']}",
            headers={"Authorization": f"token {github_token}"}
        )
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Trigger AI continuous delivery directly via GitHub Actions",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create new project with repository creation
  %(prog)s ljniox/random-poem-api random-poem-api.yaml --create-repo
  
  # Work on existing project
  %(prog)s username/existing-project spec.yaml --branch feature/new-feature
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
        '--github-token',
        default=os.getenv('GITHUB_TOKEN'),
        help='GitHub personal access token (default: from GITHUB_TOKEN env var)'
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
        help='Create GitHub repository if it doesn\'t exist (requires separate call)'
    )
    
    args = parser.parse_args()
    
    # Validate inputs
    if not args.github_token:
        print("❌ GitHub token required")
        print("   Set GITHUB_TOKEN env var or use --github-token")
        return 1
    
    if '/' not in args.repo or len(args.repo.split('/')) != 2:
        print("❌ Repository must be in format 'owner/name'")
        return 1
    
    if not os.path.exists(args.spec_file):
        print(f"❌ Specification file does not exist: {args.spec_file}")
        return 1
    
    # Handle repository creation if requested
    if args.create_repo:
        print("🔧 Repository creation requested...")
        print("💡 Use the enhanced multi-project-webhook.py with --create-repo flag")
        
        # Import create_github_repo function
        import sys
        import os
        sys.path.append(os.path.dirname(__file__))
        from multi_project_webhook import create_github_repo
        repo_desc = args.project_name or f"AI-generated project: {args.repo}"
        
        if not create_github_repo(args.repo, repo_desc, args.github_token, False):
            print("❌ Failed to create repository")
            return 1
        print()
    
    # Trigger the workflow
    success = trigger_github_workflow_directly(
        repo=args.repo,
        spec_file=args.spec_file,
        github_token=args.github_token,
        branch=args.branch,
        project_name=args.project_name,
        requester_email=args.email
    )
    
    if success:
        print("\n🎉 AI continuous delivery triggered successfully!")
        print("   Monitor progress:")
        print(f"   • Control-plane: https://github.com/ljniox/ai-continuous-delivery/actions")
        print(f"   • Target repo: https://github.com/{args.repo}")
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