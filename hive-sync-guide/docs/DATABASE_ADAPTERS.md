# Hive Sync - Database Adapters Reference
 
> **Complete implementation examples for syncing Blade's Hive database with popular external databases**
 
## Overview
 
This guide provides ready-to-use adapter implementations for:
 
1. [Convex](#1-convex) - Real-time serverless database
2. [PostgreSQL with Prisma](#2-postgresql-with-prisma) - Traditional SQL with TypeScript ORM
3. [Supabase](#3-supabase) - PostgreSQL with real-time features
4. [MongoDB](#4-mongodb) - NoSQL document database
5. [Firebase Firestore](#5-firebase-firestore) - Google's real-time NoSQL
6. [PlanetScale](#6-planetscale) - Serverless MySQL
7. [Turso (libSQL)](#7-turso-libsql) - Edge SQLite
8. [Neon](#8-neon) - Serverless PostgreSQL
9. [Custom REST API](#9-custom-rest-api) - Generic HTTP adapter
 
---
 
## General Structure
 
Each adapter follows the same pattern:
 
```typescript
// 1. Setup client/connection
// 2. Create sync helper
// 3. Implement router handler
// 4. Add database-specific mutations/queries
```
 
---
 
## 1. Convex
 
**Best for:** Real-time apps, serverless architecture, TypeScript-first
 
### 1.1 Installation
 
```bash
npm install convex
npx convex dev
```
 
### 1.2 Environment Variables
 
```bash
CONVEX_URL=https://your-deployment.convex.cloud
SYNC_SECRET=your_sync_secret
```
 
### 1.3 Sync Helper
 
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
    const response = await fetch(`${bladeUrl}/convex/sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sync-Secret': syncSecret,
      },
      body: JSON.stringify({ model, operation, data, hiveId }),
    });
    
    if (!response.ok) {
      throw new Error('Sync failed');
    }
    
    return await response.json();
  } catch (error) {
    console.error(`[Convex Sync] Failed:`, error);
  }
}
```
 
### 1.4 Router Handler
 
```typescript
// router.ts
import { ConvexHttpClient } from 'convex/browser';
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
```
 
### 1.5 Convex Schema
 
```typescript
// convex/schema.ts
import { defineSchema, defineTable } from 'convex/server';
import { v } from 'convex/values';
export default defineSchema({
  users: defineTable({
    email: v.string(),
    name: v.string(),
    handle: v.optional(v.string()),
    bladeId: v.string(),
    createdAt: v.number(),
  })
    .index('by_email', ['email'])
    .index('by_bladeId', ['bladeId']),
  
  posts: defineTable({
    title: v.string(),
    content: v.string(),
    authorBladeId: v.string(),
    published: v.boolean(),
    createdAt: v.number(),
  })
    .index('by_author', ['authorBladeId'])
    .index('by_published', ['published']),
});
```
 
### 1.6 Convex Mutations
 
```typescript
// convex/users.ts
import { mutation } from './_generated/server';
import { v } from 'convex/values';
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
      .query('users')
      .withIndex('by_email', q => q.eq('email', args.email))
      .first();
    
    if (existingUser) {
      // Update existing user
      await ctx.db.patch(existingUser._id, {
        name: args.name,
        handle: args.handle,
        bladeId: args.bladeId,
      });
      return { userId: existingUser._id, action: 'updated' };
    } else {
      // Create new user
      const userId = await ctx.db.insert('users', {
        email: args.email,
        name: args.name || 'User',
        handle: args.handle,
        bladeId: args.bladeId,
        createdAt: Date.now(),
      });
      return { userId, action: 'created' };
    }
  },
});
```
 
---
 
## 2. PostgreSQL with Prisma
 
**Best for:** Traditional apps, strong typing, complex queries
 
### 2.1 Installation
 
```bash
npm install @prisma/client
npm install -D prisma
npx prisma init
```
 
### 2.2 Environment Variables
 
```bash
DATABASE_URL="postgresql://user:password@localhost:5432/dbname?schema=public"
SYNC_SECRET=your_sync_secret
```
 
### 2.3 Prisma Schema
 
```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
model User {
  id        String   @id @default(cuid())
  bladeId   String   @unique
  email     String   @unique
  name      String?
  handle    String?  @unique
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  
  posts     Post[]
}
model Post {
  id             String   @id @default(cuid())
  bladeId        String   @unique
  title          String
  content        String
  published      Boolean  @default(false)
  authorBladeId  String
  author         User     @relation(fields: [authorBladeId], references: [bladeId])
  createdAt      DateTime @default(now())
  updatedAt      DateTime @updatedAt
}
```
 
```bash
# Generate Prisma client and run migrations
npx prisma generate
npx prisma migrate dev --name init
```
 
### 2.4 Prisma Client
 
```typescript
// lib/prisma.ts
import { PrismaClient } from '@prisma/client';
const globalForPrisma = global as unknown as { prisma: PrismaClient };
export const prisma =
  globalForPrisma.prisma ||
  new PrismaClient({
    log: ['query', 'error', 'warn'],
  });
if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}
```
 
### 2.5 Router Handler
 
```typescript
// router.ts
import { prisma } from './lib/prisma';
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  try {
    switch (model) {
      case 'users':
        await handleUserSync(operation, data, recordId);
        break;
      
      case 'posts':
        await handlePostSync(operation, data, recordId);
        break;
    }
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
async function handleUserSync(operation: string, data: any, recordId: string) {
  switch (operation) {
    case 'create':
    case 'update':
      await prisma.user.upsert({
        where: { bladeId: recordId },
        update: {
          email: data.email,
          name: data.name,
          handle: data.handle,
        },
        create: {
          bladeId: recordId,
          email: data.email,
          name: data.name,
          handle: data.handle,
        },
      });
      break;
    
    case 'delete':
      await prisma.user.delete({
        where: { bladeId: recordId },
      });
      break;
  }
}
async function handlePostSync(operation: string, data: any, recordId: string) {
  switch (operation) {
    case 'create':
    case 'update':
      await prisma.post.upsert({
        where: { bladeId: recordId },
        update: {
          title: data.title,
          content: data.content,
          published: data.published,
        },
        create: {
          bladeId: recordId,
          title: data.title,
          content: data.content,
          published: data.published,
          authorBladeId: data.authorBladeId,
        },
      });
      break;
    
    case 'delete':
      await prisma.post.delete({
        where: { bladeId: recordId },
      });
      break;
  }
}
```
 
---
 
## 3. Supabase
 
**Best for:** PostgreSQL + real-time + auth + storage
 
### 3.1 Installation
 
```bash
npm install @supabase/supabase-js
```
 
### 3.2 Environment Variables
 
```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_service_role_key
SYNC_SECRET=your_sync_secret
```
 
### 3.3 Supabase Client
 
```typescript
// lib/supabase.ts
import { createClient } from '@supabase/supabase-js';
// Use service role key for server-side operations
export const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  }
);
```
 
### 3.4 Supabase Tables
 
```sql
-- Run in Supabase SQL Editor
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blade_id TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  handle TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- Posts table
CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blade_id TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  published BOOLEAN DEFAULT false,
  author_blade_id TEXT NOT NULL REFERENCES users(blade_id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- Indexes
CREATE INDEX idx_users_blade_id ON users(blade_id);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_posts_blade_id ON posts(blade_id);
CREATE INDEX idx_posts_author ON posts(author_blade_id);
CREATE INDEX idx_posts_published ON posts(published);
-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER posts_updated_at
  BEFORE UPDATE ON posts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
```
 
### 3.5 Router Handler
 
```typescript
// router.ts
import { supabase } from './lib/supabase';
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  try {
    switch (model) {
      case 'users':
        await handleSupabaseUserSync(operation, data, recordId);
        break;
      
      case 'posts':
        await handleSupabasePostSync(operation, data, recordId);
        break;
    }
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
async function handleSupabaseUserSync(
  operation: string,
  data: any,
  recordId: string
) {
  switch (operation) {
    case 'create':
    case 'update':
      const { error } = await supabase
        .from('users')
        .upsert({
          blade_id: recordId,
          email: data.email,
          name: data.name,
          handle: data.handle,
        }, {
          onConflict: 'blade_id',
        });
      
      if (error) throw error;
      break;
    
    case 'delete':
      await supabase
        .from('users')
        .delete()
        .eq('blade_id', recordId);
      break;
  }
}
async function handleSupabasePostSync(
  operation: string,
  data: any,
  recordId: string
) {
  switch (operation) {
    case 'create':
    case 'update':
      await supabase
        .from('posts')
        .upsert({
          blade_id: recordId,
          title: data.title,
          content: data.content,
          published: data.published,
          author_blade_id: data.authorBladeId,
        }, {
          onConflict: 'blade_id',
        });
      break;
    
    case 'delete':
      await supabase
        .from('posts')
        .delete()
        .eq('blade_id', recordId);
      break;
  }
}
```
 
---
 
## 4. MongoDB
 
**Best for:** Flexible schemas, document storage, high write throughput
 
### 4.1 Installation
 
```bash
npm install mongodb
```
 
### 4.2 Environment Variables
 
```bash
MONGODB_URI=mongodb://localhost:27017/your-database
# Or for MongoDB Atlas:
# MONGODB_URI=mongodb+srv://user:password@cluster.mongodb.net/dbname?retryWrites=true&w=majority
SYNC_SECRET=your_sync_secret
```
 
### 4.3 MongoDB Client
 
```typescript
// lib/mongodb.ts
import { MongoClient, Db } from 'mongodb';
let cachedClient: MongoClient | null = null;
let cachedDb: Db | null = null;
export async function connectToDatabase() {
  if (cachedClient && cachedDb) {
    return { client: cachedClient, db: cachedDb };
  }
  
  const client = await MongoClient.connect(process.env.MONGODB_URI!, {
    maxPoolSize: 10,
  });
  
  const db = client.db();
  
  cachedClient = client;
  cachedDb = db;
  
  return { client, db };
}
export async function getDatabase(): Promise {
  const { db } = await connectToDatabase();
  return db;
}
```
 
### 4.4 Initialize Collections
 
```typescript
// scripts/init-mongodb.ts
import { getDatabase } from '../lib/mongodb';
async function initMongoDB() {
  const db = await getDatabase();
  
  // Create collections
  await db.createCollection('users');
  await db.createCollection('posts');
  
  // Create indexes
  await db.collection('users').createIndex({ bladeId: 1 }, { unique: true });
  await db.collection('users').createIndex({ email: 1 }, { unique: true });
  await db.collection('users').createIndex({ handle: 1 }, { unique: true, sparse: true });
  
  await db.collection('posts').createIndex({ bladeId: 1 }, { unique: true });
  await db.collection('posts').createIndex({ authorBladeId: 1 });
  await db.collection('posts').createIndex({ published: 1 });
  
  console.log('✅ MongoDB initialized');
}
initMongoDB();
```
 
### 4.5 Router Handler
 
```typescript
// router.ts
import { getDatabase } from './lib/mongodb';
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  try {
    const db = await getDatabase();
    
    switch (model) {
      case 'users':
        await handleMongoUserSync(db, operation, data, recordId);
        break;
      
      case 'posts':
        await handleMongoPostSync(db, operation, data, recordId);
        break;
    }
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
async function handleMongoUserSync(
  db: Db,
  operation: string,
  data: any,
  recordId: string
) {
  const collection = db.collection('users');
  
  switch (operation) {
    case 'create':
    case 'update':
      await collection.updateOne(
        { bladeId: recordId },
        {
          $set: {
            email: data.email,
            name: data.name,
            handle: data.handle,
            updatedAt: new Date(),
          },
          $setOnInsert: {
            bladeId: recordId,
            createdAt: new Date(),
          },
        },
        { upsert: true }
      );
      break;
    
    case 'delete':
      await collection.deleteOne({ bladeId: recordId });
      break;
  }
}
async function handleMongoPostSync(
  db: Db,
  operation: string,
  data: any,
  recordId: string
) {
  const collection = db.collection('posts');
  
  switch (operation) {
    case 'create':
    case 'update':
      await collection.updateOne(
        { bladeId: recordId },
        {
          $set: {
            title: data.title,
            content: data.content,
            published: data.published,
            authorBladeId: data.authorBladeId,
            updatedAt: new Date(),
          },
          $setOnInsert: {
            bladeId: recordId,
            createdAt: new Date(),
          },
        },
        { upsert: true }
      );
      break;
    
    case 'delete':
      await collection.deleteOne({ bladeId: recordId });
      break;
  }
}
```
 
---
 
## 5. Firebase Firestore
 
**Best for:** Google Cloud integration, real-time mobile apps
 
### 5.1 Installation
 
```bash
npm install firebase-admin
```
 
### 5.2 Environment Variables
 
```bash
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=your-service-account-email
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
SYNC_SECRET=your_sync_secret
```
 
### 5.3 Firebase Admin Setup
 
```typescript
// lib/firebase.ts
import { initializeApp, cert, getApps, App } from 'firebase-admin/app';
import { getFirestore, Firestore } from 'firebase-admin/firestore';
let app: App;
let db: Firestore;
export function getFirebaseApp() {
  if (!app) {
    const apps = getApps();
    if (apps.length > 0) {
      app = apps[0];
    } else {
      app = initializeApp({
        credential: cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        }),
      });
    }
  }
  return app;
}
export function getFirebaseDb(): Firestore {
  if (!db) {
    getFirebaseApp();
    db = getFirestore();
  }
  return db;
}
```
 
### 5.4 Router Handler
 
```typescript
// router.ts
import { getFirebaseDb } from './lib/firebase';
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  try {
    const db = getFirebaseDb();
    
    switch (model) {
      case 'users':
        await handleFirestoreUserSync(db, operation, data, recordId);
        break;
      
      case 'posts':
        await handleFirestorePostSync(db, operation, data, recordId);
        break;
    }
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
async function handleFirestoreUserSync(
  db: Firestore,
  operation: string,
  data: any,
  recordId: string
) {
  const docRef = db.collection('users').doc(recordId);
  
  switch (operation) {
    case 'create':
      await docRef.set({
        bladeId: recordId,
        email: data.email,
        name: data.name,
        handle: data.handle,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      break;
    
    case 'update':
      await docRef.update({
        email: data.email,
        name: data.name,
        handle: data.handle,
        updatedAt: Date.now(),
      });
      break;
    
    case 'delete':
      await docRef.delete();
      break;
  }
}
async function handleFirestorePostSync(
  db: Firestore,
  operation: string,
  data: any,
  recordId: string
) {
  const docRef = db.collection('posts').doc(recordId);
  
  switch (operation) {
    case 'create':
      await docRef.set({
        bladeId: recordId,
        title: data.title,
        content: data.content,
        published: data.published,
        authorBladeId: data.authorBladeId,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      break;
    
    case 'update':
      await docRef.update({
        title: data.title,
        content: data.content,
        published: data.published,
        updatedAt: Date.now(),
      });
      break;
    
    case 'delete':
      await docRef.delete();
      break;
  }
}
```
 
---
 
## 6. PlanetScale
 
**Best for:** Serverless MySQL, horizontal scaling
 
PlanetScale uses MySQL, so you can use Prisma (see [PostgreSQL example](#2-postgresql-with-prisma)) with a different datasource:
 
```prisma
datasource db {
  provider = "mysql"
  url      = env("DATABASE_URL")
  relationMode = "prisma" // Required for PlanetScale
}
```
 
```bash
DATABASE_URL="mysql://user:password@aws.connect.psdb.cloud/dbname?sslaccept=strict"
```
 
Everything else is the same as the Prisma example!
 
---
 
## 7. Turso (libSQL)
 
**Best for:** Edge deployments, SQLite at scale
 
### 7.1 Installation
 
```bash
npm install @libsql/client
```
 
### 7.2 Environment Variables
 
```bash
TURSO_DATABASE_URL=libsql://your-database.turso.io
TURSO_AUTH_TOKEN=your_auth_token
SYNC_SECRET=your_sync_secret
```
 
### 7.3 Turso Client
 
```typescript
// lib/turso.ts
import { createClient } from '@libsql/client';
export const turso = createClient({
  url: process.env.TURSO_DATABASE_URL!,
  authToken: process.env.TURSO_AUTH_TOKEN!,
});
```
 
### 7.4 Router Handler
 
```typescript
// router.ts
import { turso } from './lib/turso';
app.post('/sync', async (c) => {
  const syncSecret = c.req.header('x-sync-secret');
  
  if (syncSecret !== process.env.SYNC_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }
  
  const { model, operation, data, recordId } = await c.req.json();
  
  try {
    switch (model) {
      case 'users':
        await handleTursoUserSync(operation, data, recordId);
        break;
    }
    
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 500);
  }
});
async function handleTursoUserSync(
  operation: string,
  data: any,
  recordId: string
) {
  switch (operation) {
    case 'create':
    case 'update':
      await turso.execute({
        sql: `
          INSERT INTO users (blade_id, email, name, handle, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(blade_id) DO UPDATE SET
            email = excluded.email,
            name = excluded.name,
            handle = excluded.handle,
            updated_at = excluded.updated_at
        `,
        args: [
          recordId,
          data.email,
          data.name,
          data.handle,
          new Date().toISOString(),
          new Date().toISOString(),
        ],
      });
      break;
    
    case 'delete':
      await turso.execute({
        sql: 'DELETE FROM users WHERE blade_id = ?',
        args: [recordId],
      });
      break;
  }
}
```
 
---
 
## 8. Neon
 
**Best for:** Serverless PostgreSQL with branching
 
Neon uses PostgreSQL, so you can use the same Prisma setup as [PostgreSQL example](#2-postgresql-with-prisma):
 
```bash
DATABASE_URL="postgresql://user:password@ep-xxx.us-east-2.aws.neon.tech/dbname?sslmode=require"
```
 
---
 
## 9. Custom REST API
 
**Best for:** Existing APIs, custom backends
 
### 9.1 Sync Helper
 
```typescript
// lib/api-sync.ts
export async function syncToCustomAPI(
  model: string,
  operation: 'create' | 'update' | 'delete',
  data: any,
  recordId: string
) {
  const apiUrl = process.env.CUSTOM_API_URL!;
  const apiKey = process.env.CUSTOM_API_KEY!;
  
  const endpoint = `${apiUrl}/${model}/${recordId}`;
  
  let method: string;
  switch (operation) {
    case 'create':
      method = 'POST';
      break;
    case 'update':
      method = 'PUT';
      break;
    case 'delete':
      method = 'DELETE';
      break;
    default:
      throw new Error(`Unknown operation: ${operation}`);
  }
  
  try {
    const response = await fetch(endpoint, {
      method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: operation !== 'delete' ? JSON.stringify(data) : undefined,
    });
    
    if (!response.ok) {
      throw new Error(`API request failed: ${response.statusText}`);
    }
    
    return await response.json();
  } catch (error) {
    console.error('[API Sync] Failed:', error);
  }
}
```
 
### 9.2 Use in Trigger
 
```typescript
// triggers/account.ts
import { triggers } from 'blade/schema';
import type { Account } from 'blade/types';
import { syncToCustomAPI } from '../lib/api-sync';
export default triggers({
  followingAdd: async ({ records, waitUntil }) => {
    if (!waitUntil) return;
    
    for (const account of records) {
      waitUntil(
        syncToCustomAPI('users', 'create', {
          email: account.email,
          name: account.name,
          // ... your data
        }, account.id)
      );
    }
  },
});
```
 
---
 
## Comparison Table
 
| Database | Real-time | Serverless | Query Language | Best For |
|----------|-----------|------------|----------------|----------|
| Convex | ✅ | ✅ | TypeScript | Real-time apps |
| PostgreSQL | ❌ | ❌ | SQL | Complex queries |
| Supabase | ✅ | ✅ | SQL | Full-stack apps |
| MongoDB | ❌ | ✅ | Query API | Flexible schemas |
| Firestore | ✅ | ✅ | Query API | Mobile apps |
| PlanetScale | ❌ | ✅ | SQL | Scalable MySQL |
| Turso | ❌ | ✅ | SQL | Edge SQLite |
| Neon | ❌ | ✅ | SQL | Serverless Postgres |
---
 
## Choosing the Right Database
 
### Use Convex if:
- You need real-time subscriptions
- You want TypeScript-first development
- You're building a reactive app
 
### Use PostgreSQL/Supabase if:
- You need relational data
- You want mature ecosystem
- You need complex queries
 
### Use MongoDB if:
- You have flexible/evolving schemas
- You need high write throughput
- You store JSON documents
 
### Use Firebase if:
- You're building mobile apps
- You need Google Cloud integration
- You want real-time without setup
 
---
 
## Testing Your Adapter
 
```bash
# Test with curl
curl -X POST http://localhost:3000/sync \
  -H "Content-Type: application/json" \
  -H "X-Sync-Secret: your_secret" \
  -d '{
    "model": "users",
    "operation": "create",
    "data": {
      "bladeId": "test123",
      "email": "test@example.com",
      "name": "Test User"
    },
    "recordId": "test123"
  }'
```
 
---
 
## Need Help?
 
- **Quick Start:** [QUICK_START.md](./QUICK_START.md)
- **Complete Guide:** [COMPLETE_GUIDE.md](./COMPLETE_GUIDE.md)

---
 
**That's it!** Choose your database, copy the adapter code, and start syncing! 🚀



