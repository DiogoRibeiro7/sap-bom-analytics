BEGIN;

WITH run AS (
    INSERT INTO audit.ingestion_run (
        source_system, source_reference, source_sha256, status, completed_at
    )
    VALUES (
        'SAP_ECC',
        'synthetic://examples/synthetic_bom',
        repeat('0', 64),
        'succeeded',
        CURRENT_TIMESTAMP
    )
    RETURNING ingestion_run_id
),
materials AS (
    INSERT INTO core.material (
        source_system, sap_material_id, description, material_group,
        base_unit, valid_from, ingestion_run_id
    )
    SELECT
        'SAP_ECC',
        value.sap_material_id,
        value.description,
        value.material_group,
        value.base_unit,
        DATE '2026-01-01',
        run.ingestion_run_id
    FROM run
    CROSS JOIN (
        VALUES
            ('FG-1000', 'Shampoo 500 ml', 'FINISHED_GOOD', 'EA'),
            ('PKG-1100', 'Bottle 500 ml clear', 'PACKAGING', 'EA'),
            ('PKG-1200', 'Closure black', 'PACKAGING', 'EA'),
            ('PKG-1300', 'Pressure-sensitive label', 'PACKAGING', 'EA')
    ) AS value(sap_material_id, description, material_group, base_unit)
    RETURNING material_id, sap_material_id, ingestion_run_id
),
bom_row AS (
    INSERT INTO core.bom (
        source_system, sap_bom_id, parent_material_id, plant, usage_code, ingestion_run_id
    )
    SELECT 'SAP_ECC', 'BOM-1000', material_id, 'GB01', '1', ingestion_run_id
    FROM materials
    WHERE sap_material_id = 'FG-1000'
    RETURNING bom_id, ingestion_run_id
),
version_row AS (
    INSERT INTO core.bom_version (
        bom_id, alternative, revision, valid_from, ingestion_run_id
    )
    SELECT bom_id, '01', 'A', DATE '2026-01-01', ingestion_run_id
    FROM bom_row
    RETURNING bom_version_id, ingestion_run_id
)
INSERT INTO core.bom_component (
    bom_version_id, component_material_id, item_number, quantity, unit,
    source_record_id, ingestion_run_id
)
SELECT
    version_row.bom_version_id,
    materials.material_id,
    component.item_number,
    component.quantity,
    component.unit,
    component.source_record_id,
    version_row.ingestion_run_id
FROM version_row
CROSS JOIN (
    VALUES
        ('0010', 'PKG-1100', 1.00000000::NUMERIC, 'EA', 'STPO:1000:0010'),
        ('0020', 'PKG-1200', 1.00000000::NUMERIC, 'EA', 'STPO:1000:0020'),
        ('0030', 'PKG-1300', 1.00000000::NUMERIC, 'EA', 'STPO:1000:0030')
) AS component(item_number, sap_material_id, quantity, unit, source_record_id)
JOIN materials ON materials.sap_material_id = component.sap_material_id;

INSERT INTO classification.material_classification (
    material_id, material_family, polymer, confidence, method, classifier_version
)
SELECT
    material_id,
    'plastic',
    CASE sap_material_id
        WHEN 'PKG-1100' THEN 'HDPE'
        WHEN 'PKG-1200' THEN 'PP'
        ELSE NULL
    END,
    0.98,
    'synthetic-example',
    '0.1.0'
FROM core.material
WHERE sap_material_id IN ('PKG-1100', 'PKG-1200');

COMMIT;
