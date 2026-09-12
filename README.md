# Loslo Dashboard — Swift pour Mac

Application macOS native et autonome, portée depuis le dashboard web Loslo. SwiftUI, Swift Charts, Liquid Glass et accès directs aux API. Aucun WebView, serveur localhost, Node.js ou abonnement supplémentaire nécessaire.

Le projet web d’origine est indépendant et n’est pas modifié.

## Lancer

Requis : **macOS 26 ou supérieur**, Xcode 26 ou supérieur.

Ouvrir `LosloDashboard.xcodeproj`, sélectionner le schéma **LosloDashboard**, destination **My Mac**, puis Run. Le script utilise le certificat Apple Development du Mac lorsqu’il est disponible, sinon une signature locale ad hoc. Dans Xcode, sélectionner son certificat pour conserver l’accès au Trousseau entre recompilations.

Pour créer et installer l’app :

```sh
./scripts/install.sh
```

L’application est copiée dans `~/Applications/Loslo Dashboard.app`. Un lancement depuis le Finder suffit ensuite ; aucun terminal ni site web n’est nécessaire. Cette version locale n’est pas notarisée pour une distribution à d’autres Macs.

## Connexions et copie des données

Ouvrir **Loslo Dashboard → Réglages…** (`⌘,`).

- Importer le dossier du dashboard web avec le bouton de migration, ou saisir les connexions séparément.
- L’import lit `.env.local`, la clé `.p8` référencée et les instantanés de `data/dashboard-cache`.
- Les secrets sont enregistrés exclusivement dans le **Trousseau macOS**, sous le service `com.loslo.dashboard.swift`, avec accès local à cet appareil.
- L’historique de la copie est stocké dans `~/Library/Application Support/Loslo Dashboard Swift`, avec permissions restreintes. Il n’entre jamais dans le dépôt ni dans l’app compilée.
- Les fichiers et clés de la version web ne sont ni réécrits, ni déplacés, ni supprimés.

**TikTok :** l’import reprend les chiffres et les vidéos sauvegardés, mais pas le refresh token du site. Ce token tourne lors de chaque renouvellement : le partager entre deux apps risquerait de déconnecter la version web. Pour une synchronisation TikTok autonome, importer une autorisation réservée à l’app dans Réglages (JSON contenant `accounts`, avec `open_id` et `refresh_token` pour chaque compte). La version actuelle ne crée pas cette autorisation via une fenêtre OAuth. Tant qu’elle n’est pas ajoutée, l’historique TikTok reste consultable et ce statut est indiqué dans Réglages.

Ce dépôt contient seulement le code et les ressources visuelles. **Ne pas y ajouter de clés, de fichiers `.env`, de tokens TikTok ou de données personnelles**, même en dépôt privé.

## Pages

- **Vue d’ensemble** : MRR, revenus, téléchargements, inscriptions ; graphiques séparés par unité et filtres des séries.
- **Revenus** : revenus quotidiens, cumul, MRR, abonnements actifs, essais, conversion par offre et revenus mensuels.
- **Téléchargements** : indicateurs de période, histogramme et cumul.
- **Utilisateurs** : inscriptions et points reliés par une ligne grise, cumul.
- **Géographie** : classement filtrable, répartition et globe rotatif dessiné en SwiftUI.
- **TikTok** : statistiques, vues par publication, nuage de points d’engagement, comptes, mois et tableau filtrable/triable/paginé.

Les courbes réagissent au survol ; les flèches gauche/droite parcourent les données du graphique sélectionné et Échap ferme l’infobulle. Les segments des camemberts se sélectionnent et leurs légendes réagissent au survol.

Les animations de chargement reprennent le reflet du dashboard web. Les préférences de réduction des animations sont respectées. Les polices locales Bricolage Grotesque et Hanken Grotesk conservent leurs licences OFL.

## Calculs et synchronisation

Périodes en UTC jusqu’à hier, limitées par la date de lancement. Les zéros avérés restent des zéros, les données absentes restent absentes. Les rapports Apple sont filtrés par identifiant d’application et premiers téléchargements ; l’archive conserve les rapports historiques. Une valeur cumulée s’arrête au premier jour manquant.

La formule du RPM TikTok est conservée : `(revenus + revenu attendu des essais en cours par offre) / vues × 1 000`. Le taux de conversion utilise uniquement les essais terminés. Les KPI TikTok et son RPM restent globaux comme dans la version web ; la période et le compte filtrent les graphiques et publications.

Synchronisation au lancement puis toutes les cinq minutes lorsque l’app est active ; `⌘R` la déclenche manuellement. En cas d’échec, les dernières données sauvegardées sont conservées et l’état de connexion est accessible dans Réglages. Les nouvelles données exigent une connexion Internet aux services correspondants.

## Développement

Sources dans `Sources/`, tests dans `Tests/`. Le fichier Xcode est inclus ; pour le régénérer après une modification de `project.yml`, utiliser `xcodegen generate`.

```sh
xcodebuild -project LosloDashboard.xcodeproj -scheme LosloDashboard \
  -destination 'platform=macOS' -derivedDataPath build test
```

Références Apple : [Liquid Glass en SwiftUI](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [Swift Charts et interaction](https://developer.apple.com/videos/play/wwdc2023/10037/).
