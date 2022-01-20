
--tri_meta_dates_change_synthese
-- On garde les dates existantes dans les schémas importés
-- Mais on update les enregistrements où date_insert et date_update serait restée vides
UPDATE gn_synthese.synthese SET meta_create_date = NOW() WHERE meta_create_date IS NULL;
UPDATE gn_synthese.synthese SET meta_update_date = NOW() WHERE meta_update_date IS NULL;


--maintenance sur la table synthese avant intersects lourd
VACUUM FULL gn_synthese.synthese;
VACUUM ANALYSE gn_synthese.synthese;
REINDEX TABLE gn_synthese.synthese;

-- Actions du trigger tri_insert_cor_area_synthese
-- On recalcule l'intersection entre les données de la synthèse et les géométries de ref_geo.l_areas
--TRUNCATE TABLE gn_synthese.cor_area_synthese;
INSERT INTO gn_synthese.cor_area_synthese 
SELECT
  s.id_synthese,
  a.id_area
FROM ref_geo.l_areas a
JOIN gn_synthese.synthese s ON public.st_intersects(s.the_geom_local, a.geom)
WHERE a.enable = true;

-- Maintenance
VACUUM FULL gn_synthese.cor_area_synthese;
VACUUM FULL gn_synthese.cor_observer_synthese;
VACUUM FULL gn_synthese.synthese;
VACUUM FULL gn_synthese.t_sources;

VACUUM ANALYSE gn_synthese.cor_area_synthese;
VACUUM ANALYSE gn_synthese.cor_observer_synthese;
VACUUM ANALYSE gn_synthese.synthese;
VACUUM ANALYSE gn_synthese.t_sources;

REINDEX TABLE gn_synthese.cor_area_synthese;
REINDEX TABLE gn_synthese.cor_observer_synthese;
REINDEX TABLE gn_synthese.synthese;
REINDEX TABLE gn_synthese.t_sources;


-- On réactive les triggers du schéma synthese après avoir joué (ci-dessus) leurs actions
ALTER TABLE gn_synthese.cor_observer_synthese ENABLE TRIGGER trg_maj_synthese_observers_txt;
ALTER TABLE gn_synthese.synthese ENABLE TRIGGER tri_meta_dates_change_synthese;
ALTER TABLE gn_synthese.synthese ENABLE TRIGGER tri_insert_cor_area_synthese;
ALTER TABLE gn_synthese.synthese ENABLE TRIGGER tri_insert_calculate_sensitivity;

