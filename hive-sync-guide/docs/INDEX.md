# Hive Database Sync - Documentation Index
 
> **Complete documentation for syncing Blade's Hive database with external databases**
 
## 📚 Documentation Overview
 
This folder contains comprehensive guides for implementing database synchronization between Blade's embedded Hive (SQLite) database and external databases like Convex, PostgreSQL, Supabase, MongoDB, and more.
 
---
 
## 🚀 Quick Start
 
**New to Hive sync?** Start here:
 
### [QUICK_START.md](./QUICK_START.md)
 
**10-minute setup guide** with:
- ✅ Minimal configuration
- ✅ Basic implementation in 4 steps
- ✅ Database-specific examples (Convex, Postgres, Supabase, MongoDB)
- ✅ Testing instructions
- ✅ Common troubleshooting
 
**Perfect for:** Getting sync working quickly, proof-of-concept projects
 
---
 
## 📖 Complete Guides
 
### [COMPLETE_GUIDE.md](./COMPLETE_GUIDE.md)
 
**Production-ready implementation guide** covering:
- 🏗️ Architecture deep dive
- 🔧 All core components explained
- 🔐 Security best practices
- 🐛 Error handling & retry logic
- 🧪 Testing & debugging
- 📊 Production considerations
- 📈 Performance optimization
 
**Perfect for:** Production deployments, understanding the full system
 
---
 
## 🔌 Database Adapters
 
### [DATABASE_ADAPTERS.md](./DATABASE_ADAPTERS.md)
 
**Ready-to-use adapters for 9+ databases:**
 
1. **Convex** - Real-time serverless database
2. **PostgreSQL** - Traditional SQL with Prisma ORM
3. **Supabase** - PostgreSQL + real-time features
4. **MongoDB** - NoSQL document database
5. **Firebase Firestore** - Google's real-time NoSQL
6. **PlanetScale** - Serverless MySQL
7. **Turso** - Edge SQLite (libSQL)
8. **Neon** - Serverless PostgreSQL
9. **Custom REST API** - Generic HTTP adapter
 
Each adapter includes:
- ✅ Installation instructions
- ✅ Schema/table setup
- ✅ Complete router implementation
- ✅ Database-specific optimizations
- ✅ Testing examples
 
**Perfect for:** Copy-paste implementations, database comparisons
 
---
 
## 🎯 Specific Implementations
 
### [convex.md](./reference/convex.md)
 
**Detailed Convex.dev integration guide:**
- Convex schema setup
- Mutation implementations
- Real-time subscriptions
- Advanced patterns
 
**Perfect for:** Convex-specific projects, real-time apps
 
---
 
### [triggers.md](./reference/triggers.md)
 
**Comprehensive Blade triggers reference:**
- All trigger hooks explained
- Lifecycle diagrams
- Advanced patterns
- Implementing sync for any database
- Database-specific examples
 
**Perfect for:** Understanding triggers deeply, advanced customization
 
---
 
## 📋 Choosing Your Guide
 
### "I want to get sync working FAST"
→ Start with **[QUICK_START.md](./QUICK_START.md)**
 
### "I'm building for production"
→ Read **[COMPLETE_GUIDE.md](./COMPLETE_GUIDE.md)**
 
### "I need code for [specific database]"
→ Check **[DATABASE_ADAPTERS.md](./DATABASE_ADAPTERS.md)**
 
### "I'm using Convex"
→ Use **[convex.md](./convex.md)**
 
### "I want to understand triggers deeply"
→ Study **[triggers.md](./triggers.md)**
 
---
 
## 🏗️ Architecture Overview
 
```
┌─────────────────────────────────────────────────────┐
│                 Blade Application                    │
│              (React 19 + TypeScript)                │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│          Hive Database (SQLite)                      │
│  Fast, embedded, zero-latency                       │
│  • Accounts                                         │
│  • Sessions                                         │
│  • Your Models                                      │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ Blade Triggers fire on changes
                  ▼
┌─────────────────────────────────────────────────────┐
│              Blade Triggers                          │
│  • followingAdd (after insert)                      │
│  • followingSet (after update)                      │
│  • followingRemove (after delete)                   │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ HTTP POST with secret
                  ▼
┌─────────────────────────────────────────────────────┐
│              Router Endpoint                         │
│  • Validates SYNC_SECRET                            │
│  • Routes to database handler                       │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ Database API call
                  ▼
┌─────────────────────────────────────────────────────┐
│          External Database                           │
│  Real-time, scalable, collaborative                 │
│  • Convex, PostgreSQL, Supabase, etc.              │
└─────────────────────────────────────────────────────┘
```
 
---
 
## 🎓 Key Concepts
 
### 1. **Hybrid Architecture**
Use Hive for fast auth/sessions, external DB for collaborative features.
 
### 2. **Blade Triggers**
Lifecycle hooks that fire when data changes in Hive.
 
### 3. **`waitUntil()` Function**
Non-blocking async operations - sync doesn't slow down your app.
 
### 4. **SYNC_SECRET**
Authentication between triggers and router endpoint.
 
### 5. **Graceful Degradation**
App works even if sync fails - never break user experience.
 
---
 
## 🔧 Core Components
 
Every sync implementation needs these 4 files:
 
### 1. Sync Helper (`lib/database-sync.ts`)
```typescript
export async function syncToDatabase(
  model: string,
  operation: 'create' | 'update' | 'delete',
  data: any,
  recordId: string
) {
  // Makes authenticated HTTP request to router
}
```
 
### 2. Trigger (`triggers/account.ts`)
```typescript
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    waitUntil(syncToDatabase('users', 'create', data, id));
  },
});
```
 
### 3. Router Endpoint (`router.ts`)
```typescript
app.post('/sync', async (c) => {
  // Validate SYNC_SECRET
  // Route to database handler
});
```
 
### 4. Database Handler
```typescript
async function handleUserSync(operation, data, recordId) {
  // Call your database API
  await yourDatabase.upsert('users', data);
}
```
 
---
 
## ⚙️ Environment Variables
 
All implementations require:
 
```bash
# Generate with: openssl rand -hex 32
SYNC_SECRET=your_secure_random_secret
# Your Blade app URL
BLADE_PUBLIC_URL=http://localhost:3000
# Your database connection
DATABASE_URL=your_database_connection_string
```
 
---
 
## 🧪 Testing Your Sync
 
### 1. Manual Test
```bash
curl -X POST http://localhost:3000/sync \
  -H "Content-Type: application/json" \
  -H "X-Sync-Secret: your_secret" \
  -d '{
    "model": "users",
    "operation": "create",
    "data": {"email": "test@example.com"},
    "recordId": "test123"
  }'
```
 
### 2. Create Test User
Sign up in your app and check if user appears in external database.
 
### 3. Check Logs
Look for:
- `[Sync] Received:` - Router got the request
- `[Sync] Success:` - Sync completed
- `[Sync] Failed:` - Something went wrong
 
---
 
## 🔐 Security Checklist
 
- ✅ Generate strong `SYNC_SECRET` with crypto.randomBytes
- ✅ Store secrets in `.env`, never commit to git
- ✅ Validate secret in router endpoint
- ✅ Use HTTPS in production
- ✅ Implement rate limiting
- ✅ Log all sync operations
- ✅ Validate input data types
- ✅ Use allowlist for models/operations
 
---
 
## 🐛 Troubleshooting
 
### Sync not working?
 
1. ✅ Check `SYNC_SECRET` is set in `.env`
2. ✅ Verify `BLADE_PUBLIC_URL` is correct
3. ✅ Confirm trigger file exists in `triggers/`
4. ✅ Check router endpoint is registered
5. ✅ Test database connection separately
6. ✅ Look for errors in console logs
7. ✅ Try manual curl request
8. ✅ Verify database credentials
 
### Common Errors
 
**"SYNC_SECRET not configured"**
→ Add `SYNC_SECRET` to `.env`
 
**"Unauthorized" (401)**
→ Secret mismatch between trigger and router
 
**"Connection refused"**
→ Check `BLADE_PUBLIC_URL` and ensure server is running
 
**Data not appearing**
→ Check trigger logs, router logs, and database connection
 
---
 
## 📊 Production Best Practices
 
1. ✅ Use `waitUntil()` for non-blocking sync
2. ✅ Implement retry logic for failed syncs
3. ✅ Make operations idempotent (safe to retry)
4. ✅ Log sync metrics (success rate, latency)
5. ✅ Monitor database connection pool
6. ✅ Use batch syncing for high volume
7. ✅ Set up error alerting
8. ✅ Test with staging database first
 
---
 
## 🎯 Next Steps
 
### Phase 1: Basic Setup
1. Read [Quick Start Guide](./HIVE_SYNC_QUICK_START.md)
2. Choose your database from [Adapters Guide](./HIVE_SYNC_DATABASE_ADAPTERS.md)
3. Implement the 4 core components
4. Test with curl and sample data
 
### Phase 2: Production Ready
1. Read [Complete Guide](./HIVE_SYNC_COMPLETE_GUIDE.md)
2. Implement error handling & retry logic
3. Add monitoring and logging
4. Set up rate limiting
5. Test in staging environment
 
### Phase 3: Advanced Features
1. Implement batch syncing
2. Add bidirectional sync (DB → Hive)
3. Set up queue-based retry system
4. Optimize for high volume
5. Add real-time features (if using Convex/Supabase)
 
---
 
## 💡 Tips & Tricks
 
### Performance
- Use batch operations for multiple records
- Implement connection pooling
- Cache database client instances
- Use indexes on `bladeId` fields
 
### Reliability
- Make sync operations idempotent
- Never throw errors in triggers
- Implement exponential backoff for retries
- Log all sync operations
 
### Security
- Rotate `SYNC_SECRET` periodically
- Use different secrets per environment
- Implement rate limiting
- Validate all input data
 
---
 
## 📚 Additional Resources
 
### Official Blade Documentation
- Blade Triggers: [blade.new/docs/triggers](https://blade.new/docs/triggers)
- Hive Database: [blade.new/docs/hive](https://blade.new/docs/hive)
 
### Database Documentation
- Convex: [docs.convex.dev](https://docs.convex.dev)
- Prisma: [prisma.io/docs](https://www.prisma.io/docs)
- Supabase: [supabase.com/docs](https://supabase.com/docs)
- MongoDB: [mongodb.com/docs](https://www.mongodb.com/docs)
 
---
 
## 🤝 Contributing
 
Found an issue or want to add a database adapter?
 
1. Test your implementation thoroughly
2. Follow existing code style
3. Add documentation and examples
4. Include error handling
5. Submit with test results
 
---
 
## 📝 Document Changelog
 
### v1.0.0 (Current)
- Initial release
- 9 database adapters
- Complete implementation guides
- Quick start guide
- Troubleshooting documentation
 
---
 
## ✨ Summary
 
You now have everything you need to:
- ✅ Understand the hybrid database architecture
- ✅ Implement sync for any database
- ✅ Deploy to production with confidence
- ✅ Debug and troubleshoot issues
- ✅ Optimize for performance
 
**Start with the [Quick Start Guide](./QUICK_START.md) and you'll be syncing in 10 minutes!** 🚀
 
---
 
**Questions?** Check the troubleshooting sections in each guide or open an issue in the repository.
Request changes...





