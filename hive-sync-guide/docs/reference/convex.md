# Convex Integration Reference
 
> **Complete guide for syncing Blade Hive with Convex.dev**
 
## Overview
 
Convex is a real-time serverless database that pairs perfectly with Blade's Hive database. This guide shows you how to sync data between them.
 
## Why Convex?
 
✅ **Real-time subscriptions** - Live updates across all clients  
✅ **TypeScript-first** - Full type safety  
✅ **Serverless** - No infrastructure to manage  
✅ **Built-in auth** - OAuth and custom auth  
✅ **Edge functions** - Actions and mutations  
✅ **Great DX** - Hot reload, logs, dashboard  
 
## Architecture
 
```
Hive (Local SQLite)           Convex (Cloud)
└─ Accounts (auth)           ├─ Users (synced profiles)
└─ Sessions (fast)           ├─ Posts (real-time)
└─ Local cache              ├─ Comments (collaborative)
                            └─ Analytics (aggregated)
```
 
---
 
## Quick Start
 
### 1. Install Convex
 
```bash
npm install convex
npx convex dev
```
 
### 2. Create Convex Schema
 
```typescript
// convex/schema.ts
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
export default defineSchema({
  users: defineTable({
    email: v.string(),
    name: v.string(),
    handle: v.optional(v.string()),
    bladeId: v.string(), // Links to Hive Account.id
    createdAt: v.number(),
  })
    .index("by_email", ["email"])
    .index("by_bladeId", ["bladeId"]),
  
  posts: defineTable({
    title: v.string(),
    content: v.string(),
    authorBladeId: v.string(),
    published: v.boolean(),
    createdAt: v.number(),
  })
    .index("by_author", ["authorBladeId"])
    .index("by_published", ["published"]),
});
```
 
### 3. Create Sync Mutation
 
```typescript
// convex/users.ts
import { mutation } from "./_generated/server";
import { v } from "convex/values";
export const syncFromBlade = mutation({
  args: {
    bladeId: v.string(),
    email: v.string(),
    name: v.optional(v.string()),
    handle: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Check if user exists
    const existingUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.email))
      .first();
    
    if (existingUser) {
      // Update existing user
      await ctx.db.patch(existingUser._id, {
        name: args.name,
        handle: args.handle,
        bladeId: args.bladeId,
      });
      return { userId: existingUser._id, action: "updated" };
    } else {
      // Create new user
      const userId = await ctx.db.insert("users", {
        email: args.email,
        name: args.name || "User",
        handle: args.handle,
        bladeId: args.bladeId,
        createdAt: Date.now(),
      });
      return { userId, action: "created" };
    }
  },
});
```
 
### 4. Create Sync Helper (Blade)
 
```typescript
// lib/convex-sync.ts
export async function syncToConvex(
  model: string,
  operation: 'add' | 'set' | 'remove',
  data: any,
  hiveId: string
) {
  const bladeUrl = process.env.BLADE_PUBLIC_URL || 'http://localhost:3000';
  const syncSecret = process.env.SYNC_SECRET;
  
  if (!syncSecret) {
    console.warn('[Convex Sync] SYNC_SECRET not configured');
    return;
  }
  
  try {
    await fetch(`${bladeUrl}/convex/sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sync-Secret': syncSecret,
      },
      body: JSON.stringify({ model, operation, data, hiveId }),
    });
  } catch (error) {
    console.error(`[Convex Sync] Failed:`, error);
  }
}
```
 
### 5. Create Blade Trigger
 
```typescript
// triggers/account.ts
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToConvex } from '../lib/convex-sync';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToConvex('users', 'add', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
        }, account.id)
      );
    }
  },
  
  followingSet: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToConvex('users', 'set', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
        }, account.id)
      );
    }
  },
});
```
 
### 6. Add Router Endpoint
 
```typescript
// router.ts
import { Hono } from 'hono';
import { ConvexHttpClient } from 'convex/browser';
const app = new Hono();
const convex = new ConvexHttpClient(process.env.CONVEX_URL!);
app.post('/convex/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, hiveId } = await c.req.json();
  
  try {
    switch (model) {
      case 'users':
        await convex.mutation('users:syncFromBlade' as any, data);
        break;
      
      case 'posts':
        await convex.mutation('posts:syncFromBlade' as any, data);
        break;
    }
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
export default app;
```
 
---
 
## Environment Variables
 
```bash
# Convex
CONVEX_URL=https://your-deployment.convex.cloud
# Sync secret (generate with: openssl rand -hex 32)
SYNC_SECRET=your_secure_random_secret
# Blade app URL
BLADE_PUBLIC_URL=http://localhost:3000
```
 
---
 
## Advanced Patterns
 
### Real-time Subscriptions
 
```typescript
// In your Blade component
import { useQuery } from "convex/react";
export function UserList() {
  const users = useQuery(api.users.list);
  
  // Auto-updates when data changes in Convex!
  return (
    
      {users?.map(user => (
        {user.name}
      ))}
    
  );
}
```
 
### Server-side Queries
 
```typescript
// convex/users.ts
export const list = query({
  handler: async (ctx) => {
    return await ctx.db
      .query("users")
      .order("desc")
      .take(100);
  },
});
export const getByBladeId = query({
  args: { bladeId: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .withIndex("by_bladeId", (q) => q.eq("bladeId", args.bladeId))
      .first();
  },
});
```
 
### Background Actions
 
```typescript
// convex/users.ts
import { action } from "./_generated/server";
export const sendWelcomeEmail = action({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.runQuery(api.users.getById, { id: args.userId });
    
    // Call external API (Resend, SendGrid, etc.)
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: user.email,
        subject: 'Welcome!',
        html: 'Welcome to our app!',
      }),
    });
  },
});
```
 
### Scheduled Functions
 
```typescript
// convex/crons.ts
import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";
const crons = cronJobs();
crons.interval(
  "cleanup old sessions",
  { hours: 24 },
  internal.sessions.cleanup,
);
export default crons;
```
 
---
 
## Syncing Multiple Models
 
### Posts
 
```typescript
// triggers/post.ts
import { triggers } from 'blade/schema';
import type { Post } from 'blade/types';
import { syncToConvex } from '../lib/convex-sync';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const post of records) {
      waitUntil(
        syncToConvex('posts', 'add', {
          bladeId: post.id,
          title: post.title,
          content: post.content,
          authorBladeId: post.accountId,
          published: post.published,
          createdAt: Date.now(),
        }, post.id)
      );
    }
  },
  
  followingSet: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const post of records) {
      waitUntil(
        syncToConvex('posts', 'set', {
          bladeId: post.id,
          title: post.title,
          content: post.content,
          published: post.published,
        }, post.id)
      );
    }
  },
});
```
 
```typescript
// convex/posts.ts
export const syncFromBlade = mutation({
  args: {
    bladeId: v.string(),
    title: v.string(),
    content: v.string(),
    authorBladeId: v.string(),
    published: v.boolean(),
    createdAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const existingPost = await ctx.db
      .query("posts")
      .filter((q) => q.eq(q.field("bladeId"), args.bladeId))
      .first();
    
    if (existingPost) {
      await ctx.db.patch(existingPost._id, {
        title: args.title,
        content: args.content,
        published: args.published,
      });
      return { postId: existingPost._id, action: "updated" };
    } else {
      const postId = await ctx.db.insert("posts", {
        bladeId: args.bladeId,
        title: args.title,
        content: args.content,
        authorBladeId: args.authorBladeId,
        published: args.published,
        createdAt: args.createdAt || Date.now(),
      });
      return { postId, action: "created" };
    }
  },
});
```
 
---
 
## Testing
 
### Test Sync Manually
 
```bash
# Create a test user in Hive
# Check Convex dashboard to see if it synced
```
 
### Test with Curl
 
```bash
curl -X POST http://localhost:3000/convex/sync \
  -H "Content-Type: application/json" \
  -H "X-Sync-Secret: your_secret" \
  -d '{
    "model": "users",
    "operation": "add",
    "data": {
      "bladeId": "test123",
      "email": "test@example.com",
      "name": "Test User"
    },
    "hiveId": "test123"
  }'
```
 
### Check Convex Logs
 
```bash
# In your terminal
npx convex logs
# Or check dashboard
# https://dashboard.convex.dev
```
 
---
 
## Debugging
 
### Common Issues
 
**"Could not resolve 'users:syncFromBlade'"**
```bash
# Make sure functions are deployed
npx convex dev
```
 
**"Unauthorized"**
```bash
# Check SYNC_SECRET matches in both places
echo $SYNC_SECRET
```
 
**Data not syncing**
```typescript
// Add debug logs to your trigger
console.log('[Trigger] Syncing:', account.id);
// Check router logs
console.log('[Router] Received:', model, operation);
// Check Convex mutation
console.log('[Convex] Syncing user:', args.email);
```
 
### Enable Debug Logging
 
```typescript
// lib/convex-sync.ts
export async function syncToConvex(/* ... */) {
  console.log('[Convex Sync] Starting:', { model, operation, hiveId });
  
  try {
    const response = await fetch(/* ... */);
    console.log('[Convex Sync] Response:', response.status);
    
    const result = await response.json();
    console.log('[Convex Sync] Result:', result);
    
    return result;
  } catch (error) {
    console.error('[Convex Sync] Error:', error);
  }
}
```
 
---
 
## Performance Tips
 
### 1. Use Batch Mutations
 
```typescript
// Instead of multiple mutations
for (const user of users) {
  await convex.mutation('users:syncFromBlade', user); // ❌ Slow
}
// Use a batch mutation
await convex.mutation('users:syncBatch', { users }); // ✅ Fast
```
 
### 2. Index Everything
 
```typescript
// convex/schema.ts
users: defineTable({
  email: v.string(),
  bladeId: v.string(),
})
  .index("by_email", ["email"])      // For lookups
  .index("by_bladeId", ["bladeId"])  // For sync
```
 
### 3. Use Paginated Queries
 
```typescript
export const listUsers = query({
  args: { 
    paginationOpts: paginationOptsValidator 
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .order("desc")
      .paginate(args.paginationOpts);
  },
});
```
 
---
 
## Security
 
### Validate Data in Mutations
 
```typescript
export const syncFromBlade = mutation({
  args: {
    bladeId: v.string(),
    email: v.string(),
    name: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Validate email format
    if (!args.email.includes('@')) {
      throw new Error('Invalid email');
    }
    
    // Validate bladeId format
    if (!args.bladeId || args.bladeId.length < 10) {
      throw new Error('Invalid bladeId');
    }
    
    // Proceed with sync...
  },
});
```
 
### Use Internal Mutations
 
```typescript
// Only callable from other Convex functions
export const syncFromBlade = internalMutation({
  args: { /* ... */ },
  handler: async (ctx, args) => {
    // This can't be called from client
  },
});
```
 
---
 
## Production Checklist
 
- [ ] Deploy Convex to production (`npx convex deploy`)
- [ ] Set `CONVEX_URL` to production deployment
- [ ] Rotate `SYNC_SECRET` regularly
- [ ] Monitor Convex dashboard for errors
- [ ] Set up Convex alerts
- [ ] Add retry logic for failed syncs
- [ ] Index all foreign keys
- [ ] Test sync under load
- [ ] Document your schema
- [ ] Backup strategy in place
 
---
 
## Resources
 
- [Convex Documentation](https://docs.convex.dev)
- [Convex Dashboard](https://dashboard.convex.dev)
- [Convex Discord](https://convex.dev/community)
- [Convex Examples](https://github.com/get-convex/convex-demos)
 
---
 
## Next Steps
 
1. ✅ Set up Convex project
2. ✅ Create schema
3. ✅ Add sync mutations
4. ✅ Create Blade triggers
5. ✅ Test sync
6. ⬜ Add real-time subscriptions
7. ⬜ Implement search
8. ⬜ Add file storage
9. ⬜ Deploy to production
 
---
 
**Need help?** Check the [main documentation](./QUICK_START.md) or [database adapters guide](./DATABASE_ADAPTERS.md).

