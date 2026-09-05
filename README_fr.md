# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **Un remplaçant léger et au pixel près pour macOS Spotlight, conçu en pur Swift — conçu pour les développeurs et les utilisateurs expérimentés qui veulent une vitesse instantanée sans la lourdeur de l'indexation des fichiers.**

Lightspot reproduit fidèlement le design moderne en forme de pilule flottante et l'esthétique de verre translucide de macOS Spotlight (`NSVisualEffectView`). Sous le capot, il offre une réactivité inférieure à la milliseconde (< 1,0 ms de recherche) avec **zéro indexation de fichiers en arrière-plan**, consommant **0,0 % de CPU au repos** et moins de **25 Mo de RAM**.

---

## 💡 Pourquoi Lightspot ?

Spotlight intégré d'Apple a été conçu pour une recherche occasionnelle de fichiers. Mais pour les développeurs et les utilisateurs expérimentés, les processus d'arrière-plan de Spotlight créent souvent d'importants ralentissements du système. **Lightspot est conçu pour résoudre ce problème.**

### Le Problème : Apple Spotlight

1. **Épuisement du CPU et de la Batterie :** Les démons d'arrière-plan (`mds`, `mdworker`) indexent agressivement les fichiers. Un simple `npm install` ou `git checkout` peut saturer votre CPU à 100 %, faisant tourner les ventilateurs et ruinant la durée de vie de la batterie.
2. **Applications Manquantes :** L'index de Spotlight se corrompt fréquemment, le faisant échouer dans sa tâche la plus élémentaire : trouver des applications comme Terminal ou Slack. Pour le réparer, il faut exécuter des commandes `mdutil` obscures pour reconstruire l'index de zéro.
3. **Utilisation Disque Exagérée :** Spotlight met silencieusement en cache des métadonnées dans un dossier caché `/.Spotlight-V100`. Sur les machines de développeurs, cet index gonfle régulièrement à **50 Go – 200 Go**, gaspillant un stockage SSD coûteux.
4. **Accaparement de la Mémoire :** Les processus de Spotlight fuient fréquemment et consomment des gigaoctets de RAM unifiée — de la mémoire qui devrait être disponible pour votre IDE, Docker, ou des LLM locaux.
5. **Analyse de Fichiers Indésirable :** Exclure des dossiers massifs comme `node_modules`, `.git`, ou `.venv` via les Paramètres Système est notoirement maladroit, lent, et se réinitialise souvent lors des mises à jour de macOS.

*(Voir les retours de la communauté : [High CPU](https://www.reddit.com/r/MacOS/comments/1p10c3f/pages_caused_insane_cpu_spikes_on_macos_i_think_i/), [Missing Apps](https://www.reddit.com/r/MacOS/comments/1gjhiha/spotlight_not_looking_for_apps/), [Storage Waste](https://dev.to/vvo/how-to-avoid-spotlight-using-hundreds-of-gbs-and-rebuild-its-index-4kki), [Memory Leaks](https://discussions.apple.com/thread/256167358?sortBy=rank))*

---

## ⚡ La Solution : Architecture à Zéro-Indexation

Lightspot résout ces problèmes en adoptant une approche fondamentalement différente : **Zéro indexation de fichiers en arrière-plan.** 

Au lieu d'analyser agressivement l'intégralité de votre disque dur, Lightspot se concentre strictement sur ce que les utilisateurs expérimentés recherchent réellement : Applications, Projets IDE, Onglets de Navigateur, Utilitaires de Développement, et Commandes Personnalisées.

### Matrice de Comparaison

| Métrique | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **Indexation de Fichiers** | Analyse d'arrière-plan incontrôlée | Optionnelle / Configurable | **Jamais** (Par garantie architecturale) |
| **Utilisation CPU au Repos** | Pics à 100%+ durant les opérations | 1% – 5% en arrière-plan | **0,0%** (S'endort complètement) |
| **Stockage Disque** | 10 Go – 200 Go+ cache caché | 100 Mo – 1 Go | **0 Ko** (Zéro empreinte disque) |
| **Empreinte RAM** | 500 Mo – 2 Go+ | 200 Mo – 500 Mo | **~15 – 25 Mo** (Pur Swift) |
| **Lancement d'App** | Se casse fréquemment ; requiert des reconstructions | Fiable | **100% Fiable** (Analyse directe) |
| **Latence de Recherche** | Temporisée (50 – 200 ms) | 10 – 30 ms | **< 1,0 ms** (Synchrone instantané) |
| **Confidentialité Hors Ligne** | Envoie la télémétrie de Siri à Apple | Compte requis pour la synchro | **100% Local, Hors Ligne & Sans Télémétrie** |

---

## 🛠️ Personnalisation Orientée Développeur & Flux de Travail pour Utilisateurs Expérimentés

Lightspot a été conçu dès le départ comme le centre de commande principal d'un développeur. Chaque aspect peut être moulé selon vos besoins précis de terminal, d'éditeur, de script et de flux de travail :

### 1. ⚡ Commandes Personnalisées & Lanceurs de Scripts (`⌘⇧C`)
Ouvrez l'Éditeur interactif de Commandes Personnalisées avec **`⌘⇧C`** pour créer et organiser des raccourcis personnalisés :
- **4 Moteurs d'Exécution** :
  - `terminal` : Exécute la commande directement dans votre émulateur de terminal préféré.
  - `shell` : S'exécute de manière invisible en arrière-plan via `/bin/zsh`.
  - `applescript` : Exécute des automatisations natives macOS AppleScript.
  - `url` : Ouvre des URL modélisées dans votre navigateur par défaut.
- **Expansion Dynamique des Paramètres** :
  - Utilisez `{query}`, `%s`, ou `%@` pour remplacer les arguments que vous tapez après la commande.
- **Déclencheurs de Préfixes** :
  - Liez des préfixes personnalisés de 1 à 3 lettres (par exemple `dlog <container>` pour suivre les logs docker, `c <url>` pour curl les en-têtes, `png <host>` pour ping).
- **Mots-clés & Icônes Personnalisés** :
  - Ajoutez des mots-clés flous pour une découverte instantanée et personnalisez les icônes à l'aide de SF Symbols ou d'icônes d'application base64.

### 2. 💬 Extraits de Texte Dynamiques (`⌘P` / `snippets`)
Définissez des extraits de texte réutilisables avec expansion dynamique automatique des variables :
- `{{date}}` : Date actuelle (`AAAA-MM-JJ`)
- `{{time}}` : Heure actuelle (`HH:mm:ss`)
- `{{iso}}` : Horodatage ISO 8601 UTC (`2026-09-05T14:30:00Z`)
- `{{uuid}}` : UUID aléatoire v4
- `{{clipboard}}` : Contenu actuel de votre presse-papiers

Tapez n'importe quel mot-clé d'extrait (par exemple `iso`, `uuid`, `date`) et appuyez sur **`↵`** pour copier la chaîne évaluée directement dans votre presse-papiers.

### 3. 💻 Choisissez Parmi 7 Émulateurs de Terminal Modernes
Lightspot s'intègre à votre émulateur de terminal préféré. Changez à tout moment via la barre de menus :
- **Ghostty**, **Warp**, **Alacritty**, **iTerm2**, **Kitty**, **WezTerm**, et **Apple Terminal**.
- **"Terminal dans le Dossier du Finder"** : Tapez `term` ou appuyez sur l'action pour lancer instantanément votre terminal préféré dans le répertoire actuellement ouvert dans le Finder.

### 4. 📂 Découverte Multi-IDE de Projets Récents
Lightspot surveille automatiquement les espaces de travail récents sur :
- **VS Code**, **Cursor**, **Zed**, **Suite JetBrains** (IntelliJ IDEA, WebStorm, PyCharm, CLion, GoLand, Rider, etc.), et **Sublime Text**.
- **Modificateurs de Clavier** :
  - `↵` (Retour) : Ouvrir l'espace de travail dans son IDE associé.
  - `⌘↵` (Commande + Retour) : Lancer votre terminal préféré dans le répertoire racine du projet.
  - `⌥↵` (Option + Retour) : Révéler le dossier du projet dans le Finder.

### 5. 🔌 Tueur de Processus & Terminateur de Port (`kill`)
Terminez rapidement les serveurs de développement persistants, les tâches d'arrière-plan bloquées ou les processus malveillants :
- **Tuer par port :** `kill :3000`, `kill :8080`, `kill :5173` (résout automatiquement le PID en écoute via `lsof`).
- **Tuer par nom de processus ou PID :** `kill node`, `kill python`, `kill 14205`.
- **Niveaux de terminaison :**
  - `↵` (Retour) : Terminaison gracieuse (`SIGTERM`).
  - `⌥↵` (Option + Retour) : Force l'arrêt (`SIGKILL`).

### 6. 🛠️ Utilitaires de Développeur Hors Ligne Intégrés (DevTools)
Effectuez les opérations de développement courantes en quelques millisecondes sans ouvrir d'utilitaires web ni installer de paquets CLI :
- **`uuid`** : Génère un UUID v4 cryptographiquement aléatoire.
- **`b64 <text>`** / **`b64d <hash>`** : Encodage et décodage Base64.
- **`urlencode <url>`** / **`urldecode <url>`** : Encodage URL (pourcentage).
- **`hash sha256 <text>`** / **`sha1`** / **`md5`** : Sommes de contrôle cryptographiques instantanées.
- **`jwt <token>`** : Décode et affiche de manière formatée les en-têtes et le payload JWT.
- **`json <raw>`** : Formate, indente, et valide le JSON minifié.
- **`epoch`** / **`now`** : Conversion d'horodatage Unix en dates humaines et vice-versa.
- **`#3498db`** : Nuancier d'aperçu de couleur en direct avec copie en 1 clic au format Hex, RGB, et HSL.

### 7. 🔐 Touch ID sans Interface pour Sudo & Actions Privilégiées
Exécutez des actions de maintenance privilégiées (`Vider le Cache DNS`, `Purger la Mémoire Inactive`) avec l'authentification biométrique par empreinte digitale :
- **Pas de Pop-ups de Terminal** : S'exécute via un pseudo-terminal en arrière-plan (PTY) invoquant `pam_tid.so` de macOS pour une authentification Touch ID instantanée.
- **Activer Touch ID pour Sudo dans le Terminal** : Action de menu en 1 clic pour configurer `/etc/pam.d/sudo_local` afin que vos commandes `sudo` habituelles du terminal puissent également utiliser Touch ID.

### 8. 📜 Historique zsh & Commandes Épinglées (`⌘P` / `⌘⇧P`)
- Recherchez dans votre `~/.zsh_history` local (ou `$HISTFILE` personnalisé) avec un classement instantané inférieur à la milliseconde.
- Appuyez sur **`⌘P`** sur n'importe quelle commande de l'historique pour l'épingler en haut de votre lanceur.
- Appuyez sur **`⌘⇧P`** pour gérer, réorganiser ou supprimer les commandes épinglées.

### 9. 📦 Sauvegarde des Paramètres & Synchronisation Inter-Machines
- Exportez l'intégralité de votre configuration (commandes personnalisées, éléments épinglés, extraits, raccourcis) vers un fichier JSON propre.
- La désinfection automatique des chemins remplace `/Users/username` par `~` afin que les configurations puissent être partagées sans heurts entre les Mac de travail et personnels.

---

## ✨ Capacités Intégrées Supplémentaires

- **Interface exacte de macOS Spotlight** : Pilule flottante translucide en forme de cercle carré avec expansion animée et panneau d'aperçu (`NSVisualEffectView`).
- **Affichage Matériel Mach / IOKit** : Diagnostics matériels instantanés sans sous-processus (`sys`, `cpu`, `ram`, `battery`, `uptime`) :
  - Charge CPU multicœur normalisée %
  - RAM Physique Active, Résidente (Wired), Compressée, et Totale
  - Stockage libre et total du SSD de démarrage
  - Pourcentage de batterie et état de charge
- **Mathématiques Intelligentes & Conversions Souples** : Analyseur mathématique complet à descente récursive prenant en charge les unités, les devises, et les bases numériques :
  - Math : `(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - Unités : `100km in mi`, `72F in C`, `16GB in MB`
  - Devise : `$100 in EUR`, `50 GBP in USD`
  - Bases numériques : `0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **Signets & Onglets du Navigateur par Défaut** : Intégration de signets et d'onglets ouverts sans redondance, uniquement pour votre navigateur par défaut actif (**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**).
- **Presse-papiers Éphémère en Mémoire** : Tampon circulaire volatile uniquement en RAM (jusqu'à 50 éléments) accessible via `clip <query>`. N'écrit jamais sur le disque et filtre strictement les gestionnaires de mots de passe (`1Password`, `Bitwarden`).
- **Liens Profonds des Paramètres Système macOS** : 35+ liens profonds directs ouvrant des volets spécifiques des paramètres de macOS (`x-apple.systempreferences:...`).
- **Recherche Web Multi-Moteurs** : Raccourcis de préfixes intégrés : `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `brew`, `yt`, `ddg`.

---

## 🛑 Gestion Complète de macOS Spotlight

Lightspot inclut des automatisations intégrées dans la barre de menus pour désactiver ou réactiver le Spotlight intégré d'Apple :

1. **Raccourci Spotlight (`⌘Space`)** : Désactive ou restaure le raccourci `⌘Space` par défaut d'Apple dans les raccourcis symboliques macOS sans nécessiter d'accès root.
2. **Processus d'Arrière-plan (`com.apple.Spotlight`)** : Désactive ou active l'agent d'arrière-plan GUI de Spotlight via `launchctl`.
3. **Indexation de Fichiers (`mdutil`)** : Arrête complètement l'indexation des métadonnées du système de fichiers (`mds` / `mds_stores`) sur tous les volumes montés.
4. **Actions Maîtresses en 1 Clic** :
   - **`Tout Désactiver (Raccourci + Processus + Indexation)...`** : Arrête complètement Apple Spotlight pour récupérer du CPU, de la RAM, de l'espace disque, et `⌘Space`.
   - **`Restaurer Spotlight par Défaut...`** : Rétablit tous les paramètres aux valeurs par défaut d'usine de macOS à tout moment.

---

## 🚀 Construction & Installation (Aucun Xcode Requis)

Lightspot est construit avec des outils Swift standards et des scripts shell simples. Aucune installation de l'IDE Xcode n'est requise.

### 1. Construire
```bash
./build.sh
# ou : make build
```
Compile un binaire de release (`-Osize -wmo`), supprime les symboles de débogage, intègre `Info.plist` et les icônes haute résolution, et signe le code de `build/Lightspot.app`.

### 2. Exécuter
```bash
./run.sh
# ou : make run
```

### 3. Installer dans `/Applications`
```bash
./install.sh
# ou : make install
# (Passez --user pour installer dans ~/Applications à la place)
```

### 4. Tests & Vérification
Lightspot inclut 112 suites de tests automatisés et des vérifications d'exécution sur système en direct :
```bash
# Tests de logique de base & moteur (24 suites de tests)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/test_engine

# Vérifications du système en direct (88 vérifications)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ Raccourcis & Navigation

| Touche | Action |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** | Invoquer ou rejeter Lightspot n'importe où (configurable dans la barre de menus) |
| **`↓` / `↑`** | Naviguer dans les résultats de recherche |
| **`Return` (`↵`)** | Ouvrir l'application sélectionnée, le projet dans l'IDE, exécuter la commande, ou copier le calcul |
| **`⌘Return` (`⌘↵`)** | Ouvrir le projet sélectionné dans le Terminal préféré |
| **`⌥Return` (`⌥↵`)** | Révéler le projet dans le Finder / Forcer l'arrêt du processus sélectionné (`SIGKILL`) |
| **`⌘P`** | Épingler ou désépingler la commande d'Historique du Terminal sélectionnée |
| **`⌘⇧P`** | Ouvrir la superposition du gestionnaire de commandes épinglées |
| **`⌘⇧C`** | Ouvrir la superposition du gestionnaire de commandes personnalisées |
| **`⌘Y`** / **`⌘⇧H`** | Ouvrir la superposition du gestionnaire d'historique de recherche |
| **`Escape`** | Rejeter les superpositions, effacer le champ de recherche, ou fermer Lightspot |
| **Cliquer en Dehors** | Rejette automatiquement le panneau flottant |

---

## 📁 Structure du Projet

```
mac-lightspot/
├── Package.swift                 # Manifeste SPM (Swift 6, macOS 13+)
├── Makefile                      # make build / run / install / uninstall / clean
├── build.sh                      # Build de release & script de création .app
├── run.sh                        # Assistant de build & lancement
├── install.sh                    # Installation vers /Applications ou ~/Applications
├── uninstall.sh                  # Script de suppression propre
├── README.md                     # Documentation & justification
├── CLAUDE.md                     # Architecture, invariants & guide développeur
├── Resources/
│   ├── Info.plist                # LSUIElement=1, permissions, métadonnées du bundle
│   └── AppIcon.icns              # Icône d'application macOS multi-tailles
├── scripts/
│   ├── generate_icon.sh          # Générateur d'icônes programmatique (Core Graphics + iconutil)
│   ├── test_engine.swift         # Exécuteur de tests automatisés (24 suites de tests)
│   └── deep_verify.swift         # Vérification sur système en direct (88 vérifications)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main point d'entrée & NSApplicationDelegate
        ├── Core/
        │   ├── Models.swift      # SearchResult, ResultCategory, SearchAction, FuzzyMatcher
        │   ├── AppScanner.swift  # Analyseur d'app rapide asynchrone & cache d'icônes en mémoire
        │   ├── BrowserIntegrationProvider.swift # Signets et onglets du navigateur par défaut
        │   ├── CalculatorEngine.swift # Analyseur mathématique & répartiteur de conversion
        │   ├── ClipboardHistoryManager.swift    # Tampon circulaire du presse-papiers éphémère en mémoire
        │   ├── ConversionEngine.swift   # Moteur d'unités, devises, bases & températures
        │   ├── CustomCommandsStore.swift # Modèle et persistance de commandes utilisateur personnalisées
        │   ├── DevToolsProvider.swift   # UUID, Base64, Hash, JWT, JSON, Nuancier Couleur
        │   ├── NetworkInfoProvider.swift # IPv4 local & adresse IP internet publique
        │   ├── ProcessKillerProvider.swift # Terminateur de processus par nom, PID, et port
        │   ├── QuickActionsProvider.swift # Actions système ciblées & Terminal dans le Finder
        │   ├── RecentProjectsProvider.swift # Analyseur de projets multi-IDE (VS Code, Cursor, Zed, JetBrains, Sublime)
        │   ├── SearchEngine.swift       # Agrégateur de recherche synchrone & classement
        │   ├── SearchHistoryManager.swift # Historique des requêtes de recherche & sélections
        │   ├── SettingsBackup.swift     # Sauvegarde d'exportation & importation des paramètres
        │   ├── SettingsProvider.swift   # 35+ liens profonds de Paramètres Système macOS
        │   ├── ShellHistoryProvider.swift # Analyseur d'historique zsh & commandes épinglées
        │   ├── SnippetsStore.swift      # Extraits d'expansion de texte avec interpolation de variables
        │   ├── SystemInfoProvider.swift # Tableau de bord matériel Mach/IOKit sans sous-processus
        │   └── WebSearchProvider.swift  # Recherche multi-moteurs & raccourcis de préfixes
        ├── System/
        │   ├── HotkeyManager.swift      # Raccourci global Carbon
        │   ├── MenuBarController.swift  # Élément d'état de la barre de menus & préférences
        │   ├── SettingsBackupController.swift # Contrôleur d'importation/exportation des paramètres
        │   ├── SpotlightManager.swift   # Automatisations de désactivation/restauration de macOS Spotlight
        │   └── TerminalLauncher.swift   # Lanceur pour 7 émulateurs de terminal & détection du Finder
        └── UI/
            ├── CustomCommandsView.swift # Superposition du gestionnaire de commandes personnalisées
            ├── HistoryManagerView.swift # Superposition du gestionnaire d'historique de recherche
            ├── PinnedCommandsView.swift # Superposition du gestionnaire de commandes épinglées
            ├── PreviewPaneView.swift    # Carte de détails riches & aperçus en direct
            ├── SearchFieldView.swift    # Pont NSTextField & éditeur de champ personnalisé
            ├── SearchViewModel.swift    # Modèle de vue réactif & routeur d'événements clés
            ├── SpotlightComponents.swift# Lignes de résultats de recherche, boutons, & en-têtes de catégorie
            ├── SpotlightPanel.swift     # NSPanel sans bordure flottant avec vibrance
            └── SpotlightView.swift      # Vue SwiftUI racine
```

---

## 🔒 Garanties de Confidentialité & de Sécurité

- **Zéro Indexation de Fichiers** : Lightspot n'indexe jamais vos fichiers personnels, documents, téléchargements, ou dépôts de code.
- **Presse-papiers Éphémère Uniquement en RAM** : L'historique du presse-papiers reste exclusivement dans la mémoire volatile (jamais écrit sur le disque) et ignore activement les types dissimulés/gestionnaires de mots de passe (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`).
- **Isolation du Navigateur par Défaut** : Les signets et les onglets sont lus uniquement depuis votre navigateur par défaut configuré, évitant le grattage (scraping) inter-navigateurs.
- **Sous-processus Sandboxés** : Les commandes et les scripts ne s'exécutent qu'après une action explicite de l'utilisateur (`Return` ou `⌘↵`).
- **Zéro Télémétrie & 100% Hors Ligne** : Aucune requête réseau, aucune analyse à distance, aucun suivi.
