-- ==============================================================================
-- Migration 001: Driver Compliance Documents
-- ==============================================================================
-- Repository: vehealth-compliance-infra-services
-- Tables: driver_documents
-- Dependencies: vehealth-infrastructure (users)
-- ==============================================================================

-- Note: This migration must run AFTER:
--   - vehealth-infrastructure: 001_core_entities (users)

-- ==============================================================================
-- ENUM Types for Driver Documents
-- ==============================================================================

DO $$ BEGIN
    CREATE TYPE document_type AS ENUM (
        'drivers_license',
        'vehicle_registration',
        'vehicle_insurance',
        'background_check',
        'profile_photo',
        'vehicle_photo',
        'proof_of_address'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE document_status AS ENUM (
        'pending',
        'under_review',
        'approved',
        'rejected',
        'expired'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ==============================================================================
-- 1. Driver Documents Table (onboarding & verification)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Document Info
    document_type document_type NOT NULL,
    document_number VARCHAR(100), -- License number, etc.

    -- File Storage
    file_key VARCHAR(500) NOT NULL, -- S3 key
    file_name VARCHAR(255),
    file_size_bytes INTEGER,
    mime_type VARCHAR(100),

    -- Document Details
    issuing_authority VARCHAR(255),
    issue_date DATE,
    expiry_date DATE,

    -- Review Status
    status document_status DEFAULT 'pending' NOT NULL,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,

    -- Vehicle-specific fields (for vehicle_registration, vehicle_insurance, vehicle_photo)
    vehicle_make VARCHAR(50),
    vehicle_model VARCHAR(50),
    vehicle_year INTEGER,
    vehicle_plate VARCHAR(20),

    -- Notes
    notes TEXT,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_documents_driver ON driver_documents(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_documents_status ON driver_documents(status);
CREATE INDEX IF NOT EXISTS idx_driver_documents_type ON driver_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_driver_documents_expiry ON driver_documents(expiry_date) WHERE status = 'approved';

COMMENT ON TABLE driver_documents IS 'Driver document uploads for verification - Owner: vehealth-compliance-infra-services';

-- ==============================================================================
-- Triggers for updated_at
-- ==============================================================================

CREATE TRIGGER update_driver_documents_updated_at BEFORE UPDATE ON driver_documents FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- Schema Version
-- ==============================================================================

INSERT INTO schema_versions (version, description)
VALUES ('compliance-001', 'Driver compliance: driver_documents')
ON CONFLICT (version) DO NOTHING;
