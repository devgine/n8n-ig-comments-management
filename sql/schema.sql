-- Persistent storage for the Instagram Comment Automation n8n workflow.
-- Run this once against the Postgres database referenced by the "Postgres" credential
-- used in workflows/instagram-comment-automation.json and workflows/retry-failed-public-replies.json.

CREATE TABLE IF NOT EXISTS ig_processed_comments (
    comment_id           TEXT PRIMARY KEY,
    media_id             TEXT NOT NULL,
    comment_text          TEXT,
    username              TEXT,
    matched_rule           TEXT,
    selected_dm             TEXT,
    selected_public_reply   TEXT,
    dm_status               TEXT NOT NULL DEFAULT 'pending'
        CHECK (dm_status IN ('pending', 'sent', 'failed')),
    public_reply_status      TEXT NOT NULL DEFAULT 'pending'
        CHECK (public_reply_status IN ('pending', 'sent', 'failed', 'skipped')),
    status                    TEXT NOT NULL DEFAULT 'processing'
        CHECK (status IN ('processing', 'done', 'error')),
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at               TIMESTAMPTZ,
    error_message               TEXT
);

-- comment_id is already the PRIMARY KEY, which is what makes
-- "Reserve Comment (Atomic)" (INSERT ... ON CONFLICT (comment_id) DO NOTHING RETURNING comment_id)
-- a genuinely atomic reservation under concurrent workflow executions.

-- Speeds up the query used by the "Retry Failed Public Replies" companion workflow.
CREATE INDEX IF NOT EXISTS idx_ig_processed_comments_retry_public_reply
    ON ig_processed_comments (dm_status, public_reply_status)
    WHERE dm_status = 'sent' AND public_reply_status = 'failed';
