# README - Blade Hive Database Sync

> **Sync your Blade app's embedded Hive database with any external database in 10 minutes**

## What is This?

This is a comprehensive guide for implementing **database synchronization** between:
- **Hive** (Blade's embedded SQLite database) ← Fast, local, zero-latency
- **Your Database** (Convex, PostgreSQL, Supabase, MongoDB, etc.) ← Scalable, real-time

## Why Sync Two Databases?

**The Problem:**
- Embedded databases are fast but can't scale across multiple instances
- External databases are scalable but add network latency

**The Solution:**
- Use Hive for authentication & sessions (instant)
- Sync to external database for collaborative features (scalable)
- Get the best of both worlds! 🎉

## Quick Start

### 1. Choose Your Database

We have ready-to-use adapters for:
- ✅ **Convex** - Real-time serverless (recommended for beginners)
- ✅ **PostgreSQL** - Traditional SQL with Prisma ORM
- ✅ **Supabase** - PostgreSQL + real-time + auth
- ✅ **MongoDB** - NoSQL document database
- ✅ **Firebase** - Google's real-time database
- ✅ **PlanetScale** - Serverless MySQL
- ✅ **Turso** - Edge SQLite
- ✅ **Neon** - Serverless PostgreSQL
- ✅ **Custom API** - Roll your own

### 2. Read the Guide

**New to this?** → Start here:
- **[HIVE_SYNC_QUICK_START.md](./docs/QUICK_START.md)** - 10-minute setup

**Need production-ready code?** → Read this:
- **[HIVE_SYNC_COMPLETE_GUIDE.md](./docs/COMPLETE_GUIDE.md)** - Full implementation

**Want database-specific code?** → Copy from here:
- **[HIVE_SYNC_DATABASE_ADAPTERS.md](./docs/DATABASE_ADAPTERS.md)** - 9 ready-to-use adapters

**Using Convex specifically?** → Check this:
- **[HIVE_CONVEX_SYNC.md](./docs/reference/convex.md)** - Convex deep dive

**Want to master triggers?** → Study this:
- **[BLADE_TRIGGERS_SYNC_GUIDE.md](./docs/reference/triggers.md)** - Complete triggers reference

### 3. Implement (4 Simple Steps)

**Step 1:** Add environment variables
```bash
SYNC_SECRET=your_random_secret_here
BLADE_PUBLIC_URL=http://localhost:3000
DATABASE_URL=your_database_connection_string
```

**Step 2:** Create `lib/database-sync.ts`
```typescript
export async function syncToDatabase(model, operation, data, recordId) {
  // Make authenticated HTTP request to router
}
```

**Step 3:** Create `triggers/account.ts`
```typescript
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    waitUntil(syncToDatabase('users', 'create', data, id));
  },
});
```

**Step 4:** Add router endpoint in `router.ts`
```typescript
app.post('/sync', async (c) => {
  // Validate secret
  // Route to your database
});
```

**That's it!** See the guides for complete code examples.

## Architecture

```
User Action
    ↓
Hive Database (Fast, local)
    ↓
Blade Trigger (Detects changes)
    ↓
Sync Helper (Makes HTTP request)
    ↓
Router Endpoint (Validates & routes)
    ↓
External Database (Scalable, real-time)
```

## Features

✅ **Non-blocking** - Uses `waitUntil()` for background sync  
✅ **Secure** - Validates `SYNC_SECRET` on every request  
✅ **Reliable** - Graceful degradation, app works even if sync fails  
✅ **Idempotent** - Safe to retry operations  
✅ **Scalable** - Supports batch operations  
✅ **Universal** - Works with any database  

## Example: Convex (Simplest)

```typescript
// 1. Install
npm install convex

// 2. Create sync helper (lib/convex-sync.ts)
export async function syncToConvex(model, operation, data, hiveId) {
  await fetch(`${process.env.BLADE_PUBLIC_URL}/convex/sync`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Sync-Secret': process.env.SYNC_SECRET,
    },
    body: JSON.stringify({ model, operation, data, hiveId }),
  });
}

// 3. Add trigger (triggers/account.ts)
import { triggers } from 'blade/schema';
import { syncToConvex } from '../lib/convex-sync';

export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    for (const account of records) {
      waitUntil(
        syncToConvex('users', 'add', {
          email: account.email,
          name: account.name,
        }, account.id)
      );
    }
  },
});

// 4. Add router endpoint (router.ts)
import { ConvexHttpClient } from 'convex/browser';

const convex = new ConvexHttpClient(process.env.CONVEX_URL!);

app.post('/convex/sync', async (c) => {
  if (c.req.header('x-sync-secret') !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, data } = await c.req.json();
  
  if (model === 'users') {
    await convex.mutation('users:syncFromBlade', data);
  }
  
  return c.json({ success: true });
});

// 5. Create Convex mutation (convex/users.ts)
export const syncFromBlade = mutation({
  args: { email: v.string(), name: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query('users')
      .withIndex('by_email', q => q.eq('email', args.email))
      .first();
    
    if (existing) {
      await ctx.db.patch(existing._id, { name: args.name });
    } else {
      await ctx.db.insert('users', args);
    }
  },
});
```

**Done!** Sign up a user and they'll automatically sync to Convex.

## Testing

```bash
# Test with curl
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

## Troubleshooting

**Sync not working?**
1. Check `SYNC_SECRET` is in `.env`
2. Verify `BLADE_PUBLIC_URL` is correct
3. Look for errors in console logs
4. Test with curl (see above)

**Common errors:**
- `"SYNC_SECRET not configured"` → Add to `.env`
- `"Unauthorized"` → Secret mismatch
- `"Connection refused"` → Check URL

## Documentation Index

All guides are in the `docs/` folder:

| File | Purpose | Time to Read |
|------|---------|--------------|
| [INDEX.md](./docs/INDEX.md) | Overview of all docs | 2 min |
| [QUICK_START.md](./docs/QUICK_START.md) | Get started fast | 10 min |
| [COMPLETE_GUIDE.md](./docs/COMPLETE_GUIDE.md) | Production guide | 30 min |
| [DATABASE_ADAPTERS.md](./docs/DATABASE_ADAPTERS.md) | Database examples | 5 min/adapter |
| [reference/convex.md](./docs/reference/convex.md) | Convex specific | 15 min |
| [reference/triggers.md](./docs/reference/triggers.md) | Triggers reference | 25 min |

## Key Concepts

### 1. Blade Triggers
Lifecycle hooks that fire when data changes in Hive:
- `followingAdd` - After insert (best for sync)
- `followingSet` - After update (best for sync)
- `followingRemove` - After delete (best for sync)

### 2. `waitUntil()` Function
Non-blocking async operations:
```typescript
waitUntil(syncToDatabase(...)); // Doesn't block user request
```

### 3. SYNC_SECRET
Authentication token shared between trigger and router:
```bash
# Generate with:
openssl rand -hex 32
```

### 4. Graceful Degradation
App works even if sync fails - never throw errors in sync functions.

### 5. Idempotency
Operations can be retried safely - use upsert instead of insert.

## Production Checklist

Before deploying to production:

- ✅ Generate strong `SYNC_SECRET`
- ✅ Test sync with sample data
- ✅ Implement error handling
- ✅ Add retry logic
- ✅ Set up monitoring/logging
- ✅ Test in staging environment
- ✅ Use HTTPS with proper TLS
- ✅ Implement rate limiting
- ✅ Add database indexes on `bladeId`
- ✅ Document your sync schema

## License

These documentation files are provided as-is for educational purposes. Feel free to:
- ✅ Copy to your own projects
- ✅ Modify for your use case
- ✅ Share with your team
- ✅ Create derivatives

## Credits

This sync system was built for [Blade](https://blade.new), a modern React 19 framework with embedded Hive database.

---

## Quick Links

- 🚀 [Quick Start](./docs/QUICK_START.md)
- 📖 [Complete Guide](./docs/COMPLETE_GUIDE.md)
- 🔌 [Database Adapters](./docs/DATABASE_ADAPTERS.md)
- 📚 [All Documentation](./docs/INDEX.md)

---

**Ready to start?** → Open [QUICK_START.md](./docs/QUICK_START.md) and follow the 4-step guide!

**Questions?** → Check [INDEX.md](./docs/INDEX.md) for the complete documentation index.

Happy syncing! 🚀