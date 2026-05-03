CREATE TABLE IF NOT EXISTS categorias (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre     VARCHAR(100) NOT NULL,
    slug       VARCHAR(100) NOT NULL,
    icono_url  VARCHAR(500),
    activa     BOOLEAN      NOT NULL DEFAULT true,
    orden      INTEGER      NOT NULL DEFAULT 0,
    created_at TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    CONSTRAINT uq_categorias_nombre UNIQUE (nombre),
    CONSTRAINT uq_categorias_slug   UNIQUE (slug)
);

CREATE INDEX IF NOT EXISTS idx_categorias_activa_orden ON categorias (activa, orden);

CREATE OR REPLACE TRIGGER categorias_updated_at
    BEFORE UPDATE ON categorias
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
