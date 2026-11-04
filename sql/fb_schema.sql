-- Table de suivi pour le workflow "Facebook Comment Automation"
CREATE TABLE IF NOT EXISTS fb_processed_comments (
  comment_id            text PRIMARY KEY,
  post_id               text,
  comment_text          text,
  username              text,
  matched_rule          text,
  selected_dm           text,
  dm_status             text,          -- sent | failed
  selected_public_reply text,
  public_reply_status   text,          -- sent | failed | skipped
  status                text,          -- done | error
  error_message         text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  processed_at          timestamptz
);

CREATE INDEX IF NOT EXISTS fb_processed_comments_status_idx
  ON fb_processed_comments (status, public_reply_status);
