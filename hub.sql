﻿-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
---- FONCTIONS LOCALES ET GLOBALES POUR LE PARTAGE DE DONNÉES AU SEIN DU RESEAU DES CBN
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
--- Marche à suivre pour générer un hub fonctionnel
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
--- 1. Lancer le fichier hub.sql
--- la fonction hub_admin_init sera lancé automatiquement.

--- 2. Installer le hub	(cette fonction lance les fonctions hub_admin_clone et hub_admin_ref)							
--- SELECT * FROM hub_admin_install('hub');	

--- 3. Importer une jeu de données (ex :  TAXA)
--- SELECT * FROM hub_import('hub','taxa','D:/Temp/import/');

--- 4. Vérifier le jeu de données (ex : TAXA)
--- SELECT * FROM hub_verif_all('hub','taxa');

--- 5. Pousser les données dans la partie propre (ex : TAXA)
--- SELECT * FROM hub_push('hub','taxa');

--- 6. Envoyer les données sur le hub national (ex : TAXA)
--- SELECT * FROM hub_connect([adresse_ip], '5433','si_flore_national',[utilisateur],[mdp], 'taxa', 'hub', [trigramme_cbn]);

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
--- Fonction Admin 
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.zz_log (lib_schema character varying,lib_table character varying,lib_champ character varying,typ_log character varying,lib_log character varying,nb_occurence character varying,date_log timestamp);
DROP TABLE public.bilan;CREATE TABLE IF NOT EXISTS public.bilan (uid integer NOT NULL,lib_cbn character varying,data_nb_releve integer,data_nb_observation integer,data_nb_taxon integer,taxa_nb_taxon integer,temp_data_nb_releve integer,temp_data_nb_observation integer,temp_data_nb_taxon integer,temp_taxa_nb_taxon integer,derniere_action character varying, date_derniere_action date,CONSTRAINT bilan_pkey PRIMARY KEY (uid));
CREATE TABLE IF NOT EXISTS public.threecol (col1 varchar, col2 varchar, col3 varchar);
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_init
--- Description : initialise les fonction du hub (supprime toutes les fonctions) et  initialise certaines tables (zz_log et bilan)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_init() RETURNS void  AS 
$BODY$ 
DECLARE cmd varchar;
DECLARE fonction varchar;
DECLARE listFunction varchar[];
DECLARE schem varchar;
DECLARE tabl varchar;
DECLARE exist varchar;
DECLARE date_log timestamp;
BEGIN 
--- Variable
SELECT CURRENT_TIMESTAMP INTO date_log;	
--- Récupération de toutes les fonction du hub
cmd = 'SELECT routine_name||''(''||string_agg(data_type ,'','')||'')'' FROM(
	SELECT routine_name, z.specific_name, 
		CASE WHEN z.data_type  = ''ARRAY'' THEN z.udt_name||''[]'' 
		WHEN z.data_type  = ''USER-DEFINED'' THEN z.udt_name 
		ELSE z.data_type END as data_type
	FROM information_schema.routines a
	JOIN information_schema.parameters z ON a.specific_name = z.specific_name
	WHERE  routine_name LIKE ''hub_%''
	ORDER BY routine_name,ordinal_position
	) as one
	GROUP BY routine_name, specific_name';
--- Suppression de ces fonctions
FOR fonction IN EXECUTE cmd
   LOOP EXECUTE 'DROP FUNCTION '||fonction||';';
   END LOOP;

-- Fonctions utilisées par le hub
listFunction = ARRAY['dblink','uuid-ossp','postgis'];
FOREACH fonction IN ARRAY listFunction LOOP
	EXECUTE 'SELECT extname from pg_extension WHERE extname = '''||fonction||''';' INTO exist;
	CASE WHEN exist IS NULL THEN EXECUTE 'CREATE EXTENSION "'||fonction||'";';
	ELSE END CASE;
END LOOP;
END;$BODY$ LANGUAGE plpgsql;

--- Lancé à chaque fois pour réinitialier les fonctions
SELECT * FROM hub_admin_init();

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_install 
--- Description : Installe le hub en local (concataine la construction d'un hub et l'installation des référentiels)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_install (libSchema varchar, path varchar = '/home/hub/00_ref/') RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
BEGIN
SELECT * INTO out FROM hub_admin_ref('create',path);PERFORM hub_log ('public', out);RETURN NEXT out;
SELECT * INTO out FROM hub_admin_clone(libSchema);PERFORM hub_log (libSchema, out);RETURN NEXT out;
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_uninstall 
--- Description : Desinstalle le hub en local
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_uninstall (libSchema varchar) RETURNS varchar AS 
$BODY$
BEGIN
PERFORM hub_admin_ref('drop');
PERFORM hub_admin_drop(libSchema);
DROP TABLE public.bilan;
DROP TABLE public.zz_log CASCADE;
RETURN libSchema||' supprimé';
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_clone 
--- Description : Création d'un hub complet
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_clone(libSchema varchar, typ varchar = 'all') RETURNS setof zz_log AS 
$BODY$ 
DECLARE out zz_log%rowtype; 
DECLARE flag integer; 
DECLARE typjdd varchar; 
DECLARE cd_table varchar; 
DECLARE list_champ varchar; 
DECLARE list_champ_sans_format varchar; 
DECLARE list_contraint varchar; 
DECLARE schema_lower varchar; 
BEGIN
--- Variable
schema_lower = lower(libSchema);
EXECUTE 'SELECT DISTINCT 1 FROM pg_tables WHERE schemaname = '''||schema_lower||''';' INTO flag;
--- Commande
CASE WHEN flag = 1 THEN
	out.lib_log := 'Schema '||schema_lower||' existe déjà';
ELSE 
	EXECUTE 'CREATE SCHEMA "'||schema_lower||'";';

	--- META : PARTIE PROPRE 
	FOR typjdd IN SELECT typ_jdd FROM ref.fsd GROUP BY typ_jdd
	LOOP
		FOR cd_table IN EXECUTE 'SELECT cd_table FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' GROUP BY cd_table'
		LOOP
			CASE WHEN typ = 'all' OR typ = 'propre' THEN
				EXECUTE 'SELECT string_agg(one.cd_champ||'' ''||one.format,'','') FROM (SELECT cd_champ, format FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' AND cd_table = '''||cd_table||''' ORDER BY ordre_champ) as one;' INTO list_champ;
				EXECUTE 'SELECT ''CONSTRAINT ''||cd_table||''_pkey PRIMARY KEY (''||string_agg(cd_champ,'','')||'')'' FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' AND cd_table = '''||cd_table||''' AND unicite = ''Oui'' GROUP BY cd_table' INTO list_contraint ;
				EXECUTE 'CREATE TABLE '||schema_lower||'.'||cd_table||' ('||list_champ||','||list_contraint||');';
			ELSE END CASE;
			CASE WHEN typ = 'all' OR typ = 'temp' THEN
				EXECUTE 'SELECT string_agg(one.cd_champ||'' character varying'','','') FROM (SELECT cd_champ, format FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' AND cd_table = '''||cd_table||''' ORDER BY ordre_champ) as one;' INTO list_champ_sans_format;
				EXECUTE 'CREATE TABLE '||schema_lower||'.temp_'||cd_table||' ('||list_champ_sans_format||');';
			ELSE END CASE;
		END LOOP;
	END LOOP;
	--- LISTE TAXON
	EXECUTE '
	CREATE TABLE "'||schema_lower||'".zz_log_liste_taxon  (cd_ref character varying, nom_valide character varying);
	CREATE TABLE "'||schema_lower||'".zz_log_liste_taxon_et_infra  (cd_ref_demande character varying, nom_valide_demande character varying, cd_ref_cite character varying, nom_complet_cite character varying, rang_cite character varying, cd_taxsup_cite character varying);
	';
	--- LOG
	EXECUTE '
	CREATE TABLE "'||schema_lower||'".zz_log  (lib_schema character varying,lib_table character varying,lib_champ character varying,typ_log character varying,lib_log character varying,nb_occurence character varying,date_log timestamp);
	';
	out.lib_log := 'Schema '||schema_lower||' créé';
END CASE;
--- Output&Log
out.lib_schema := schema_lower;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_clone';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log (schema_lower, out);RETURN NEXT out;
END; $BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_drop
--- Description : Supprimer un hub dans sa totalité (ATTENTION, NON REVERSIBLE)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_drop(libSchema varchar) RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE flag integer;
BEGIN
--- Commandes
EXECUTE 'SELECT DISTINCT 1 FROM pg_tables WHERE schemaname = '''||libSchema||''';' INTO flag;
CASE flag WHEN 1 THEN
	EXECUTE 'DROP SCHEMA IF EXISTS "'||libSchema||'" CASCADE;';
	out.lib_log := 'Schema '||libSchema||' supprimé';
ELSE out.lib_log := 'Schema '||libSchema||' inexistant pas dans le Hub';
END CASE;
--- Output&Log
out.lib_schema := libSchema;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_drop';out.nb_occurence := 1;SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log ('public', out);RETURN next out;
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_ref 
--- Description : Création des référentiels
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_ref(typAction varchar, path varchar = '/home/hub/00_ref/', version varchar = '3.2') RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE flag1 integer;
DECLARE flag2 integer;
DECLARE champFonction varchar;
DECLARE libTable varchar;
DECLARE delimitr varchar;
DECLARE structure varchar;
BEGIN
--- Output
out.lib_schema := '-';out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_ref';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;
---Variables


--- Commandes 
CASE WHEN typAction = 'drop' THEN	--- Suppression
	EXECUTE 'SELECT DISTINCT 1 FROM information_schema.schemata WHERE schema_name = ''ref''' INTO flag1;
	CASE WHEN flag1 = 1 THEN DROP SCHEMA IF EXISTS ref CASCADE; out.lib_log := 'Schema ref supprimé';RETURN next out;
	ELSE out.lib_log := 'Schéma ref inexistant';RETURN next out;END CASE;

WHEN typAction = 'delete' THEN	--- Suppression
	EXECUTE 'SELECT DISTINCT 1 FROM information_schema.schemata WHERE schema_name = ''ref''' INTO flag1;
	CASE WHEN flag1 = 1 THEN
		FOR libTable IN EXECUTE 'SELECT nom_ref FROM ref.aa_meta GROUP BY nom_ref ORDER BY nom_ref'
		LOOP EXECUTE 'SELECT DISTINCT 1 FROM pg_tables WHERE schemaname = ''ref'' AND tablename = '''||libTable||''';' INTO flag2;
		CASE WHEN flag2 = 1 THEN 
			EXECUTE 'DROP TABLE ref."'||libTable||'" CASCADE';  out.lib_log := 'Table '||libTable||' supprimée';RETURN next out;
		ELSE out.lib_log := 'Table '||libTable||' inexistante';
		END CASE;
		END LOOP;
	ELSE out.lib_log := 'Schéma ref inexistant';RETURN next out;END CASE;

WHEN typAction = 'create' THEN	--- Creation
	EXECUTE 'SELECT DISTINCT 1 FROM information_schema.schemata WHERE schema_name =  ''ref''' INTO flag1;
	CASE WHEN flag1 = 1 THEN out.lib_log := 'Schema ref déjà créés';RETURN next out;ELSE CREATE SCHEMA "ref"; out.lib_log := 'Schéma ref créés';RETURN next out;END CASE;
	--- Initialisation du meta-référentiel
	CREATE TABLE IF NOT EXISTS ref.aa_meta(id serial NOT NULL, nom_ref varchar, typ varchar, ordre integer, libelle varchar, format varchar, CONSTRAINT aa_meta_pk PRIMARY KEY(id));
	TRUNCATE ref.aa_meta;
	EXECUTE 'COPY ref.aa_meta (nom_ref, typ, ordre, libelle, format) FROM '''||path||'aa_meta.csv'' HEADER CSV ENCODING ''UTF8'' DELIMITER '';'';';
	--- Tables
	FOR libTable IN EXECUTE 'SELECT nom_ref FROM ref.aa_meta GROUP BY nom_ref  ORDER BY nom_ref'
		LOOP EXECUTE 'SELECT DISTINCT 1 FROM pg_tables WHERE schemaname = ''ref'' AND tablename = '''||libTable||''';' INTO flag2;
		CASE WHEN flag2 = 1 THEN 
			out.lib_log := libTable||' a déjà été créée' ;RETURN next out;
		ELSE EXECUTE 'SELECT ''(''||champs||'',''||contrainte||'')''
			FROM (SELECT nom_ref, string_agg(libelle||'' ''||format,'','') as champs FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''champ'' GROUP BY nom_ref) as one
			JOIN (SELECT nom_ref, ''CONSTRAINT ''||nom_ref||''_pk PRIMARY KEY (''||libelle||'')'' as contrainte FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''cle_primaire'') as two ON one.nom_ref = two.nom_ref
			' INTO structure;
			EXECUTE 'SELECT CASE WHEN libelle = ''virgule'' THEN '','' WHEN libelle = ''tab'' THEN ''\t'' WHEN libelle = ''point_virgule'' THEN '';'' ELSE '';'' END as delimiter FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''delimiter''' INTO delimitr;
			EXECUTE 'CREATE TABLE ref.'||libTable||' '||structure||';'; out.lib_log := libTable||' créée';RETURN next out;
			EXECUTE 'COPY ref.'||libTable||' FROM '''||path||'ref_'||libTable||'.csv'' HEADER CSV DELIMITER E'''||delimitr||''' ENCODING ''UTF8'';';
		out.lib_log := libTable||' : données importées';RETURN next out;
		END CASE;
		END LOOP;

WHEN typAction = 'update' THEN	--- Mise à jour
	EXECUTE 'SELECT DISTINCT 1 FROM information_schema.schemata WHERE schema_name =  ''ref''' INTO flag1;
	CASE WHEN flag1 = 1 THEN out.lib_log := 'Schema ref déjà créés';RETURN next out;ELSE CREATE SCHEMA "ref"; out.lib_log := 'Schéma ref créés';RETURN next out;END CASE;
	--- Tables
	FOR libTable IN EXECUTE 'SELECT nom_ref FROM ref.aa_meta GROUP BY nom_ref'
		LOOP 
		EXECUTE 'SELECT DISTINCT 1 FROM pg_tables WHERE schemaname = ''ref'' AND tablename = '''||libTable||''';' INTO flag2;
		EXECUTE 'SELECT CASE WHEN libelle = ''virgule'' THEN '','' WHEN libelle = ''tab'' THEN ''\t'' WHEN libelle = ''point_virgule'' THEN '';'' ELSE '';'' END as delimiter FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''delimiter''' INTO delimitr;
		CASE WHEN flag2 = 1 THEN
			EXECUTE 'TRUNCATE ref.'||libTable;
			EXECUTE 'COPY ref.'||libTable||' FROM '''||path||'ref_'||libTable||'.csv'' HEADER CSV DELIMITER E'''||delimitr||''' ENCODING ''UTF8'';';
			out.lib_log := 'Mise à jour de la table '||libTable;RETURN next out;
		ELSE out.lib_log := 'Les tables doivent être créée auparavant : SELECT * FROM hub_admin_ref(''create'',path)';RETURN next out;
		END CASE;
	END LOOP;

WHEN typAction = 'export_xml' THEN	--- Mise à jour
	--- Tables
	FOR libTable IN SELECT distinct cd_table FROM ref.fsd
	LOOP
	--- Partie temp
	EXECUTE 'COPY (SELECT
	''<?xml version="1.0" encoding="UTF-8"?><schema dbmsId="postgres_id">''||string_agg("XML",'''')||''</schema>'' FROM
	(
	SELECT xmlelement(name column, 
		xmlattributes('''' as "comment",'''' as "default",cd_champ as "label",255 as "length",cd_champ as "originalDbColumnName",'''' as "pattern",0 as "precision",
			false as "key",
			true as "nullable",
			''id_String'' as "talendType",
			''VARCHAR'' as "type")
	)::varchar as "XML"
	FROM ref.fsd a WHERE cd_table = '''||libTable||''' ORDER BY ordre_champ) as one)
	TO '''||path||'st_talend_temp_'||libTable||'_'||version||'.xml'' ENCODING ''UTF8'';';

	--- Partie propre
	EXECUTE 'COPY (SELECT
	''<?xml version="1.0" encoding="UTF-8"?><schema dbmsId="postgres_id">''||string_agg("XML",'''')||''</schema>'' FROM
	(
	SELECT xmlelement(name column, 
		xmlattributes('''' as "comment",'''' as "default",cd_champ as "label",255 as "length",cd_champ as "originalDbColumnName",'''' as "pattern",0 as "precision",
			CASE unicite WHEN ''Oui'' THEN true ELSE false END as "key",
			CASE unicite WHEN ''Oui'' THEN false ELSE true END as "nullable",
			CASE format WHEN  ''character varying'' THEN ''id_String'' WHEN ''float'' THEN ''id_Float'' WHEN ''date'' THEN ''id_Date'' WHEN ''integer'' THEN ''id_Integer'' WHEN ''boolean'' THEN ''id_Boolean'' ELSE format END as "talendType",
			CASE format WHEN  ''character varying'' THEN ''VARCHAR'' WHEN ''float'' THEN ''FLOAT8'' WHEN ''date'' THEN ''DATE'' WHEN ''integer'' THEN ''INT4'' WHEN ''boolean'' THEN ''BOOL'' ELSE format END as "type")
	)::varchar as "XML"
	FROM ref.fsd a WHERE cd_table = '''||libTable||''' ORDER BY ordre_champ) as one)
	TO '''||path||'/st_talend_'||libTable||'_'||version||'.xml'' ENCODING ''UTF8'';';
	out.lib_log := 'st_talend_'||libTable||'_'||version||'.xml exporté';RETURN next out;
	END LOOP;


ELSE out.lib_log := 'Action non reconnue';RETURN next out;
END CASE;

--- Log
PERFORM hub_log ('public', out); 
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_useradd
--- Description : Ajouter un utilisateur et lui donne les droits nécessaires
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_useradd(utilisateur varchar, mdp varchar, schma varchar = null, role varchar = 'lecteur') RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
declare db_nam varchar;
declare exist varchar;
declare listSchem varchar;
BEGIN
SELECT catalog_name INTO db_nam FROM information_schema.information_schema_catalog_name;
EXECUTE '
	CREATE USER "'||utilisateur||'" PASSWORD '''||mdp||''';
	GRANT CONNECT ON DATABASE '||db_nam||' TO "'||utilisateur||'" ;
';

--- Tables hub
FOR listSchem in SELECT DISTINCT table_schema FROM information_schema.tables WHERE table_schema <> 'pg_catalog' AND table_schema <> 'information_schema'
	LOOP
		EXECUTE 'GRANT USAGE ON SCHEMA "'||listSchem||'" TO "'||utilisateur||'";';
		CASE WHEN listSchem = schma AND role = 'gestionnaire' THEN
			EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "'||listSchem||'" TO "'||utilisateur||'";';
		ELSE EXECUTE 'GRANT SELECT ON ALL TABLES IN SCHEMA "'||listSchem||'" TO "'||utilisateur||'";';
		END CASE;
	END LOOP;

--- Tables zz_log
EXECUTE 'SELECT schema_name FROM information_schema.schemata WHERE schema_name = '''||schma||''';' INTO exist;
CASE WHEN exist IS NOT NULL AND role = 'lecteur' THEN
	EXECUTE '
		GRANT INSERT ON TABLE '||schma||'.zz_log TO "'||utilisateur||'";
		GRANT INSERT,DELETE ON TABLE '||schma||'.zz_log_liste_taxon TO "'||utilisateur||'";
		GRANT INSERT,DELETE ON TABLE '||schma||'.zz_log_liste_taxon_et_infra TO "'||utilisateur||'";
		';
	ELSE END CASE;

out.lib_log := utilisateur||' ajouté';out.lib_schema := 'public';out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_userdrop';out.nb_occurence := 1;SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log ('public', out);RETURN next out;
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_userdrop
--- Description : Supprime un utilisateur
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_userdrop(utilisateur varchar) RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE db_nam varchar;
DECLARE listSchem varchar;
BEGIN
SELECT catalog_name INTO db_nam FROM information_schema.information_schema_catalog_name;
EXECUTE '
	REVOKE ALL PRIVILEGES ON DATABASE '||db_nam||' FROM "'||utilisateur||'";
	---REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA "public" FROM "'||utilisateur||'";
	---REVOKE ALL PRIVILEGES ON SCHEMA "public" FROM "'||utilisateur||'";
	---REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA "ref" FROM "'||utilisateur||'";
	---REVOKE ALL PRIVILEGES ON SCHEMA "ref" FROM "'||utilisateur||'";
	';
FOR listSchem in SELECT DISTINCT table_schema FROM information_schema.tables WHERE table_schema != 'pg_catalog' AND table_schema != 'information_schema'
	LOOP
		EXECUTE '
		REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA "'||listSchem||'" FROM "'||utilisateur||'";
		REVOKE ALL PRIVILEGES ON SCHEMA "'||listSchem||'" FROM "'||utilisateur||'";
		';
	END LOOP;
EXECUTE 'DROP USER IF EXISTS "'||utilisateur||'";';
--- Output&Log
out.lib_log := utilisateur||' supprimé';out.lib_schema := 'public';out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_userdrop';out.nb_occurence := 1;SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log ('public', out);RETURN next out;
END;$BODY$LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_admin_refresh
--- Description : Pour mettre à jour la structure du FSD lors de changement benin (type de donnée, clé primaire)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_admin_refresh(libSchema varchar) RETURNS setof zz_log  AS 
$BODY$ 
DECLARE out zz_log%rowtype;
DECLARE libTable varchar;
DECLARE sch_from varchar;
DECLARE sch_to varchar;
BEGIN
EXECUTE '
SELECT * FROM hub_admin_clone('''||libSchema||'_''); 
';

sch_from = libSchema;
sch_to = libSchema||'_';

--- Pour les tables du FSD
FOR libTable IN SELECT DISTINCT cd_table FROM ref.fsd
	LOOP EXECUTE '
		INSERT INTO '||sch_to||'.'||libTable||' SELECT * FROM '||sch_from||'.'||libTable||';
		INSERT INTO '||sch_to||'.temp_'||libTable||' SELECT * FROM '||sch_from||'.temp_'||libTable||';
		';
	END LOOP;
--- Pour les logs
EXECUTE '
	INSERT INTO '||sch_to||'.zz_log SELECT * FROM '||sch_from||'.zz_log;
	INSERT INTO '||sch_to||'.zz_log_liste_taxon SELECT * FROM '||sch_from||'.zz_log_liste_taxon;
	INSERT INTO '||sch_to||'.zz_log_liste_taxon_et_infra SELECT * FROM '||sch_from||'.zz_log_liste_taxon_et_infra;
	';

--- Ajouter une partie pour remettre les droits nécessaires ==> information_schema.column_privileges

EXECUTE '
DROP SCHEMA '||sch_from||' CASCADE;
ALTER SCHEMA '||sch_to||' RENAME TO '||sch_from||';
';



--- Output&Log
out.lib_log := 'Refresh OK';out.lib_schema := libSchema;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_refresh';out.nb_occurence := 1;SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log (libSchema, out);RETURN next out;
END; $BODY$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
--- Fonction Data management 
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_add 
--- Description : Ajout de données (fonction utilisée par une autre fonction)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Attention listJdd null sur jdd erroné
CREATE OR REPLACE FUNCTION hub_add(schemaSource varchar,schemaDest varchar, tableSource varchar, tableDest varchar,jdd varchar, typAction varchar = 'diff') RETURNS setof zz_log  AS 
$BODY$  
DECLARE out zz_log%rowtype;
DECLARE metasource varchar;
DECLARE listJdd varchar;
DECLARE champRefa varchar; 
DECLARE champRefb varchar; 
DECLARE source varchar;
DECLARE destination varchar;
DECLARE compte integer;
DECLARE listeChamp1 varchar;
DECLARE listeChamp2 varchar; 
DECLARE libChamp varchar; 
DECLARE cmd varchar; 
DECLARE jointure varchar; 
DECLARE nothing varchar; 
BEGIN
--Variables
source := '"'||schemaSource||'"."'||tableSource||'"';
destination := '"'||schemaDest||'"."'||tableDest||'"';
--- Output&Log
out.lib_schema := schemaSource; out.lib_table := tableSource; out.lib_champ := '-'; out.typ_log := 'hub_add'; SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Commande
SELECT CASE WHEN substring(tableSource from 0 for 5) = 'temp' THEN 'temp_metadonnees' ELSE 'metadonnees' END INTO metasource;
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN 
	EXECUTE 'SELECT CASE WHEN string_agg(''''''''||cd_jdd||'''''''','','') IS NULL THEN ''''''vide'''''' ELSE string_agg(''''''''||cd_jdd||'''''''','','') END FROM "'||schemaSource||'"."'||metasource||'" WHERE typ_jdd = '''||jdd||''';' INTO listJdd;
ELSE listJdd := ''''||jdd||'''';
END CASE;

CASE WHEN typAction = 'push_total' OR typAction = 'push_diff' THEN
	EXECUTE 'SELECT string_agg(''a."''||column_name||''"::''||data_type,'','')  FROM information_schema.columns where table_name = '''||tableDest||''' AND table_schema = '''||schemaDest||''' ' INTO listeChamp1;
	EXECUTE 'SELECT string_agg(''"''||column_name||''"'','','')  FROM information_schema.columns where table_name = '''||tableSource||''' AND table_schema = '''||schemaSource||''' ' INTO listeChamp2;
ELSE SELECT 1 INTO nothing; END CASE;

CASE WHEN typAction = 'diff' OR typAction = 'diff_plus' OR typAction = 'push_diff' THEN
	EXECUTE 'SELECT string_agg(''a.''||cd_champ,''||'') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRefa;
	EXECUTE 'SELECT string_agg(''b.''||cd_champ||'' IS NULL'','' AND '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRefb;
	EXECUTE 'SELECT string_agg(''a."''||cd_champ||''" = b."''||cd_champ||''"'','' AND '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO jointure;
	EXECUTE 'SELECT count(DISTINCT '||champRefa||') FROM '||source||' a LEFT JOIN '||destination||' b ON '||jointure||' WHERE '||champRefb||' AND a.cd_jdd IN ('||listJdd||')' INTO compte;
ELSE SELECT 1 INTO nothing; END CASE;

CASE WHEN typAction = 'push_total' THEN --- CAS utilisé pour ajouter en masse.
	EXECUTE 'INSERT INTO '||destination||' ('||listeChamp2||') SELECT '||listeChamp1||' FROM '||source||' a WHERE cd_jdd IN ('||listJdd||')';
		out.nb_occurence := 'total'; out.lib_log := 'Remplacement : Jdd complet(s) ajouté(s)'; RETURN NEXT out; --- PERFORM hub_log (schemaSource, out);
WHEN typAction = 'push_diff' THEN --- CAS utilisé pour ajouter les différences
	--- Recherche des concepts (obsevation, jdd ou entite) présent dans la source et absent dans la destination
	CASE WHEN (compte > 0) THEN --- Si de nouveau concept sont succeptible d'être ajouté
		EXECUTE 'INSERT INTO '||destination||' ('||listeChamp2||') SELECT '||listeChamp1||' FROM '||source||' a LEFT JOIN '||destination||' b ON '||jointure||' WHERE '||champRefb||' AND a.cd_jdd IN ('||listJdd||')';
		out.nb_occurence := compte||' occurence(s)'; out.lib_log := 'Ajout de la différence : Concept(s) ajouté(s)'; RETURN NEXT out; ---PERFORM hub_log (schemaSource, out);
	ELSE out.nb_occurence := '-'; out.lib_log := 'Ajout de la différence : Aucune différence'; RETURN NEXT out; --- PERFORM hub_log (schemaSource, out);
	END CASE;	
WHEN typAction = 'diff' THEN --- CAS utilisé pour analyser les différences
	--- Recherche des concepts (obsevation, jdd ou entite) présent dans la source et absent dans la destination
	CASE WHEN (compte > 0) THEN --- Si de nouveau concept sont succeptible d'être ajouté
		out.nb_occurence := compte||' occurence(s)'; out.lib_log := 'Différence : concept à ajouter depuis '||tableSource||' vers '||tableDest; RETURN NEXT out; --- PERFORM hub_log (schemaSource, out);
	ELSE out.nb_occurence := '-'; out.lib_log := 'Aucune différence détectée'; RETURN NEXT out; ---PERFORM hub_log (schemaSource, out);
	END CASE;
WHEN typAction = 'diff_plus' THEN --- CAS utilisé pour analyser les différences en profondeur
	CASE WHEN (compte > 0) THEN
		cmd := 'SELECT '||champRefa||' FROM '||source||' a LEFT JOIN '||destination||' b ON '||jointure||' WHERE '||champRefb||' AND a.cd_jdd IN ('||listJdd||');';
		out.nb_occurence := compte||' ajout'; out.lib_log := cmd; RETURN NEXT out;
	ELSE out.nb_occurence := '-'; out.lib_log := 'Aucune différence détectée'; RETURN NEXT out;
	END CASE;
ELSE out.lib_champ := '-'; out.lib_log := 'ERREUR : sur champ action = '||typAction; RETURN NEXT out; ---PERFORM hub_log (schemaSource, out);
END CASE;	
END;$BODY$ LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_bilan
--- Description : Met à jour le bilan sur les données disponibles dans un schema
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_bilan(libSchema varchar) RETURNS setof zz_log  AS 
$BODY$
DECLARE out zz_log%rowtype;
BEGIN
--- Output&Log
out.lib_schema := libSchema;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_bilan';out.nb_occurence := '-'; SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Commandes
EXECUTE '
UPDATE public.bilan SET 
data_nb_releve = (SELECT count(*) FROM '||libSchema||'.releve),
data_nb_observation = (SELECT count(*) FROM '||libSchema||'.observation),
data_nb_taxon = (SELECT count(DISTINCT cd_ref) FROM '||libSchema||'.observation),
taxa_nb_taxon = (SELECT count(*) FROM '||libSchema||'.entite),
temp_data_nb_releve = (SELECT count(*) FROM '||libSchema||'.temp_releve),
temp_data_nb_observation = (SELECT count(*) FROM '||libSchema||'.temp_observation),
temp_data_nb_taxon = (SELECT count(DISTINCT cd_ref) FROM '||libSchema||'.temp_observation),
temp_taxa_nb_taxon = (SELECT count(*) FROM '||libSchema||'.temp_entite),
derniere_action = (SELECT typ_log||'' : ''||lib_log FROM '||libSchema||'.zz_log WHERE date_log = (SELECT max(date_log) FROM '||libSchema||'.zz_log) GROUP BY typ_log,lib_log,date_log LIMIT 1),
date_derniere_action = (SELECT max(date_log) FROM '||libSchema||'.zz_log)
WHERE lib_cbn = '''||libSchema||'''
	';
--- Output&Log
out.lib_log = 'bilan réalisé';
PERFORM hub_log (libSchema, out);RETURN NEXT out;
END; $BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_clear 
--- Description : Nettoyage simple des tables (partie temporaires ou propre)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_clear(libSchema varchar, jdd varchar, partie varchar = 'temp') RETURNS setof zz_log  AS 
$BODY$ BEGIN
EXECUTE 'SELECT * FROM hub_clear_plus('''||libSchema||''','''||libSchema||''','''||jdd||''','''||partie||''','''||partie||''');';
END; $BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_clear_plus 
--- Description : Nettoyage complexe des tables (partie temporaires ou propre)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_clear_plus(fromlibSchema varchar, tolibSchema varchar, jdd varchar, fromPartie varchar = 'temp', toPartie varchar = 'temp') RETURNS setof zz_log  AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE fromprefixe varchar;
DECLARE toprefixe varchar;
DECLARE metasource varchar;
DECLARE libTable varchar;
DECLARE listJdd varchar;
DECLARE typJdd varchar;
DECLARE blabal varchar;
BEGIN
--- Variables 
--- les jeux de données de référence à surpprimer
CASE WHEN fromPartie = 'temp' THEN fromprefixe = 'temp_'; WHEN fromPartie = 'propre' THEN fromprefixe = ''; ELSE END CASE;
--- Où les supprimer (permet de supprimer des jeu de données de la partie propre depuis la partie temporaire ==> intéressant pour l'agrégation).
CASE WHEN toPartie = 'temp' THEN toprefixe = 'temp_'; WHEN toPartie = 'propre' THEN toprefixe = ''; ELSE END CASE;
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN 
	EXECUTE 'SELECT CASE WHEN string_agg(''''''''||cd_jdd||'''''''','','') IS NULL THEN ''''''vide'''''' ELSE string_agg(''''''''||cd_jdd||'''''''','','') END FROM '||fromlibSchema||'.'||fromprefixe||'metadonnees WHERE typ_jdd = '''||jdd||''';' INTO listJdd;
	typJdd := jdd;
ELSE 
	listJdd := ''''||jdd||'''';
	EXECUTE 'SELECT typ_jdd FROM "'||fromlibSchema||'".temp_metadonnees WHERE cd_jdd = '''||jdd||''';' INTO typJdd;
END CASE;
--- Output&Log
out.lib_schema := tolibSchema;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_clear_plus';out.nb_occurence := '-'; SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Commandes
CASE WHEN listJdd <> 'vide' THEN
	FOR libTable IN EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta'';'
		LOOP 
		EXECUTE 'DELETE FROM '||tolibSchema||'.'||toprefixe||libTable||' WHERE cd_jdd IN ('||listJdd||');'; 
		END LOOP;
	---log---
	out.lib_log = jdd||' effacé de la partie '||toPartie;
WHEN listJdd = '''vide''' THEN out.lib_log = 'jdd vide '||jdd;
ELSE out.lib_log = 'ERREUR : mauvais typPartie : '||toPartie;
END CASE;
--- Output&Log
CASE WHEN fromlibSchema <> tolibSchema THEN
	PERFORM hub_log (fromlibSchema, out);RETURN NEXT out;
	PERFORM hub_log (tolibSchema, out);RETURN NEXT out;
ELSE
	PERFORM hub_log (fromlibSchema, out);RETURN NEXT out;
END CASE;

END; $BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_connect 
--- Description :  Copie du Hub vers un serveur distant
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_connect(hote varchar, port varchar,dbname varchar,utilisateur varchar,mdp varchar, jdd varchar, libSchema_from varchar, libSchema_to varchar) RETURNS setof zz_log  AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE connction varchar;
DECLARE libTable varchar;
DECLARE list_champ varchar;
DECLARE listJdd varchar;
DECLARE typJdd varchar;
DECLARE isvid varchar;
BEGIN
--- Variables
connction = 'hostaddr='||hote||' port='||port||' dbname='||dbname||' user='||utilisateur||' password='||mdp||'';
EXECUTE 'SELECT * FROM dblink_connect_u(''link'','''||connction||''');';

CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN    
   EXECUTE 'SELECT * FROM dblink_send_query(''link'',''SELECT CASE WHEN string_agg(''''''''''''''''''''''''||cd_jdd||'''''''''''''''''''''''','''','''') IS NULL THEN ''''vide'''' ELSE string_agg(''''''''''''''''''''''''||cd_jdd||'''''''''''''''''''''''','''','''') END FROM "'||libSchema_from||'".metadonnees WHERE typ_jdd = '''''||jdd||''''''');';
   EXECUTE 'SELECT * FROM dblink_get_result(''link'') as t1(listJdd varchar);' INTO listJdd;
   PERFORM dblink_disconnect('link');
   typJdd = jdd;
ELSE 
   listJdd := ''''''||jdd||'''''';
   EXECUTE 'SELECT * FROM dblink_send_query(''link'',''SELECT CASE WHEN typ_jdd IS NULL THEN ''''vide'''' ELSE typ_jdd END FROM "'||libSchema_from||'".metadonnees WHERE cd_jdd = '''''||jdd||''''''');';
   EXECUTE 'SELECT * FROM dblink_get_result(''link'') as t1(typJdd varchar);' INTO typJdd;
   PERFORM dblink_disconnect('link');
END CASE;

--- Commande
FOR libTable IN EXECUTE 'SELECT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta'' GROUP BY cd_table' 
	LOOP
	EXECUTE 'SELECT * FROM dblink_connect_u(''link'','''||connction||''');';
	EXECUTE 'SELECT string_agg(one.cd_champ||'' ''||one.format,'','') FROM (SELECT cd_champ, format FROM ref.fsd WHERE (typ_jdd = '''||typjdd||''' OR typ_jdd = ''meta'') AND cd_table = '''||libTable||''' ORDER BY ordre_champ) as one;' INTO list_champ;
	EXECUTE 'SELECT * from dblink_send_query(''link'',''SELECT * FROM '||libSchema_from||'.'||libTable||' WHERE cd_jdd IN ('||listJdd||')'');';
	EXECUTE 'INSERT INTO '||libSchema_to||'.temp_'||libTable||' SELECT * FROM dblink_get_result(''link'') as t1 ('||list_champ||');';
	PERFORM dblink_disconnect('link');
END LOOP;

--- Output&Log
out.lib_log := jdd||' importé';out.lib_schema := libSchema_to;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_connect';out.nb_occurence := 1;SELECT CURRENT_TIMESTAMP INTO out.date_log;
PERFORM hub_log (libSchema_to, out);RETURN next out;

END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_connect_ref
--- Description :  Mise à jour du référentiel FSD depuis un serveur distant
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_connect_ref(hote varchar, port varchar,dbname varchar,utilisateur varchar,mdp varchar,refPartie varchar = 'fsd') RETURNS setof zz_log  AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE connction varchar;
DECLARE flag integer;
DECLARE libTable varchar;
DECLARE structure varchar;
DECLARE bdlink_structure varchar;
BEGIN
--- Variables
connction = 'hostaddr='||hote||' port='||port||' dbname='||dbname||' user='||utilisateur||' password='||mdp||'';
--- Log
out.lib_schema := '-';out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_admin_ref';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;


--- Case all
CASE WHEN refPartie = 'all' THEN DROP SCHEMA IF EXISTS ref CASCADE; ELSE END CASE;

-- Création du schema ref
SELECT DISTINCT 1 INTO flag FROM pg_tables WHERE schemaname = 'ref';
CASE WHEN flag IS NULL THEN CREATE SCHEMA ref; ELSE END CASE;
-- Création et mise à jour de la meta-table référentiel
SELECT DISTINCT 1 INTO flag FROM pg_tables WHERE schemaname = 'ref' AND tablename = 'aa_meta';
CASE WHEN flag IS NULL THEN CREATE TABLE ref.aa_meta(id serial NOT NULL, nom_ref varchar, typ varchar, ordre integer, libelle varchar, format varchar, CONSTRAINT aa_meta_pk PRIMARY KEY(id)); ELSE END CASE;

TRUNCATE ref.aa_meta;
EXECUTE 'INSERT INTO ref.aa_meta SELECT * FROM dblink('''||connction||''', ''SELECT * FROM ref.aa_meta'') as t1 (id integer, nom_ref character varying, typ character varying, ordre integer, libelle character varying, format character varying)';

--- Les référentiels
FOR libTable IN EXECUTE 'SELECT nom_ref FROM ref.aa_meta GROUP BY nom_ref ORDER BY nom_ref'
	LOOP
	EXECUTE 'SELECT ''(''||champs||'',''||contrainte||'')''
		FROM (SELECT nom_ref, string_agg(libelle||'' ''||format,'','') as champs FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''champ'' GROUP BY nom_ref) as one
		JOIN (SELECT nom_ref, ''CONSTRAINT ''||nom_ref||''_pk PRIMARY KEY (''||libelle||'')'' as contrainte FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''cle_primaire'') as two ON one.nom_ref = two.nom_ref
		' INTO structure;
	EXECUTE 'SELECT string_agg(libelle||'' ''||format,'','') as champs 
		FROM (SELECT nom_ref, libelle,CASE WHEN format = ''serial NOT NULL'' OR format = ''serial'' THEN ''integer'' ELSE format END as format
		FROM ref.aa_meta WHERE nom_ref = '''||libTable||''' AND typ = ''champ'')AS one GROUP BY nom_ref
		' INTO bdlink_structure;

	CASE WHEN refPartie = 'all' OR refPartie = libTable THEN
		EXECUTE 'SELECT DISTINCT 1 FROM pg_tables WHERE schemaname = ''ref'' AND tablename = '''||libTable||''';' INTO flag ;
		CASE WHEN flag IS NULL THEN EXECUTE 'CREATE TABLE ref.'||libTable||' '||structure||';'; out.lib_log := libTable||' créée';RETURN next out; ELSE END CASE;
		EXECUTE 'TRUNCATE ref.'||libTable||';';
		
		EXECUTE 'INSERT INTO ref.'||libTable||' SELECT * FROM dblink('''||connction||''', ''SELECT * FROM ref.'||libTable||''') as t1 ('||bdlink_structure||')';
		out.lib_log := libTable||' : données importées';RETURN next out;
	ELSE END CASE;
END LOOP;

--- Output&Log
out.lib_log := 'ref mis à jour';out.lib_schema := 'ref';out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_connect_ref';out.nb_occurence := 1;SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log ('public', out);RETURN next out;
END;$BODY$ LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_del 
--- Description : Suppression de données (fonction utilisée par une autre fonction)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_del(schemaSource varchar,schemaDest varchar, tableSource varchar, tableDest varchar, jdd varchar, typAction varchar = 'diff') RETURNS setof zz_log  AS 
$BODY$  
DECLARE out zz_log%rowtype;
DECLARE metasource varchar;
DECLARE listJdd varchar;
DECLARE source varchar;
DECLARE destination varchar;
DECLARE champRef varchar;
DECLARE champRefb varchar;
DECLARE champRefc varchar;
DECLARE compte integer;
DECLARE jointure varchar;
DECLARE cmd varchar;
BEGIN
--Variable
SELECT CASE WHEN substring(tableSource from 0 for 5) = 'temp' THEN 'temp_metadonnees' ELSE 'metadonnees' END INTO metasource;
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN EXECUTE 'SELECT CASE WHEN string_agg(''''''''||cd_jdd||'''''''','','') IS NULL THEN ''''''vide'''''' ELSE string_agg(''''''''||cd_jdd||'''''''','','') END FROM "'||schemaSource||'"."'||metasource||'" WHERE typ_jdd = '''||jdd||''';' INTO listJdd;
ELSE listJdd := ''''||jdd||'''';END CASE;
source := '"'||schemaSource||'"."'||tableSource||'"';
destination := '"'||schemaDest||'"."'||tableDest||'"';
--- Output&Log
out.lib_schema := schemaSource; out.lib_table := tableSource; out.lib_champ := '-';out.typ_log := 'hub_del'; SELECT CURRENT_TIMESTAMP INTO out.date_log;

--- Commande
EXECUTE 'SELECT string_agg(''a."''||cd_champ||''" = b."''||cd_champ||''"'','' AND '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO jointure;
--- Recherche des concepts (obsevation, jdd ou entite) présent dans la partie propre et présent dans la partie temporaire
EXECUTE 'SELECT string_agg(''b.''||cd_champ,''||'') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRef;
EXECUTE 'SELECT string_agg('' b.''||cd_champ||'' = b.''||cd_champ,'' AND '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRefb;
EXECUTE 'SELECT string_agg(''a.''||cd_champ||'' IS NULL'','' AND '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRefc;
EXECUTE 'SELECT count(DISTINCT '||champRef||') FROM '||source||' b LEFT JOIN '||destination||' a ON '||jointure||' WHERE b.cd_jdd IN ('||listJdd||')' INTO compte; 
	
CASE WHEN (compte > 0) THEN --- Si de nouveau concept sont succeptible d'être ajouté
	out.nb_occurence := compte||' occurence(s)'; ---log
	CASE WHEN typAction = 'push_diff' THEN
		EXECUTE 'DELETE FROM '||destination||' as a USING '||source||' as b WHERE '||champRefb||' AND b.cd_jdd IN ('||listJdd||')';
		---cmd = 'DELETE FROM '||destination||' USING '||source||' as b WHERE '||champRefb||' AND b.cd_jdd IN ('||listJdd||')';
		out.nb_occurence := compte||' occurence(s)';out.lib_log := 'Concepts supprimés'; RETURN NEXT out; ---PERFORM hub_log (schemaSource, out);
		---out.nb_occurence := compte||' occurence(s)';out.lib_log := cmd; RETURN NEXT out; ---PERFORM hub_log (schemaSource, out);
	WHEN typAction = 'diff' THEN
		out.nb_occurence := compte||' occurence(s)';out.lib_log := 'Points communs'; PERFORM hub_log (schemaSource, out);RETURN NEXT out;
	WHEN typAction = 'diff_plus' THEN
		CASE WHEN (compte > 0) THEN
		cmd := 'SELECT '||champRef||' FROM '||source||' a RIGHT JOIN '||destination||' b ON '||jointure||' WHERE '||champRefc||' AND a.cd_jdd IN ('||listJdd||');';
		out.nb_occurence := compte||' suppression'; out.lib_log := cmd; RETURN NEXT out;
	ELSE out.nb_occurence := '-'; out.lib_log := 'Aucune différence détectée'; RETURN NEXT out;
	END CASE;
	ELSE out.nb_occurence := compte||' occurence(s)'; out.lib_log := 'ERREUR : sur champ action = '||typAction; RETURN NEXT out; ---PERFORM hub_log (schemaSource, out);
	END CASE;
ELSE out.lib_log := 'Aucune différence';out.nb_occurence := '-'; RETURN NEXT out; --- PERFORM hub_log (schemaSource, out); 
END CASE;	
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_diff 
--- Description : Analyse des différences entre une source et une cible
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_diff(libSchema varchar, jdd varchar,typAction varchar = 'add',mode integer = 1) RETURNS setof zz_log  AS 
$BODY$ 
DECLARE out zz_log%rowtype;
DECLARE flag integer;
DECLARE ct integer;
DECLARE ct2 integer;
DECLARE typJdd varchar;
DECLARE cmd varchar;
DECLARE libTable varchar;
DECLARE tableSource varchar;
DECLARE tableDest varchar;
DECLARE schemaSource varchar;
DECLARE schemaDest varchar;
DECLARE tableRef varchar;
DECLARE nothing varchar;
BEGIN
--- Output&Log
out.lib_schema := schemaSource; 
--- Variables
ct =0; ct2=0;
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN  typJdd := jdd; flag := 1;
ELSE EXECUTE 'SELECT typ_jdd FROM "'||libSchema||'".temp_metadonnees WHERE cd_jdd = '''||jdd||''';' INTO typJdd;
	CASE WHEN typJdd = 'data' OR typJdd = 'taxa' THEN flag := 1; ELSE flag := 0; END CASE;
END CASE;
--- mode 1 = intra Shema / mode 2 = entre shema et agregation
CASE WHEN mode = 1 THEN schemaSource :=libSchema; schemaDest :=libSchema; WHEN mode = 2 THEN schemaSource :=libSchema; schemaDest :='agregation'; ELSE flag :=0; END CASE;
--- Commandes
CASE WHEN typAction = 'add' AND flag = 1 THEN
	--- Données et metadonnées
	FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta'' ORDER BY cd_table;' LOOP 
		ct = ct +1;
		CASE WHEN mode = 1 THEN tableSource := 'temp_'||libTable; tableDest := libTable; WHEN mode = 2 THEN tableSource := libTable; tableDest := 'temp_'||libTable; END CASE;
		SELECT * INTO out FROM  hub_add(schemaSource,schemaDest, tableSource, tableDest , jdd,'diff'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out);ELSE ct2 = ct2 +1; END CASE;
		SELECT * INTO out FROM  hub_update(schemaSource,schemaDest, tableSource, tableDest , jdd,'diff'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out);ELSE ct2 = ct2 +1; END CASE;
		SELECT * INTO out FROM  hub_add(schemaDest,schemaSource, tableDest, tableSource , jdd,'diff'); --- sens inverse (champ présent dans le propre et absent dans le temporaire)
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out);ELSE ct2 = ct2 +1; END CASE;
	END LOOP;
	ct2 = ct2/3;
WHEN typAction = 'del' AND flag = 1 THEN
	--- Données et métadonnées
	FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta'' ORDER BY cd_table;' LOOP 
		ct = ct +1;
		CASE WHEN mode = 1 THEN tableSource := 'temp_'||libTable; tableDest := libTable; WHEN mode = 2 THEN tableSource := libTable; tableDest := 'temp_'||libTable; END CASE;
		SELECT * INTO out FROM  hub_del(schemaSource,schemaDest, tableSource, tableDest , jdd,'diff'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out);ELSE ct2 = ct2 +1; END CASE;
	END LOOP;
WHEN typAction = 'diff_plus' AND flag = 1 THEN
	FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta'' ORDER BY cd_table;' LOOP 
		ct = ct +1;
		CASE WHEN mode = 1 THEN tableSource := 'temp_'||libTable; tableDest := libTable; WHEN mode = 2 THEN tableSource := libTable; tableDest := 'temp_'||libTable; END CASE;
		SELECT * INTO out FROM  hub_add(schemaSource,schemaDest, tableSource, tableDest , jdd,'diff_plus'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; ELSE ct2 = ct2 +1; END CASE;
		SELECT * INTO out FROM  hub_update(schemaSource,schemaDest, tableSource, tableDest , jdd,'diff_plus'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; ELSE ct2 = ct2 +1; END CASE;
		SELECT * INTO out FROM  hub_add(schemaDest,schemaSource, tableDest, tableSource , jdd,'diff_plus'); --- sens inverse (champ présent dans le propre et absent dans le temporaire)
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; ELSE ct2 = ct2 +1; END CASE;
	END LOOP;
	ct2 = ct2/3;	
ELSE out.lib_table := libTable; out.lib_log := jdd||' n''est pas un jeu de données valide'; out.nb_occurence := '-'; PERFORM hub_log (libSchema, out);RETURN NEXT out;
END CASE;

--- Last log
out.typ_log := 'hub_diff'; SELECT CURRENT_TIMESTAMP INTO out.date_log; out.lib_table := '-'; out.lib_champ := '-'; out.nb_occurence := ct||' tables analysées';
CASE WHEN ct = ct2 AND typAction = 'del' THEN out.lib_log := 'Aucun point commun sur le jdd '||jdd;  
	WHEN ct <> ct2 AND typAction = 'del' THEN out.lib_log := 'Des points communs sont présents - jdd '||jdd; 
	WHEN ct = ct2 AND typAction = 'add' THEN out.lib_log := 'Aucune différence sur le jdd '||jdd;
	WHEN ct <> ct2 AND typAction = 'add' THEN out.lib_log := 'Des différences sont présentes - jdd '||jdd;
	WHEN ct = ct2 AND typAction = 'diff_plus' THEN out.lib_log := 'Aucune différence sur le jdd '||jdd;
	WHEN ct <> ct2 AND typAction = 'diff_plus' THEN out.lib_log := 'Des différences sont présentes - jdd '||jdd;
	ELSE SELECT 1 INTO  nothing; END CASE;
PERFORM hub_log (libSchema, out);RETURN NEXT out; 
END;$BODY$ LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_export 
--- Description : Exporter les données depuis un hub
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_export(libSchema varchar,jdd varchar,path varchar,format varchar = 'fcbn',source varchar = '') RETURNS setof zz_log  AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE libTable varchar;
DECLARE typJdd varchar; 
DECLARE listJdd varchar; 
BEGIN
--- Variables Jdd
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN 	
	typJdd := 'WHERE typ_jdd = '''||jdd||''' OR typ_jdd = ''meta''';
	EXECUTE 'SELECT CASE WHEN string_agg(''''''''||cd_jdd||'''''''','','') IS NULL THEN ''''''vide'''''' ELSE string_agg(''''''''||cd_jdd||'''''''','','') END FROM "'||libSchema||'"."temp_metadonnees" WHERE typ_jdd = '''||jdd||''';' INTO listJdd;
	listJdd := 'WHERE cd_jdd IN ('||listJdd||')';
WHEN jdd = 'all' THEN 
	typJdd := ''; listJdd = '';
WHEN jdd = 'list_taxon' THEN 
	format = 'list_taxon';
ELSE
	EXECUTE 'SELECT typ_jdd FROM "'||libSchema||'".temp_metadonnees WHERE cd_jdd = '''||jdd||''';' INTO typJdd;
	typJdd := 'WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta''';
	listJdd := 'WHERE cd_jdd IN ('''||jdd||''')';
END CASE;
CASE WHEN source = 'temp' THEN source = 'temp_'; ELSE END CASE;
--- Output&Log
out.lib_schema := libSchema;out.lib_table := '-';out.lib_champ := '-';out.typ_log := 'hub_export';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Commandes
CASE WHEN format = 'fcbn' THEN
	FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd '||typJdd||''
		LOOP EXECUTE 'COPY (SELECT * FROM  '||libSchema||'.'||source||libTable||' '||listJdd||') TO '''||path||'std_'||libTable||'.csv'' HEADER CSV DELIMITER '';'' ENCODING ''UTF8'';'; END LOOP;
	out.lib_log :=  'Tous les jdd ont été exporté au format '||format;
WHEN format = 'sinp' THEN
	out.lib_log :=  'format SINP à implémenter';
WHEN format = 'list_taxon' THEN
	EXECUTE 'COPY (SELECT * FROM  '||libSchema||'.'||source||libTable||') TO '''||path||'std_zz_log_liste_taxon.csv'' HEADER CSV DELIMITER '';'' ENCODING ''UTF8'';';
	EXECUTE 'COPY (SELECT * FROM  '||libSchema||'.'||source||libTable||') TO '''||path||'std_zz_log_liste_taxon_et_infra.csv'' HEADER CSV DELIMITER '';'' ENCODING ''UTF8'';';
	out.lib_log :=  'Liste de taxon exporté ';
ELSE out.lib_log :=  'format ('||format||') non implémenté ou jdd ('||jdd||') mauvais';
END CASE;
PERFORM hub_log (libSchema, out);RETURN NEXT out;
END; $BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_idperm 
--- Description : Production des identifiants uniques
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_idperm(libSchema varchar, nomDomaine varchar, champ_perm varchar, jdd varchar = 'all', rempla boolean = false) RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE flag integer;
DECLARE cpt1 integer;
DECLARE cpt2 integer;
DECLARE champMere varchar;
DECLARE typ_jdd varchar;
DECLARE typ_ref varchar;
DECLARE wherejdd varchar;
DECLARE jeudedonnee varchar;
DECLARE tableRef varchar;
DECLARE listTable varchar;
DECLARE listPerm varchar;
BEGIN
--- Variables
CASE WHEN jdd = 'all' THEN wherejdd = '';  WHEN jdd = 'data' OR  jdd = 'taxa' THEN wherejdd = 'WHERE typ_jdd = '''||jdd||'''';ELSE wherejdd = 'WHERE cd_jdd = '''||jdd||''''; END CASE;
CASE 	WHEN champ_perm = 'cd_jdd_perm' 	THEN champMere = 'cd_jdd';	tableRef = 'temp_metadonnees'; 	typ_ref = 'all';	flag = 1;
	WHEN champ_perm = 'cd_ent_perm' 	THEN champMere = 'cd_ent_mere';	tableRef = 'temp_entite'; 	typ_ref = 'taxa';	flag = 1;
	WHEN champ_perm = 'cd_releve_perm' 	THEN champMere = 'cd_releve';	tableRef = 'temp_releve'; 	typ_ref = 'data';	flag = 1;
	WHEN champ_perm = 'cd_obs_perm' 	THEN champMere = 'cd_obs_mere';	tableRef = 'temp_observation'; 	typ_ref = 'data';	flag = 1;
	ELSE out.lib_log := 'ERREUR : Mauvais champ_perm';out.lib_table := '-'; PERFORM hub_log (libSchema, out); RETURN next out;flag = 1;
END CASE;
cpt1 = 0;cpt2 = 0;
--- Output
out.lib_schema := libSchema;out.lib_table := tableRef;out.lib_champ := champ_perm;out.typ_log := 'hub_idperm'; SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Commandes
FOR jeudedonnee IN EXECUTE 'SELECT CASE WHEN cd_jdd IS NULL THEN ''vide'' ELSE cd_jdd END as cd_jdd FROM '||libSchema||'.temp_metadonnees '||wherejdd||';'
	LOOP
	EXECUTE 'SELECT CASE WHEN typ_jdd IS NULL THEN ''vide'' ELSE typ_jdd END as typ_jdd FROM '||libSchema||'.temp_metadonnees WHERE cd_jdd = '''||jeudedonnee||''';' INTO typ_jdd;
	--- On vide les champ perm pour remplacer	
	CASE WHEN rempla = TRUE THEN EXECUTE 'UPDATE '||libSchema||'.'||tableRef||' ot SET '||champ_perm||' = ''a'' WHERE cd_jdd = '''||jeudedonnee||''';'; ELSE END CASE;
	--- CASE WHEN rempla = TRUE THEN EXECUTE 'UPDATE '||libSchema||'.'||tableRef||' ot SET '||champ_perm||' = NULL WHERE cd_jdd = '''||jeudedonnee||''';'; ELSE END CASE;
	CASE WHEN flag = 1 AND (typ_jdd = typ_ref OR champ_perm = 'cd_jdd_perm')THEN 
		FOR listPerm IN EXECUTE 'SELECT DISTINCT '||champMere||' FROM '||libSchema||'.'||tableRef||' ot WHERE cd_jdd = '''||jeudedonnee||''' AND '||champ_perm||' = ''a'';' 
		--- FOR listPerm IN EXECUTE 'SELECT DISTINCT '||champMere||' FROM '||libSchema||'.'||tableRef||' ot WHERE cd_jdd = '''||jeudedonnee||''' AND '||champ_perm||' IS NULL;'
			LOOP 
			EXECUTE 'UPDATE '||libSchema||'.'||tableRef||' ot SET '||champ_perm||' = NULL WHERE '||champMere||' = '''||listPerm||''' AND cd_jdd = '''||jeudedonnee||'''';
			EXECUTE 'UPDATE '||libSchema||'.'||tableRef||' ot SET '||champ_perm||' = ('''||nomdomaine||'/'||champ_perm||'/''||(SELECT uuid_generate_v4())) WHERE '||champ_perm||' IS NULL';
			--- EXECUTE 'UPDATE '||libSchema||'.'||tableRef||' ot SET ('||champ_perm||') = ('''||nomdomaine||'/'||champ_perm||'/''||(SELECT uuid_generate_v4())) WHERE '||champMere||' = '''||listPerm||''' AND cd_jdd = '''||jeudedonnee||''';';
			cpt1 = cpt1 + 1;
		END LOOP;	
		FOR listTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE cd_champ = '''||champ_perm||''''  --- Peuplement du nouvel idPermanent dans les autres tables
			LOOP 
			--- EXECUTE 'UPDATE '||libSchema||'.temp_'||listTable||' ot SET '||champ_perm||' = o.'||champ_perm||' FROM '||libSchema||'.'||tableRef||' o WHERE o.cd_jdd = ot.cd_jdd AND o.'||champMere||' = ot.'||champMere;
			cpt2 = cpt2 + 1;
		END LOOP;
	out.lib_log := 'id_permanent produit'; out.nb_occurence := cpt1||' identifiants'; PERFORM hub_log (libSchema, out); RETURN next out;
	out.lib_log := 'id_permanent propagé'; out.nb_occurence := cpt2||' tables concernées'; PERFORM hub_log (libSchema, out);RETURN next out;
	ELSE END CASE;
	END LOOP;
END; $BODY$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_import 
--- Description : Importer des données (fichiers CSV) dans un hub
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_import(libSchema varchar, jdd varchar, path varchar, rempla boolean = false, delimitr varchar = 'point_virgule', files varchar = '', champ varchar = '') RETURNS setof zz_log AS 
$BODY$
DECLARE typJdd varchar;
DECLARE listJdd varchar;
DECLARE libTable varchar;
--DECLARE delim_import varchar;
DECLARE out zz_log%rowtype;
BEGIN
--- Variable
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN 	
	typJdd := jdd;
	EXECUTE 'SELECT CASE WHEN string_agg(''''''''||cd_jdd||'''''''','','') IS NULL THEN ''''''vide'''''' ELSE string_agg(''''''''||cd_jdd||'''''''','','') END FROM "'||libSchema||'"."temp_metadonnees" WHERE typ_jdd = '''||jdd||''';' INTO listJdd;
ELSE
	EXECUTE 'SELECT typ_jdd FROM "'||libSchema||'".temp_metadonnees WHERE cd_jdd = '''||jdd||''';' INTO typJdd; 
	listJdd := ''''||jdd||'''';
END CASE;
--- delimitr
CASE WHEN delimitr = 'virgule' THEN delimitr = ''','''; WHEN delimitr = 'tab' THEN delimitr = 'E''\t'''; WHEN delimitr = 'point_virgule' THEN delimitr = ''';'''; ELSE delimitr = ''';'''; END CASE;
--- Commande
--- Cas du chargement de tous les jeux de données
CASE WHEN jdd = 'all' THEN 
	FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd;'
	LOOP 
		CASE WHEN rempla = TRUE THEN EXECUTE 'TRUNCATE "'||libSchema||'".temp_'||libTable||';';out.lib_log := ' Tous les fichiers ont été remplacé '; ELSE out.lib_log := ' Tous les fichiers ont été importé '; END CASE;
		EXECUTE 'COPY "'||libSchema||'".temp_'||libTable||' FROM '''||path||'std_'||libTable||'.csv'' HEADER CSV DELIMITER '||delimitr||' ENCODING ''UTF8'';'; 
	END LOOP;
--- Cas du chargement global (tous les fichiers)
WHEN files = '' THEN
	FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''' OR typ_jdd = ''meta'';'
	LOOP 
		CASE WHEN rempla = TRUE THEN EXECUTE 'DELETE FROM "'||libSchema||'".temp_'||libTable||' WHERE cd_jdd IN ('||listJdd||');'; ELSE PERFORM 1; END CASE;
		EXECUTE 'COPY "'||libSchema||'".temp_'||libTable||' FROM '''||path||'std_'||libTable||'.csv'' HEADER CSV DELIMITER '||delimitr||' ENCODING ''UTF8'';'; 
	END LOOP;
	CASE WHEN rempla = TRUE THEN out.lib_log := 'jdd '||jdd||' remplacé'; ELSE out.lib_log := 'jdd '||jdd||' ajouté';END CASE;
--- Cas du chargement spécifique (un seul fichier)
ELSE
	CASE WHEN rempla = TRUE THEN EXECUTE 'DELETE FROM "'||libSchema||'".temp_'||files||' WHERE cd_jdd IN ('||listJdd||');'; ELSE PERFORM 1; END CASE;
	EXECUTE 'COPY "'||libSchema||'".temp_'||files||' ('||champ||') FROM '''||path||'std_'||files||'.csv'' HEADER CSV DELIMITER '||delimitr||' ENCODING ''UTF8'';';
	CASE WHEN rempla = TRUE THEN out.lib_log := 'fichier std_'||files||'.csv remplacé'; ELSE out.lib_log := 'fichier std_'||files||'.csv ajouté'; END CASE;
END CASE;
--- WHEN jdd <> 'data' AND jdd <> 'taxa' AND files <> '' THEN 
--- 	CASE WHEN rempla = TRUE THEN EXECUTE 'DELETE FROM "'||libSchema||'".temp_'||files||' WHERE cd_jdd IN ('||listJdd||');'; out.lib_log := 'Fichier remplacé'; ELSE out.lib_log := 'Fichier ajouté'; END CASE;
--- 	EXECUTE 'COPY "'||libSchema||'".temp_'||files||' FROM '''||path||'std_'||files||'.csv'' HEADER CSV DELIMITER '||delimitr||' ENCODING ''UTF8'';';
--- ELSE out.lib_log := 'Problème identifié (Soit le jdd soit le fichier)'; END CASE;

--- Output&Log
out.lib_schema := libSchema;out.lib_champ := '-';out.lib_table := '-';out.typ_log := 'hub_import';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log (libSchema, out);RETURN next out;
END; $BODY$  LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_import_taxon 
--- Description : Importer une liste de taxon dans un hub
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_import_taxon(libSchema varchar, path varchar, files varchar) RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
BEGIN
--- Commande
CASE WHEN files <> '' THEN 
	EXECUTE 'TRUNCATE TABLE "'||libSchema||'".zz_log_liste_taxon; TRUNCATE TABLE "'||libSchema||'".zz_log_liste_taxon_et_infra;';
	EXECUTE 'COPY "'||libSchema||'".zz_log_liste_taxon FROM '''||path||files||''' HEADER CSV DELIMITER '';'' ENCODING ''UTF8'';';
	out.lib_log := files||' importé depuis '||path;
ELSE out.lib_log := 'Paramètre "files" incorrect'; END CASE;

--- Output&Log
out.lib_schema := libSchema;out.lib_champ := '-';out.lib_table := 'zz_log_liste_taxon';out.typ_log := 'hub_import_taxon';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log (libSchema, out);RETURN next out;
END; $BODY$  LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_txinfra 
--- Description : Générer une table avec les taxon infra depuis la table zz_log_liste_taxon
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_txinfra(libSchema varchar) RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE i varchar;
BEGIN
--- Commande
FOR i in EXECUTE 'select cd_ref from "'||libSchema||'".zz_log_liste_taxon' 
	LOOP  
	EXECUTE
		'INSERT INTO "'||libSchema||'".zz_log_liste_taxon_et_infra (cd_ref_demande, nom_valide_demande, cd_ref_cite, nom_complet_cite,cd_taxsup_cite,rang_cite)
		select '''||i||''' as cd_ref_demande, '''' as nom_valide_demande, foo.* from 
		(WITH RECURSIVE hierarchie(cd_nom,nom_complet, cd_taxsup, rang) AS (
		SELECT cd_nom, nom_complet, cd_taxsup, rang
		FROM ref.taxref_v5 t1
		WHERE t1.cd_nom = '''||i||''' AND t1.cd_nom = t1.cd_ref
		UNION
		SELECT t2.cd_nom, t2.nom_complet, t2.cd_taxsup, t2.rang
		FROM ref.taxref_v5 t2
		JOIN hierarchie h ON t2.cd_taxsup = h.cd_nom
		WHERE t2.cd_nom = t2.cd_ref
		) SELECT * FROM hierarchie) as foo';
	end loop;
EXECUTE 'update  "'||libSchema||'".zz_log_liste_taxon_et_infra set nom_valide_demande = nom_valide from "'||libSchema||'".zz_log_liste_taxon where zz_log_liste_taxon_et_infra.cd_ref_demande= zz_log_liste_taxon.cd_ref ' ;
out.lib_log := 'Liste de sous taxons générée';

--- Output&Log
out.lib_schema := libSchema;out.lib_champ := '-';out.lib_table := 'zz_log_liste_taxon_et_infra';out.typ_log := 'hub_txinfra';out.nb_occurence := 1; SELECT CURRENT_TIMESTAMP INTO out.date_log;PERFORM hub_log (libSchema, out);RETURN next out;
END; $BODY$  LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_pull 
--- Description : Récupération d'un jeu de données depuis la partie propre vers la partie temporaire
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_pull(libSchema varchar,jdd varchar, mode integer = 1) RETURNS setof zz_log AS 
$BODY$ 
DECLARE out zz_log%rowtype; 
DECLARE flag integer; 
DECLARE ct integer; 
DECLARE ct2 integer; 
DECLARE typJdd varchar; 
DECLARE libTable varchar; 
DECLARE schemaSource varchar; 
DECLARE schemaDest varchar; 
DECLARE tableSource varchar; 
DECLARE tableDest varchar; 
DECLARE champRef varchar; 
DECLARE tableRef varchar; 
DECLARE nothing varchar; 

BEGIN
--- Variables Jdd
CASE WHEN jdd = 'data' THEN champRef = 'cd_obs_perm'; tableRef = 'observation'; flag := 1;
	WHEN jdd = 'taxa' THEN champRef = 'cd_ent_perm';	tableRef = 'entite'; flag := 1;
	ELSE EXECUTE 'SELECT typ_jdd FROM "'||libSchema||'".temp_metadonnees WHERE cd_jdd = '''||jdd||''';' INTO typJdd;
		CASE WHEN typJdd = 'data' THEN champRef = 'cd_obs_perm'; tableRef = 'observation'; flag := 1;
			WHEN typJdd = 'taxa' THEN champRef = 'cd_ent_perm';	tableRef = 'entite'; flag := 1;
			ELSE flag := 0;
		END CASE;
	END CASE;
--- mode 1 = intra Shema / mode 2 = entre schema et agregation
CASE WHEN mode = 1 THEN schemaSource :=libSchema; schemaDest :=libSchema; WHEN mode = 2 THEN schemaSource :=libSchema; schemaDest :='agregation'; ELSE flag :=0; END CASE;

--- Commandes
--- Remplacement total (NB : equivalent au push 'replace' mais dans l'autre sens)
CASE WHEN flag = 1 THEN
	SELECT * INTO out FROM hub_clear(libSchema, jdd, 'temp'); return next out;
	FOR libTable in EXECUTE 'SELECT DISTINCT table_name FROM information_schema.tables WHERE table_name LIKE ''metadonnees%'' AND table_schema = '''||libSchema||''' ORDER BY table_name;' LOOP
		ct = ct+1;
		CASE WHEN mode = 1 THEN tableSource := libTable; tableDest := 'temp_'||libTable; WHEN mode = 2 THEN tableSource := 'temp_'||libTable; tableDest := libTable; END CASE;
		SELECT * INTO out FROM hub_add(schemaSource,schemaDest, tableSource, tableDest , jdd, 'push_total'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; ELSE ct2 = ct2+1; END CASE;
	END LOOP;
	FOR libTable in EXECUTE 'SELECT DISTINCT table_name FROM information_schema.tables WHERE table_name LIKE '''||tableRef||'%'' AND table_schema = '''||libSchema||''' ORDER BY table_name;' LOOP 
		ct = ct+1;
		CASE WHEN mode = 1 THEN tableSource := libTable; tableDest := 'temp_'||libTable; WHEN mode = 2 THEN tableSource := 'temp_'||libTable; tableDest := libTable; END CASE;
		SELECT * INTO out FROM hub_add(schemaSource,schemaDest, tableSource, tableDest , jdd, 'push_total'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; ELSE ct2 = ct2+1; END CASE;
	END LOOP;
ELSE ---Log
	out.lib_schema := libSchema; out.lib_champ := '-'; out.typ_log := 'hub_pull';SELECT CURRENT_TIMESTAMP INTO out.date_log; out.lib_log := 'ERREUR : sur champ jdd = '||jdd; PERFORM hub_log (libSchema, out);RETURN NEXT out;
END CASE;

---Log final
out.typ_log := 'hub_pull'; SELECT CURRENT_TIMESTAMP INTO out.date_log; out.lib_table := '-'; out.lib_champ := '-';
CASE 
WHEN (ct = ct2) THEN out.lib_log := 'Partie propre vide - jdd = '||jdd; out.nb_occurence := '-'; 
WHEN (ct <> ct2) THEN out.lib_log := 'Données tirées - jdd = '||jdd; out.nb_occurence := '-';
ELSE SELECT 1 into nothing; END CASE;
PERFORM hub_log (libSchema, out);RETURN NEXT out; 


END; $BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_push 
--- Description : Mise à jour des données (on pousse les données)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_push(libSchema varchar,jdd varchar, typAction varchar = 'replace', mode integer = 1) RETURNS setof zz_log AS 
$BODY$ 
DECLARE out zz_log%rowtype; 
DECLARE flag integer; 
DECLARE ct integer; 
DECLARE ct2 integer; 
DECLARE typJdd varchar; 
DECLARE libTable varchar; 
DECLARE schemaSource varchar; 
DECLARE schemaDest varchar; 
DECLARE tableSource varchar; 
DECLARE tableDest varchar; 
DECLARE nothing varchar; 

BEGIN
--- Variables Jdd
ct=0;ct2=0;
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN typJdd = jdd;
ELSE EXECUTE 'SELECT typ_jdd FROM "'||libSchema||'".temp_metadonnees WHERE cd_jdd = '''||jdd||''';' INTO typJdd;
END CASE;
--- mode 1 = intra Shema / mode 2 = entre shema et agregation
CASE WHEN mode = 1 THEN schemaSource :=libSchema; schemaDest :=libSchema; WHEN mode = 2 THEN schemaSource :=libSchema; schemaDest :='agregation'; ELSE flag :=0; END CASE;

--- Commandes
--- Remplacement total = hub_clear + hub_add
CASE WHEN typAction = 'replace' THEN
	CASE WHEN mode = 1 THEN SELECT * INTO out FROM hub_clear_plus(schemaSource,schemaDest, jdd, 'temp', 'propre'); WHEN mode = 2 THEN SELECT * INTO out FROM hub_clear_plus(schemaSource,schemaDest, jdd, 'propre', 'temp'); ELSE END CASE; return next out;
	FOR libTable IN EXECUTE 'SELECT cd_table FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' OR typ_jdd = ''meta'' GROUP BY cd_table' LOOP
		ct = ct+1;
		CASE WHEN mode = 1 THEN tableSource := 'temp_'||libTable; tableDest := libTable; WHEN mode = 2 THEN tableSource := libTable; tableDest := 'temp_'||libTable; END CASE;
		SELECT * INTO out FROM hub_add(schemaSource,schemaDest, tableSource, tableDest , jdd, 'push_total'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out); ELSE ct2 = ct2+1; END CASE;
	END LOOP;
--- Ajout de la différence = hub_add + hub_update sur meta et data/taxa
WHEN typAction = 'add' THEN
	FOR libTable IN EXECUTE 'SELECT cd_table FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' OR typ_jdd = ''meta'' GROUP BY cd_table' LOOP
		ct = ct+1;
		CASE WHEN mode = 1 THEN tableSource := 'temp_'||libTable; tableDest := libTable; WHEN mode = 2 THEN tableSource := libTable; tableDest := 'temp_'||libTable; END CASE;
		SELECT * INTO out FROM hub_add(schemaSource,schemaDest, tableSource, tableDest , jdd, 'push_diff'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out); ELSE ct2 = ct2+1; END CASE;
		SELECT * INTO out FROM hub_update(schemaSource,schemaDest, tableSource, tableDest , jdd, 'push_diff'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out); ELSE ct2 = ct2+1; END CASE;
	END LOOP;
	ct2 = ct2/2;
--- Suppression de l'existant depuis la partie temporaire = hub_del
WHEN typAction = 'del' THEN
	FOR libTable IN EXECUTE 'SELECT cd_table FROM ref.fsd WHERE typ_jdd = '''||typjdd||''' OR typ_jdd = ''meta'' GROUP BY cd_table' LOOP
		ct = ct+1;
		CASE WHEN mode = 1 THEN tableSource := 'temp_'||libTable; tableDest := libTable; WHEN mode = 2 THEN tableSource := libTable; tableDest := 'temp_'||libTable; END CASE;
		SELECT * INTO out FROM hub_del(schemaSource,schemaDest, tableSource, tableDest , jdd, 'push_diff'); 
			CASE WHEN out.nb_occurence <> '-' THEN RETURN NEXT out; PERFORM hub_log (libSchema, out); ELSE ct2 = ct2+1; END CASE;
	END LOOP;
ELSE ---Log
	out.lib_schema := libSchema; out.lib_champ := '-'; out.typ_log := 'hub_push';SELECT CURRENT_TIMESTAMP INTO out.date_log; out.lib_log := 'ERREUR : sur champ action = '||jdd; PERFORM hub_log (libSchema, out);RETURN NEXT out;
END CASE;

---Log final
out.typ_log := 'hub_push'; SELECT CURRENT_TIMESTAMP INTO out.date_log; out.lib_table := '-'; out.lib_champ := '-';
CASE 
WHEN (ct = ct2) AND typAction = 'replace' THEN out.lib_log := 'Partie temporaire vide - jdd = '||jdd; out.nb_occurence := jdd; 
WHEN (ct <> ct2) AND typAction = 'replace' THEN out.lib_log := 'Données poussées - jdd = '||jdd; out.nb_occurence := jdd;
WHEN (ct = ct2) AND typAction = 'add' THEN out.lib_log := 'Aucune modification à apporter à la partie propre - jdd = '||jdd; out.nb_occurence := jdd; 
WHEN (ct <> ct2) AND typAction = 'add' THEN out.lib_log := 'Modification apportées à la partie propre - jdd = '||jdd; out.nb_occurence := jdd;
WHEN (ct = ct2) AND typAction = 'del' THEN out.lib_log := 'Aucun point commun entre les partie propre et temporaire - jdd = '||jdd; out.nb_occurence := jdd; 
WHEN (ct <> ct2) AND typAction = 'del' THEN out.lib_log := 'Partie temporaire nettoyée - jdd = '||jdd; out.nb_occurence := jdd;
ELSE SELECT 1 into nothing; END CASE;
PERFORM hub_log (libSchema, out);RETURN NEXT out; 

END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_update 
--- Description : Mise à jour de données (fonction utilisée par une autre fonction)
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_update(schemaSource varchar,schemaDest varchar, tableSource varchar, tableDest varchar, jdd varchar, typAction varchar = 'diff') RETURNS setof zz_log  AS 
$BODY$  
DECLARE out zz_log%rowtype; 
DECLARE metasource varchar; 
DECLARE listJdd varchar; 
DECLARE cmd varchar; 
DECLARE champRef varchar; 
DECLARE champRef_guillement varchar; 
DECLARE source varchar; 
DECLARE destination varchar; 
DECLARE flag integer; 
DECLARE compte integer;
DECLARE listeChamp varchar;
DECLARE libChamp varchar;
DECLARE val varchar;
DECLARE wheres varchar;
DECLARE jointure varchar;
BEGIN
--Variable
SELECT CASE WHEN substring(tableSource from 0 for 5) = 'temp' THEN 'temp_metadonnees' ELSE 'metadonnees' END INTO metasource;
CASE WHEN jdd = 'data' OR jdd = 'taxa' THEN EXECUTE 'SELECT CASE WHEN string_agg(''''''''||cd_jdd||'''''''','','') IS NULL THEN ''''''vide'''''' ELSE string_agg(''''''''||cd_jdd||'''''''','','') END FROM "'||schemaSource||'"."'||metasource||'" WHERE typ_jdd = '''||jdd||''';' INTO listJdd;
ELSE listJdd := ''''||jdd||'''';END CASE;
source := '"'||schemaSource||'"."'||tableSource||'"';
destination := '"'||schemaDest||'"."'||tableDest||'"';
--- Output
out.lib_schema := schemaSource; out.lib_table := tableSource; out.lib_champ := '-'; out.typ_log := 'hub_update';SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Commande
EXECUTE 'SELECT string_agg(''a."''||cd_champ||''" = b."''||cd_champ||''"'','' AND '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO jointure;
EXECUTE 'SELECT string_agg(''''''''||cd_champ||'''''''','', '') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRef_guillement;
EXECUTE 'SELECT string_agg(''a.''||cd_champ,''||'') FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') AND unicite = ''Oui''' INTO champRef;
EXECUTE 'SELECT string_agg(''"''||column_name||''" = b."''||column_name||''"::''||data_type,'','')  FROM information_schema.columns WHERE table_name = '''||tableDest||''' AND table_schema = '''||schemaDest||''' AND column_name NOT IN ('||champRef_guillement||')' INTO listeChamp;
EXECUTE 'SELECT string_agg(''a."''||column_name||''"::varchar <> b."''||column_name||''"::varchar'','' OR '')  FROM information_schema.columns where table_name = '''||tableSource||''' AND table_schema = '''||schemaSource||''' AND column_name NOT IN ('||champRef_guillement||')' INTO wheres;
EXECUTE 'SELECT count(DISTINCT '||champRef||') FROM '||source||' a JOIN '||destination||' b ON '||jointure||' WHERE a.cd_jdd IN ('||listJdd||') AND ('||wheres||');' INTO compte;

CASE WHEN (compte > 0) THEN
	CASE WHEN typAction = 'push_diff' THEN
		---EXECUTE 'SELECT string_agg(''''''''||b."'||champRef||'"||'''''''','','') FROM '||source||' a JOIN '||destination||' b ON '||jointure||' WHERE a.cd_jdd IN ('||listJdd||') AND ('||wheres||');' INTO val;
		EXECUTE 'UPDATE '||destination||' a SET '||listeChamp||' FROM (SELECT * FROM '||source||') b WHERE '||jointure||';';
		out.lib_table := tableSource; out.lib_log := 'Concept(s) modifié(s)'; out.nb_occurence := compte||' occurence(s)'; return next out; ---PERFORM hub_log (schemaSource, out);
	WHEN typAction = 'diff' THEN
		out.lib_log := 'Différences : concept(s) à modifier'; out.nb_occurence := compte||' occurence(s)';return next out; ---PERFORM hub_log (schemaSource, out); 
	WHEN typAction = 'diff_plus' THEN --- CaS utilisé pour analyser les différences en profondeur
	FOR libChamp IN EXECUTE 'SELECT cd_champ FROM ref.fsd WHERE (cd_table = '''||tableSource||''' OR cd_table = '''||tableDest||''') GROUP BY cd_champ'
		LOOP 
		EXECUTE 'SELECT count('||champRef||') FROM '||source||' a LEFT JOIN '||destination||' b ON '||jointure||' WHERE a.'||libChamp||'::varchar <> b.'||libChamp||'::varchar AND a.cd_jdd IN ('||listJdd||')' INTO compte;
		CASE WHEN (compte > 0) THEN
			cmd := 'SELECT '||champRef||', a.'||libChamp||', b.'||libChamp||' FROM '||source||' a LEFT JOIN '||destination||' b ON '||jointure||' WHERE a.'||libChamp||' <> b.'||libChamp||' AND a.cd_jdd IN ('||listJdd||');';
			out.nb_occurence := compte||' ajout'; out.lib_log := cmd; RETURN NEXT out;
		ELSE out.nb_occurence := '-'; out.lib_log := 'Aucune différence détectée'; RETURN NEXT out;
		END CASE;
	END LOOP;
	END CASE;

ELSE out.lib_log := 'Aucune différence'; out.nb_occurence := '-'; return next out; ---PERFORM hub_log (schemaSource, out);
END CASE;	
END;$BODY$ LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_verif 
--- Description : Vérification des données
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_verif(libSchema varchar, jdd varchar, typVerif varchar = 'all') RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE typJdd varchar;
DECLARE libTable varchar;
DECLARE libChamp varchar;
DECLARE typChamp varchar;
DECLARE val varchar;
DECLARE flag integer;
DECLARE compte integer;
BEGIN
--- Output
out.lib_schema := libSchema;out.typ_log := 'hub_verif';SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Variables
CASE WHEN jdd = 'data' OR jdd = 'taxa' OR jdd = 'meta' THEN typJdd := Jdd;
ELSE EXECUTE 'SELECT typ_jdd FROM "'||libSchema||'"."temp_metadonnees" WHERE cd_jdd = '''||jdd||'''' INTO typJdd;
END CASE;
out.lib_log = '';

--- Test concernant l'obligation
CASE WHEN (typVerif = 'obligation' OR typVerif = 'all') THEN
FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''''
LOOP		
	FOR libChamp in EXECUTE 'SELECT cd_champ FROM ref.fsd WHERE cd_table = '''||libTable||''' AND typ_jdd = '''||typJdd||''' AND obligation = ''Oui'''
	LOOP		
		compte := 0;
		EXECUTE 'SELECT count(*) FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" IS NULL' INTO compte;
		CASE WHEN (compte > 0) THEN
			--- log
			out.lib_table := libTable; out.lib_champ := libChamp;out.lib_log := 'Champ obligatoire non renseigné => SELECT * FROM hub_verif_plus('''||libSchema||''','''||libTable||''','''||libChamp||''',''obligation'');'; out.nb_occurence := compte||' champs vides'; return next out;
			out.lib_log := typJdd ||' : Champ obligatoire';PERFORM hub_log (libSchema, out);
		ELSE --- rien
		END CASE;
	END LOOP;
END LOOP;
ELSE --- rien
END CASE;

--- Test concernant le typage des champs
CASE WHEN (typVerif = 'type' OR typVerif = 'all') THEN
FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''''
	LOOP
	FOR libChamp in EXECUTE 'SELECT cd_champ FROM ref.fsd WHERE cd_table = '''||libTable||''' AND typ_jdd = '''||typJdd||''''
	LOOP	
		compte := 0;
		EXECUTE 'SELECT DISTINCT format FROM ref.fsd WHERE cd_champ = '''||libChamp||'''' INTO typChamp;
		IF (typChamp = 'int') THEN --- un entier
			EXECUTE 'SELECT count(*) FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^\d+$''' INTO compte;
		ELSIF (typChamp = 'float') THEN --- un float
			EXECUTE 'SELECT count(*) FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^\-?\d+\.\d+$''' INTO compte;
		ELSIF (typChamp = 'date') THEN --- une date
			EXECUTE 'SELECT count(*) FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^[1,2][0-9]{2}[0-9]\-[0,1][0-9]\-[0-3][0-9]$''' INTO compte;
		ELSIF (typChamp = 'boolean') THEN --- Boolean
			EXECUTE 'SELECT count(*) FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^t$'' AND "'||libChamp||'" !~ ''^f$''' INTO compte;
		ELSE --- le reste
			compte := 0;
		END IF;
		CASE WHEN (compte > 0) THEN
			--- log
			out.lib_table := libTable; out.lib_champ := libChamp;	out.lib_log := typChamp||' incorrecte => SELECT * FROM hub_verif_plus('''||libSchema||''','''||libTable||''','''||libChamp||''',''type'');'; out.nb_occurence := compte||' occurence(s)'; return next out;
			out.lib_log := typJdd ||' : '||typChamp||' incorrecte ';PERFORM hub_log (libSchema, out);
		ELSE --- rien
		END CASE;	
		END LOOP;
	END LOOP;
ELSE --- rien
END CASE;

--- Test concernant les doublon
CASE WHEN (typVerif = 'doublon' OR typVerif = 'all') THEN
FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''''
	LOOP
	FOR libChamp in EXECUTE 'SELECT string_agg(''"''||cd_champ||''"'',''||'') FROM ref.fsd WHERE cd_table = '''||libTable||''' AND unicite = ''Oui'' AND typ_jdd = '''||typJdd||''''
		LOOP	
		compte := 0;
		EXECUTE 'SELECT count('||libChamp||') FROM "'||libSchema||'"."temp_'||libTable||'" GROUP BY '||libChamp||' HAVING COUNT('||libChamp||') > 1' INTO compte;
		CASE WHEN (compte > 0) THEN
			--- log
			out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := 'doublon(s) => SELECT * FROM hub_verif_plus('''||libSchema||''','''||libTable||''','''||libChamp||''',''doublon'');'; out.nb_occurence := compte||' occurence(s)'; return next out;
			out.lib_log := typJdd ||' : doublon(s)';PERFORM hub_log (libSchema, out);			
		ELSE --- rien
		END CASE;
		END LOOP;
	END LOOP;
ELSE --- rien
END CASE;

--- Test concernant le vocbulaire controlé
CASE WHEN (typVerif = 'vocactrl' OR typVerif = 'all') THEN
FOR libTable in EXECUTE 'SELECT DISTINCT cd_table FROM ref.fsd WHERE typ_jdd = '''||typJdd||''''
	LOOP FOR libChamp in EXECUTE 'SELECT cd_champ FROM ref.fsd WHERE cd_table = '''||libTable||''' AND typ_jdd = '''||typJdd||''''
		LOOP EXECUTE 'SELECT DISTINCT 1 FROM ref.voca_ctrl WHERE cd_champ = '''||libChamp||''' ;' INTO flag;
		CASE WHEN flag = 1 THEN
			compte := 0;
			EXECUTE 'SELECT count("'||libChamp||'") FROM "'||libSchema||'"."temp_'||libTable||'" LEFT JOIN ref.voca_ctrl ON "'||libChamp||'" = code_valeur WHERE code_valeur IS NULL'  INTO compte;
			CASE WHEN (compte > 0) THEN
				--- log
				out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := 'Valeur(s) non listée(s) => SELECT * FROM hub_verif_plus('''||libSchema||''','''||libTable||''','''||libChamp||''',''vocactrl'');'; out.nb_occurence := compte||' occurence(s)'; return next out;
				out.lib_log := typJdd ||' : Valeur(s) non listée(s)';PERFORM hub_log (libSchema, out);
			ELSE --- rien
			END CASE;
		ELSE --- rien
		END CASE;
		END LOOP;
	END LOOP;
ELSE --- rien
END CASE;

--- Le 100%
CASE WHEN out.lib_log = '' THEN
	out.lib_table := '-'; out.lib_champ := typVerif; out.lib_log := jdd||' conformes pour '||typVerif; out.nb_occurence := '-'; PERFORM hub_log (libSchema, out); return next out;
ELSE ---Rien
END CASE;

END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_verif_plus
--- Description : Vérification des données
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_verif_plus(libSchema varchar, libTable varchar, libChamp varchar, typVerif varchar = 'all') RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
DECLARE champRefSelected varchar;
DECLARE champRef varchar;
DECLARE typChamp varchar;
DECLARE flag integer;
BEGIN
--- Output
out.lib_schema := libSchema;out.typ_log := 'hub_verif_plus';SELECT CURRENT_TIMESTAMP INTO out.date_log;
--- Variables
EXECUTE 'SELECT string_agg(cd_champ,''||'') FROM ref.fsd WHERE cd_table = '''||libTable||''' AND unicite = ''Oui'';' INTO champRef;

--- Test concernant l'obligation
CASE WHEN (typVerif = 'obligation' OR typVerif = 'all') THEN
FOR champRefSelected IN EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" IS NULL'
	LOOP out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out; END LOOP;
ELSE --- rien
END CASE;

--- Test concernant le typage des champs
CASE WHEN (typVerif = 'type' OR typVerif = 'all') THEN
	EXECUTE 'SELECT DISTINCT format FROM ref.fsd WHERE cd_champ = '''||libChamp||'''' INTO typChamp;
		IF (typChamp = 'int') THEN --- un entier
			FOR champRefSelected IN EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^\d+$''' 
			LOOP out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out;END LOOP;
		ELSIF (typChamp = 'float') THEN --- un float
			FOR champRefSelected IN EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^\-?\d+\.\d+$'''
			LOOP out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out;END LOOP;
		ELSIF (typChamp = 'date') THEN --- une date
			FOR champRefSelected IN EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^[1,2][0-9]{2}[0-9]\-[0,1][0-9]\-[0-3][0-9]$'' AND "'||libChamp||'" !~ ''^[1,2][0-9]{2}[0-9]\-[0,1][0-9]$'' AND "'||libChamp||'" !~ ''^[1,2][0-9]{2}[0-9]$'''
			LOOP out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out;END LOOP;
		ELSIF (typChamp = 'boolean') THEN --- Boolean
			FOR champRefSelected IN EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" WHERE "'||libChamp||'" !~ ''^t$'' AND "'||libChamp||'" !~ ''^f$'''
			LOOP out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out;END LOOP;
		ELSE --- le reste
			EXECUTE 'SELECT 1';
		END IF;
ELSE --- rien
END CASE;

--- Test concernant les doublon
CASE WHEN (typVerif = 'doublon' OR typVerif = 'all') THEN
	FOR champRefSelected IN EXECUTE 'SELECT '||libChamp||' FROM "'||libSchema||'"."temp_'||libTable||'" GROUP BY '||libChamp||' HAVING COUNT('||libChamp||') > 1'
		LOOP EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" WHERE '||libChamp||' = '''||champRefSelected||''';' INTO champRefSelected;
		out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out;END LOOP;
ELSE --- rien
END CASE;

--- Test concernant le vocbulaire controlé
CASE WHEN (typVerif = 'vocactrl' OR typVerif = 'all') THEN
	EXECUTE 'SELECT DISTINCT 1 FROM ref.voca_ctrl WHERE cd_champ = '''||libChamp||''' ;' INTO flag;
		CASE WHEN flag = 1 THEN
		FOR champRefSelected IN EXECUTE 'SELECT '||champRef||' FROM "'||libSchema||'"."temp_'||libTable||'" LEFT JOIN ref.voca_ctrl ON "'||libChamp||'" = code_valeur WHERE code_valeur IS NULL'
		LOOP out.lib_table := libTable; out.lib_champ := libChamp; out.lib_log := champRefSelected; out.nb_occurence := 'SELECT * FROM "'||libSchema||'"."temp_'||libTable||'" WHERE  '||champRef||' = '''||champRefSelected||''''; return next out; END LOOP;
	ELSE ---Rien
	END CASE;
ELSE --- rien
END CASE;

--- Log général
RETURN;END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_verif_all
--- Description : Chainage des vérification
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_verif_all(libSchema varchar) RETURNS setof zz_log AS 
$BODY$
DECLARE out zz_log%rowtype;
BEGIN
SELECT * into out FROM hub_verif(libSchema,'meta','all');return next out;
SELECT * into out FROM hub_verif(libSchema,'data','all');return next out;
SELECT * into out FROM hub_verif(libSchema,'taxa','all');return next out;
END;$BODY$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_help 
--- Description : Création de l'aide et Accéder à la description d'un fonction
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_help() RETURNS setof threecol AS 
$BODY$
DECLARE out threecol%rowtype;
DECLARE nom_fonction varchar;
DECLARE cmd varchar;
BEGIN
--- Variable

--- Commande
out.col1 := '-------------------------'; out.col2 := '-------------------------'; RETURN next out; 
out.col1 := ' Pour accéder à la description d''une fonction : ';
out.col2 := 'SELECT * FROM hub_help(''fonction'');';
RETURN next out;
out.col1 := ' Pour utiliser une fonction : '; 
out.col2 := 'SELECT * FROM fonction(''variables'');';
RETURN next out;
out.col1:= ' Liste des fonctions : ';
out.col2 = 'http://wiki.fcbn.fr/doku.php?id=outil:hub:fonction:liste;';
RETURN next out;
out.col1 := '-------------------------'; out.col2 := '-------------------------'; RETURN next out; 

FOR nom_fonction IN EXECUTE 'SELECT DISTINCT routine_name FROM information_schema.routines WHERE  routine_name LIKE ''hub_%'' ORDER BY routine_name'
LOOP 
	out.col1 := nom_fonction;
	cmd = 'SELECT routine_name||''(''||string_agg(parameter_name,'','')||'')'' FROM(
	SELECT routine_name, z.specific_name, z.parameter_name
	FROM information_schema.routines a
	JOIN information_schema.parameters z ON a.specific_name = z.specific_name
	WHERE  routine_name = '''||nom_fonction||'''
	ORDER BY routine_name,ordinal_position
	) as one
	GROUP BY routine_name, specific_name';

	EXECUTE cmd INTO out.col2;
	out.col3 := 'http://wiki.fcbn.fr/doku.php?id=outil:hub:fonction:'||nom_fonction;
	RETURN next out; 
   END LOOP;


END;$BODY$ LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_log
--- Description : ecrit les output dans le Log du schema et le log global
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_log (libSchema varchar, outp zz_log, action varchar = 'write') RETURNS void AS 
$BODY$ 
BEGIN
CASE WHEN action = 'write' THEN
	EXECUTE 'INSERT INTO "'||libSchema||'".zz_log (lib_schema,lib_table,lib_champ,typ_log,lib_log,nb_occurence,date_log) VALUES ('''||outp.lib_schema||''','''||outp.lib_table||''','''||outp.lib_champ||''','''||outp.typ_log||''','''||outp.lib_log||''','''||outp.nb_occurence||''','''||outp.date_log||''');';
	CASE WHEN libSchema <> 'public' THEN EXECUTE 'INSERT INTO "public".zz_log (lib_schema,lib_table,lib_champ,typ_log,lib_log,nb_occurence,date_log) VALUES ('''||outp.lib_schema||''','''||outp.lib_table||''','''||outp.lib_champ||''','''||outp.typ_log||''','''||outp.lib_log||''','''||outp.nb_occurence||''','''||outp.date_log||''');'; ELSE PERFORM 1; END CASE;
WHEN action = 'clear' THEN
	EXECUTE 'DELETE FROM "'||libSchema||'".zz_log';
ELSE SELECT 1;
END CASE;
END;$BODY$ LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- Nom : hub_runfc
--- Description : Lancer successivement une fonction pour chaque cbn
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hub_runfc() RETURNS varchar AS
$BODY$ 
DECLARE cbn varchar[];
DECLARE nb integer;
BEGIN
--- Liste des schema
cbn = ARRAY['als', 'alp', 'bal','bpa', 'bre', 'cor', 'frc','mas','mce','med','pmp','sat'];

--- Changer le nombre à chaque fois
-- nb = 1; -- 
-- nb = 2; -- 
-- nb = 3; -- 
-- nb = 4; -- 
-- nb = 5; -- 
-- nb = 6; --
-- nb = 7; --
-- nb = 8; --
-- nb = 9; --
-- nb = 10; --
-- nb = 11; --
-- nb = 12; --

--- Fonctions lancés
---PERFORM hub_push(''||cbn[nb]||'','data', 'replace', 2);
---PERFORM hub_push(''||cbn[nb]||'','taxa', 'replace', 2);

RETURN nb||'-'||cbn[nb];
END;$BODY$ LANGUAGE plpgsql;

--- SELECT hub_runfc();

---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
--- FIN : Affichage de la réinitialisation
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
INSERT INTO public.zz_log (lib_schema,lib_table,lib_champ,typ_log,lib_log,nb_occurence,date_log) 
VALUES ('public','-','-','hub_admin_init','Initialisation de hub.sql','1',CURRENT_TIMESTAMP);
SELECT * FROM public.zz_log ORDER BY date_log desc LIMIT 1;