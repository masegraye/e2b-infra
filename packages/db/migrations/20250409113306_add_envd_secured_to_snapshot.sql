-- +goose Up
-- +goose StatementBegin
BEGIN;

ALTER TABLE snapshots
ADD COLUMN env_secure boolean NOT NULL DEFAULT false;


-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
BEGIN;

ALTER TABLE snapshots
DROP COLUMN IF EXISTS env_secure;


-- +goose StatementEnd
