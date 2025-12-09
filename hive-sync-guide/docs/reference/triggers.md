# Blade Triggers Reference
 
> **Complete reference for using Blade triggers to sync data**
 
## Overview
 
Blade triggers are **lifecycle hooks** that run automatically when data changes in your Hive database. They're perfect for syncing data to external databases.
 
## Why Triggers?
 
✅ **Automatic** - Fire on every data change  
✅ **Non-blocking** - Use `waitUntil()` for async operations  
✅ **Reliable** - Only fire after successful database writes  
✅ **Flexible** - Access to full database client  
✅ **Type-safe** - Full TypeScript support  
 
---
 
## Available Hooks
 
### Before Hooks
Run **before** database operation, can modify or prevent:
 
```typescript
triggers({
  beforeAdd: async ({ query, client }) => {
    // Called BEFORE insert
    // Can modify query or return null to cancel
    return query;
  },
  
  beforeSet: async ({ query, client }) => {
    // Called BEFORE update
    // Can modify query or return null to cancel
    return query;
  },
  
  beforeRemove: async ({ query, client }) => {
    // Called BEFORE delete
    // Can prevent deletion by returning null
    return query;
  },
})
```
 
### During Hooks
Run **during** database operation:
 
```typescript
triggers({
  add: async ({ query, client }) => {
    // Called DURING insert
    // Can modify the query
    return query;
  },
  
  set: async ({ query, client }) => {
    // Called DURING update
    return query;
  },
  
  remove: async ({ query, client }) => {
    // Called DURING delete
    return query;
  },
})
```
 
### Following Hooks ⭐ (Best for Sync)
Run **after** database operation succeeds:
 
```typescript
triggers({
  followingAdd: async ({ records, client, waitUntil }) => {
    // Called AFTER insert succeeds
    // Perfect for syncing to external databases
    // Use waitUntil() for async operations
  },
  
  followingSet: async ({ records, client, waitUntil }) => {
    // Called AFTER update succeeds
    // Perfect for syncing updates
  },
  
  followingRemove: async ({ records, client, waitUntil }) => {
    // Called AFTER delete succeeds
    // Perfect for cleanup
  },
})
```
 
---
 
## Basic Usage
 
### Creating a Trigger File
 
```typescript
// triggers/account.ts
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    console.log('New account created:', records[0].email);
  },
});
```
 
### File Naming Convention
 
```
triggers/
├── account.ts       // For Account model
├── session.ts       // For Session model
├── post.ts          // For Post model
└── comment.ts       // For Comment model
```
 
**Rule:** Filename should match model slug in `schema/index.ts`
 
---
 
## The `waitUntil()` Function
 
### What is it?
 
`waitUntil()` allows triggers to perform async operations **without blocking** the main request.
 
### Example: Syncing Data
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  if (!waitUntil) return; // Always check if available
  
  // This runs in the background
  // User gets immediate response
  waitUntil(
    syncToDatabase('users', 'create', {
      email: records[0].email,
      name: records[0].name,
    }, records[0].id)
  );
  
  // Multiple operations can run in parallel
  waitUntil(
    sendWelcomeEmail(records[0].email)
  );
  
  waitUntil(
    trackAnalytics('user_created', { userId: records[0].id })
  );
}
```
 
### Benefits
 
✅ **Non-blocking** - User doesn't wait for sync  
✅ **Parallel** - Multiple operations run simultaneously  
✅ **Reliable** - Errors don't break user experience  
✅ **Fast** - Better performance  
 
### Important Notes
 
```typescript
// Always check if waitUntil is available
if (!waitUntil) return;
// Don't use await inside waitUntil
waitUntil(syncData()); // ✅ Correct
// Don't do this
await waitUntil(syncData()); // ❌ Wrong
```
 
---
 
## The `client` Object
 
### What is it?
 
The `client` object provides methods to query and modify other models within triggers.
 
### Available Methods
 
```typescript
const { get, add, set, remove } = client;
```
 
### Example: Query Related Data
 
```typescript
followingAdd: async ({ records, client, waitUntil }) => {
  const { get, add } = client;
  
  for (const account of records) {
    // Get related profile
    const profile = await get.profile({
      with: { account: { id: account.id } }
    });
    
    // Create profile if it doesn't exist
    if (!profile) {
      await add.profile.with({
        account: { id: account.id },
        bio: '',
        avatar: null,
      });
    }
  }
}
```
 
### Example: Update Related Records
 
```typescript
followingSet: async ({ records, client }) => {
  const { set } = client;
  
  for (const post of records) {
    // Update author's last active timestamp
    await set.account({
      with: { id: post.accountId },
      to: { lastActive: new Date() }
    });
  }
}
```
 
### Example: Delete Related Records
 
```typescript
followingRemove: async ({ records, client }) => {
  const { remove } = client;
  
  for (const account of records) {
    // Delete all user's sessions
    await remove.session({
      with: { account: { id: account.id } }
    });
  }
}
```
 
---
 
## Complete Sync Example
 
### Step 1: Create Sync Helper
 
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
    console.error(`[Sync] Failed to sync ${model}:`, error);
  }
}
```
 
### Step 2: Create Trigger with Sync
 
```typescript
// triggers/account.ts
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToDatabase } from '../lib/database-sync';
export default triggers({
  // Sync new accounts
  followingAdd: async ({ records, waitUntil, client }) => {
    if (!waitUntil) return;
    
    const { add } = client;
    
    for (const account of records) {
      // Validate data
      if (!account?.id || !account?.email) {
        console.warn('[Trigger] Invalid account:', account);
        continue;
      }
      
      console.log('[Trigger] New account:', {
        id: account.id,
        email: account.email,
      });
      
      // Create related records
      await add.profile.with({
        account: { id: account.id },
        bio: '',
      });
      
      // Sync to external database
      waitUntil(
        syncToDatabase('users', 'create', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
          createdAt: Date.now(),
        }, account.id)
      );
    }
  },
  
  // Sync account updates
  followingSet: async ({ records, waitUntil, query }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      if (!account?.id) continue;
      
      console.log('[Trigger] Account updated:', {
        id: account.id,
        changes: query.to, // What changed
      });
      
      waitUntil(
        syncToDatabase('users', 'update', {
          bladeId: account.id,
          email: account.email,
          name: account.name,
          handle: account.handle,
          updatedAt: Date.now(),
        }, account.id)
      );
    }
  },
  
  // Sync account deletions
  followingRemove: async ({ records, waitUntil, client }) => {
    if (!waitUntil) return;
    
    const { remove } = client;
    
    for (const account of records) {
      if (!account?.id) continue;
      
      console.log('[Trigger] Account deleted:', account.id);
      
      // Clean up related records
      await remove.session({
        with: { account: { id: account.id } }
      });
      
      // Sync deletion to external database
      waitUntil(
        syncToDatabase('users', 'delete', {
          bladeId: account.id,
        }, account.id)
      );
    }
  },
});
```
 
---
 
## Advanced Patterns
 
### 1. Conditional Sync
 
Only sync certain records:
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  if (!waitUntil) return;
  
  for (const post of records) {
    // Only sync published posts
    if (post.published) {
      waitUntil(syncToDatabase('posts', 'create', post, post.id));
    }
  }
}
```
 
### 2. Transform Data Before Sync
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  if (!waitUntil) return;
  
  for (const account of records) {
    // Transform data for external database
    const transformedData = {
      id: account.id,
      emailAddress: account.email, // Rename field
      fullName: account.name,
      username: account.handle,
      isVerified: account.emailVerified,
      registeredAt: new Date().toISOString(), // Format date
    };
    
    waitUntil(syncToDatabase('users', 'create', transformedData, account.id));
  }
}
```
 
### 3. Batch Processing
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  if (!waitUntil) return;
  
  // Collect all records
  const batch = records.map(account => ({
    data: {
      bladeId: account.id,
      email: account.email,
      name: account.name,
    },
    recordId: account.id,
  }));
  
  // Sync in one batch
  waitUntil(
    batchSyncToDatabase('users', 'create', batch)
  );
}
```
 
### 4. Error Handling
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  if (!waitUntil) return;
  
  for (const account of records) {
    waitUntil(
      (async () => {
        try {
          await syncToDatabase('users', 'create', account, account.id);
          console.log('[Trigger] Sync successful:', account.id);
        } catch (error) {
          console.error('[Trigger] Sync failed:', account.id, error);
          // Don't throw - fail gracefully
          // Optionally: queue for retry
          await queueForRetry({ model: 'users', data: account });
        }
      })()
    );
  }
}
```
 
### 5. Audit Logging
 
```typescript
followingAdd: async ({ records, waitUntil, client }) => {
  const { add } = client;
  
  for (const account of records) {
    // Create audit log
    await add.auditLog.with({
      action: 'account_created',
      accountId: account.id,
      data: JSON.stringify(account),
      timestamp: new Date(),
    });
    
    // Sync to external DB
    if (waitUntil) {
      waitUntil(syncToDatabase('users', 'create', account, account.id));
    }
  }
}
```
 
---
 
## The `query` Object
 
Available in `beforeSet` and `followingSet` hooks:
 
```typescript
followingSet: async ({ records, query, waitUntil }) => {
  console.log('What changed:', query.to);
  
  // Example: Only sync if specific fields changed
  if (query.to?.name || query.to?.email) {
    waitUntil(syncToDatabase('users', 'update', records[0], records[0].id));
  }
}
```
 
### Structure
 
```typescript
query = {
  with: { id: 'abc123' },      // Which record
  to: { name: 'New Name' },    // What changed (only in Set hooks)
}
```
 
---
 
## Multiple Models Example
 
### Posts Trigger
 
```typescript
// triggers/post.ts
import { triggers } from 'blade/schema';
import type { Post } from 'blade/types';
import { syncToDatabase } from '../lib/database-sync';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const post of records) {
      waitUntil(
        syncToDatabase('posts', 'create', {
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
        syncToDatabase('posts', 'update', {
          bladeId: post.id,
          title: post.title,
          content: post.content,
          published: post.published,
          updatedAt: Date.now(),
        }, post.id)
      );
    }
  },
  
  followingRemove: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const post of records) {
      waitUntil(
        syncToDatabase('posts', 'delete', {
          bladeId: post.id,
        }, post.id)
      );
    }
  },
});
```
 
---
 
## Testing Triggers
 
### 1. Add Debug Logging
 
```typescript
followingAdd: async ({ records, waitUntil }) => {
  console.log('[Trigger] Starting for records:', records.length);
  
  for (const record of records) {
    console.log('[Trigger] Processing:', record.id);
    
    if (waitUntil) {
      waitUntil(
        (async () => {
          console.log('[Trigger] Syncing:', record.id);
          await syncToDatabase('users', 'create', record, record.id);
          console.log('[Trigger] Synced:', record.id);
        })()
      );
    } else {
      console.warn('[Trigger] waitUntil not available');
    }
  }
  
  console.log('[Trigger] Completed');
}
```
 
### 2. Test Manually
 
```typescript
// In your app, create a test record
const account = await createAccount({
  email: 'test@example.com',
  name: 'Test User',
});
// Check logs to see if trigger fired
// Check external database to see if synced
```
 
### 3. Automated Tests
 
```typescript
// test/triggers.test.ts
import { describe, it, expect } from 'bun:test';
describe('Account Trigger', () => {
  it('should sync new account to external database', async () => {
    // Create account
    const account = await createTestAccount({
      email: 'test@example.com',
    });
    
    // Wait for sync
    await sleep(1000);
    
    // Verify in external database
    const syncedUser = await externalDb.users.findOne({
      where: { bladeId: account.id },
    });
    
    expect(syncedUser).toBeDefined();
    expect(syncedUser.email).toBe('test@example.com');
  });
});
```
 
---
 
## Common Patterns
 
### Pattern 1: Sync Everything
 
```typescript
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    for (const record of records) {
      waitUntil(syncToDatabase('users', 'create', record, record.id));
    }
  },
  followingSet: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    for (const record of records) {
      waitUntil(syncToDatabase('users', 'update', record, record.id));
    }
  },
  followingRemove: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    for (const record of records) {
      waitUntil(syncToDatabase('users', 'delete', {}, record.id));
    }
  },
});
```
 
### Pattern 2: Selective Sync
 
```typescript
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const post of records) {
      // Only sync published posts
      if (post.published) {
        waitUntil(syncToDatabase('posts', 'create', post, post.id));
      }
    }
  },
});
```
 
### Pattern 3: Create Related Records
 
```typescript
export default triggers({
  followingAdd: async ({ records, client, waitUntil }) => {
    const { add } = client;
    
    for (const account of records) {
      // Create profile
      await add.profile.with({
        account: { id: account.id },
        bio: '',
      });
      
      // Create settings
      await add.settings.with({
        account: { id: account.id },
        theme: 'light',
      });
      
      // Sync to external DB
      if (waitUntil) {
        waitUntil(syncToDatabase('users', 'create', account, account.id));
      }
    }
  },
});
```
 
---
 
## Best Practices
 
### 1. Always Check `waitUntil`
 
```typescript
if (!waitUntil) return; // ✅ Good
```
 
### 2. Validate Data
 
```typescript
for (const record of records) {
  if (!record?.id || !record?.email) {
    console.warn('[Trigger] Invalid record:', record);
    continue; // Skip invalid records
  }
  
  // Process valid record
}
```
 
### 3. Don't Throw Errors
 
```typescript
try {
  await syncToDatabase(/* ... */);
} catch (error) {
  console.error('[Trigger] Sync failed:', error);
  // Don't throw - fail gracefully
}
```
 
### 4. Use Descriptive Logs
 
```typescript
console.log('[Account Trigger] New account:', {
  id: account.id,
  email: account.email,
  timestamp: new Date().toISOString(),
});
```
 
### 5. Keep Triggers Fast
 
```typescript
// ✅ Good - async with waitUntil
waitUntil(slowOperation());
// ❌ Bad - blocks the request
await slowOperation();
```
 
---
 
## Debugging Checklist
 
When triggers aren't working:
 
- [ ] Trigger file exists in `triggers/` folder
- [ ] Filename matches model slug
- [ ] File exports default triggers
- [ ] `waitUntil` is checked before use
- [ ] Data validation passes
- [ ] Sync helper is imported correctly
- [ ] Console logs show trigger firing
- [ ] Router endpoint is registered
- [ ] Database connection works
 
---
 
## Resources
 
- [Blade Triggers Documentation](https://blade.new/docs/triggers)
- [Sync Quick Start](./HIVE_SYNC_QUICK_START.md)
- [Complete Sync Guide](./HIVE_SYNC_COMPLETE_GUIDE.md)
- [Database Adapters](./HIVE_SYNC_DATABASE_ADAPTERS.md)
 
---
 
**Pro Tip:** Start with a simple trigger that just logs data, then gradually add sync functionality. This makes debugging much easier!

