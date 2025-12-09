-- Supabase setup SQL for Hive sync
-- Run this in the Supabase SQL Editor to create tables
 
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
 
-- ==================== USERS TABLE ====================
-- Synced from Hive Account model
 
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Link to Hive database
  blade_id TEXT UNIQUE NOT NULL,
  
  -- Core fields
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  handle TEXT UNIQUE,
  
  -- Profile
  bio TEXT,
  avatar TEXT,
  
  -- Status
  email_verified BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
 
-- Indexes for users
CREATE INDEX idx_users_blade_id ON users(blade_id);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_handle ON users(handle);
 
-- RLS (Row Level Security) for users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
 
-- Allow users to read their own data
CREATE POLICY "Users can view own data"
  ON users FOR SELECT
  USING (auth.uid()::text = blade_id);
 
-- Allow authenticated users to view other users
CREATE POLICY "Authenticated users can view users"
  ON users FOR SELECT
  USING (auth.role() = 'authenticated');
 
-- ==================== POSTS TABLE ====================
-- Synced from Hive Post model
 
CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Link to Hive
  blade_id TEXT UNIQUE NOT NULL,
  
  -- Core fields
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  excerpt TEXT,
  
  -- Author
  author_blade_id TEXT NOT NULL REFERENCES users(blade_id) ON DELETE CASCADE,
  
  -- Status
  published BOOLEAN DEFAULT false,
  featured BOOLEAN DEFAULT false,
  
  -- Metadata
  tags TEXT[],
  view_count INTEGER DEFAULT 0,
  like_count INTEGER DEFAULT 0,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  published_at TIMESTAMPTZ
);
 
-- Indexes for posts
CREATE INDEX idx_posts_blade_id ON posts(blade_id);
CREATE INDEX idx_posts_author ON posts(author_blade_id);
CREATE INDEX idx_posts_published ON posts(published);
CREATE INDEX idx_posts_published_date ON posts(published, published_at DESC);
CREATE INDEX idx_posts_featured ON posts(featured);
 
-- RLS for posts
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
 
-- Allow everyone to read published posts
CREATE POLICY "Anyone can view published posts"
  ON posts FOR SELECT
  USING (published = true);
 
-- Allow authors to view their own posts
CREATE POLICY "Authors can view own posts"
  ON posts FOR SELECT
  USING (auth.uid()::text = author_blade_id);
 
-- ==================== COMMENTS TABLE ====================
-- Synced from Hive Comment model
 
CREATE TABLE comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Link to Hive
  blade_id TEXT UNIQUE NOT NULL,
  
  -- Core fields
  content TEXT NOT NULL,
  
  -- Post
  post_blade_id TEXT NOT NULL REFERENCES posts(blade_id) ON DELETE CASCADE,
  
  -- Author
  author_blade_id TEXT NOT NULL REFERENCES users(blade_id) ON DELETE CASCADE,
  
  -- Parent comment (for nested comments)
  parent_blade_id TEXT REFERENCES comments(blade_id) ON DELETE CASCADE,
  
  -- Status
  is_deleted BOOLEAN DEFAULT false,
  is_edited BOOLEAN DEFAULT false,
  
  -- Metadata
  like_count INTEGER DEFAULT 0,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
 
-- Indexes for comments
CREATE INDEX idx_comments_blade_id ON comments(blade_id);
CREATE INDEX idx_comments_post ON comments(post_blade_id);
CREATE INDEX idx_comments_author ON comments(author_blade_id);
CREATE INDEX idx_comments_parent ON comments(parent_blade_id);
 
-- RLS for comments
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
 
-- Allow everyone to read non-deleted comments
CREATE POLICY "Anyone can view comments"
  ON comments FOR SELECT
  USING (is_deleted = false);
 
-- ==================== LIKES TABLE ====================
-- Track user likes for posts/comments
 
CREATE TYPE target_type AS ENUM ('POST', 'COMMENT');
 
CREATE TABLE likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- User
  user_blade_id TEXT NOT NULL REFERENCES users(blade_id) ON DELETE CASCADE,
  
  -- Target
  target_blade_id TEXT NOT NULL,
  target_type target_type NOT NULL,
  
  -- Timestamp
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure one like per user per target
  UNIQUE(user_blade_id, target_blade_id)
);
 
-- Indexes for likes
CREATE INDEX idx_likes_user ON likes(user_blade_id);
CREATE INDEX idx_likes_target ON likes(target_blade_id);
 
-- RLS for likes
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
 
-- Allow users to view all likes
CREATE POLICY "Anyone can view likes"
  ON likes FOR SELECT
  USING (true);
 
-- ==================== SESSIONS TABLE ====================
-- Optional: Track active sessions for presence
 
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  user_blade_id TEXT NOT NULL REFERENCES users(blade_id) ON DELETE CASCADE,
  device_id TEXT,
  last_active TIMESTAMPTZ DEFAULT NOW(),
  is_online BOOLEAN DEFAULT true
);
 
-- Indexes for sessions
CREATE INDEX idx_sessions_user ON sessions(user_blade_id);
CREATE INDEX idx_sessions_online ON sessions(is_online);
 
-- ==================== NOTIFICATIONS TABLE ====================
-- Real-time notifications
 
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  user_blade_id TEXT NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  action_url TEXT,
  is_read BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);
 
-- Indexes for notifications
CREATE INDEX idx_notifications_user ON notifications(user_blade_id);
CREATE INDEX idx_notifications_user_unread ON notifications(user_blade_id, is_read);
 
-- RLS for notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
 
-- Users can only see their own notifications
CREATE POLICY "Users can view own notifications"
  ON notifications FOR SELECT
  USING (auth.uid()::text = user_blade_id);
 
-- ==================== ANALYTICS TABLE ====================
-- Track events for analytics
 
CREATE TABLE analytics_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  event_name TEXT NOT NULL,
  user_blade_id TEXT,
  properties JSONB,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);
 
-- Indexes for analytics
CREATE INDEX idx_analytics_event ON analytics_events(event_name);
CREATE INDEX idx_analytics_user ON analytics_events(user_blade_id);
CREATE INDEX idx_analytics_timestamp ON analytics_events(timestamp);
 
-- ==================== FUNCTIONS ====================
 
-- Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
 
-- Create triggers for updated_at
CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER posts_updated_at
  BEFORE UPDATE ON posts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER comments_updated_at
  BEFORE UPDATE ON comments
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
 
-- Increment like count when like is added
CREATE OR REPLACE FUNCTION increment_like_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.target_type = 'POST' THEN
    UPDATE posts 
    SET like_count = like_count + 1 
    WHERE blade_id = NEW.target_blade_id;
  ELSIF NEW.target_type = 'COMMENT' THEN
    UPDATE comments 
    SET like_count = like_count + 1 
    WHERE blade_id = NEW.target_blade_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER likes_increment
  AFTER INSERT ON likes
  FOR EACH ROW
  EXECUTE FUNCTION increment_like_count();
 
-- Decrement like count when like is removed
CREATE OR REPLACE FUNCTION decrement_like_count()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.target_type = 'POST' THEN
    UPDATE posts 
    SET like_count = GREATEST(like_count - 1, 0)
    WHERE blade_id = OLD.target_blade_id;
  ELSIF OLD.target_type = 'COMMENT' THEN
    UPDATE comments 
    SET like_count = GREATEST(like_count - 1, 0)
    WHERE blade_id = OLD.target_blade_id;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER likes_decrement
  AFTER DELETE ON likes
  FOR EACH ROW
  EXECUTE FUNCTION decrement_like_count();
 
-- ==================== REALTIME SUBSCRIPTIONS ====================
 
-- Enable realtime for tables
ALTER PUBLICATION supabase_realtime ADD TABLE users;
ALTER PUBLICATION supabase_realtime ADD TABLE posts;
ALTER PUBLICATION supabase_realtime ADD TABLE comments;
ALTER PUBLICATION supabase_realtime ADD TABLE likes;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
 
-- ==================== VIEWS ====================
 
-- View for posts with author info
CREATE VIEW posts_with_author AS
SELECT 
  p.*,
  u.name as author_name,
  u.handle as author_handle,
  u.avatar as author_avatar
FROM posts p
JOIN users u ON p.author_blade_id = u.blade_id;
 
-- View for comments with author and post info
CREATE VIEW comments_with_details AS
SELECT 
  c.*,
  u.name as author_name,
  u.handle as author_handle,
  p.title as post_title
FROM comments c
JOIN users u ON c.author_blade_id = u.blade_id
JOIN posts p ON c.post_blade_id = p.blade_id;
 
-- ==================== SETUP NOTES ====================
 
/*
 * 1. Row Level Security (RLS):
 *    - All tables have RLS enabled
 *    - Policies control who can read/write data
 *    - Update policies based on your requirements
 * 
 * 2. Triggers:
 *    - Auto-update updated_at timestamp
 *    - Auto-increment/decrement like counts
 *    - Add more triggers as needed
 * 
 * 3. Realtime:
 *    - Tables are enabled for realtime subscriptions
 *    - Use Supabase client to subscribe to changes
 * 
 * 4. Indexes:
 *    - All foreign keys are indexed
 *    - Common query patterns are indexed
 *    - Add more indexes based on your queries
 * 
 * 5. Views:
 *    - Convenience views for common joins
 *    - Use these in your Supabase queries
 * 
 * 6. Functions:
 *    - PostgreSQL functions for business logic
 *    - Can be called via Supabase RPC
 */
 
-- ==================== USAGE EXAMPLES ====================
 
/*
 * Upsert user from Blade sync:
 * INSERT INTO users (blade_id, email, name)
 * VALUES ('abc123', 'user@example.com', 'User Name')
 * ON CONFLICT (blade_id) DO UPDATE
 * SET email = EXCLUDED.email,
 *     name = EXCLUDED.name,
 *     updated_at = NOW();
 * 
 * Query published posts:
 * SELECT * FROM posts_with_author
 * WHERE published = true
 * ORDER BY published_at DESC
 * LIMIT 10;
 * 
 * Subscribe to new comments (Supabase client):
 * supabase
 *   .from('comments')
 *   .on('INSERT', payload => {
 *     console.log('New comment:', payload.new);
 *   })
 *   .subscribe();
 */
 
-- ==================== CLEANUP ====================
 
-- To reset everything (WARNING: deletes all data):
/*
DROP TABLE IF EXISTS analytics_events CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS likes CASCADE;
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS posts CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TYPE IF EXISTS target_type CASCADE;
DROP FUNCTION IF EXISTS update_updated_at CASCADE;
DROP FUNCTION IF EXISTS increment_like_count CASCADE;
DROP FUNCTION IF EXISTS decrement_like_count CASCADE;
DROP VIEW IF EXISTS posts_with_author CASCADE;
DROP VIEW IF EXISTS comments_with_details CASCADE;
*/
