# System Component Diagram

## High-Level Architecture

```
                    ┌─────────────────────────────────┐
                    │         INGESTION LAYER         │
                    │                                 │
                    │  ┌─────────────┐ ┌─────────────┐│
                    │  │Gmail Push   │ │   REST API  ││
                    │  │Notifications│ │   Webhooks  ││
                    │  └─────────────┘ └─────────────┘│
                    └─────────────────────────────────┘
                                    │
                                    ▼
                    ┌─────────────────────────────────┐
                    │        CONTROL PLANE            │
                    │                                 │
                    │  ┌─────────────┐ ┌─────────────┐│
                    │  │ Supabase B  │ │Edge Functions││
                    │  │PostgreSQL   │ │ Notifications││
                    │  │   + RLS     │ │  Processing  ││
                    │  └─────────────┘ └─────────────┘│
                    └─────────────────────────────────┘
                                    │
                                    ▼
                    ┌─────────────────────────────────┐
                    │       EXECUTION LAYER           │
                    │                                 │
                    │  ┌─────────────┐ ┌─────────────┐│
                    │  │GitHub Actions│ │Self-Hosted  ││
                    │  │   Workflow   │ │ARM64 Runner ││
                    │  └─────────────┘ └─────────────┘│
                    └─────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
        ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
        │   AI AGENTS     │ │   TESTING       │ │   ARTIFACTS     │
        │                 │ │                 │ │                 │
        │┌───────────────┐│ │┌───────────────┐│ │┌───────────────┐│
        ││  Claude Code  ││ ││    pytest     ││ ││ Test Reports  ││
        ││   Planning    ││ ││  Unit Tests   ││ ││   Coverage    ││
        │└───────────────┘│ │└───────────────┘│ │└───────────────┘│
        │┌───────────────┐│ │┌───────────────┐│ │┌───────────────┐│
        ││  Archon MCP   ││ ││  Playwright   ││ ││  Screenshots  ││
        ││   Context     ││ ││   E2E Tests   ││ ││    Videos     ││
        │└───────────────┘│ │└───────────────┘│ │└───────────────┘│
        └─────────────────┘ └─────────────────┘ └─────────────────┘
                    │               │               │
                    └───────────────┼───────────────┘
                                    ▼
                    ┌─────────────────────────────────┐
                    │      VALIDATION LAYER           │
                    │                                 │
                    │  ┌─────────────┐ ┌─────────────┐│
                    │  │DoD Gate     │ │Notifications││
                    │  │Validation   │ │  & Reports  ││
                    │  └─────────────┘ └─────────────┘│
                    └─────────────────────────────────┘
```

## Component Details

### Ingestion Layer
- **Gmail Push**: Real-time email processing for specification ingestion
- **REST API**: Direct API access for immediate workflow triggers
- **Webhook Support**: GitHub and external service integrations

### Control Plane
- **Supabase B**: Primary database for workflow orchestration
- **Edge Functions**: Serverless processing and notifications
- **Authentication**: Service-based auth with RLS policies

### Execution Layer
- **GitHub Actions**: CI/CD orchestration platform
- **Self-Hosted Runner**: ARM64 Ubuntu runner for consistent environment
- **Resource Management**: Docker containers and process isolation

### AI Agents
- **Claude Code**: Primary planning and development agent
- **Archon MCP**: Context provider and project data access
- **Model Selection**: Flexible model choice based on task requirements

### Testing
- **pytest**: Python unit testing with coverage reporting
- **Playwright**: Cross-browser E2E testing with artifacts
- **Validation**: Automated quality gates and DoD checking

### Artifacts
- **Reports**: HTML, JUnit, coverage reports
- **Media**: Screenshots, videos from failed tests
- **Logs**: Complete execution traces and debugging info

## Data Flow Patterns

### 1. Specification Processing
```
Email/API → Supabase B → GitHub Workflow → Claude Code → Code Generation
```

### 2. Testing Pipeline
```
Code Commit → pytest Execution → Playwright Tests → Report Generation → Artifact Upload
```

### 3. Validation Gate
```
Test Results → DoD Evaluation → Status Update → Notification → Optional PR Creation
```

## Integration Points

### External Integrations
- **GitHub**: Repository management, Actions execution, PR creation
- **Supabase**: Database, authentication, file storage, Edge Functions
- **Claude**: AI model access via subscription or API
- **Docker**: Service containerization and isolation

### Internal Integrations
- **MCP Protocol**: Standardized AI agent communication
- **REST APIs**: Service-to-service communication
- **Database Events**: Real-time status updates and notifications
- **File Storage**: Secure artifact and specification storage

## Scalability Architecture

### Horizontal Scaling Points
- **Multiple Runners**: Scale GitHub Actions execution capacity
- **Database Replicas**: Read replicas for reporting and analytics
- **Load Balancers**: Distribute Archon MCP connections
- **CDN**: Global artifact delivery

### Performance Optimizations
- **Caching**: Dependencies, test results, artifacts
- **Parallel Execution**: Tests, validations, uploads
- **Incremental Processing**: Only process changed specifications
- **Resource Pooling**: Shared database connections and compute resources