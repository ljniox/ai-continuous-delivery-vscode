#!/usr/bin/env python3
"""
Test script for Archon + Claude Code integration
Validates the complete MCP setup and knowledge base functionality
"""

import requests
import json
import subprocess
import sys
import time
from typing import Dict, Any, Optional

def test_archon_api(base_url: str = "http://localhost:8181") -> bool:
    """Test Archon API connectivity"""
    print("🏛️ Testing Archon API...")
    
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        if response.status_code == 200:
            print("✅ Archon API accessible")
            return True
        else:
            print(f"❌ Archon API returned status {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Archon API not accessible: {e}")
        return False

def test_mcp_server(mcp_url: str = "http://localhost:8051") -> bool:
    """Test Archon MCP server"""
    print("🔌 Testing Archon MCP server...")
    
    try:
        response = requests.get(mcp_url, timeout=10)
        print("✅ Archon MCP server responding")
        return True
    except requests.exceptions.RequestException as e:
        print(f"❌ Archon MCP server not accessible: {e}")
        return False

def test_knowledge_base(base_url: str = "http://localhost:8181") -> bool:
    """Test knowledge base functionality"""
    print("📚 Testing knowledge base...")
    
    try:
        # Test adding a document
        doc_data = {
            "title": "Test Document",
            "content": "This is a test document for Archon integration testing.",
            "type": "test",
            "tags": ["test", "integration"]
        }
        
        response = requests.post(
            f"{base_url}/api/knowledge/documents",
            json=doc_data,
            timeout=10
        )
        
        if response.status_code in [200, 201]:
            print("✅ Document added to knowledge base")
        else:
            print(f"⚠️ Document addition returned status {response.status_code}")
        
        # Test search functionality
        search_data = {
            "query": "test document integration",
            "limit": 3
        }
        
        search_response = requests.post(
            f"{base_url}/api/rag/search",
            json=search_data,
            timeout=10
        )
        
        if search_response.status_code == 200:
            results = search_response.json()
            print(f"✅ Knowledge search working - found {len(results.get('results', []))} results")
            return True
        else:
            print(f"❌ Knowledge search failed with status {search_response.status_code}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Knowledge base test failed: {e}")
        return False

def test_mcp_config() -> bool:
    """Test MCP configuration file"""
    print("⚙️ Testing MCP configuration...")
    
    try:
        with open('mcp-config.json', 'r') as f:
            config = json.load(f)
        
        if 'mcpServers' in config and 'archon' in config['mcpServers']:
            archon_config = config['mcpServers']['archon']
            
            if 'transport' in archon_config and archon_config['transport']['type'] == 'sse':
                print("✅ MCP configuration valid")
                return True
            else:
                print("❌ MCP configuration missing transport settings")
                return False
        else:
            print("❌ MCP configuration missing Archon server")
            return False
            
    except FileNotFoundError:
        print("❌ MCP configuration file not found")
        return False
    except json.JSONDecodeError:
        print("❌ Invalid JSON in MCP configuration")
        return False

def test_claude_code_integration() -> bool:
    """Test Claude Code MCP integration"""
    print("🤖 Testing Claude Code + Archon integration...")
    
    try:
        # Check if Claude Code is available
        result = subprocess.run(
            ['claude', '--version'], 
            capture_output=True, 
            text=True, 
            timeout=30
        )
        
        if result.returncode != 0:
            print("❌ Claude Code not available")
            return False
        
        print("✅ Claude Code available")
        
        # Test MCP connection (if mcp-config.json exists)
        if test_mcp_config():
            print("✅ Claude Code MCP configuration ready")
            return True
        else:
            print("⚠️ Claude Code available but MCP config needs setup")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ Claude Code command timed out")
        return False
    except FileNotFoundError:
        print("❌ Claude Code not installed")
        return False

def test_docker_setup() -> bool:
    """Test Docker container setup"""
    print("🐳 Testing Docker setup...")
    
    try:
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=archon', '--format', '{{.Names}}'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if 'archon' in result.stdout:
            print("✅ Archon Docker container running")
            return True
        else:
            print("❌ Archon Docker container not found")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ Docker command timed out")
        return False
    except FileNotFoundError:
        print("❌ Docker not available")
        return False

def run_integration_test() -> bool:
    """Run complete integration test"""
    print("🧪 Archon + Claude Code Integration Test")
    print("=" * 50)
    
    tests = [
        ("Docker Setup", test_docker_setup),
        ("Archon API", test_archon_api),
        ("MCP Server", test_mcp_server),
        ("Knowledge Base", test_knowledge_base),
        ("MCP Configuration", test_mcp_config),
        ("Claude Code Integration", test_claude_code_integration),
    ]
    
    results = []
    
    for test_name, test_func in tests:
        print(f"\n📋 Running: {test_name}")
        print("-" * 30)
        
        try:
            success = test_func()
            results.append((test_name, success))
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
            results.append((test_name, False))
    
    # Summary
    print(f"\n📊 Test Results Summary")
    print("=" * 50)
    
    passed = 0
    total = len(results)
    
    for test_name, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"  {test_name}: {status}")
        if success:
            passed += 1
    
    print(f"\nResults: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Archon integration is working correctly.")
        return True
    else:
        print("⚠️ Some tests failed. Check the output above for details.")
        return False

def main():
    """Main test execution"""
    
    print("🏛️ Archon Integration Test Suite")
    print("=================================")
    print()
    
    success = run_integration_test()
    
    if success:
        print("\n🚀 Integration Ready!")
        print("You can now use Claude Code with enhanced Archon capabilities:")
        print("  - Knowledge-based code generation")
        print("  - RAG search for similar projects")
        print("  - Pattern recognition across project history")
        print("  - Enhanced context sharing via MCP")
        return 0
    else:
        print("\n🔧 Integration Issues Detected")
        print("Please review the failed tests and:")
        print("  1. Ensure Archon is running: ./ops/archon/init-archon.sh")
        print("  2. Check Docker containers: docker ps")
        print("  3. Verify configuration files")
        print("  4. Review logs for errors")
        return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n⏹️ Test cancelled by user")
        sys.exit(1)