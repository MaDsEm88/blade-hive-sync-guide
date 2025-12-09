# Hive Database Sync - Quick Start Guide
 
> **Quick implementation guide for syncing Blade's embedded Hive database with external databases**
 
## What is This?
 
This guide shows you how to sync data from **Blade's embedded Hive database** (SQLite) to an **external database** (Convex, PostgreSQL, Supabase, MongoDB, etc.) using Blade's built-in triggers system.
 
## Why Sync Databases?
 
**Hive (Local SQLite):**
- ✅ Fast auth & sessions (zero latency)
- ✅ Works offline
- ❌ No real-time sync across clients
- ❌ Single instance only
 
**External Database:**
- ✅ Real-time sync across clients
- ✅ Scalable & distributed
- ✅ Advanced queries & analytics
- ❌ Network latency
 
**Best of Both:** Use Hive for auth/sessions, external database for collaborative features!
 
---
 
## Architecture Overview
 
```
┌──────────────────┐
│  User Action     │  (signup, create post, etc.)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Hive Database   │  (Embedded SQLite)
│  - Accounts      │
│  - Sessions      │
│  - Your Models   │
└────────┬─────────┘
         │
         │ Trigger fires on insert/update
         ▼
┌──────────────────┐
│  Blade Trigger   │  (triggers/your-model.ts)
│  - Detects change│
│  - Calls sync    │
└────────┬─────────┘
         │
         │ HTTP POST with secret
         ▼
┌──────────────────┐
│  Router Endpoint │  (router.ts: /sync)
│  - Validates     │
│  - Routes to DB  │
└────────┬─────────┘
         │
         │ Database API call
         ▼
┌──────────────────┐
│ External Database│  (Convex, Postgres, etc.)
│  - Stores data   │
│  - Real-time sync│
└──────────────────┘
```
 
---
 
## Quick Setup (4 Steps)
 
### Step 1: Add Environment Variables
 
Add to your `.env`:
 
```bash
# Generate with: openssl rand -hex 32
SYNC_SECRET=your_secure_random_secret_here
# Your Blade app URL
BLADE_PUBLIC_URL=http://localhost:3000
# Your external database URL/connection
DATABASE_URL=your_database_connection_string
```
 
### Step 2: Create Sync Helper
 
Create `lib/database-sync.ts`:
 
```typescript
// lib/database-sync.ts
export async function syncToDatabase(
  model: string,
  operation: 'create' | 'update' | 'delete',
  data: any,
  recordId: string
) {
  const bladeUrl = process.env.BLADE_PUBLIC_URL || 'http://localhost:3000';
  const syncSecret = process.env.SYNC_SECRET;
  
  if (!syncSecret) {
    console.warn('[Sync] SYNC_SECRET not configured, skipping sync');
    return;
  }
  
  try {
    const response = await fetch(`${bladeUrl}/sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sync-Secret': syncSecret,
      },
      body: JSON.stringify({ model, operation, data, recordId }),
    });
    
    if (!response.ok) {
      throw new Error('Sync failed');
    }
    
    return await response.json();
  } catch (error) {
    console.error(`[Sync] Failed to sync ${model}:`, error);
    // Fail gracefully - don't break the user experience
  }
}
```
 
### Step 3: Create Blade Trigger
 
Create `triggers/account.ts` (or your model name):
 
```typescript
// triggers/account.ts
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToDatabase } from '../lib/database-sync';
export default triggers({
  // Fires AFTER a new record is created
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToDatabase('users', 'create', {
          id: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
          createdAt: Date.now(),
        }, account.id)
      );
    }
  },
  
  // Fires AFTER a record is updated
  followingSet: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToDatabase('users', 'update', {
          id: account.id,
          email: account.email,
          name: account.name,
          updatedAt: Date.now(),
        }, account.id)
      );
    }
  },
  
  // Fires AFTER a record is deleted
  followingRemove: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToDatabase('users', 'delete', {
          id: account.id,
        }, account.id)
      );
    }
  },
});
```
 
### Step 4: Add Router Endpoint
 
Add to your `router.ts`:
 
```typescript
// router.ts
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  // Validate secret
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  console.log('[Sync] Received:', { model, operation, recordId });
  
  try {
    // Route based on model
    switch (model) {
      case 'users':
        // Call your database here
        await yourDatabase.upsert('users', data);
        break;
      
      case 'posts':
        await yourDatabase.upsert('posts', data);
        break;
      
      default:
        console.warn(`[Sync] Unknown model: ${model}`);
    }
    
    return c.json({ success: true, model, operation });
  } catch (error: any) {
    console.error('[Sync] Failed:', error);
    return c.json({ error: error.message }, 500);
  }
});
```
 
---
 
## Database-Specific Examples
 
### Example 1: Convex
 
```typescript
// router.ts
import { ConvexHttpClient } from 'convex/browser';
const convex = new ConvexHttpClient(process.env.CONVEX_URL!);
app.post('/sync', async (c) => {
  const { model, data } = await c.req.json();
  
  // Validate secret (see Step 4 above)
  
  switch (model) {
    case 'users':
      await convex.mutation('users:syncFromBlade', data);
      break;
  }
  
  return c.json({ success: true });
});
```
 
```typescript
// convex/users.ts
import { mutation } from './_generated/server';
import { v } from 'convex/values';
export const syncFromBlade = mutation({
  args: {
    id: v.string(),
    email: v.string(),
    name: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query('users')
      .withIndex('by_email', q => q.eq('email', args.email))
      .first();
    
    if (existing) {
      await ctx.db.patch(existing._id, {
        name: args.name,
      });
    } else {
      await ctx.db.insert('users', {
        email: args.email,
        name: args.name || 'User',
        bladeId: args.id,
        createdAt: Date.now(),
      });
    }
  },
});
```
 
### Example 2: PostgreSQL (via Prisma)
 
```typescript
// lib/prisma.ts
import { PrismaClient } from '@prisma/client';
export const prisma = new PrismaClient();
```
 
```typescript
// router.ts
import { prisma } from './lib/prisma';
app.post('/sync', async (c) => {
  const { model, operation, data } = await c.req.json();
  
  // Validate secret (see Step 4 above)
  
  switch (model) {
    case 'users':
      if (operation === 'create' || operation === 'update') {
        await prisma.user.upsert({
          where: { email: data.email },
          update: { name: data.name },
          create: {
            email: data.email,
            name: data.name,
            bladeId: data.id,
          },
        });
      } else if (operation === 'delete') {
        await prisma.user.delete({
          where: { bladeId: data.id },
        });
      }
      break;
  }
  
  return c.json({ success: true });
});
```
 
### Example 3: Supabase
 
```typescript
// lib/supabase.ts
import { createClient } from '@supabase/supabase-js';
export const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY! // Use service key for server-side
);
```
 
```typescript
// router.ts
import { supabase } from './lib/supabase';
app.post('/sync', async (c) => {
  const { model, operation, data } = await c.req.json();
  
  // Validate secret (see Step 4 above)
  
  switch (model) {
    case 'users':
      if (operation === 'create' || operation === 'update') {
        await supabase
          .from('users')
          .upsert({
            blade_id: data.id,
            email: data.email,
            name: data.name,
          });
      } else if (operation === 'delete') {
        await supabase
          .from('users')
          .delete()
          .eq('blade_id', data.id);
      }
      break;
  }
  
  return c.json({ success: true });
});
```
 
### Example 4: MongoDB
 
```typescript
// lib/mongodb.ts
import { MongoClient } from 'mongodb';
const client = new MongoClient(process.env.MONGODB_URI!);
export const db = client.db('your-database');
```
 
```typescript
// router.ts
import { db } from './lib/mongodb';
app.post('/sync', async (c) => {
  const { model, operation, data } = await c.req.json();
  
  // Validate secret (see Step 4 above)
  
  switch (model) {
    case 'users':
      if (operation === 'create' || operation === 'update') {
        await db.collection('users').updateOne(
          { bladeId: data.id },
          { $set: data },
          { upsert: true }
        );
      } else if (operation === 'delete') {
        await db.collection('users').deleteOne({ bladeId: data.id });
      }
      break;
  }
  
  return c.json({ success: true });
});
```
 
---
 
## Testing Your Sync
 
### 1. Create a test account
 
```bash
# Start your Blade app
bun dev
```
 
Sign up a new user and check if they appear in your external database.
 
### 2. Manual test with curl
 
```bash
curl -X POST http://localhost:3000/sync \
  -H "Content-Type: application/json" \
  -H "X-Sync-Secret: your_sync_secret" \
  -d '{
    "model": "users",
    "operation": "create",
    "data": {
      "id": "test123",
      "email": "test@example.com",
      "name": "Test User"
    },
    "recordId": "test123"
  }'
```
 
### 3. Check logs
 
Look for log messages:
- `[Sync] Received:` - Router received sync request
- `[Sync] Failed:` - Something went wrong
- Check your external database for the new record
 
---
 
## Common Issues
 
### "SYNC_SECRET not configured"
 
**Solution:** Add `SYNC_SECRET` to your `.env`:
```bash
openssl rand -hex 32
# Copy output to .env
```
 
### "Unauthorized" (401)
 
**Solution:** Make sure the secret matches in both places:
- `lib/database-sync.ts` (sends it)
- `router.ts` (validates it)
 
### Data not appearing
 
**Debug steps:**
1. Check trigger logs: Add `console.log()` in your trigger
2. Check router logs: Add `console.log()` in your router endpoint
3. Check external database connection
4. Verify `BLADE_PUBLIC_URL` is correct
 
### Sync is slow
 
**Good news!** Sync happens in the background via `waitUntil()` - it doesn't slow down your app. Users get immediate responses.
 
---
 
## Best Practices
 
1. ✅ **Use Hive for auth/sessions** - Fast, no network latency
2. ✅ **Use external DB for features** - Real-time sync, scalability
3. ✅ **Always validate SYNC_SECRET** - Security first!
4. ✅ **Log sync operations** - Helps with debugging
5. ✅ **Fail gracefully** - Don't throw errors if sync fails
6. ✅ **Use `waitUntil()`** - Non-blocking background sync
 
---
 
## What's Next?
 
- Add more models (Posts, Comments, etc.)
- Implement bidirectional sync (external DB → Hive)
- Add retry logic for failed syncs
- Monitor sync performance
- Set up error alerting
 
---
 
## Need Help?
 
- Check the full guide: `COMPLETE_GUIDE.md`
- Review database examples: `DATABASE_ADAPTERS.md`
- See Convex implementation: `convex.md`
 
---
 
**That's it!** You now have a working sync system between Blade's Hive database and your external database. 🎉


