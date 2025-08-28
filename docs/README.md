# AI Continuous Delivery System

An autonomous continuous delivery system that uses AI agents to plan, develop, test, and deploy code based on natural language specifications.

## System Overview

This system implements a complete AI-driven continuous delivery pipeline that:
- Ingests project specifications via email or API
- Uses Claude Code + Archon MCP for automated planning and development
- Runs comprehensive testing (unit + E2E) with validation gates
- Manages the entire process through database-driven workflows

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Email/API     │───▶│   Supabase B    │───▶│ GitHub Actions  │
│   Ingestion     │    │  (Control-Plane)│    │   (Runner)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                │                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Archon MCP    │◀───│   Claude Code   │◀───│  Sprint Runner  │
│  (Port 8051)    │    │   Planning      │    │   Workflow      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       │                       │
         │                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Supabase A    │    │    Testing &    │    │   Artifacts &   │
│  (Archon Data)  │    │   Validation    │    │   Reporting     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Key Components

- **Archon MCP**: Model Context Protocol server for AI agent communication
- **Claude Code**: AI planning and development agent
- **Supabase Projects**: A (Archon data) + B (Control-plane)
- **GitHub Actions**: Self-hosted ARM64 runner for CI/CD execution
- **Testing Stack**: pytest (unit) + Playwright (E2E)

## Documentation Structure

- [`architecture/`](./architecture/) - System design and component diagrams
- [`schemas/`](./schemas/) - Database schemas and API contracts
- [`workflows/`](./workflows/) - GitHub Actions and process flows
- [`setup/`](./setup/) - Installation and configuration guides

## Quick Start

1. **Prerequisites**: Archon MCP running, Supabase projects configured
2. **Deploy**: GitHub Actions runner + workflow files
3. **Test**: Trigger workflow via API or repository dispatch
4. **Monitor**: Check run status in Supabase control-plane

For detailed setup instructions, see [`setup/deployment-guide.md`](./setup/deployment-guide.md).

## Status

✅ **Fully Operational** - All tests passing, complete pipeline working
- Python Tests: 3/3 ✅
- Playwright E2E: 2/2 ✅  
- Database Operations: Working ✅
- Report Generation: Working ✅