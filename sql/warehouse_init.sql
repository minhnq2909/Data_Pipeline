CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS raw.wikimedia_recentchanges (
    _raw_id BIGSERIAL PRIMARY KEY,
    _raw JSONB NOT NULL,
    _window_start TIMESTAMPTZ NOT NULL,
    _window_end TIMESTAMPTZ NOT NULL,
    _ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_wikimedia_window_order
        CHECK (_window_start < _window_end)
);

-- Idempotency is enforced with the source natural key rcid.
-- The JSON payload remains unchanged in _raw.
CREATE UNIQUE INDEX IF NOT EXISTS uq_wikimedia_recentchanges_rcid
    ON raw.wikimedia_recentchanges (((_raw ->> 'rcid')::BIGINT))
    WHERE _raw ? 'rcid';

CREATE INDEX IF NOT EXISTS ix_wikimedia_recentchanges_window
    ON raw.wikimedia_recentchanges (_window_start, _window_end);

CREATE TABLE IF NOT EXISTS raw.wikimedia_recentchanges_errors (
    _error_id BIGSERIAL PRIMARY KEY,
    _error_fingerprint TEXT NOT NULL UNIQUE,
    _raw JSONB NOT NULL,
    _error_type TEXT NOT NULL,
    _error_message TEXT NOT NULL,
    _window_start TIMESTAMPTZ NOT NULL,
    _window_end TIMESTAMPTZ NOT NULL,
    _ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);



CREATE OR REPLACE FUNCTION raw.reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'raw tables are append-only; % is not allowed on %',
        TG_OP,
        TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER trg_wikimedia_recentchanges_no_update_delete
    BEFORE UPDATE OR DELETE ON raw.wikimedia_recentchanges
    FOR EACH ROW
    EXECUTE FUNCTION raw.reject_mutation();

CREATE TRIGGER trg_wikimedia_recentchanges_no_truncate
    BEFORE TRUNCATE ON raw.wikimedia_recentchanges
    FOR EACH STATEMENT
    EXECUTE FUNCTION raw.reject_mutation();

COMMENT ON TABLE raw.wikimedia_recentchanges IS
    'Append-only landing table. Original Wikimedia payload plus technical metadata only.';

COMMENT ON TABLE raw.wikimedia_recentchanges_errors IS
    'Quarantine table for invalid source records. A bad record must not discard the rest of the page.';
