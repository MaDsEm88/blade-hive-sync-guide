# Hive Sync - Quick Reference Card
 
> **One-page reference for implementing Hive database sync**
 
## 🚀 4-Step Implementation
 
### 1️⃣ Environment Variables
```bash
# Generate secret: openssl rand -hex 32
SYNC_SECRET=your_secure_random_secret_here
BLADE_PUBLIC_URL=http://localhost:3000
DATABASE_URL=your_database_connection_string
```
 
### 2️⃣ Sync Helper (`lib/database-sync.ts`)
```typescript
export async function syncToDatabase(
  model: string,
  operation: 'create' | 'update' | 'delete',
  data: any,
  recordId: string
) {
  const bladeUrl = process.env.BLADE_PUBLIC_URL || 'http://localhost:3000';
  const syncSecret = process.env.SYNC_SECRET;
  
  if (!syncSecret) {
    console.warn('[Sync] SYNC_SECRET not configured');
    return;
  }
  
  try {
    await fetch(`${bladeUrl}/sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sync-Secret': syncSecret,
      },
      body: JSON.stringify({ model, operation, data, recordId }),
    });
  } catch (error) {
    console.error(`[Sync] Failed:`, error);
  }
}
```
 
### 3️⃣ Blade Trigger (`triggers/account.ts`)
```typescript
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToDatabase } from '../lib/database-sync';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToDatabase('users', 'create', {
          email: account.email,
          name: account.name,
        }, account.id)
      );
    }
  },
  
  followingSet: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToDatabase('users', 'update', {
          email: account.email,
          name: account.name,
        }, account.id)
      );
    }
  },
});
```
 
### 4️⃣ Router Endpoint (`router.ts`)
```typescript
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  try {
    // Call your database
    await yourDatabase.upsert(model, data, recordId);
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
```
 
---
 
## 📊 Database Quick Examples
 
### Convex
```typescript
import { ConvexHttpClient } from 'convex/browser';
const convex = new ConvexHttpClient(process.env.CONVEX_URL!);
await convex.mutation('users:syncFromBlade', data);
```
 
### PostgreSQL (Prisma)
```typescript
import { prisma } from './lib/prisma';
await prisma.user.upsert({
  where: { bladeId: recordId },
  update: data,
  create: { ...data, bladeId: recordId },
});
```
 
### Supabase
```typescript
import { supabase } from './lib/supabase';
await supabase.from('users').upsert({
  blade_id: recordId,
  ...data,
});
```
 
### MongoDB
```typescript
import { getDatabase } from './lib/mongodb';
const db = await getDatabase();
await db.collection('users').updateOne(
  { bladeId: recordId },
  { $set: data },
  { upsert: true }
);
```
 
---
 
## 🧪 Testing
 
```bash
# Test sync endpoint
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
 
---
 
## 🐛 Debugging Checklist
 
- [ ] `SYNC_SECRET` set in `.env`
- [ ] `BLADE_PUBLIC_URL` correct
- [ ] Trigger file exists in `triggers/`
- [ ] Router endpoint registered
- [ ] Database connection working
- [ ] Check console logs for errors
- [ ] Test with curl command
- [ ] Verify database credentials
 
---
 
## 🔐 Security Checklist
 
- [ ] Generate strong `SYNC_SECRET` (32+ chars)
- [ ] Never commit `.env` to git
- [ ] Validate secret in router
- [ ] Use HTTPS in production
- [ ] Implement rate limiting
- [ ] Log sync operations
- [ ] Validate input types
- [ ] Use operation allowlist
 
---
 
## 💡 Key Concepts
 
**`waitUntil()`** - Non-blocking async operations
```typescript
waitUntil(syncToDatabase(...)); // Doesn't block user
```
 
**Idempotency** - Safe to retry
```typescript
// Use upsert, not insert
await db.upsert({ where: { id }, update, create });
```
 
**Graceful Degradation** - Never throw in sync
```typescript
try {
  await syncToDatabase(...);
} catch (error) {
  console.error(error); // Log but don't throw
}
```
 
---
 
## 📚 Documentation Links
 
| Need | Read | Time |
|------|------|------|
| Quick start | [HIVE_SYNC_QUICK_START.md](./HIVE_SYNC_QUICK_START.md) | 10 min |
| Production | [HIVE_SYNC_COMPLETE_GUIDE.md](./HIVE_SYNC_COMPLETE_GUIDE.md) | 30 min |
| DB Code | [HIVE_SYNC_DATABASE_ADAPTERS.md](./HIVE_SYNC_DATABASE_ADAPTERS.md) | 5 min |
| Convex | [HIVE_CONVEX_SYNC.md](./HIVE_CONVEX_SYNC.md) | 15 min |
| Triggers | [BLADE_TRIGGERS_SYNC_GUIDE.md](./BLADE_TRIGGERS_SYNC_GUIDE.md) | 25 min |
---
 
## ⚡ Common Commands
 
```bash
# Generate SYNC_SECRET
openssl rand -hex 32
# Start Blade dev server
bun dev
# Test database connection
bun run test-db-connection.ts
# Check logs
tail -f server.log | grep Sync
```
 
---
 
## 🎯 Architecture Flow
 
```
User Action
    ↓
Hive (SQLite) - Fast, local storage
    ↓
Blade Trigger - Detects changes
    ↓
Sync Helper - Makes HTTP POST
    ↓
Router - Validates secret
    ↓
Database - Stores data
```
 
---
 
## ✅ Production Checklist
 
- [ ] Strong `SYNC_SECRET` configured
- [ ] HTTPS enabled
- [ ] Rate limiting implemented
- [ ] Error logging setup
- [ ] Monitoring alerts configured
- [ ] Database indexes on `bladeId`
- [ ] Retry logic for failures
- [ ] Backup strategy in place
- [ ] Tested in staging
- [ ] Documentation updated
 
---
 
**Print this card and keep it handy!** 📋
 
For complete guides, see [SYNC_README_INDEX.md](./SYNC_README_INDEX.md)

