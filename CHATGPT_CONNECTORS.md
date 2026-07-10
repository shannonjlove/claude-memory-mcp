# ChatGPT Connectors Integration Guide

This document explains how the **Claude Memory MCP** service integrates with ChatGPT Custom Actions and the **sjl-mcp-filesystem** service to provide ChatGPT with conversation memory management and file persistence capabilities.

## Overview

Claude Memory MCP provides:
- Universal conversation storage across AI platforms
- Conversation importing from ChatGPT, Cursor, Claude, and others
- Full-text search with SQLite FTS5 optimization
- Conversation summarization and tagging
- Multi-platform metadata storage

When combined with the **sjl-mcp-filesystem** connector, ChatGPT gains:
1. Ability to save conversations to persistent storage
2. Search across all imported conversations
3. Generate conversation summaries
4. Access structured conversation data
5. Export conversations in multiple formats

## Architecture

```
┌─────────────────────────┐
│     ChatGPT             │
└──────────┬──────────────┘
           │
           ├──────────────────────────────────────┐
           │                                      │
    ┌──────▼──────────────┐         ┌────────────▼──────────┐
    │ Claude Memory MCP   │         │ SJL MCP Filesystem    │
    │ Connector           │         │ Connector             │
    │                     │         │                       │
    │ - Store memories    │         │ - Read/write files    │
    │ - Search convs      │         │ - Backup conversations│
    │ - Generate summaries│         │ - Export data         │
    └──────┬──────────────┘         └────────────┬──────────┘
           │                                      │
           ▼                                      ▼
    ┌──────────────────────────┐      ┌──────────────────────┐
    │ Claude Memory Service    │      │ sjl-mcp-file         │
    │ (Local or remote)        │      │ (72.61.74.250:8813)  │
    └──────────────────────────┘      └──────────────────────┘
```

## Available Tools

### Memory Tools (via MCP)

- **add_conversation** - Store a new conversation
- **search_conversations** - Find conversations by content
- **search_by_topic** - Search conversations by topic
- **list_conversations** - List all stored conversations
- **get_conversation** - Retrieve specific conversation
- **generate_weekly_summary** - Create conversation summaries
- **get_search_stats** - Get search statistics

### Filesystem Tools (via sjl-mcp-filesystem)

- **read_file** - Read stored conversation files
- **write_file** - Write conversation data to storage
- **list_directory** - List conversation storage directory
- **search_files** - Find conversation files by pattern
- **create_directory** - Create storage directories
- **get_file_info** - Get file metadata

## ChatGPT Integration

### Configuration

**Claude Memory MCP:**
- **Base URL:** `http://localhost:8001` (local) or remote instance
- **Authentication:** Token-based (if required)
- **Endpoint:** `/mcp/tools/call` or similar

**SJL MCP Filesystem:**
- **Base URL:** `https://72.61.74.250:8813`
- **Authentication:** Bearer Token (JWT)
- **Endpoint:** `/api/tools/call`

### Environment Setup

```bash
# Claude Memory MCP configuration
export CLAUDE_MEMORY_URL="http://localhost:8001"
export CLAUDE_MEMORY_TOKEN="your-token"

# SJL MCP Filesystem configuration
export SJL_MCP_TOKEN="Bearer YOUR-FILESYSTEM-TOKEN"

# Or in .claude/settings.json
{
  "env": {
    "CLAUDE_MEMORY_URL": "http://localhost:8001",
    "CLAUDE_MEMORY_TOKEN": "your-token",
    "SJL_MCP_TOKEN": "Bearer YOUR-FILESYSTEM-TOKEN"
  }
}
```

## Usage Examples

### Example 1: Save ChatGPT Conversation

```
User: "Save this conversation to my memory storage with tags: 'project-x, architecture, discussion'"

ChatGPT will:
1. Collect current conversation content
2. Call Claude Memory MCP add_conversation tool
3. Store with tags and metadata
4. Return confirmation with conversation ID
```

### Example 2: Search Past Conversations

```
User: "Search all my saved conversations for discussions about Phase 2 deployment"

ChatGPT will:
1. Call Claude Memory MCP search_conversations
2. Find matching conversations
3. Display summaries and links
4. Allow further analysis or export
```

### Example 3: Generate Weekly Summary

```
User: "Generate a summary of all conversations this week and save to /home/user/.github/infrastructure/weekly-summary.md"

ChatGPT will:
1. Call Claude Memory MCP generate_weekly_summary
2. Format summary document
3. Call sjl-mcp-filesystem to write file
4. Return file path and summary statistics
```

### Example 4: Export Conversation Archive

```
User: "Export all conversations tagged 'project-x' to /var/lib/para-codes/project-x-archive.json"

ChatGPT will:
1. Search for all 'project-x' conversations
2. Collect conversation data
3. Format as JSON array
4. Write to specified path via filesystem connector
5. Return statistics (file size, conversation count)
```

### Example 5: Conversation Analysis

```
User: "Analyze all conversations about 'VPS deployment' and create:
1. Topic summary
2. Key decisions made
3. Unresolved items
Save analysis to /home/user/.github/infrastructure/vps-analysis.md"

ChatGPT will:
1. Search conversations by topic
2. Analyze content patterns
3. Extract key points
4. Generate markdown report
5. Write to filesystem
6. Return analysis preview
```

## Data Flow

### Saving a Conversation

```
ChatGPT Message
    ↓
add_conversation() call
    ↓
Claude Memory MCP
    ↓
Store to database/file
    ↓
(Optionally) Write to sjl-mcp-filesystem
    ↓
Return confirmation + ID
```

### Exporting Conversation

```
search_conversations() call
    ↓
Claude Memory MCP retrieves data
    ↓
write_file() call (via sjl-mcp-filesystem)
    ↓
File written to disk
    ↓
Backup created automatically
    ↓
Return confirmation with path
```

## Conversation Storage Paths

Conversations can be stored in multiple locations:

**Local Storage (Default):**
```
~/.claude-memory/conversations/
  ├── conversation-123.json
  ├── conversation-456.json
  └── ...
```

**Centralized Storage (via filesystem connector):**
```
/home/user/.github/infrastructure/conversations/
  ├── project-x-conv-1.json
  ├── project-x-conv-2.json
  └── ...

/var/lib/para-codes/conversations/
  ├── analysis-conv-1.json
  ├── analysis-conv-2.json
  └── ...
```

## Security Considerations

### Token Management

Keep tokens separate:
```json
{
  "env": {
    "CLAUDE_MEMORY_TOKEN": "memory-service-token",
    "SJL_MCP_TOKEN": "Bearer filesystem-token"
  }
}
```

### Conversation Privacy

- Conversations stored with user ID and session metadata
- Access control enforced at filesystem level
- Backups created automatically
- Audit logging of all operations

### File Access Control

When exporting conversations:
- Only write to whitelisted paths
- Automatic backups before overwrite
- All operations logged
- Require confirmation for large exports

## Performance Optimization

### SQLite FTS5 Search

Claude Memory MCP uses SQLite FTS5 for optimized search:
- 4.4x faster than linear search
- Full-text relevance scoring
- Automatic indexing
- Sub-3ms search times

### Conversation Caching

```
❌ Inefficient: Re-search same query multiple times
✅ Efficient: Cache search results in local file
```

### Batch Export

```
❌ Inefficient: Export one conversation at a time
✅ Efficient: Bulk export all conversations to single file
```

## Available MCP Endpoints

### Claude Memory MCP
- `POST /add_conversation` - Store conversation
- `POST /search_conversations` - Full-text search
- `POST /search_by_topic` - Topic-based search
- `GET /list_conversations` - List all conversations
- `GET /get_conversation/:id` - Get specific conversation
- `POST /generate_weekly_summary` - Create summary
- `GET /get_search_stats` - Search statistics

### SJL MCP Filesystem
- `POST /api/tools/call` with `read_file` - Read export files
- `POST /api/tools/call` with `write_file` - Write conversions
- `POST /api/tools/call` with `list_directory` - List storage
- `POST /api/tools/call` with `search_files` - Find files

## Integration Examples

### CI/CD Integration

```bash
#!/bin/bash
# Generate and save weekly summary automatically

TOKEN="Bearer YOUR-FILESYSTEM-TOKEN"
MEMORY_URL="http://localhost:8001"

# Generate summary
SUMMARY=$(curl -s $MEMORY_URL/generate_weekly_summary)

# Save to filesystem
curl -X POST https://72.61.74.250:8813/api/tools/call \
  -H "Authorization: $TOKEN" \
  -d '{
    "method": "write_file",
    "arguments": {
      "path": "/home/user/.github/infrastructure/weekly-summary.md",
      "content": "'$SUMMARY'",
      "backup_existing": true
    }
  }'
```

### Automated Backup

```bash
#!/bin/bash
# Backup all conversations

TOKEN="Bearer YOUR-FILESYSTEM-TOKEN"
MEMORY_URL="http://localhost:8001"
DATE=$(date +%Y-%m-%d)

# Export all conversations
CONVS=$(curl -s $MEMORY_URL/list_conversations)

# Save with timestamp
curl -X POST https://72.61.74.250:8813/api/tools/call \
  -H "Authorization: $TOKEN" \
  -d '{
    "method": "write_file",
    "arguments": {
      "path": "/var/lib/para-codes/conversations-backup-'$DATE'.json",
      "content": "'$CONVS'",
      "mode": "600"
    }
  }'
```

## Troubleshooting

### "Connection Refused" (Claude Memory MCP)

**Solution:**
1. Verify service is running: `systemctl status claude-memory-mcp`
2. Check configured URL
3. Verify network connectivity
4. Check firewall rules

### "Unauthorized" (SJL Filesystem)

**Solution:**
1. Verify bearer token is correct
2. Check token hasn't expired
3. Regenerate token if needed
4. Update in ChatGPT settings

### "File Not Found" (Export)

**Solution:**
1. Verify export path exists
2. Check write permissions
3. Use `create_dirs: true` for new directories
4. Verify path is in whitelist

### "Rate Limited" (Filesystem)

**Solution:**
1. Wait 1 hour before retrying
2. Cache results to reduce queries
3. Batch multiple operations
4. Contact infrastructure team to increase limits

## Best Practices

### DO

✅ Save conversations regularly  
✅ Use descriptive tags  
✅ Create backups before export  
✅ Archive old conversations  
✅ Search before duplicating  
✅ Document conversation context  
✅ Review generated summaries  

### DON'T

❌ Store sensitive data in plaintext  
❌ Export without verification  
❌ Share conversation archives  
❌ Delete conversations without backup  
❌ Overwrite production backups  
❌ Commit tokens to version control  
❌ Ignore permission errors  

## Documentation References

- **Claude Memory MCP:** See CLAUDE.md in this project
- **SJL MCP Filesystem:** See `.github/connectors/chatgpt/` directory
- **ChatGPT Setup:** See `.github/connectors/chatgpt/chatgpt-instructions.md`
- **API Reference:** See `docs/` directory in this project

## Support

For issues:
1. Check Claude Memory MCP is running
2. Verify SJL MCP Filesystem is accessible
3. Test connectors separately
4. Review logs: `journalctl -u claude-memory-mcp`
5. Contact infrastructure team

---

**Last Updated:** July 10, 2026  
**Part of:** claude/chatgpt-connectors-write-access-agtyc7 branch
