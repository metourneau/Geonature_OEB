Migration des données de GeoNature V1 vers V2
---------------------------------------------

La procédure consiste à aller chercher les données de GeoNature V1 en Foreign data wrapper pour ensuite les intégrer dans les tables de la BDD de GeoNature v2, fraichement installé (à côté ou sur un nouveau serveur).
Pré-requis : GeoNature 1.9.1 en place, à migrer vers 2.1.2. UsersHub et TaxHub avec leurs schémas de BDD à jour (UH 2.0.3 et TH 1.6.3).

- Copier et renommer le fichier ``migratetoV2.ini.sample`` en ``migratetoV2.ini``
- Renseigner le fichier ``migratetoV2.ini``
- Analyser le fichier ``migratetoV2.sh`` pour identifier les scripts SQL qu'il joue et leur ordre, 
  et analyser aussi ces derniers pour les comprendre, éventuellement les adapter
- Exécuter le fichier ``migratetoV2.sh``

La partie spécifique au PnEcrins est dans le répertoire ``my_organisme``, à adapter pour votre contexte.

**NB** : La personnalisation des métadonnées et notamment l'association des acteurs associés aux JDD et CA (indispensable pour les notions de droits) n'est pas prise en compte dans la migration. Un exemple est présent dans le script ``my_organisme/mymeta.sql``.
