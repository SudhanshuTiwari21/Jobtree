import db from './connection.js';
import logger from '../utils/logger.js';

/**
 * Database Migration Script
 * Creates all required tables for the Jobtree salon hiring platform
 */

const migrations = [
  {
    name: 'create_uuid_extension',
    sql: `
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    `,
  },
  {
    name: 'create_salons_table',
    sql: `
      CREATE TABLE IF NOT EXISTS salons (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        phone_number VARCHAR(20) UNIQUE NOT NULL,
        country_code VARCHAR(5) DEFAULT '+91',
        salon_name VARCHAR(100),
        owner_name VARCHAR(100),
        
        -- Location fields (progressive)
        city VARCHAR(100),
        area VARCHAR(200),
        full_address TEXT,
        latitude DECIMAL(10, 8),
        longitude DECIMAL(11, 8),
        
        -- Verification and completion
        verification_status VARCHAR(20) DEFAULT 'unverified' 
          CHECK (verification_status IN ('unverified', 'pending', 'verified', 'rejected')),
        profile_completion_percent INTEGER DEFAULT 0 CHECK (profile_completion_percent >= 0 AND profile_completion_percent <= 100),
        is_profile_complete BOOLEAN DEFAULT false,
        
        -- Metadata
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Index for phone number lookups
      CREATE INDEX IF NOT EXISTS idx_salons_phone_number ON salons(phone_number);
      
      -- Index for verification status queries
      CREATE INDEX IF NOT EXISTS idx_salons_verification_status ON salons(verification_status);
    `,
  },
  {
    name: 'create_otp_requests_table',
    sql: `
      CREATE TABLE IF NOT EXISTS otp_requests (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        phone_number VARCHAR(20) NOT NULL,
        otp_hash VARCHAR(255) NOT NULL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        attempts INTEGER DEFAULT 0 CHECK (attempts >= 0),
        resend_count INTEGER DEFAULT 0 CHECK (resend_count >= 0),
        last_resend_at TIMESTAMP WITH TIME ZONE,
        is_verified BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Index for phone number lookups (active OTPs)
      CREATE INDEX IF NOT EXISTS idx_otp_requests_phone_number ON otp_requests(phone_number);
      
      -- Index for cleanup of expired OTPs
      CREATE INDEX IF NOT EXISTS idx_otp_requests_expires_at ON otp_requests(expires_at);
    `,
  },
  {
    name: 'create_salon_media_table',
    sql: `
      CREATE TABLE IF NOT EXISTS salon_media (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        media_type VARCHAR(20) NOT NULL CHECK (media_type IN ('photo', 'video')),
        media_url TEXT NOT NULL,
        thumbnail_url TEXT,
        is_primary BOOLEAN DEFAULT false,
        display_order INTEGER DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Index for salon media lookups
      CREATE INDEX IF NOT EXISTS idx_salon_media_salon_id ON salon_media(salon_id);
      
      -- Index for primary media queries
      CREATE INDEX IF NOT EXISTS idx_salon_media_is_primary ON salon_media(salon_id, is_primary) WHERE is_primary = true;
    `,
  },
  {
    name: 'create_salon_policies_table',
    sql: `
      CREATE TABLE IF NOT EXISTS salon_policies (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        policy_text TEXT,
        working_hours JSONB,
        benefits JSONB,
        requirements JSONB,
        last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Unique constraint: one policy per salon
      CREATE UNIQUE INDEX IF NOT EXISTS idx_salon_policies_salon_id ON salon_policies(salon_id);
    `,
  },
  {
    name: 'create_salon_verification_docs_table',
    sql: `
      CREATE TABLE IF NOT EXISTS salon_verification_docs (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        doc_type VARCHAR(50) NOT NULL CHECK (doc_type IN ('aadhaar', 'gst', 'shop_license', 'pan', 'other')),
        doc_last_4 VARCHAR(4),
        doc_file_url TEXT NOT NULL,
        verification_status VARCHAR(20) DEFAULT 'pending' 
          CHECK (verification_status IN ('pending', 'approved', 'rejected')),
        rejection_reason TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        reviewed_at TIMESTAMP WITH TIME ZONE,
        reviewed_by UUID
      );

      -- Index for salon document lookups
      CREATE INDEX IF NOT EXISTS idx_salon_verification_docs_salon_id ON salon_verification_docs(salon_id);
      
      -- Index for verification status queries
      CREATE INDEX IF NOT EXISTS idx_salon_verification_docs_status ON salon_verification_docs(verification_status);
    `,
  },
  {
    name: 'create_refresh_tokens_table',
    sql: `
      CREATE TABLE IF NOT EXISTS refresh_tokens (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        token_hash VARCHAR(255) NOT NULL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        is_revoked BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Index for token lookups
      CREATE INDEX IF NOT EXISTS idx_refresh_tokens_salon_id ON refresh_tokens(salon_id);
      CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
    `,
  },
  {
    name: 'create_jobs_table',
    sql: `
      CREATE TABLE IF NOT EXISTS jobs (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        
        -- Basic Job Details (Step 1)
        job_role VARCHAR(50) NOT NULL CHECK (job_role IN (
          'hair_stylist', 'beautician', 'makeup_artist', 'massage_therapist',
          'receptionist', 'helper', 'manager', 'other'
        )),
        other_category VARCHAR(50),
        custom_role_name VARCHAR(100),
        skills JSONB DEFAULT '[]',
        location VARCHAR(200) NOT NULL,
        number_of_staff INTEGER NOT NULL DEFAULT 1 CHECK (number_of_staff >= 1),
        salary_min DECIMAL(10, 2) NOT NULL,
        salary_max DECIMAL(10, 2) NOT NULL,
        
        -- Work Details (Step 2)
        work_type VARCHAR(20) NOT NULL CHECK (work_type IN ('full_time', 'part_time')),
        experience VARCHAR(30) NOT NULL CHECK (experience IN ('fresher_ok', 'experience_required')),
        accommodation VARCHAR(10) CHECK (accommodation IN ('yes', 'no')),
        preferred_gender VARCHAR(10) CHECK (preferred_gender IN ('male', 'female', 'any')),
        
        -- Job Status
        status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('draft', 'active', 'paused', 'closed', 'expired')),
        is_featured BOOLEAN DEFAULT false,
        views_count INTEGER DEFAULT 0,
        applications_count INTEGER DEFAULT 0,
        
        -- Profile Enrichment (from Improve Job flow)
        description TEXT,
        shift_type VARCHAR(20) CHECK (shift_type IN ('morning', 'evening', 'night', 'flexible')),
        weekly_off JSONB DEFAULT '[]',
        facilities JSONB DEFAULT '[]',
        
        -- Completion tracking
        completion_percent INTEGER DEFAULT 40 CHECK (completion_percent >= 0 AND completion_percent <= 100),
        
        -- Timestamps
        expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 days'),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Indexes for job lookups
      CREATE INDEX IF NOT EXISTS idx_jobs_salon_id ON jobs(salon_id);
      CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
      CREATE INDEX IF NOT EXISTS idx_jobs_job_role ON jobs(job_role);
      CREATE INDEX IF NOT EXISTS idx_jobs_location ON jobs(location);
      CREATE INDEX IF NOT EXISTS idx_jobs_work_type ON jobs(work_type);
      CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at DESC);
      
      -- Index for active jobs in location (for job seekers)
      CREATE INDEX IF NOT EXISTS idx_jobs_active_location ON jobs(location, status) WHERE status = 'active';
      
      -- Trigger for jobs updated_at
      DROP TRIGGER IF EXISTS update_jobs_updated_at ON jobs;
      CREATE TRIGGER update_jobs_updated_at
        BEFORE UPDATE ON jobs
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'create_job_applications_table',
    sql: `
      CREATE TABLE IF NOT EXISTS job_applications (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
        applicant_phone VARCHAR(20) NOT NULL,
        applicant_name VARCHAR(100),
        status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'viewed', 'shortlisted', 'rejected', 'hired')),
        notes TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Indexes
      CREATE INDEX IF NOT EXISTS idx_job_applications_job_id ON job_applications(job_id);
      CREATE INDEX IF NOT EXISTS idx_job_applications_phone ON job_applications(applicant_phone);
      CREATE UNIQUE INDEX IF NOT EXISTS idx_job_applications_unique ON job_applications(job_id, applicant_phone);
    `,
  },
  {
    name: 'create_updated_at_trigger',
    sql: `
      -- Function to automatically update updated_at timestamp
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$ language 'plpgsql';

      -- Trigger for salons table
      DROP TRIGGER IF EXISTS update_salons_updated_at ON salons;
      CREATE TRIGGER update_salons_updated_at
        BEFORE UPDATE ON salons
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'create_notification_type_enum',
    sql: `
      DO $$ BEGIN
        CREATE TYPE notification_type AS ENUM (
          'CANDIDATE_APPLIED',
          'CANDIDATE_REPLIED',
          'INTERVIEW_REMINDER',
          'JOB_PERFORMANCE_TIP',
          'PROFILE_INCOMPLETE',
          'ACCOUNT_ALERT',
          'PROMOTION'
        );
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `,
  },
  {
    name: 'create_notifications_table',
    sql: `
      CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        type notification_type NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        deep_link TEXT,
        is_read BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Indexes for notifications
      CREATE INDEX IF NOT EXISTS idx_notifications_salon_id ON notifications(salon_id);
      CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
      CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
      CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_notifications_salon_unread ON notifications(salon_id, is_read) WHERE is_read = false;
    `,
  },
  {
    name: 'create_notification_preferences_table',
    sql: `
      CREATE TABLE IF NOT EXISTS notification_preferences (
        salon_id UUID PRIMARY KEY REFERENCES salons(id) ON DELETE CASCADE,
        hiring_updates BOOLEAN DEFAULT true NOT NULL,
        job_tips BOOLEAN DEFAULT true,
        profile_improvements BOOLEAN DEFAULT true,
        account_alerts BOOLEAN DEFAULT true,
        promotions BOOLEAN DEFAULT false,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Trigger for notification_preferences updated_at
      DROP TRIGGER IF EXISTS update_notification_preferences_updated_at ON notification_preferences;
      CREATE TRIGGER update_notification_preferences_updated_at
        BEFORE UPDATE ON notification_preferences
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'create_device_type_enum',
    sql: `
      DO $$ BEGIN
        CREATE TYPE device_type AS ENUM ('ios', 'android', 'web');
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `,
  },
  {
    name: 'create_push_tokens_table',
    sql: `
      CREATE TABLE IF NOT EXISTS push_tokens (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        device_type device_type NOT NULL,
        push_token TEXT NOT NULL,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Indexes for push_tokens
      CREATE INDEX IF NOT EXISTS idx_push_tokens_salon_id ON push_tokens(salon_id);
      CREATE INDEX IF NOT EXISTS idx_push_tokens_token ON push_tokens(push_token);
      CREATE INDEX IF NOT EXISTS idx_push_tokens_active ON push_tokens(salon_id, is_active) WHERE is_active = true;
      
      -- Unique constraint: one active token per salon per device type
      CREATE UNIQUE INDEX IF NOT EXISTS idx_push_tokens_salon_device_active 
        ON push_tokens(salon_id, device_type) 
        WHERE is_active = true;

      -- Trigger for push_tokens updated_at
      DROP TRIGGER IF EXISTS update_push_tokens_updated_at ON push_tokens;
      CREATE TRIGGER update_push_tokens_updated_at
        BEFORE UPDATE ON push_tokens
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'create_analytics_event_type_enum',
    sql: `
      DO $$ BEGIN
        CREATE TYPE analytics_event_type AS ENUM (
          'NOTIFICATION_SENT',
          'NOTIFICATION_OPENED',
          'CTA_CLICKED',
          'JOB_EDITED',
          'CANDIDATE_VIEWED',
          'SUBSCRIPTION_VIEWED'
        );
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `,
  },
  {
    name: 'create_analytics_events_table',
    sql: `
      CREATE TABLE IF NOT EXISTS analytics_events (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        notification_id UUID REFERENCES notifications(id) ON DELETE SET NULL,
        event_type analytics_event_type NOT NULL,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Indexes for analytics_events
      CREATE INDEX IF NOT EXISTS idx_analytics_events_salon_id ON analytics_events(salon_id);
      CREATE INDEX IF NOT EXISTS idx_analytics_events_notification_id ON analytics_events(notification_id);
      CREATE INDEX IF NOT EXISTS idx_analytics_events_type ON analytics_events(event_type);
      CREATE INDEX IF NOT EXISTS idx_analytics_events_created_at ON analytics_events(created_at DESC);
    `,
  },
  {
    name: 'create_support_issue_type_enum',
    sql: `
      DO $$ BEGIN
        CREATE TYPE support_issue_type AS ENUM (
          'JOB_POSTING',
          'CANDIDATE',
          'APP_ISSUE',
          'PAYMENT',
          'OTHER'
        );
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `,
  },
  {
    name: 'create_support_status_enum',
    sql: `
      DO $$ BEGIN
        CREATE TYPE support_status AS ENUM (
          'OPEN',
          'IN_PROGRESS',
          'RESOLVED',
          'CLOSED'
        );
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `,
  },
  {
    name: 'create_support_priority_enum',
    sql: `
      DO $$ BEGIN
        CREATE TYPE support_priority AS ENUM (
          'LOW',
          'MEDIUM',
          'HIGH'
        );
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `,
  },
  // ===================== SEEKER TABLES =====================
  {
    name: 'create_seeker_profiles_table',
    sql: `
      CREATE TABLE IF NOT EXISTS seeker_profiles (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        phone_number VARCHAR(20) UNIQUE NOT NULL,
        country_code VARCHAR(5) DEFAULT '+91',
        full_name VARCHAR(100),
        gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other')),
        city VARCHAR(100),
        preferred_role VARCHAR(50),
        experience VARCHAR(50),
        expected_salary DECIMAL(10, 2),
        skills JSONB DEFAULT '[]',
        profile_photo_url TEXT,
        profile_completion_percent INTEGER DEFAULT 0 CHECK (profile_completion_percent >= 0 AND profile_completion_percent <= 100),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_seeker_profiles_phone ON seeker_profiles(phone_number);
      CREATE INDEX IF NOT EXISTS idx_seeker_profiles_city ON seeker_profiles(city);
      CREATE INDEX IF NOT EXISTS idx_seeker_profiles_role ON seeker_profiles(preferred_role);

      DROP TRIGGER IF EXISTS update_seeker_profiles_updated_at ON seeker_profiles;
      CREATE TRIGGER update_seeker_profiles_updated_at
        BEFORE UPDATE ON seeker_profiles
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'create_seeker_preferences_table',
    sql: `
      CREATE TABLE IF NOT EXISTS seeker_preferences (
        seeker_id UUID PRIMARY KEY REFERENCES seeker_profiles(id) ON DELETE CASCADE,
        job_type VARCHAR(20) CHECK (job_type IN ('full_time', 'part_time', 'any')),
        preferred_salary DECIMAL(10, 2),
        preferred_cities JSONB DEFAULT '[]',
        immediate_join BOOLEAN DEFAULT true,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      DROP TRIGGER IF EXISTS update_seeker_preferences_updated_at ON seeker_preferences;
      CREATE TRIGGER update_seeker_preferences_updated_at
        BEFORE UPDATE ON seeker_preferences
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'create_applications_table',
    sql: `
      CREATE TABLE IF NOT EXISTS applications (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
        seeker_id UUID NOT NULL REFERENCES seeker_profiles(id) ON DELETE CASCADE,
        status VARCHAR(20) DEFAULT 'applied' CHECK (status IN ('applied', 'shortlisted', 'interview', 'rejected', 'hired')),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_applications_unique ON applications(job_id, seeker_id);
      CREATE INDEX IF NOT EXISTS idx_applications_job_id ON applications(job_id);
      CREATE INDEX IF NOT EXISTS idx_applications_seeker_id ON applications(seeker_id);
      CREATE INDEX IF NOT EXISTS idx_applications_status ON applications(status);
      CREATE INDEX IF NOT EXISTS idx_applications_job_status ON applications(job_id, status);
    `,
  },
  {
    name: 'alter_applications_add_interview_status',
    sql: `
      -- Add 'interview' to status enum if not already present, add updated_at column
      ALTER TABLE applications DROP CONSTRAINT IF EXISTS applications_status_check;
      ALTER TABLE applications ADD CONSTRAINT applications_status_check
        CHECK (status IN ('applied', 'shortlisted', 'interview', 'rejected', 'hired'));
      
      -- Add updated_at if missing
      ALTER TABLE applications ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

      -- Add composite index for job + status filtering
      CREATE INDEX IF NOT EXISTS idx_applications_job_status ON applications(job_id, status);
    `,
  },
  {
    name: 'create_seeker_refresh_tokens_table',
    sql: `
      CREATE TABLE IF NOT EXISTS seeker_refresh_tokens (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        seeker_id UUID NOT NULL REFERENCES seeker_profiles(id) ON DELETE CASCADE,
        token_hash VARCHAR(255) NOT NULL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        is_revoked BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_seeker_refresh_tokens_seeker_id ON seeker_refresh_tokens(seeker_id);
      CREATE INDEX IF NOT EXISTS idx_seeker_refresh_tokens_token_hash ON seeker_refresh_tokens(token_hash);
    `,
  },
  {
    name: 'create_support_tickets_table',
    sql: `
      CREATE TABLE IF NOT EXISTS support_tickets (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        salon_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        issue_type support_issue_type NOT NULL,
        description TEXT,
        status support_status DEFAULT 'OPEN' NOT NULL,
        priority support_priority DEFAULT 'MEDIUM' NOT NULL,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Indexes for support_tickets
      CREATE INDEX IF NOT EXISTS idx_support_tickets_salon_id ON support_tickets(salon_id);
      CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);
      CREATE INDEX IF NOT EXISTS idx_support_tickets_issue_type ON support_tickets(issue_type);
      CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at ON support_tickets(created_at DESC);
      
      -- Trigger for support_tickets updated_at
      DROP TRIGGER IF EXISTS update_support_tickets_updated_at ON support_tickets;
      CREATE TRIGGER update_support_tickets_updated_at
        BEFORE UPDATE ON support_tickets
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    `,
  },
  {
    name: 'add_vacancy_count_to_jobs',
    sql: `
      -- Add vacancy_count column to jobs (defaults to number_of_staff for backwards compat)
      ALTER TABLE jobs ADD COLUMN IF NOT EXISTS vacancy_count INTEGER DEFAULT 1;

      -- Backfill: set vacancy_count = number_of_staff where not already set
      UPDATE jobs SET vacancy_count = number_of_staff WHERE vacancy_count = 1 AND number_of_staff > 1;
    `,
  },
  {
    name: 'create_application_status_logs_table',
    sql: `
      CREATE TABLE IF NOT EXISTS application_status_logs (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
        old_status VARCHAR(20) NOT NULL,
        new_status VARCHAR(20) NOT NULL,
        changed_by UUID NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_status_logs_application_id ON application_status_logs(application_id);
      CREATE INDEX IF NOT EXISTS idx_status_logs_changed_by ON application_status_logs(changed_by);
      CREATE INDEX IF NOT EXISTS idx_status_logs_created_at ON application_status_logs(created_at DESC);
    `,
  },
  {
    name: 'create_call_sessions_table',
    sql: `
      CREATE TABLE IF NOT EXISTS call_sessions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
        application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
        owner_id UUID NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
        seeker_id UUID NOT NULL REFERENCES seeker_profiles(id) ON DELETE CASCADE,
        call_status VARCHAR(30) DEFAULT 'initiated' 
          CHECK (call_status IN ('initiated', 'ringing', 'in_progress', 'completed', 'failed', 'no_answer', 'busy')),
        provider_call_sid VARCHAR(255),
        provider VARCHAR(30) DEFAULT 'twilio',
        duration_seconds INTEGER DEFAULT 0,
        failure_reason TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        ended_at TIMESTAMP WITH TIME ZONE
      );

      CREATE INDEX IF NOT EXISTS idx_call_sessions_application_id ON call_sessions(application_id);
      CREATE INDEX IF NOT EXISTS idx_call_sessions_owner_id ON call_sessions(owner_id);
      CREATE INDEX IF NOT EXISTS idx_call_sessions_seeker_id ON call_sessions(seeker_id);
      CREATE INDEX IF NOT EXISTS idx_call_sessions_job_id ON call_sessions(job_id);
      CREATE INDEX IF NOT EXISTS idx_call_sessions_created_at ON call_sessions(created_at DESC);
      -- Anti-abuse: quick lookup for rate limiting (owner + seeker + today)
      CREATE INDEX IF NOT EXISTS idx_call_sessions_rate_limit ON call_sessions(owner_id, seeker_id, created_at);
    `,
  },
  {
    name: 'add_interview_fields_to_applications',
    sql: `
      -- Interview scheduling fields on applications
      ALTER TABLE applications ADD COLUMN IF NOT EXISTS interview_scheduled_at TIMESTAMP WITH TIME ZONE NULL;
      ALTER TABLE applications ADD COLUMN IF NOT EXISTS interview_mode VARCHAR(30) NULL
        CHECK (interview_mode IN ('in_person', 'phone_call', 'video_call'));
      ALTER TABLE applications ADD COLUMN IF NOT EXISTS interview_notes TEXT NULL;
      ALTER TABLE applications ADD COLUMN IF NOT EXISTS interview_status VARCHAR(20) DEFAULT 'not_scheduled'
        CHECK (interview_status IN ('not_scheduled', 'scheduled', 'completed', 'cancelled'));

      CREATE INDEX IF NOT EXISTS idx_applications_interview_status ON applications(interview_status);
      CREATE INDEX IF NOT EXISTS idx_applications_interview_scheduled ON applications(interview_scheduled_at)
        WHERE interview_scheduled_at IS NOT NULL;
    `,
  },
  {
    name: 'create_interview_events_table',
    sql: `
      CREATE TABLE IF NOT EXISTS interview_events (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
        scheduled_by UUID NOT NULL,
        scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
        mode VARCHAR(30) CHECK (mode IN ('in_person', 'phone_call', 'video_call')),
        notes TEXT,
        event_type VARCHAR(20) DEFAULT 'scheduled'
          CHECK (event_type IN ('scheduled', 'rescheduled', 'completed', 'cancelled')),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_interview_events_application_id ON interview_events(application_id);
      CREATE INDEX IF NOT EXISTS idx_interview_events_scheduled_by ON interview_events(scheduled_by);
      CREATE INDEX IF NOT EXISTS idx_interview_events_scheduled_at ON interview_events(scheduled_at);
    `,
  },
  {
    name: 'create_user_devices_table',
    sql: `
      CREATE TABLE IF NOT EXISTS user_devices (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL,
        user_type VARCHAR(10) NOT NULL CHECK (user_type IN ('owner', 'seeker')),
        fcm_token TEXT NOT NULL,
        platform VARCHAR(10) NOT NULL CHECK (platform IN ('android', 'ios')),
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_user_devices_fcm_token ON user_devices(fcm_token) WHERE is_active = true;
      CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(user_id, user_type);
      CREATE INDEX IF NOT EXISTS idx_user_devices_active ON user_devices(user_id, user_type, is_active) WHERE is_active = true;
    `,
  },
  {
    name: 'create_push_notification_log_table',
    sql: `
      CREATE TABLE IF NOT EXISTS push_notification_log (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL,
        user_type VARCHAR(10) NOT NULL CHECK (user_type IN ('owner', 'seeker')),
        type VARCHAR(50) NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        data JSONB DEFAULT '{}',
        is_read BOOLEAN DEFAULT false,
        sent_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_push_log_user ON push_notification_log(user_id, user_type);
      CREATE INDEX IF NOT EXISTS idx_push_log_type ON push_notification_log(type);
      CREATE INDEX IF NOT EXISTS idx_push_log_created ON push_notification_log(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_push_log_user_unread ON push_notification_log(user_id, user_type, is_read) WHERE is_read = false;
    `,
  },
  {
    name: 'add_interview_reminder_sent_to_applications',
    sql: `
      ALTER TABLE applications ADD COLUMN IF NOT EXISTS interview_reminder_sent BOOLEAN DEFAULT false;
    `,
  },
  {
    name: 'create_chat_messages_table',
    sql: `
      CREATE TABLE IF NOT EXISTS chat_messages (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
        sender_role VARCHAR(20) NOT NULL CHECK (sender_role IN ('owner', 'seeker')),
        body TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_chat_messages_application_created
        ON chat_messages(application_id, created_at DESC);
    `,
  },
  {
    name: 'alter_seeker_profiles_extended_fields',
    sql: `
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS current_salary DECIMAL(10, 2);
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS expected_salary_max DECIMAL(10, 2);
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS experience_years INTEGER;
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS marital_status VARCHAR(30);
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS email VARCHAR(255);
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS has_professional_course BOOLEAN;
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS professional_course_certificate_url TEXT;
      ALTER TABLE seeker_profiles ADD COLUMN IF NOT EXISTS work_portfolio_urls JSONB DEFAULT '[]'::jsonb;
    `,
  },
  {
    name: 'relax_jobs_job_role_and_seeker_preferred_role',
    sql: `
      ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_job_role_check;
      ALTER TABLE jobs ALTER COLUMN job_role TYPE VARCHAR(100);
      ALTER TABLE seeker_profiles ALTER COLUMN preferred_role TYPE VARCHAR(100);
    `,
  },
];

/**
 * Run all migrations
 */
async function runMigrations() {
  logger.info('Starting database migrations...');
  
  try {
    // Check database connection
    const connected = await db.checkConnection();
    if (!connected) {
      throw new Error('Cannot connect to database');
    }

    // Run each migration
    for (const migration of migrations) {
      logger.info(`Running migration: ${migration.name}`);
      try {
        await db.query(migration.sql);
        logger.info(`✓ Migration completed: ${migration.name}`);
      } catch (error) {
        // If error is about something already existing, continue
        if (error.code === '42P07' || error.code === '42710') {
          logger.warn(`Migration ${migration.name} skipped (already exists)`);
          continue;
        }
        throw error;
      }
    }

    logger.info('All migrations completed successfully!');
  } catch (error) {
    logger.error('Migration failed:', error.message);
    throw error;
  } finally {
    await db.closePool();
  }
}

// Run migrations if executed directly
runMigrations().catch((error) => {
  console.error('Migration error:', error);
  process.exit(1);
});

export { runMigrations, migrations };


