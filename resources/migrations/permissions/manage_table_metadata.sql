-- Insert DB-level permissions with a check for table-level permissions
ALTER TABLE data_permissions DISABLE TRIGGER ALL;

INSERT INTO data_permissions (group_id, perm_type, db_id, schema_name, table_id, perm_value)
SELECT pg.id AS group_id,
       'perms/manage-table-metadata' AS perm_type,
       md.id AS db_id,
       NULL AS schema_name,
       NULL AS table_id,
       CASE
           WHEN EXISTS
                  (SELECT 1
                   FROM permissions p
                   WHERE p.group_id = pg.id
                     AND (p.object = concat('/data-model/db/', md.id, '/')
                          OR p.object = concat('/data-model/db/', md.id, '/schema/'))) THEN 'yes'
            ELSE 'no'
       END AS perm_value
FROM permissions_group pg
CROSS JOIN metabase_database md
WHERE pg.name != 'Administrators'
  AND NOT EXISTS
    (SELECT 1
     FROM data_permissions dp
     WHERE dp.group_id = pg.id
       AND dp.db_id = md.id
       AND dp.perm_type = 'perms/manage-table-metadata')
  AND CASE
          WHEN EXISTS
                 (SELECT 1
                  FROM permissions p
                  WHERE p.group_id = pg.id
                    AND (p.object = concat('/data-model/db/', md.id, '/')
                         OR p.object = concat('/data-model/db/', md.id, '/schema/'))) THEN TRUE
          WHEN NOT EXISTS
                 (SELECT 1
                  FROM permissions p
                  WHERE p.group_id = pg.id
                    AND p.object like concat('/data-model/db/', md.id, '/schema/%')) THEN TRUE
          ELSE FALSE
      END;

ANALYZE data_permissions;

WITH escaped_schema_table AS (
    SELECT
        mt.id AS table_id,
        mt.db_id,
        mt.schema,
        CONCAT('/data-model/db/', mt.db_id, '/schema/', REPLACE(REPLACE(mt.schema, '\', '\\'), '/', '\/'), '/') AS schema_path,
        CONCAT('/data-model/db/', mt.db_id, '/schema/', REPLACE(REPLACE(mt.schema, '\', '\\'), '/', '\/'), '/table/', mt.id, '/') AS table_path
    FROM metabase_table mt
)
-- Insert 'yes' permissions based on existing permissions
INSERT INTO data_permissions (group_id, perm_type, db_id, schema_name, table_id, perm_value)
SELECT
    p.group_id,
    'perms/manage-table-metadata' AS perm_type,
    est.db_id,
    est.schema AS schema_name,
    est.table_id,
    'yes' AS perm_value
FROM escaped_schema_table est
JOIN permissions p
ON p.object IN (
    est.schema_path,
    est.table_path
)
WHERE NOT EXISTS (
    SELECT 1
    FROM data_permissions dp
    WHERE dp.group_id = p.group_id
      AND dp.db_id = est.db_id
      AND dp.table_id = est.table_id
      AND dp.perm_type = 'perms/manage-table-metadata'
);

ANALYZE data_permissions;

-- Insert 'no' permissions for any table and group combinations that weren't covered by the previous query
INSERT INTO data_permissions (group_id, perm_type, db_id, schema_name, table_id, perm_value)
SELECT
    pg.id AS group_id,
    'perms/manage-table-metadata' AS perm_type,
    mt.db_id,
    mt.schema AS schema_name,
    mt.id AS table_id,
    'no' AS perm_value
FROM permissions_group pg
CROSS JOIN metabase_table mt
WHERE NOT EXISTS (
    SELECT 1
    FROM data_permissions dp
    WHERE dp.group_id = pg.id
      AND dp.db_id = mt.db_id
      AND (dp.table_id = mt.id
           OR dp.table_id IS NULL)
      AND dp.perm_type = 'perms/manage-table-metadata'
)
AND pg.name != 'Administrators';

ALTER TABLE data_permissions ENABLE TRIGGER ALL;
