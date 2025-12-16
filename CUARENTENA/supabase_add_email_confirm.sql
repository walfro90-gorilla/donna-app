-- Add email_confirm field to users table if it doesn't exist
-- Run this in your Supabase SQL editor

DO $$ 
BEGIN
    -- Add email_confirm column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='users' AND column_name='email_confirm') THEN
        ALTER TABLE users ADD COLUMN email_confirm BOOLEAN DEFAULT false;
    END IF;

    -- Add avatar_url column if it doesn't exist  
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='users' AND column_name='avatar_url') THEN
        ALTER TABLE users ADD COLUMN avatar_url TEXT;
    END IF;

    -- Update existing users to have email_confirm = true (assuming they were verified manually)
    UPDATE users SET email_confirm = true WHERE email_confirm IS NULL;
    
END $$;

-- Create index for email_confirm field
CREATE INDEX IF NOT EXISTS idx_users_email_confirm ON users(email_confirm);