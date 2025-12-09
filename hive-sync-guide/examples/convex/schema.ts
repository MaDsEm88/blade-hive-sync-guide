// Convex schema example for Hive sync
// This defines the Convex database schema that mirrors your Hive models
 
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
 
export default defineSchema({
  // ==================== USERS ====================
  // Synced from Hive Account model
  users: defineTable({
    // Core fields
    email: v.string(),
    name: v.string(),
    handle: v.optional(v.string()),
    
    // Link to Hive database
    bladeId: v.string(), // Maps to Account.id in Hive
    
    // Profile fields
    bio: v.optional(v.string()),
    avatar: v.optional(v.string()),
    
    // Status
    emailVerified: v.optional(v.boolean()),
    isActive: v.optional(v.boolean()),
    
    // Timestamps
    createdAt: v.number(),
    updatedAt: v.optional(v.number()),
  })
    .index("by_email", ["email"])
    .index("by_bladeId", ["bladeId"])
    .index("by_handle", ["handle"]),
  
  // ==================== POSTS ====================
  // Synced from Hive Post model
  posts: defineTable({
    // Core fields
    title: v.string(),
    content: v.string(),
    excerpt: v.optional(v.string()),
    
    // Link to Hive
    bladeId: v.string(), // Maps to Post.id in Hive
    authorBladeId: v.string(), // Maps to Post.accountId in Hive
    
    // Status
    published: v.boolean(),
    featured: v.optional(v.boolean()),
    
    // Metadata
    tags: v.optional(v.array(v.string())),
    viewCount: v.optional(v.number()),
    likeCount: v.optional(v.number()),
    
    // Timestamps
    createdAt: v.number(),
    updatedAt: v.optional(v.number()),
    publishedAt: v.optional(v.number()),
  })
    .index("by_bladeId", ["bladeId"])
    .index("by_author", ["authorBladeId"])
    .index("by_published", ["published"])
    .index("by_published_date", ["published", "publishedAt"])
    .index("by_featured", ["featured"]),
  
  // ==================== COMMENTS ====================
  // Synced from Hive Comment model
  comments: defineTable({
    // Core fields
    content: v.string(),
    
    // Links to Hive
    bladeId: v.string(), // Maps to Comment.id in Hive
    postBladeId: v.string(), // Maps to Comment.postId in Hive
    authorBladeId: v.string(), // Maps to Comment.accountId in Hive
    parentBladeId: v.optional(v.string()), // For nested comments
    
    // Status
    isDeleted: v.optional(v.boolean()),
    isEdited: v.optional(v.boolean()),
    
    // Metadata
    likeCount: v.optional(v.number()),
    
    // Timestamps
    createdAt: v.number(),
    updatedAt: v.optional(v.number()),
  })
    .index("by_bladeId", ["bladeId"])
    .index("by_post", ["postBladeId"])
    .index("by_author", ["authorBladeId"])
    .index("by_parent", ["parentBladeId"]),
  
  // ==================== LIKES ====================
  // Track user likes for posts/comments
  likes: defineTable({
    // Links
    userBladeId: v.string(),
    targetBladeId: v.string(), // Post or Comment ID from Hive
    targetType: v.union(v.literal("post"), v.literal("comment")),
    
    // Timestamp
    createdAt: v.number(),
  })
    .index("by_user", ["userBladeId"])
    .index("by_target", ["targetBladeId"])
    .index("by_user_and_target", ["userBladeId", "targetBladeId"]),
  
  // ==================== SESSIONS ====================
  // Optional: Track active sessions for real-time presence
  sessions: defineTable({
    userBladeId: v.string(),
    deviceId: v.optional(v.string()),
    lastActive: v.number(),
    isOnline: v.boolean(),
  })
    .index("by_user", ["userBladeId"])
    .index("by_online", ["isOnline"]),
  
  // ==================== NOTIFICATIONS ====================
  // Real-time notifications
  notifications: defineTable({
    userBladeId: v.string(),
    type: v.string(),
    title: v.string(),
    message: v.string(),
    actionUrl: v.optional(v.string()),
    isRead: v.boolean(),
    createdAt: v.number(),
  })
    .index("by_user", ["userBladeId"])
    .index("by_user_unread", ["userBladeId", "isRead"]),
  
  // ==================== ANALYTICS ====================
  // Track events for analytics
  analytics: defineTable({
    eventName: v.string(),
    userBladeId: v.optional(v.string()),
    properties: v.optional(v.any()),
    timestamp: v.number(),
  })
    .index("by_event", ["eventName"])
    .index("by_user", ["userBladeId"])
    .index("by_timestamp", ["timestamp"]),
});
 
// ==================== SCHEMA NOTES ====================
/*
 * Design Principles:
 * 
 * 1. **bladeId fields** - Every table has a bladeId that maps to the Hive record ID
 *    This allows easy lookups and ensures we can match records between databases
 * 
 * 2. **Indexes** - All foreign keys and frequently queried fields are indexed
 *    This ensures fast queries even as data grows
 * 
 * 3. **Optional fields** - Use v.optional() for fields that might not exist
 *    This makes the schema flexible and sync-friendly
 * 
 * 4. **Timestamps** - Use numbers (Date.now()) for timestamps
 *    This is Convex's recommended approach for date handling
 * 
 * 5. **Status fields** - Boolean flags for published, deleted, active, etc.
 *    Allows efficient filtering without complex queries
 * 
 * 6. **Denormalization** - Store author/user IDs directly in related tables
 *    This optimizes for read performance in Convex
 * 
 * 7. **Real-time features** - Add tables like sessions, notifications, likes
 *    These leverage Convex's real-time capabilities
 */
 
// ==================== USAGE EXAMPLES ====================
/*
 * Query users:
 * const user = await ctx.db.query("users")
 *   .withIndex("by_email", q => q.eq("email", "user@example.com"))
 *   .first();
 * 
 * Query posts by author:
 * const posts = await ctx.db.query("posts")
 *   .withIndex("by_author", q => q.eq("authorBladeId", userId))
 *   .filter(q => q.eq(q.field("published"), true))
 *   .order("desc")
 *   .take(10);
 * 
 * Query unread notifications:
 * const notifications = await ctx.db.query("notifications")
 *   .withIndex("by_user_unread", q => 
 *     q.eq("userBladeId", userId).eq("isRead", false))
 *   .collect();
 */

