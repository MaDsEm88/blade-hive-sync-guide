# Hive Database Sync - Complete Implementation Guide
 
> **Comprehensive guide for implementing production-ready database synchronization with Blade's Hive database**
 
## Table of Contents
 
1. [Architecture Overview](#architecture-overview)
2. [Why Hybrid Database Architecture?](#why-hybrid-database-architecture)
3. [Core Components](#core-components)
4. [Step-by-Step Implementation](#step-by-step-implementation)
5. [Blade Triggers Deep Dive](#blade-triggers-deep-dive)
6. [Router Implementation](#router-implementation)
7. [Security Best Practices](#security-best-practices)
8. [Error Handling & Retry Logic](#error-handling--retry-logic)
9. [Testing & Debugging](#testing--debugging)
10. [Production Considerations](#production-considerations)
11. [Database Adapters](#database-adapters)
 
---
 
## Architecture Overview
 
### System Diagram
 
```
┌────────────────────────────────────────────────────────────┐
│                     USER ACTION                             │
│         (Signup, Create Post, Update Profile, etc.)        │
└─────────────────────┬──────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────┐
│                  BLADE APPLICATION                          │
│  - Pages (React 19 + TypeScript)                           │
│  - Components (Client/Server)                              │
│  - Business Logic                                          │
└─────────────────────┬──────────────────────────────────────┘
                      │
                      │ Writes to database
                      ▼
┌────────────────────────────────────────────────────────────┐
│              HIVE DATABASE (SQLite)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Account    │  │   Session    │  │  YourModel   │     │
│  │   Table      │  │   Table      │  │   Table      │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                             │
│  Features:                                                  │
│  • Zero-latency reads (embedded)                           │
│  • ACID transactions                                       │
│  • Works offline                                           │
│  • Single instance                                         │
└─────────────────────┬──────────────────────────────────────┘
                      │
                      │ Record inserted/updated/deleted
                      ▼
┌────────────────────────────────────────────────────────────┐
│                  BLADE TRIGGERS                             │
│  Located in: triggers/your-model.ts                        │
│                                                             │
│  Available Hooks:                                          │
│  • beforeAdd    - Validate/modify before insert           │
│  • followingAdd - Sync after insert (BEST FOR SYNC)       │
│  • beforeSet    - Validate/modify before update           │
│  • followingSet - Sync after update (BEST FOR SYNC)       │
│  • followingRemove - Sync after delete (BEST FOR SYNC)    │
│                                                             │
│  Key Features:                                             │
│  • waitUntil() for async background operations            │
│  • client object for querying related data                │
│  • Non-blocking execution                                  │
└─────────────────────┬──────────────────────────────────────┘
                      │
                      │ HTTP POST with authentication
                      ▼
┌────────────────────────────────────────────────────────────┐
│                  SYNC HELPER                                │
│  Location: lib/database-sync.ts                            │
│                                                             │
│  Responsibilities:                                         │
│  • Construct HTTP request                                  │
│  • Add authentication (X-Sync-Secret header)              │
│  • Handle errors gracefully                                │
│  • Log sync operations                                     │
└─────────────────────┬──────────────────────────────────────┘
                      │
                      │ POST /sync with JSON payload
                      ▼
┌────────────────────────────────────────────────────────────┐
│              ROUTER ENDPOINT (Hono)                         │
│  Location: router.ts                                       │
│                                                             │
│  Responsibilities:                                         │
│  • Validate X-Sync-Secret header                          │
│  • Parse request body                                      │
│  • Route to appropriate database handler                   │
│  • Return success/error response                           │
│  • Log requests for monitoring                             │
└─────────────────────┬──────────────────────────────────────┘
                      │
                      │ Database API call
                      ▼
┌────────────────────────────────────────────────────────────┐
│              EXTERNAL DATABASE                              │
│  Options: Convex, PostgreSQL, MongoDB, Supabase, etc.      │
│                                                             │
│  Features:                                                  │
│  • Real-time subscriptions                                 │
│  • Horizontal scaling                                      │
│  • Complex queries & aggregations                          │
│  • Multi-user collaboration                                │
│  • Analytics & reporting                                   │
│  • Managed backups                                         │
└────────────────────────────────────────────────────────────┘
```
 
---
 
## Why Hybrid Database Architecture?
 
### The Problem with Single-Database Systems
 
**Option 1: Only Embedded Database (Hive/SQLite)**
- ❌ No real-time sync across clients
- ❌ Difficult to scale horizontally
- ❌ Limited query capabilities
- ❌ No collaborative features
 
**Option 2: Only External Database**
- ❌ Network latency on every request
- ❌ Requires internet connection
- ❌ External dependency (single point of failure)
- ❌ Higher costs
 
### The Hybrid Solution
 
Use **both** databases for what they're best at:
 
| Feature | Hive (Local) | External DB | Winner |
|---------|--------------|-------------|--------|
| Auth/Sessions | ✅ Instant | ❌ Network delay | **Hive** |
| User Profiles | ✅ Fast reads | ✅ Real-time sync | **Both** |
| Collaborative Data | ❌ No sync | ✅ Real-time | **External** |
| Analytics | ❌ Limited | ✅ Advanced | **External** |
| Offline Support | ✅ Works | ❌ Requires internet | **Hive** |
| Cost | ✅ Free | ❌ Per-usage | **Hive** |
### Real-World Use Cases
 
**1. Authentication System**
- Store accounts/sessions in Hive (instant validation)
- Sync user profile to external DB (for public display)
- **Result:** Fast login + real-time profile updates
 
**2. Social Media App**
- Store user preferences in Hive (instant UI)
- Store posts/comments in external DB (real-time feed)
- **Result:** Responsive UI + live updates
 
**3. Collaborative Tool**
- Store settings in Hive (instant app launch)
- Store documents in external DB (real-time collaboration)
- **Result:** Fast startup + live collaboration
 
---
 
## Core Components
 
### 1. Hive Schema (`schema/index.ts`)
 
Define your data models:
 
```typescript
// schema/index.ts
import { model, string, date, link, boolean, number } from 'blade/schema';
export const Account = model({
  slug: "account",
  fields: {
    email: string({ unique: true }),
    name: string(),
    handle: string({ unique: true }),
    emailVerified: boolean(),
    
    // Subscription data (synced to external DB)
    subscriptionPlan: string({ default: 'free' }),
    subscriptionStatus: string({ default: 'none' }),
    
    // Timestamps
    createdAt: date(),
    updatedAt: date(),
  },
});
export const Session = model({
  slug: "session",
  fields: {
    account: link({ target: "account" }),
    token: string({ unique: true }),
    expiresAt: date(),
    createdAt: date(),
  },
});
// Add your custom models
export const Post = model({
  slug: "post",
  pluralSlug: "posts",
  fields: {
    account: link({ target: "account" }),
    title: string(),
    content: string(),
    published: boolean({ default: false }),
    createdAt: date(),
  },
});
```
 
### 2. Blade Trigger (`triggers/account.ts`)
 
Watch for changes and trigger sync:
 
```typescript
// triggers/account.ts
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToDatabase } from '../lib/database-sync';
export default triggers({
  /**
   * Fires AFTER a new account is created
   * Perfect for syncing to external database
   */
  followingAdd: async ({ records, waitUntil, client }) => {
    if (!waitUntil) return;
    
    const { add } = client;
    
    for (const account of records) {
      // Validate data
      if (!account?.id || !account?.email) {
        console.warn('[Account Trigger] Invalid account data:', account);
        continue;
      }
      
      console.log('[Account Trigger] New account:', {
        id: account.id,
        email: account.email,
        name: account.name,
      });
      
      // Create related records (e.g., profile)
      try {
        await add.profile.with({
          account: { id: account.id },
          bio: '',
          avatar: null,
        });
      } catch (err) {
        console.error('[Account Trigger] Failed to create profile:', err);
      }
      
      // Sync to external database
      // waitUntil() doesn't block the request
      waitUntil(
        syncToDatabase('users', 'create', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
          emailVerified: account.emailVerified,
          subscriptionPlan: account.subscriptionPlan,
          subscriptionStatus: account.subscriptionStatus,
          createdAt: Date.now(),
        }, account.id)
      );
    }
  },
  
  /**
   * Fires AFTER an account is updated
   * Sync changes to external database
   */
  followingSet: async ({ records, waitUntil, query }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      if (!account?.id || !account?.email) continue;
      
      console.log('[Account Trigger] Account updated:', {
        id: account.id,
        changes: query.to, // What fields were changed
      });
      
      // Sync updates
      waitUntil(
        syncToDatabase('users', 'update', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
          subscriptionPlan: account.subscriptionPlan,
          subscriptionStatus: account.subscriptionStatus,
          updatedAt: Date.now(),
        }, account.id)
      );
    }
  },
  
  /**
   * Fires AFTER an account is deleted
   * Clean up external database
   */
  followingRemove: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      if (!account?.id) continue;
      
      console.log('[Account Trigger] Account deleted:', account.id);
      
      waitUntil(
        syncToDatabase('users', 'delete', {
          bladeId: account.id,
        }, account.id)
      );
    }
  },
});
```
 
### 3. Sync Helper (`lib/database-sync.ts`)
 
Centralized function for making sync requests:
 
```typescript
// lib/database-sync.ts
/**
 * Syncs data from Hive to external database
 * 
 * @param model - The model/table name (e.g., 'users', 'posts')
 * @param operation - The operation type ('create', 'update', 'delete')
 * @param data - The data to sync
 * @param recordId - The Hive record ID
 * @returns Promise that resolves when sync completes
 */
export async function syncToDatabase(
  model: string,
  operation: 'create' | 'update' | 'delete',
  data: any,
  recordId: string
): Promise {
  const bladeUrl = process.env.BLADE_PUBLIC_URL || 'http://localhost:3000';
  const syncSecret = process.env.SYNC_SECRET;
  
  // Gracefully skip if not configured
  if (!syncSecret) {
    console.warn('[Database Sync] SYNC_SECRET not configured, skipping sync');
    return;
  }
  
  // Validate inputs
  if (!model || !operation || !recordId) {
    console.error('[Database Sync] Missing required parameters:', {
      model,
      operation,
      recordId,
    });
    return;
  }
  
  const startTime = Date.now();
  
  try {
    console.log('[Database Sync] Starting sync:', {
      model,
      operation,
      recordId,
      dataKeys: Object.keys(data || {}),
    });
    
    const response = await fetch(`${bladeUrl}/sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sync-Secret': syncSecret,
      },
      body: JSON.stringify({
        model,
        operation,
        data,
        recordId,
        timestamp: Date.now(),
      }),
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`HTTP ${response.status}: ${errorText}`);
    }
    
    const result = await response.json();
    const duration = Date.now() - startTime;
    
    console.log('[Database Sync] Success:', {
      model,
      operation,
      recordId,
      duration: `${duration}ms`,
      result,
    });
    
    return result;
  } catch (error) {
    const duration = Date.now() - startTime;
    
    console.error('[Database Sync] Failed:', {
      model,
      operation,
      recordId,
      duration: `${duration}ms`,
      error: error instanceof Error ? error.message : String(error),
    });
    
    // Don't throw - fail gracefully to avoid breaking the user experience
    // The app should work even if sync fails
  }
}
/**
 * Batch sync multiple records
 * More efficient than individual syncs
 */
export async function batchSyncToDatabase(
  model: string,
  operation: 'create' | 'update' | 'delete',
  records: Array
): Promise {
  const bladeUrl = process.env.BLADE_PUBLIC_URL || 'http://localhost:3000';
  const syncSecret = process.env.SYNC_SECRET;
  
  if (!syncSecret) {
    console.warn('[Database Sync] SYNC_SECRET not configured, skipping batch sync');
    return;
  }
  
  try {
    const response = await fetch(`${bladeUrl}/sync/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sync-Secret': syncSecret,
      },
      body: JSON.stringify({
        model,
        operation,
        records,
        timestamp: Date.now(),
      }),
    });
    
    if (!response.ok) {
      throw new Error(`Batch sync failed: ${response.statusText}`);
    }
    
    console.log('[Database Sync] Batch sync successful:', {
      model,
      operation,
      count: records.length,
    });
  } catch (error) {
    console.error('[Database Sync] Batch sync failed:', error);
  }
}
```
 
### 4. Router Endpoint (`router.ts`)
 
Handle sync requests and route to database:
 
```typescript
// router.ts
import { Hono } from 'hono';
const app = new Hono();
// ============================================
// SYNC ENDPOINT
// ============================================
app.post('/sync', async (c) => {
  // 1. Validate authentication
  const syncSecret = c.req.header('x-sync-secret');
  
  if (!syncSecret || syncSecret !== process.env.SYNC_SECRET) {
    console.warn('[Sync] Unauthorized sync attempt');
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  // 2. Parse request body
  const { model, operation, data, recordId, timestamp } = await c.req.json();
  
  console.log('[Sync] Received sync request:', {
    model,
    operation,
    recordId,
    timestamp: new Date(timestamp).toISOString(),
  });
  
  // 3. Validate required fields
  if (!model || !operation || !recordId) {
    return c.json({ error: 'Missing required fields' }, 400);
  }
  
  try {
    // 4. Route to appropriate handler based on model
    switch (model) {
      case 'users':
        await handleUserSync(operation, data, recordId);
        break;
      
      case 'posts':
        await handlePostSync(operation, data, recordId);
        break;
      
      case 'comments':
        await handleCommentSync(operation, data, recordId);
        break;
      
      default:
        console.warn('[Sync] Unknown model:', model);
        return c.json({ error: `Unknown model: ${model}` }, 400);
    }
    
    // 5. Return success
    return c.json({
      success: true,
      model,
      operation,
      recordId,
      syncedAt: Date.now(),
    });
  } catch (error: any) {
    console.error('[Sync] Error:', {
      model,
      operation,
      recordId,
      error: error.message,
      stack: error.stack,
    });
    
    return c.json({
      error: error.message || 'Sync failed',
      model,
      operation,
      recordId,
    }, 500);
  }
});
// ============================================
// BATCH SYNC ENDPOINT (Optional but recommended)
// ============================================
app.post('/sync/batch', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (!syncSecret || syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, records } = await c.req.json();
  
  console.log('[Sync] Batch sync request:', {
    model,
    operation,
    count: records.length,
  });
  
  try {
    // Process all records
    const results = await Promise.allSettled(
      records.map((record: any) => {
        switch (model) {
          case 'users':
            return handleUserSync(operation, record.data, record.recordId);
          case 'posts':
            return handlePostSync(operation, record.data, record.recordId);
          default:
            throw new Error(`Unknown model: ${model}`);
        }
      })
    );
    
    const successful = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.filter(r => r.status === 'rejected').length;
    
    console.log('[Sync] Batch sync complete:', {
      successful,
      failed,
      total: records.length,
    });
    
    return c.json({
      success: true,
      successful,
      failed,
      total: records.length,
    });
  } catch (error: any) {
    console.error('[Sync] Batch sync error:', error);
    return c.json({ error: error.message }, 500);
  }
});
// ============================================
// SYNC HANDLERS (Database-specific)
// ============================================
async function handleUserSync(
  operation: string,
  data: any,
  recordId: string
): Promise {
  // TODO: Replace with your database client
  const db = getYourDatabaseClient();
  
  switch (operation) {
    case 'create':
    case 'update':
      await db.users.upsert({
        where: { bladeId: recordId },
        update: data,
        create: { ...data, bladeId: recordId },
      });
      break;
    
    case 'delete':
      await db.users.delete({
        where: { bladeId: recordId },
      });
      break;
    
    default:
      throw new Error(`Unknown operation: ${operation}`);
  }
}
async function handlePostSync(
  operation: string,
  data: any,
  recordId: string
): Promise {
  // Similar to handleUserSync
  // Implement your database logic here
}
async function handleCommentSync(
  operation: string,
  data: any,
  recordId: string
): Promise {
  // Similar to handleUserSync
  // Implement your database logic here
}
export default app;
```
 
---
 
## Blade Triggers Deep Dive
 
### Available Trigger Hooks
 
Blade provides several lifecycle hooks for each model:
 
```typescript
export default triggers({
  // ========== BEFORE HOOKS ==========
  // Run BEFORE database operation
  // Can modify data or prevent operation
  
  beforeAdd: async ({ query, client }) => {
    // Called before INSERT
    // Can modify query or return null to cancel
    return query;
  },
  
  beforeSet: async ({ query, client }) => {
    // Called before UPDATE
    // Can modify query or return null to cancel
    return query;
  },
  
  beforeRemove: async ({ query, client }) => {
    // Called before DELETE
    // Can prevent deletion by returning null
    return query;
  },
  
  // ========== DURING HOOKS ==========
  // Run DURING database operation
  
  add: async ({ query, client }) => {
    // Called during INSERT
    // Can modify the query
    return query;
  },
  
  set: async ({ query, client }) => {
    // Called during UPDATE
    // Can modify the update
    return query;
  },
  
  remove: async ({ query, client }) => {
    // Called during DELETE
    return query;
  },
  
  // ========== FOLLOWING HOOKS ==========
  // Run AFTER database operation completes
  // ⭐ BEST FOR SYNCING TO EXTERNAL DATABASES
  
  followingAdd: async ({ records, client, waitUntil }) => {
    // Called after INSERT succeeds
    // Use waitUntil() for async operations
  },
  
  followingSet: async ({ records, client, waitUntil }) => {
    // Called after UPDATE succeeds
    // Use waitUntil() for async operations
  },
  
  followingRemove: async ({ records, client, waitUntil }) => {
    // Called after DELETE succeeds
    // Use waitUntil() for async operations
  },
});
```
 
### Why Use `following*` Hooks for Sync?
 
1. **Data is already committed** - No risk of sync running before database write
2. **Non-blocking** - Uses `waitUntil()` for background processing
3. **Reliable** - Only fires if database operation succeeded
4. **Access to final data** - Gets the actual records that were created/updated
 
### The `waitUntil()` Function
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  if (!waitUntil) {
    // waitUntil might not be available in all contexts
    console.warn('waitUntil not available');
    return;
  }
  
  // This runs in the background
  // User gets immediate response
  waitUntil(
    syncToDatabase('users', 'create', data, recordId)
  );
  
  // You can queue multiple async operations
  waitUntil(
    sendWelcomeEmail(records[0].email)
  );
  
  waitUntil(
    trackAnalytics('user_created', { userId: records[0].id })
  );
}
```
 
**Benefits:**
- ✅ User doesn't wait for sync
- ✅ Multiple async operations can run in parallel
- ✅ Better performance
- ✅ Errors don't break user experience
 
### The `client` Object
 
The `client` object lets you query and modify other models:
 
```typescript
followingAdd: async ({ records, client, waitUntil }) => {
  const { get, add, set, remove } = client;
  
  for (const account of records) {
    // Query related data
    const profile = await get.profile({
      with: { account: { id: account.id } }
    });
    
    // Create related records
    if (!profile) {
      await add.profile.with({
        account: { id: account.id },
        bio: '',
        avatar: null,
      });
    }
    
    // Update existing records
    await set.account({
      with: { id: account.id },
      to: { lastSyncedAt: new Date() }
    });
    
    // Delete related records
    await remove.session({
      with: { account: { id: account.id } }
    });
  }
}
```
 
---
 
## Step-by-Step Implementation
 
### Phase 1: Setup Environment
 
**1.1 Generate Sync Secret**
 
```bash
# Generate a secure random secret
openssl rand -hex 32
# Or use Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```
 
**1.2 Add Environment Variables**
 
Create or update `.env`:
 
```bash
# Sync Configuration
SYNC_SECRET=your_generated_secret_here
# Blade App URL
BLADE_PUBLIC_URL=http://localhost:3000
# External Database Configuration
DATABASE_URL=your_database_connection_string
DATABASE_API_KEY=your_api_key_if_needed
# Example for Convex
CONVEX_URL=https://your-deployment.convex.cloud
# Example for PostgreSQL
DATABASE_URL=postgresql://user:password@localhost:5432/dbname
# Example for MongoDB
MONGODB_URI=mongodb://localhost:27017/your-database
# Example for Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key
```
 
**⚠️ Important:** Never commit `.env` to version control!
 
### Phase 2: Create Sync Infrastructure
 
**2.1 Create Sync Helper**
 
Create `lib/database-sync.ts` with the code from [Core Components > Sync Helper](#3-sync-helper-libdatabase-syncts)
 
**2.2 Create Router Endpoint**
 
Add to `router.ts` the code from [Core Components > Router Endpoint](#4-router-endpoint-routerts)
 
### Phase 3: Implement Triggers
 
**3.1 Create Account Trigger**
 
Create `triggers/account.ts`:
 
```typescript
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToDatabase } from '../lib/database-sync';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      if (!account?.id || !account?.email) continue;
      
      waitUntil(
        syncToDatabase('users', 'create', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          // Add all fields you want to sync
        }, account.id)
      );
    }
  },
  
  followingSet: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      if (!account?.id) continue;
      
      waitUntil(
        syncToDatabase('users', 'update', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          updatedAt: Date.now(),
        }, account.id)
      );
    }
  },
});
```
 
**3.2 Create Triggers for Other Models**
 
Repeat for each model you want to sync (Posts, Comments, etc.)
 
### Phase 4: Implement Database Handler
 
**4.1 Choose Your Database**
 
See [Database Adapters](#database-adapters) section below for specific implementations.
 
**4.2 Test the Connection**
 
```typescript
// Test script: test-db-connection.ts
async function testDatabaseConnection() {
  const db = getYourDatabaseClient();
  
  try {
    // Test write
    await db.users.create({
      data: {
        bladeId: 'test123',
        email: 'test@example.com',
        name: 'Test User',
      },
    });
    console.log('✅ Database write successful');
    
    // Test read
    const user = await db.users.findUnique({
      where: { bladeId: 'test123' },
    });
    console.log('✅ Database read successful:', user);
    
    // Test cleanup
    await db.users.delete({
      where: { bladeId: 'test123' },
    });
    console.log('✅ Database delete successful');
  } catch (error) {
    console.error('❌ Database test failed:', error);
  }
}
testDatabaseConnection();
```
 
### Phase 5: Test End-to-End
 
**5.1 Start Your Application**
 
```bash
bun dev
```
 
**5.2 Create Test Data**
 
Sign up a new user or create a test record.
 
**5.3 Verify Sync**
 
Check your external database to confirm the record was created.
 
**5.4 Update Test Data**
 
Update the record in Blade and verify the change synced.
 
**5.5 Delete Test Data**
 
Delete the record and verify it was removed from the external database.
 
---
 
## Security Best Practices
 
### 1. Protect the SYNC_SECRET
 
**✅ DO:**
- Generate with cryptographically secure random bytes
- Store in `.env` file (not in code)
- Use different secrets for dev/staging/production
- Rotate periodically (e.g., every 90 days)
 
**❌ DON'T:**
- Commit to version control
- Share in public channels
- Use simple/guessable values
- Reuse across projects
 
### 2. Validate All Inputs
 
```typescript
app.post('/sync', async (c) => {
  const { model, operation, data, recordId } = await c.req.json();
  
  // Validate model whitelist
  const allowedModels = ['users', 'posts', 'comments'];
  if (!allowedModels.includes(model)) {
    return c.json({ error: 'Invalid model' }, 400);
  }
  
  // Validate operation whitelist
  const allowedOps = ['create', 'update', 'delete'];
  if (!allowedOps.includes(operation)) {
    return c.json({ error: 'Invalid operation' }, 400);
  }
  
  // Validate data types
  if (typeof recordId !== 'string' || !recordId) {
    return c.json({ error: 'Invalid recordId' }, 400);
  }
  
  // Continue with sync...
});
```
 
### 3. Rate Limiting
 
```typescript
import { rateLimiter } from 'hono-rate-limiter';
app.use('/sync', rateLimiter({
  windowMs: 60 * 1000, // 1 minute
  max: 100, // 100 requests per minute
  standardHeaders: true,
  keyGenerator: (c) => {
    return c.req.header('x-forwarded-for') || 'unknown';
  },
}));
```
 
### 4. Logging & Monitoring
 
```typescript
app.post('/sync', async (c) => {
  const startTime = Date.now();
  const requestId = crypto.randomUUID();
  
  console.log('[Sync] Request started:', {
    requestId,
    ip: c.req.header('x-forwarded-for'),
    userAgent: c.req.header('user-agent'),
  });
  
  try {
    // ... handle sync ...
    
    const duration = Date.now() - startTime;
    console.log('[Sync] Request completed:', {
      requestId,
      duration: `${duration}ms`,
      status: 'success',
    });
  } catch (error) {
    const duration = Date.now() - startTime;
    console.error('[Sync] Request failed:', {
      requestId,
      duration: `${duration}ms`,
      error,
    });
  }
});
```
 
---
 
## Error Handling & Retry Logic
 
### Graceful Degradation
 
The sync system should **never break the user experience**:
 
```typescript
export async function syncToDatabase(
  model: string,
  operation: string,
  data: any,
  recordId: string
) {
  try {
    await fetch(/* ... */);
  } catch (error) {
    // Log error but don't throw
    console.error('[Sync] Failed:', error);
    
    // Optional: Queue for retry
    await queueForRetry({ model, operation, data, recordId });
    
    // User experience continues normally
  }
}
```
 
### Retry Queue (Advanced)
 
```typescript
// lib/sync-queue.ts
import { Queue } from 'bullmq'; // or your queue library
const syncQueue = new Queue('sync-operations', {
  connection: {
    host: process.env.REDIS_HOST,
    port: Number(process.env.REDIS_PORT),
  },
});
export async function queueForRetry(syncData: any) {
  await syncQueue.add('sync', syncData, {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 2000, // 2s, 4s, 8s
    },
  });
}
// Worker process
const worker = new Worker('sync-operations', async (job) => {
  const { model, operation, data, recordId } = job.data;
  await syncToDatabase(model, operation, data, recordId);
});
```
 
### Idempotency
 
Ensure sync operations are idempotent (safe to retry):
 
```typescript
// Use upsert instead of insert
await db.users.upsert({
  where: { bladeId: recordId },
  update: data,
  create: { ...data, bladeId: recordId },
});
// Not: await db.users.insert(data); ❌
```
 
---
 
## Testing & Debugging
 
### Manual Testing with curl
 
```bash
# Test sync endpoint
curl -X POST http://localhost:3000/sync \
  -H "Content-Type: application/json" \
  -H "X-Sync-Secret: your_sync_secret" \
  -d '{
    "model": "users",
    "operation": "create",
    "data": {
      "bladeId": "test123",
      "email": "test@example.com",
      "name": "Test User"
    },
    "recordId": "test123",
    "timestamp": 1234567890
  }'
# Expected response:
# {"success":true,"model":"users","operation":"create","recordId":"test123"}
```
 
### Automated Tests
 
```typescript
// test/sync.test.ts
import { describe, it, expect } from 'bun:test';
describe('Sync System', () => {
  it('should sync new user to database', async () => {
    // Create account in Hive
    const account = await createTestAccount({
      email: 'test@example.com',
      name: 'Test User',
    });
    
    // Wait for sync (trigger runs in background)
    await sleep(1000);
    
    // Verify in external database
    const user = await db.users.findUnique({
      where: { bladeId: account.id },
    });
    
    expect(user).toBeDefined();
    expect(user.email).toBe('test@example.com');
  });
  
  it('should sync user updates', async () => {
    // Update account
    await updateAccount(testAccountId, {
      name: 'Updated Name',
    });
    
    await sleep(1000);
    
    // Verify update synced
    const user = await db.users.findUnique({
      where: { bladeId: testAccountId },
    });
    
    expect(user.name).toBe('Updated Name');
  });
});
```
 
### Debugging Checklist
 
When sync isn't working:
 
1. ✅ Check `SYNC_SECRET` is set in `.env`
2. ✅ Verify `BLADE_PUBLIC_URL` is correct
3. ✅ Confirm trigger file exists in `triggers/`
4. ✅ Check trigger exports default
5. ✅ Verify router endpoint exists
6. ✅ Check router validates secret correctly
7. ✅ Confirm database connection works
8. ✅ Look for errors in console logs
9. ✅ Test manual curl request
10. ✅ Verify database credentials
 
---
 
## Production Considerations
 
### Performance
 
**Batch Operations:**
```typescript
// Instead of syncing one at a time:
for (const record of records) {
  await syncToDatabase(/* ... */); // ❌ Slow
}
// Batch them:
await batchSyncToDatabase(model, operation, records); // ✅ Fast
```
 
**Async All the Way:**
```typescript
// Use waitUntil() for non-blocking sync
waitUntil(syncToDatabase(/* ... */));
// Not: await syncToDatabase(/* ... */); ❌
```
 
### Monitoring
 
Track key metrics:
- Sync success/failure rate
- Sync latency
- Queue depth (if using retry queue)
- Database connection pool usage
 
### Backup Strategy
 
- Keep Hive as source of truth
- External DB can be rebuilt from Hive if needed
- Regular backups of both databases
- Test restore procedures
 
### Scaling
 
- Use connection pooling for database
- Implement batch syncing for high volume
- Consider message queue for reliability
- Add read replicas for external DB
 
---
 
## Database Adapters
 
### Convex
 
See [QUICK_START.md](./QUICK_START.md#example-1-convex) for Convex example.
 
### PostgreSQL (Prisma)
 
See [QUICK_START.md](./QUICK_START.md#example-2-postgresql-via-prisma) for PostgreSQL example.
 
### Supabase
 
See [QUICK_START.md](./QUICK_START.md#example-3-supabase) for Supabase example.
 
### MongoDB
 
See [QUICK_START.md](./QUICK_START.md#example-4-mongodb) for MongoDB example.
 
---
 
## Conclusion
 
You now have a complete understanding of how to implement database synchronization between Blade's Hive database and any external database!
 
**Key Takeaways:**
1. Use Hive for fast auth/sessions
2. Sync to external DB for collaborative features
3. Use `following*` triggers with `waitUntil()`
4. Validate `SYNC_SECRET` for security
5. Fail gracefully - never break UX
6. Make operations idempotent
7. Monitor and log everything
 
**Next Steps:**
- Implement for your specific database
- Add retry logic for robustness
- Set up monitoring and alerts
- Test in staging before production
- Document your specific sync schema
 
**Need more help?**
- Quick Start: [HIVE_SYNC_QUICK_START.md](./HIVE_SYNC_QUICK_START.md)
- Convex-specific: [HIVE_CONVEX_SYNC.md](./HIVE_CONVEX_SYNC.md)
- Blade Triggers: [BLADE_TRIGGERS_SYNC_GUIDE.md](./BLADE_TRIGGERS_SYNC_GUIDE.md)


