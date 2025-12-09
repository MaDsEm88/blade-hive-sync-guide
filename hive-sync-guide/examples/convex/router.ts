// Convex router example for Hive sync
// This file shows how to set up the router endpoint for syncing Hive data to Convex
 
import { Hono } from 'hono';
import { ConvexHttpClient } from 'convex/browser';
 
const app = new Hono();
 
// Initialize Convex client
const convex = new ConvexHttpClient(process.env.CONVEX_URL!);
 
// ============================================
// CONVEX SYNC ENDPOINT
// ============================================
 
app.post('/convex/sync', async (c) => {
  // 1. Validate sync secret
  const syncSecret = c.req.header('x-sync-secret');
  
  if (!syncSecret || syncSecret !== process.env.SYNC_SECRET) {
    console.warn('[Convex Sync] Unauthorized attempt');
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  // 2. Parse request body
  const { model, operation, data, hiveId } = await c.req.json();
  
  console.log('[Convex Sync] Received sync request:', {
    model,
    operation,
    hiveId: hiveId?.substring(0, 10),
  });
  
  // 3. Validate required fields
  if (!model || !operation || !hiveId) {
    return c.json({ error: 'Missing required fields' }, 400);
  }
  
  try {
    // 4. Route to appropriate Convex mutation based on model
    switch (model) {
      case 'users':
        if (operation === 'add' || operation === 'set') {
          const result = await convex.mutation('users:syncFromBlade' as any, data);
          console.log('[Convex Sync] User synced:', result);
          return c.json({ success: true, result });
        } else if (operation === 'remove') {
          await convex.mutation('users:deleteByBladeId' as any, { bladeId: hiveId });
          return c.json({ success: true, action: 'deleted' });
        }
        break;
      
      case 'posts':
        if (operation === 'add' || operation === 'set') {
          const result = await convex.mutation('posts:syncFromBlade' as any, data);
          console.log('[Convex Sync] Post synced:', result);
          return c.json({ success: true, result });
        } else if (operation === 'remove') {
          await convex.mutation('posts:deleteByBladeId' as any, { bladeId: hiveId });
          return c.json({ success: true, action: 'deleted' });
        }
        break;
      
      case 'comments':
        if (operation === 'add' || operation === 'set') {
          const result = await convex.mutation('comments:syncFromBlade' as any, data);
          console.log('[Convex Sync] Comment synced:', result);
          return c.json({ success: true, result });
        } else if (operation === 'remove') {
          await convex.mutation('comments:deleteByBladeId' as any, { bladeId: hiveId });
          return c.json({ success: true, action: 'deleted' });
        }
        break;
      
      default:
        console.warn('[Convex Sync] Unknown model:', model);
        return c.json({ error: `Unknown model: ${model}` }, 400);
    }
    
    return c.json({ success: true, model, operation, hiveId });
  } catch (error: any) {
    console.error('[Convex Sync] Error:', {
      model,
      operation,
      hiveId,
      error: error.message,
      stack: error.stack,
    });
    
    return c.json({
      error: error.message || 'Sync failed',
      model,
      operation,
      hiveId,
    }, 500);
  }
});
 
// ============================================
// OPTIONAL: Batch sync endpoint for better performance
// ============================================
 
app.post('/convex/sync/batch', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (!syncSecret || syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, records } = await c.req.json();
  
  console.log('[Convex Sync] Batch sync request:', {
    model,
    operation,
    count: records.length,
  });
  
  try {
    const results = await Promise.allSettled(
      records.map(async (record: any) => {
        switch (model) {
          case 'users':
            return await convex.mutation('users:syncFromBlade' as any, record.data);
          case 'posts':
            return await convex.mutation('posts:syncFromBlade' as any, record.data);
          default:
            throw new Error(`Unknown model: ${model}`);
        }
      })
    );
    
    const successful = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.filter(r => r.status === 'rejected').length;
    
    console.log('[Convex Sync] Batch complete:', { successful, failed });
    
    return c.json({
      success: true,
      successful,
      failed,
      total: records.length,
    });
  } catch (error: any) {
    console.error('[Convex Sync] Batch error:', error);
    return c.json({ error: error.message }, 500);
  }
});
 
// ============================================
// OPTIONAL: Health check endpoint
// ============================================
 
app.get('/convex/health', async (c) => {
  try {
    // Try to query Convex to verify connection
    const result = await convex.query('system:ping' as any);
    return c.json({ 
      status: 'healthy',
      convex: 'connected',
      timestamp: Date.now(),
    });
  } catch (error) {
    return c.json({ 
      status: 'unhealthy',
      convex: 'disconnected',
      error: error instanceof Error ? error.message : 'Unknown error',
    }, 500);
  }
});
 
export default app;

