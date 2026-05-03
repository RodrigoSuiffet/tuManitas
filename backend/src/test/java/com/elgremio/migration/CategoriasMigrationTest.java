package com.elgremio.migration;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.sql.Timestamp;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Testcontainers
class CategoriasMigrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>(DockerImageName.parse("postgis/postgis:16-3.4")
                    .asCompatibleSubstituteFor("postgres"));

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    void postgis_versionIsValid() {
        String version = jdbc.queryForObject("SELECT PostGIS_Version()", String.class);
        assertThat(version).isNotBlank();
    }

    @Test
    void pgTrgm_similarityAboveThreshold() {
        Double similarity = jdbc.queryForObject(
                "SELECT similarity('fontanero', 'fontaner')", Double.class);
        assertThat(similarity).isGreaterThan(0.6);
    }

    @Test
    void categorias_tableHasAllColumns() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM information_schema.columns " +
                "WHERE table_schema = 'public' AND table_name = 'categorias'",
                Integer.class);
        assertThat(count).isEqualTo(8);
    }

    @Test
    void categorias_uniqueIndexNombreExists() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM pg_indexes " +
                "WHERE tablename = 'categorias' AND indexname = 'uq_categorias_nombre'",
                Integer.class);
        assertThat(count).isEqualTo(1);
    }

    @Test
    void categorias_uniqueIndexSlugExists() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM pg_indexes " +
                "WHERE tablename = 'categorias' AND indexname = 'uq_categorias_slug'",
                Integer.class);
        assertThat(count).isEqualTo(1);
    }

    @Test
    void categorias_activaOrdenIndexExists() {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM pg_indexes " +
                "WHERE tablename = 'categorias' AND indexname = 'idx_categorias_activa_orden'",
                Integer.class);
        assertThat(count).isEqualTo(1);
    }

    @Test
    void categorias_createdAtAutoSet() {
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO categorias (id, nombre, slug) VALUES (?, 'CreatedTest', 'created-test')", id);

        Timestamp createdAt = jdbc.queryForObject(
                "SELECT created_at FROM categorias WHERE id = ?", Timestamp.class, id);
        assertThat(createdAt).isNotNull();
    }

    @Test
    void categorias_updatedAtTriggerSetsTimestampOnUpdate() {
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO categorias (id, nombre, slug) VALUES (?, 'TriggerTest', 'trigger-test')", id);

        Timestamp updatedAtAfterInsert = jdbc.queryForObject(
                "SELECT updated_at FROM categorias WHERE id = ?", Timestamp.class, id);
        assertThat(updatedAtAfterInsert).isNull();

        jdbc.update("UPDATE categorias SET nombre = 'TriggerTest Updated' WHERE id = ?", id);

        Timestamp updatedAtAfterUpdate = jdbc.queryForObject(
                "SELECT updated_at FROM categorias WHERE id = ?", Timestamp.class, id);
        assertThat(updatedAtAfterUpdate).isNotNull();
    }
}
