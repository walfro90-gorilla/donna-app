-- Helper function to insert users into auth.users
CREATE OR REPLACE FUNCTION insert_user_to_auth(
    p_email TEXT,
    p_password TEXT
)
RETURNS uuid AS $$
DECLARE
    v_user_id uuid;
BEGIN
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        last_sign_in_at,
        raw_app_meta_data,
        raw_user_meta_data,
        is_sso_user,
        created_at,
        updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', -- Default instance_id
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        p_email,
        crypt(p_password, gen_salt('bf')),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}',
        '{}',
        FALSE,
        now(),
        now()
    )
    RETURNING id INTO v_user_id;

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

-- Insert users into auth.users first
INSERT INTO public.profiles (id, username, full_name, website, avatar_url, updated_at)
VALUES
    (insert_user_to_auth('john.doe@example.com', 'password123'), 'john_doe', 'John Doe', 'https://johndoe.com', NULL, NOW()),
    (insert_user_to_auth('jane.smith@example.com', 'securepass'), 'jane_smith', 'Jane Smith', 'https://janesmith.net', NULL, NOW()),
    (insert_user_to_auth('alice.wonder@example.com', 'alicepass'), 'alice_wonder', 'Alice Wonderland', NULL, NULL, NOW());

-- Insert sample data into 'teams'
INSERT INTO public.teams (id, name, created_at) VALUES
    (gen_random_uuid(), 'Alpha Team', NOW()),
    (gen_random_uuid(), 'Beta Squad', NOW()),
    (gen_random_uuid(), 'Gamma Force', NOW());

-- Insert sample data into 'team_members'
INSERT INTO public.team_members (team_id, profile_id, role, joined_at) VALUES
    ((SELECT id FROM public.teams WHERE name = 'Alpha Team'), (SELECT id FROM public.profiles WHERE username = 'john_doe'), 'admin', NOW()),
    ((SELECT id FROM public.teams WHERE name = 'Alpha Team'), (SELECT id FROM public.profiles WHERE username = 'jane_smith'), 'member', NOW()),
    ((SELECT id FROM public.teams WHERE name = 'Beta Squad'), (SELECT id FROM public.profiles WHERE username = 'jane_smith'), 'admin', NOW()),
    ((SELECT id FROM public.teams WHERE name = 'Gamma Force'), (SELECT id FROM public.profiles WHERE username = 'alice_wonder'), 'admin', NOW());

-- Insert sample data into 'projects'
INSERT INTO public.projects (id, team_id, name, description, status, created_at) VALUES
    (gen_random_uuid(), (SELECT id FROM public.teams WHERE name = 'Alpha Team'), 'Project Phoenix', 'Revamping the old system.', 'active', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.teams WHERE name = 'Alpha Team'), 'Project Chimera', 'Developing new features for mobile.', 'planning', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.teams WHERE name = 'Beta Squad'), 'Project Hydra', 'Optimizing database performance.', 'completed', NOW());

-- Insert sample data into 'tasks'
INSERT INTO public.tasks (id, project_id, assigned_to, title, description, status, due_date, created_at) VALUES
    (gen_random_uuid(), (SELECT id FROM public.projects WHERE name = 'Project Phoenix'), (SELECT id FROM public.profiles WHERE username = 'john_doe'), 'Design UI Mockups', 'Create initial wireframes and mockups for the new user interface.', 'in_progress', '2024-07-15', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.projects WHERE name = 'Project Phoenix'), (SELECT id FROM public.profiles WHERE username = 'jane_smith'), 'Develop Backend API', 'Implement RESTful APIs for user authentication and data retrieval.', 'todo', '2024-07-30', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.projects WHERE name = 'Project Chimera'), (SELECT id FROM public.profiles WHERE username = 'jane_smith'), 'Mobile App Integration', 'Integrate new features into the existing mobile application.', 'in_progress', '2024-08-10', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.projects WHERE name = 'Project Hydra'), (SELECT id FROM public.profiles WHERE username = 'alice_wonder'), 'Database Indexing', 'Analyze and add appropriate indexes to improve query performance.', 'completed', '2024-06-20', NOW());

-- Insert sample data into 'comments'
INSERT INTO public.comments (id, task_id, profile_id, content, created_at) VALUES
    (gen_random_uuid(), (SELECT id FROM public.tasks WHERE title = 'Design UI Mockups'), (SELECT id FROM public.profiles WHERE username = 'john_doe'), 'Initial designs are ready for review.', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.tasks WHERE title = 'Design UI Mockups'), (SELECT id FROM public.profiles WHERE username = 'jane_smith'), 'Looks good! Let''s discuss the navigation flow.', NOW()),
    (gen_random_uuid(), (SELECT id FROM public.tasks WHERE title = 'Develop Backend API'), (SELECT id FROM public.profiles WHERE username = 'john_doe'), 'Need clarification on error handling for user registration.', NOW());

-- Insert sample data into 'notifications'
INSERT INTO public.notifications (id, profile_id, type, content, is_read, created_at) VALUES
    (gen_random_uuid(), (SELECT id FROM public.profiles WHERE username = 'john_doe'), 'task_assigned', 'You have been assigned to "Develop Backend API".', FALSE, NOW()),
    (gen_random_uuid(), (SELECT id FROM public.profiles WHERE username = 'jane_smith'), 'comment_received', 'John Doe commented on "Design UI Mockups".', FALSE, NOW()),
    (gen_random_uuid(), (SELECT id FROM public.profiles WHERE username = 'alice_wonder'), 'project_status_change', 'Project Hydra status changed to completed.', TRUE, NOW());

-- Clean up the helper function
DROP FUNCTION IF EXISTS insert_user_to_auth(TEXT, TEXT);