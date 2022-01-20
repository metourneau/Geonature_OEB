DROP VIEW IF EXISTS pr_occtax.v_releve_list;

-- ajout du count obs et taxon pour chaque relevé
CREATE OR REPLACE VIEW pr_occtax.v_releve_list AS 
 SELECT rel.id_releve_occtax,
    rel.id_dataset,
    rel.id_digitiser,
    rel.date_min,
    rel.date_max,
    rel.altitude_min,
    rel.altitude_max,
    rel.meta_device_entry,
    rel.comment,
    rel.geom_4326,
    rel."precision",
    rel.observers_txt,
    dataset.dataset_name,
    string_agg(t.nom_valide::text, ','::text) AS taxons,
    (((string_agg(t.nom_valide::text, ','::text) || '<br/>'::text) || rel.date_min::date) || '<br/>'::text) || COALESCE(string_agg(DISTINCT (obs.nom_role::text || ' '::text) || obs.prenom_role::text, ', '::text), rel.observers_txt::text) AS leaflet_popup,
    COALESCE(string_agg(DISTINCT (obs.nom_role::text || ' '::text) || obs.prenom_role::text, ', '::text), rel.observers_txt::text) AS observateurs,
    count(DISTINCT(occ.id_occurrence_occtax)) AS nb_occ,
    count(DISTINCT(obs.id_role)) as nb_observer
   FROM pr_occtax.t_releves_occtax rel
     LEFT JOIN pr_occtax.t_occurrences_occtax occ ON rel.id_releve_occtax = occ.id_releve_occtax
     LEFT JOIN taxonomie.taxref t ON occ.cd_nom = t.cd_nom
     LEFT JOIN pr_occtax.cor_role_releves_occtax cor_role ON cor_role.id_releve_occtax = rel.id_releve_occtax
     LEFT JOIN utilisateurs.t_roles obs ON cor_role.id_role = obs.id_role
     LEFT JOIN gn_meta.t_datasets dataset ON dataset.id_dataset = rel.id_dataset
  GROUP BY dataset.dataset_name, rel.id_releve_occtax, rel.id_dataset, rel.id_digitiser, rel.date_min, rel.date_max, rel.altitude_min, rel.altitude_max, rel.meta_device_entry;

-- pas d'action sur delete entre synthese et cor_area_synthese
ALTER TABLE ONLY gn_synthese.cor_area_synthese
    DROP CONSTRAINT IF EXISTS fk_cor_area_synthese_id_synthese,
    ADD CONSTRAINT fk_cor_area_synthese_id_synthese FOREIGN KEY (id_synthese) REFERENCES gn_synthese.synthese(id_synthese) ON DELETE NO ACTION;


CREATE TABLE gn_synthese.cor_area_taxon (
  cd_nom integer NOT NULL,
  id_area integer NOT NULL, 
  nb_obs integer NOT NULL, 
  last_date timestamp without time zone NOT NULL
);

-- vue couleur taxon
CREATE OR REPLACE VIEW gn_synthese.v_color_taxon_area AS
SELECT cd_nom, id_area, nb_obs, last_date,
 CASE 
  WHEN date_part('day', (now() - last_date)) < 365 THEN 'grey'
  ELSE 'red'
 END as color
FROM gn_synthese.cor_area_taxon;

INSERT INTO gn_synthese.cor_area_taxon (cd_nom, id_area, nb_obs, last_date)
   SELECT
   DISTINCT(s.cd_nom) AS cd_nom,
   cor.id_area AS id_area, 
   count(s.id_synthese) AS nb_obs, 
   max(s.date_min) AS last_date
   FROM gn_synthese.cor_area_synthese cor
   JOIN gn_synthese.synthese s ON s.id_synthese = cor.id_synthese
   GROUP BY s.cd_nom, cor.id_area;

-- PK
ALTER TABLE gn_synthese.cor_area_taxon
  ADD CONSTRAINT pk_cor_area_taxon PRIMARY KEY (id_area, cd_nom);

-- FK
ALTER TABLE gn_synthese.cor_area_taxon
  ADD CONSTRAINT fk_cor_area_taxon_cd_nom FOREIGN KEY (cd_nom)
      REFERENCES taxonomie.taxref (cd_nom) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE NO ACTION;
ALTER TABLE gn_synthese.cor_area_taxon
  ADD CONSTRAINT fk_cor_area_taxon_id_area FOREIGN KEY (id_area)
      REFERENCES ref_geo.l_areas (id_area) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE NO ACTION;


-- trigger insertion ou update sur cor_area_syntese - déclenché après insert ou update sur cor_area_synthese
CREATE OR REPLACE FUNCTION gn_synthese.fct_tri_maj_cor_unite_taxon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE the_cd_nom integer;
BEGIN
    SELECT cd_nom INTO the_cd_nom FROM gn_synthese.synthese WHERE id_synthese = NEW.id_synthese;
  -- on supprime cor_area_taxon et recree à chaque fois
  -- cela evite de regarder dans cor_area_taxon s'il y a deja une ligne, de faire un + 1  ou -1 sur nb_obs etc...
    IF (TG_OP = 'INSERT') THEN
      DELETE FROM gn_synthese.cor_area_taxon WHERE cd_nom = the_cd_nom AND id_area IN (NEW.id_area);
    ELSE
      DELETE FROM gn_synthese.cor_area_taxon WHERE cd_nom = the_cd_nom AND id_area IN (NEW.id_area, OLD.id_area);
    END IF;
    -- puis on réinsert
    -- on récupère la dernière date de l'obs dans l'aire concernée depuis cor_area_synthese et synthese
    INSERT INTO gn_synthese.cor_area_taxon (id_area, cd_nom, last_date, nb_obs)
    SELECT id_area, s.cd_nom,  max(s.date_min) AS last_date, count(s.id_synthese) AS nb_obs
    FROM gn_synthese.cor_area_synthese cor
    JOIN gn_synthese.synthese s ON s.id_synthese = cor.id_synthese
    WHERE s.cd_nom = the_cd_nom AND id_area = NEW.id_area
    GROUP BY id_area, s.cd_nom;
    RETURN NULL;
END;
$$;

CREATE TRIGGER tri_maj_cor_area_taxon 
AFTER INSERT OR UPDATE 
ON gn_synthese.cor_area_synthese 
FOR EACH ROW 
EXECUTE PROCEDURE gn_synthese.fct_tri_maj_cor_unite_taxon();

-- trigger de suppression depuis la synthese
-- suppression dans cor_area_taxon
-- recalcule des aires
-- suppression dans cor_area_synthese
-- déclenché en BEFORE DELETE
CREATE OR REPLACE FUNCTION gn_synthese.fct_tri_manage_area_synth_and_taxon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    the_id_areas int[];
BEGIN 
   -- on récupère tous les aires intersectées par l'id_synthese concerné
    SELECT array_agg(id_area) INTO the_id_areas
    FROM gn_synthese.cor_area_synthese
    WHERE id_synthese = OLD.id_synthese;
    -- DELETE AND INSERT sur cor_area_taxon: evite de faire un count sur nb_obs
    DELETE FROM gn_synthese.cor_area_taxon WHERE cd_nom = OLD.cd_nom AND id_area = ANY (the_id_areas);
    -- on réinsert dans cor_area_synthese en recalculant les max, nb_obs
    INSERT INTO gn_synthese.cor_area_taxon (cd_nom, nb_obs, id_area, last_date)
    SELECT s.cd_nom, count(s.id_synthese), cor.id_area,  max(s.date_min)
    FROM gn_synthese.cor_area_synthese cor
    JOIN gn_synthese.synthese s ON s.id_synthese = cor.id_synthese
    -- on ne prend pas l'OLD.synthese car c'est un trigger BEFORE DELETE
    WHERE id_area = ANY (the_id_areas) AND s.cd_nom = OLD.cd_nom AND s.id_synthese != OLD.id_synthese
    GROUP BY cor.id_area, s.cd_nom;
    -- suppression dans cor_area_synthese si tg_op = DELETE
    DELETE FROM gn_synthese.cor_area_synthese WHERE id_synthese = OLD.id_synthese;
    RETURN OLD;
END;
$$;


CREATE OR REPLACE FUNCTION gn_synthese.delete_and_insert_area_taxon(my_cd_nom integer, my_id_area integer[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN 
  -- supprime dans cor_area_taxon
  DELETE FROM gn_synthese.cor_area_taxon WHERE cd_nom = my_cd_nom AND id_area = ANY (my_id_area);
  -- réinsertion et calcul
  INSERT INTO gn_synthese.cor_area_taxon (cd_nom, nb_obs, id_area, last_date)
  SELECT s.cd_nom, count(s.id_synthese), cor.id_area,  max(s.date_min)
  FROM gn_synthese.cor_area_synthese cor
  JOIN gn_synthese.synthese s ON s.id_synthese = cor.id_synthese
  WHERE id_area = ANY (my_id_area) AND s.cd_nom = my_cd_nom
  GROUP BY cor.id_area, s.cd_nom;
END;
$$;


CREATE OR REPLACE FUNCTION gn_synthese.fct_tri_update_cd_nom() RETURNS trigger
    LANGUAGE plpgsql
  AS $$
DECLARE
    the_id_areas int[];
BEGIN 
   -- on récupère tous les aires intersectées par l'id_synthese concerné
    SELECT array_agg(id_area) INTO the_id_areas
    FROM gn_synthese.cor_area_synthese
    WHERE id_synthese = OLD.id_synthese;

    -- recalcul pour l'ancien taxon
    PERFORM(gn_synthese.delete_and_insert_area_taxon(OLD.cd_nom, the_id_areas));
    -- recalcul pour le nouveau taxon
    PERFORM(gn_synthese.delete_and_insert_area_taxon(NEW.cd_nom, the_id_areas));
    
  RETURN OLD;
END;
$$;


-- trigger suppression dans la synthese
CREATE TRIGGER tri_del_area_synt_maj_corarea_tax
  BEFORE DELETE
  ON gn_synthese.synthese
  FOR EACH ROW
  EXECUTE PROCEDURE gn_synthese.fct_tri_manage_area_synth_and_taxon();

-- trigger update cd_nom dans la synthese
CREATE TRIGGER tri_update_cor_area_taxon_update_cd_nom
  AFTER UPDATE OF cd_nom
  ON gn_synthese.synthese
  FOR EACH ROW
  EXECUTE PROCEDURE gn_synthese.fct_tri_update_cd_nom();


-- Ajout type maille 5k

INSERT INTO ref_geo.bib_areas_types (type_name, type_code, type_desc, ref_name, ref_version) VALUES
('Mailles5*5', 'M5', 'Type maille INPN 5*5km', NULL,NULL);



-- Intégration du SQL validation dans le coeur

DROP VIEW gn_commons.v_lastest_validation;

CREATE OR REPLACE VIEW gn_commons.v_validations_for_web_app AS
 SELECT s.id_synthese,
    s.unique_id_sinp,
    s.unique_id_sinp_grp,
    s.id_source,
    s.entity_source_pk_value,
    s.count_min,
    s.count_max,
    s.nom_cite,
    s.meta_v_taxref,
    s.sample_number_proof,
    s.digital_proof,
    s.non_digital_proof,
    s.altitude_min,
    s.altitude_max,
    s.the_geom_4326,
    s.date_min,
    s.date_max,
    s.validator,
    s.observers,
    s.id_digitiser,
    s.determiner,
    s.comment_context,
    s.comment_description,
    s.meta_validation_date,
    s.meta_create_date,
    s.meta_update_date,
    s.last_action,
    d.id_dataset,
    d.dataset_name,
    d.id_acquisition_framework,
    s.id_nomenclature_geo_object_nature,
    s.id_nomenclature_info_geo_type,
    s.id_nomenclature_grp_typ,
    s.id_nomenclature_obs_meth,
    s.id_nomenclature_obs_technique,
    s.id_nomenclature_bio_status,
    s.id_nomenclature_bio_condition,
    s.id_nomenclature_naturalness,
    s.id_nomenclature_exist_proof,
    s.id_nomenclature_diffusion_level,
    s.id_nomenclature_life_stage,
    s.id_nomenclature_sex,
    s.id_nomenclature_obj_count,
    s.id_nomenclature_type_count,
    s.id_nomenclature_sensitivity,
    s.id_nomenclature_observation_status,
    s.id_nomenclature_blurring,
    s.id_nomenclature_source_status,
    sources.name_source,
    sources.url_source,
    t.cd_nom,
    t.cd_ref,
    t.nom_valide,
    t.lb_nom,
    t.nom_vern,
    v.id_validation,
    v.id_table_location,
    v.uuid_attached_row,
    v.id_nomenclature_valid_status,
    v.id_validator,
    v.validation_comment,
    v.validation_date,
    v.validation_auto,
    n.mnemonique
   FROM gn_synthese.synthese s
     JOIN taxonomie.taxref t ON t.cd_nom = s.cd_nom
     JOIN gn_meta.t_datasets d ON d.id_dataset = s.id_dataset
     JOIN gn_synthese.t_sources sources ON sources.id_source = s.id_source
     JOIN gn_commons.t_validations v ON v.uuid_attached_row = s.unique_id_sinp
     JOIN ref_nomenclatures.t_nomenclatures n ON n.id_nomenclature = v.id_nomenclature_valid_status;


CREATE OR REPLACE VIEW gn_commons.v_latest_validations_for_web_app AS
SELECT v1.*
FROM gn_commons.v_validations_for_web_app v1
JOIN
(
	SELECT id_synthese, Max(validation_date)
	FROM gn_commons.v_validations_for_web_app
	GROUP BY id_synthese
) v2 on v1.validation_date = v2.max AND v1.id_synthese = v2.id_synthese;
