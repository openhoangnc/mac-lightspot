# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **Un remplaçant léger et au pixel près pour macOS Spotlight, conçu en pur Swift — conçu pour les développeurs et les utilisateurs expérimentés qui veulent une vitesse instantanée sans la lourdeur de l'indexation des fichiers.**

Lightspot reproduit fidèlement le design moderne en forme de pilule flottante et l'esthétique de verre translucide de macOS Spotlight (`NSVisualEffectView`). Sous le capot, il offre une réactivité inférieure à la milliseconde (< 1,0 ms de recherche) avec **zéro indexation de fichiers en arrière-plan**. Au repos, son seul travail périodique est une légère vérification du presse-papiers toutes les 0,6 s, et il utilise moins de **25 Mo de RAM**.

![Capture d'écran de Lightspot](screenshot.png)

---

## ⚡ Démarrage Rapide

### 📦 Téléchargement & Installation en une ligne
Copiez et collez simplement cette commande dans votre Terminal pour télécharger, extraire et installer automatiquement la dernière version de **Lightspot** dans votre dossier `/Applications`. Elle télécharge la version compilée pour votre Mac, environ 1,6 Mo sur Apple silicon ou 1,75 Mo sur Intel, d'après le processeur du Mac lui-même (`sysctl hw.optional.arm64`), si bien qu'un Terminal exécuté sous Rosetta reçoit quand même la version Apple silicon :

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

*(Optionnel : Ajoutez `--user` pour installer dans `~/Applications` : `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash -s -- --user`)*

---

### 🗑️ Désinstallation Complète
Pour supprimer complètement Lightspot, désenregistrer le lancement au démarrage, effacer vos préférences, supprimer l'application et réactiver Apple Spotlight si Lightspot l'avait désactivé (réactiver l'indexation demande votre mot de passe administrateur, ou affiche la commande `sudo mdutil -a -i on` à lancer plus tard) :

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash
```

*(Optionnel : `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash -s -- --dry-run` affiche ce qui serait modifié sans rien changer ; passez plutôt `--keep-spotlight-disabled` pour laisser Spotlight désactivé.)*

Les changements de Mac Tweaks restent, y compris les éléments d'arrière-plan qu'il a désactivés (ceux de tous les utilisateurs restent désactivés pour tous les comptes) : le désinstalleur garde son journal d'annulation et la sauvegarde du Dock, et explique comment annuler ce qui reste : réinstallez Lightspot et choisissez **Undo everything Lightspot changed** dans Settings de Mac Tweaks, supprimez **Lightspot Mac Tweaks** dans Réglages Système › Général › Gestion des appareils, ou lancez **Restore Dock Icons**.

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

Au lieu d'analyser agressivement l'intégralité de votre disque dur, Lightspot se concentre strictement sur ce que les utilisateurs expérimentés recherchent réellement : Applications, Projets IDE, Onglets de Navigateur, Signets & Historique, Utilitaires de Développement, et Commandes Personnalisées.

### Matrice de Comparaison

| Métrique | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **Indexation de Fichiers** | Analyse d'arrière-plan incontrôlée | Optionnelle / Configurable | **Jamais** (Par garantie architecturale) |
| **Utilisation CPU au Repos** | Pics à 100%+ durant les opérations | 1% – 5% en arrière-plan | **Minimale** (pas d'indexation ; seulement une vérification du presse-papiers toutes les 0,6 s) |
| **Stockage Disque** | 10 Go – 200 Go+ cache caché | 100 Mo – 1 Go | **Ni index ni cache** (vos réglages dans `UserDefaults`, un fichier de verrou et de petits fichiers seulement quand vous nettoyez ou appliquez quelque chose : des journaux de reçus, le journal d'annulation de Mac Tweaks et une sauvegarde du Dock) |
| **Empreinte RAM** | 500 Mo – 2 Go+ | 200 Mo – 500 Mo | **~15 – 25 Mo** (Pur Swift) |
| **Lancement d'App** | Se casse fréquemment ; requiert des reconstructions | Fiable | **100% Fiable** (Analyse directe) |
| **Latence de Recherche** | Temporisée (50 – 200 ms) | 10 – 30 ms | **< 1,0 ms** (Synchrone instantané) |
| **Confidentialité Hors Ligne** | Envoie la télémétrie de Siri à Apple | Compte requis pour la synchro | **Local & Sans Télémétrie** (réseau uniquement pour une vérification des mises à jour optionnelle, une recherche d'IP que vous demandez et les règles de nettoyage de cdm quand vous ouvrez Clean Dev Mac) |

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
  - Donnez à une commande votre propre préfixe, puis tapez `<préfixe> <requête>` (par exemple `c <url>` pour curl les en-têtes, `png <host>` pour ping). Le menu **Presets** de l'éditeur propose neuf commandes prêtes à l'emploi : `gh`, `g`, `yt`, `so`, `ddg`, `wiki`, `npm`, `png` et `c`.
- **Mots-clés & Icônes Personnalisés** :
  - Ajoutez des mots-clés flous pour une découverte instantanée. L'icône d'une commande est par défaut celle de son application d'exécution (votre navigateur, terminal ou Script Editor) ; vous pouvez passer au symbole intégré de l'exécuteur ou choisir votre propre image ou fichier d'application.

### 2. 💬 Extraits de Texte Dynamiques
Lightspot est livré avec cinq extraits de texte — `date`, `iso`, `uuid`, `shrug` et `flip` — et développe les variables dynamiques au moment où vous en copiez un :
- `{{date}}` : Date actuelle (`AAAA-MM-JJ`)
- `{{time}}` : Heure actuelle (`HH:mm:ss`)
- `{{iso}}` : Horodatage ISO 8601 UTC (`2026-09-05T14:30:00Z`)
- `{{uuid}}` : UUID aléatoire v4
- `{{clipboard}}` : Contenu actuel de votre presse-papiers

Tapez un mot-clé d'extrait (par exemple `iso`, `uuid`, `date`) ou une partie de son nom et appuyez sur **`↵`** pour copier la chaîne évaluée directement dans votre presse-papiers.

### 3. 💻 Choisissez Parmi 7 Émulateurs de Terminal Modernes
Lightspot s'intègre à votre émulateur de terminal préféré. Changez à tout moment via la barre de menus :
- **Ghostty**, **Warp**, **Alacritty**, **iTerm2**, **Kitty**, **WezTerm**, et **Apple Terminal**. (Warp ouvre les dossiers, mais n'accepte pas de commande envoyée par une autre app : lorsque Warp est sélectionné, les commandes de l'historique, épinglées et personnalisées de terminal s'exécutent dans Apple Terminal.)
- **"Terminal dans le Dossier du Finder"** : Tapez `term` ou appuyez sur l'action pour lancer instantanément votre terminal préféré dans le répertoire actuellement ouvert dans le Finder.

### 4. 📂 Découverte Multi-IDE de Projets Récents
Lightspot surveille automatiquement les espaces de travail récents sur :
- **VS Code**, **Cursor**, **Zed**, **IDE JetBrains** (IntelliJ IDEA, PyCharm — éditions Community comprises —, WebStorm, GoLand, CLion, RustRover, Rider, PhpStorm, DataGrip, RubyMine, DataSpell), **Android Studio**, et **Sublime Text**.
- **Modificateurs de Clavier** :
  - `↵` (Retour) : Ouvrir l'espace de travail dans son IDE associé.
  - `⌘↵` (Commande + Retour) : Lancer votre terminal préféré dans le répertoire racine du projet.
  - `⌥↵` (Option + Retour) : Révéler le dossier du projet dans le Finder.

### 5. 🔌 Tueur de Processus & Terminateur de Port (`kill`)
Terminez rapidement les serveurs de développement persistants, les tâches d'arrière-plan bloquées ou les processus malveillants :
- **Tuer par port :** `kill :3000`, `kill :8080`, `kill :5173` (résout via `lsof` le processus qui *écoute* sur le port ; les clients qui y sont simplement connectés ne sont pas proposés).
- **Tuer par nom de processus ou PID :** `kill node`, `kill python`, `kill 14205`. Les processus système (`launchd`, `kernel_task`, `WindowServer`, `loginwindow`) et Lightspot lui-même ne sont jamais proposés.
- **Niveaux de terminaison :**
  - `↵` (Retour) : Terminaison gracieuse (`SIGTERM`).
  - `⌥↵` (Option + Retour) : Force l'arrêt (`SIGKILL`).

### 6. 🛠️ Utilitaires de Développeur Hors Ligne Intégrés (DevTools)
Effectuez les opérations de développement courantes en quelques millisecondes sans ouvrir d'utilitaires web ni installer de paquets CLI :
- **`uuid`** : Génère un UUID v4 cryptographiquement aléatoire.
- **`b64 <text>`** / **`b64d <base64>`** (ou **`b64 decode <base64>`**) : Encodage et décodage Base64.
- **`urlencode <url>`** / **`urldecode <url>`** : Encodage URL (pourcentage).
- **`hash <text>`** / **`hash sha256|sha1|md5 <text>`** : Sommes de contrôle cryptographiques instantanées — les trois à la fois, ou seulement l'algorithme indiqué.
- **`jwt <token>`** : Décode et affiche de manière formatée les en-têtes et le payload JWT.
- **`json <raw>`** : Formate, indente, et valide le JSON minifié.
- **`epoch`** / **`now`** : Horodatage Unix actuel ; **`epoch <horodatage>`** le convertit en date lisible et **`epoch 2024-01-15 10:30`** fait l'inverse (heure locale, ou ISO 8601 avec fuseau horaire).
- **`#3498db`** : Nuancier d'aperçu de couleur en direct avec copie en 1 clic au format Hex, RGB, et HSL.

### 7. 🔐 Touch ID sans Interface pour Sudo & Actions Privilégiées
Exécutez des actions de maintenance privilégiées (`Vider le Cache DNS`, `Purger la Mémoire Inactive`) avec l'authentification biométrique par empreinte digitale :
- **Pas de Pop-ups de Terminal** : S'exécute via un pseudo-terminal en arrière-plan (PTY) invoquant `pam_tid.so` de macOS pour une authentification Touch ID instantanée.
- **Activer Touch ID pour Sudo dans le Terminal** : Une Action Rapide recherchable (tapez `touch id` ou `sudo`) qui modifie `/etc/pam.d/sudo_local`, après une demande d'autorisation administrateur, afin que vos commandes `sudo` habituelles du terminal puissent également utiliser Touch ID. Son sous-titre indique si Touch ID pour sudo est actuellement activé.

### 8. 📜 Historique zsh & Commandes Épinglées (`⌘P` / `⌘⇧P`)
- Recherchez dans votre `~/.zsh_history` local (ou `$HISTFILE` personnalisé) avec un classement instantané inférieur à la milliseconde.
- Appuyez sur **`⌘P`** sur n'importe quelle commande de l'historique pour l'épingler en haut de votre lanceur.
- Appuyez sur **`⌘⇧P`** pour gérer, réorganiser ou supprimer les commandes épinglées.

### 9. 📦 Sauvegarde des Paramètres & Synchronisation Inter-Machines
- Utilisez **Export Settings…** / **Import Settings…** dans la barre des menus pour enregistrer votre configuration dans un fichier JSON propre et la restaurer. Elle couvre les commandes personnalisées, les commandes shell épinglées, l'historique de recherche et le classement, les applications récentes et les préférences (raccourci global, lancement à la connexion, visibilité de l'icône de la barre des menus, durée de l'historique du navigateur). Les extraits de texte, votre terminal préféré et votre moteur de recherche web par défaut ne sont pas inclus.
- La désinfection automatique des chemins remplace `/Users/username` par `~` afin que les configurations puissent être partagées sans heurts entre les Mac de travail et personnels.

### 10. 🔄 Mise à Jour Automatique Intégrée
- Consulte les Releases GitHub en arrière-plan (peu après le lancement et à l'ouverture du menu de la barre des menus) et propose la nouvelle version depuis la barre de menus. Après une vérification réussie, Lightspot attend un jour avant la suivante ; une vérification échouée (hors ligne, limite de requêtes) est relancée au lancement suivant ou à la prochaine ouverture du menu. **`Check for Updates...`** (Rechercher les mises à jour) la lance à la demande, et **`Automatically Check for Updates`** désactive entièrement les vérifications automatiques.
- Installation sur place : Lightspot télécharge la version de la release compilée pour ce Mac (`Lightspot-arm64.zip` sur Apple silicon, `Lightspot-x86_64.zip` sur Intel, d'après le processeur du Mac lui-même, si bien qu'une copie exécutée sous Rosetta passe à la version native ; `Lightspot.zip`, l'app universelle, pour une release qui n'en a pas), la vérifie, remplace son propre bundle, lance la nouvelle version et ne quitte qu’une fois celle-ci démarrée : Lightspot ne disparaît jamais. **`Skip This Version`** met en sourdine une release précise sans désactiver les vérifications. Les mises à jour intégrées de Lightspot 1.2.0 à 1.3.9 téléchargent le `Lightspot.zip` universel : elles installent donc 1.4.0 en app universelle, et les mises à jour suivantes sont la version pour votre Mac.
- Chaque téléchargement est filtré : HTTPS uniquement, hôtes GitHub uniquement (revérifiés après les redirections), le bundle décompressé doit porter l'identifiant de bundle de Lightspot, un exécutable fonctionnel contenant du code pour le processeur de ce Mac (lu dans son en-tête Mach-O) et exactement la version annoncée, et une version antérieure à celle déjà installée n'est jamais acceptée.
- Les releases sont signées en ad-hoc (ce projet ne fournit aucun Developer ID), il n'y a donc aucune signature de code à vérifier : les contrôles ci-dessus et HTTPS vers GitHub constituent tout le modèle de confiance, celui-là même que `install.sh` exige déjà.

### 11. 🧹 Clean Dev Mac (`cdm`)
[CleanDevMac](https://github.com/cleandevmac/cdm) (`cdm`) trouve les caches de développement et les artefacts de build qui remplissent votre disque ; Lightspot l'exécute dans sa propre fenêtre, que vous pouvez déplacer et qui reste ouverte pendant que le Finder, une demande de mot de passe ou cdm dans votre terminal prend le focus. Tapez `cdm`, `clean dev mac` ou le nom d'un cache (`derived data`, `npm cache`) et appuyez sur **`↵`** :
- **D'abord mesurer, ne rien cocher à l'aveugle** : chaque catégorie connue des règles de cdm (DerivedData de Xcode, Go, npm/pnpm/Yarn, Gradle, Cargo, pip/uv, CocoaPods, JetBrains, caches des navigateurs et des apps Electron, images Android inutilisées, le cache de modules de clang, les copies de Chrome qu'un navigateur arrêté de force laisse derrière lui, …) est mesurée comme le ferait `du`, triée de la plus grosse à la plus petite, et cochée selon les valeurs sûres par défaut de cdm. La fenêtre montre le disque avant et après. Comme cdm, il ajoute deux notes quand elles s'appliquent : ce qu'un redémarrage libérerait (swap, dossiers temporaires que macOS vide au démarrage, fichiers supprimés que des apps gardent encore ouverts) dès que cela dépasse l'espace libre, et, quand l'historique des sessions de Claude Code dépasse 1 Go avec des transcriptions plus anciennes que sa limite, le réglage `desktopSessionCleanupPeriodDays` qui fait aussi supprimer à Claude Code les sessions de Claude Desktop et de Cowork. Lightspot ne modifie jamais ce réglage à votre place.
- **Composants de SDK installés et vieilles sessions, non cochés** : les lignes facultatives de cdm arrivent aussi : les toolchains de PlatformIO, le NDK Android, CMake et les sources du SDK, toutes les versions de build-tools et de plateformes Android sauf la plus récente, l'image système d'un AVD que personne n'a démarré depuis 60 jours (la ligne nomme l'AVD, qui ne démarrera plus tant que l'image n'est pas réinstallée) et les sessions Claude Code inchangées depuis 30 jours, qui ne vont jamais qu'à la Corbeille. Chaque ligne dit comment les récupérer.
- **Vos dépôts aussi** : après les caches, Clean Dev Mac demande, comme cdm, s'il faut aussi analyser vos dépôts de code à la recherche de déchets de build et de dépendances ; appuyez sur **`⇥`**. Vous obtenez une ligne non cochée par dépôt avec ses `node_modules`, `dist`, `build`, `target`, `__pycache__` et autres fichiers ignorés par git. Rien n'est proposé sans que le git du dépôt lui-même ne l'ignore (un `build/` suivi reste), les fichiers `.env*` ne sont jamais proposés, pas plus qu'un dossier contenant un autre dépôt. Les dossiers régénérables sont supprimés ; les autres fichiers ignorés vont à la Corbeille.
- **Touches** : `↑↓` sélectionne (la ligne sélectionnée affiche ses chemins et leurs tailles), `Space` coche, `⇥` analyse vos dépôts, `↵` affiche le plan détaillé et `↵` à nouveau nettoie, `⌥↵` montre le cache sélectionné dans le Finder, `⌘↵` lance cdm dans votre terminal, `Esc` quitte le plan et sinon ferme la fenêtre, comme `⌘W`. Une analyse ou un nettoyage continue fenêtre fermée.
- **Les mêmes règles que cdm** : Lightspot lit les fichiers de règles de cdm (votre `~/.cleandevmac/rules` si vous en avez un, sinon les règles en ligne de cdm sur GitHub, sinon la copie intégrée à l'app) ; un cache que cdm apprend à nettoyer, Lightspot le nettoie aussi.
- **La même sécurité que cdm** : chaque chemin passe le contrôle de sécurité de cdm avant toute action : il doit se trouver dans votre dossier personnel, ou dans vos propres dossiers temporaires de `/private/var/folders` là où les règles de cdm nomment un cache (liens symboliques résolus dans les deux cas), et `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg` et iCloud Drive ne sont jamais touchés. Avant le nettoyage, le plan nomme les apps encore ouvertes qui réécriraient leurs caches (quittez-les d'abord). Chaque nettoyage est consigné dans `~/.cleandevmac/clean.log`, le même journal que tient cdm.
- **Le reste à une touche** : Docker / Podman, les toolchains Rust et leur documentation hors ligne (retirés avec `rustup`), les données d'apps désinstallées et les caches des apps en sandbox demandent un moteur de conteneurs, rustup ou une analyse de vos apps ; `⌘↵` lance donc cdm complet dans votre terminal préféré, directement depuis sa dernière version.

### 12. 📦 Installations en une touche : setup-zsh, MacStats et outils de développement
Tapez `install` (ou le nom d'un outil) et appuyez sur **`↵`** : Lightspot lance l'installeur de l'outil dans votre terminal préféré, et vous voyez chaque étape.
- **Install setup-zsh** ([setup-zsh](https://github.com/openhoangnc/setup-zsh)) : des suggestions automatiques zsh qui cherchent n'importe où dans votre historique, la coloration syntaxique et une invite qui affiche l'état git. Lance `setup.sh`, puis ouvre un nouveau zsh qui le charge. Une fois installé, la même ligne le met à jour.
- **Install MacStats** ([mac-stats](https://github.com/openhoangnc/mac-stats)) : CPU, RAM, débit réseau et température du processeur dans la barre des menus. Lance son `install.sh`, qui l'installe dans `/Applications` et le démarre.
- **Install Dev Tools** : le menu `install-dev-tool` de setup-zsh : Homebrew, Node.js, Go, Python et uv, Rust, JDK, Bun, Git, VS Code, Chrome, OrbStack, Android Studio et d'autres, plus la mise à jour de vos paquets globaux. Tapez `install node`, `install go`, `install rust`… ; sans setup-zsh, la ligne l'installe d'abord.
- Chaque ligne indique si l'outil est déjà installé ; **`⌥↵`** ouvre sa page GitHub.

### 13. 🎛️ Réglages macOS
Les commandes `defaults write` que vous copieriez d'un README de dotfiles, en actions rapides. Chaque bascule lit le réglage actuel et l'inverse ; la même ligne le rétablit :
- **Dock** : **Clear Dock Icons** (sauvegarde les icônes du Dock dans `~/Library/Application Support/Lightspot/dock-backup.plist`, puis retire toutes les apps épinglées et redémarre le Dock), **Restore Dock Icons** (les remet à leur place, garde les icônes ajoutées depuis et ne supprime la sauvegarde qu'une fois que le Dock redémarré les affiche ; les deux attendent qu'un Dock qui vient de démarrer se stabilise et réessaient une fois si un redémarrage perd le changement), **Toggle Dock Auto-Hide**, **Toggle Instant Dock Auto-Hide** (sans délai), **Toggle Dock Recent Apps**, **Restart Dock**.
- **Finder** : **Toggle Hidden Files in Finder**, **Toggle File Extensions in Finder**, **Toggle Finder Path Bar**, **Toggle Desktop Icons** (pratique avant un partage d'écran), **Toggle .DS_Store on Network & USB Drives**, **Restart Finder**.
- **Saisie et captures d'écran** : **Toggle Press-and-Hold Accents** (maintenir une touche la répète), **Toggle Smart Quotes & Dashes**, **Toggle Screenshot Shadows**.

Aucune ne demande le mot de passe administrateur. Restore Dock Icons annule Clear Dock Icons, et chaque bascule s'annule elle-même. Pour 41 réglages de plus, chacun avec son état et son annulation, voyez Settings de Mac Tweaks (section 14).

### 14. 🧰 Mac Tweaks (`free up space`)
Mac Tweaks libère l'espace que macOS garde, désactive Apple Intelligence pour tous les comptes de ce Mac, modifie 41 réglages de macOS, avec annulation, et désactive ou supprime les agents et daemons launchd que d'autres apps ont installés. Tapez `mac tweaks`, `free up space`, `debloat` ou ce que vous voulez faire disparaître (`remove garageband`, `macos installers`, `time machine snapshots`, `app caches`) et appuyez sur **`↵`**, ou choisissez **Mac Tweaks...** dans la barre des menus, juste sous **Clean Dev Mac...** ; `turn off apple intelligence` l'ouvre sur Apple Intelligence ; `stop music from opening`, `turn off apple music`, `turn off mac analytics`, `turn off personalized ads` ou `show the library folder` sur Settings ; et `turn off background items`, `turn off launch agents`, `disable launch agents`, `turn off google updater`, `leftover launch agents` ou `launch daemons` sur Background Items. Il s'ouvre dans sa propre fenêtre, avec un onglet par section, et chaque section montre un plan détaillé avant de rien changer et un reçu après. La fenêtre reste ouverte pendant que vous passez aux Réglages Système pour approuver un profil ou répondez à Touch ID : déplacez-la où vous voulez (elle retient l'endroit) et fermez-la avec son bouton de fermeture, `⌘W` ou `Esc`. (Les bascules `defaults` de la section 13 sont des actions rapides et ne font pas partie de Mac Tweaks.)
- **Free Up Space** mesure chaque ligne comme le fait Clean Dev Mac ; une ligne qui n'a rien à proposer est masquée, rien de 0 octet n'est proposé, et les trois premières lignes sont cochées :
  - **macOS installers** : les anciens `Install macOS*.app` de `/Applications`, seulement avec l'identifiant de paquet d'Apple (`com.apple.InstallAssistant…`).
  - **iPhone and iPad updates** : les mises à jour que le Finder a téléchargées, dans `~/Library/iTunes/iPhone Software Updates` et `iPad Software Updates`.
  - **Unavailable simulators** : les simulateurs dont le runtime n'est plus installé, via le `simctl` de Xcode ; jamais `/usr/bin/xcrun`, si bien qu'un Mac qui n'a que les Command Line Tools n'a ni cette ligne ni leur installeur qui s'ouvre.
  - **Time Machine local snapshots** : les instantanés locaux, affichés en nombre (macOS ne donne pas leur taille).
  - **Aerial videos** : les vidéos aériennes que partagent tous les comptes du Mac (`/Library/Application Support/com.apple.idleassetsd/Customer`) ; les copies propres à chaque compte sont une ligne de Clean Dev Mac.
  - **GarageBand and its sound library** : GarageBand et sa bibliothèque de sons ; la bibliothèque reste tant que Logic Pro ou MainStage est installé.
  - **iMovie**, **Keynote**, **Numbers** et **Pages**, seulement ceux d'Apple : un `Pages.app` qui n'est pas d'Apple reste.
  - **App caches** : les caches de `~/Library/Caches`, sauf ceux de macOS (`com.apple.*` et les autres noms qu'écrit macOS), celui de Lightspot et tous ceux que couvre une règle de Clean Dev Mac, pour que Mac Tweaks et Clean Dev Mac ne comptent jamais le même dossier. Mac Tweaks lit ces règles dans la mémoire de Clean Dev Mac, dans `~/.cleandevmac/rules` ou dans la copie intégrée à l'app, et ne les télécharge jamais.
  - Trois lignes de lien : **Apple Intelligence models** (leur taille, une fois cette section analysée et tant qu'ils sont sur le disque) ouvre la section Apple Intelligence, **Developer caches and project junk** ouvre Clean Dev Mac, **More in System Settings** ouvre Stockage dans les Réglages Système.
- **Où vont les fichiers de Free Up Space** : à la Corbeille, vous pouvez donc les en sortir tant que vous ne l'avez pas vidée. Les simulateurs (`simctl delete unavailable`) et les instantanés (`tmutil deletelocalsnapshots`) sont supprimés tout de suite, et leurs lignes le disent ; les sauvegardes de votre disque de sauvegarde ne sont pas touchées. Son reçu dit ce qui a été libéré, ce qui est allé à la Corbeille, ce qui a été supprimé, et ce qui est resté et pourquoi, par exemple une app que macOS ne laisse pas Lightspot déplacer sans l'autorisation App Management (`⌥↵` la montre dans le Finder).
- **Apple Intelligence** (Apple silicon, macOS 15.1 ou ultérieur) : une ligne par fonction de ce macOS (Siri, ChatGPT et les autres extensions d'IA, Writing Tools, Genmoji, Image Playground, les résumés de Mail, des notifications, de Messages, de Safari et de Notes, les prédictions de texte en ligne, Spatial Photos, Photos Clean Up et la complétion de code prédictive de Xcode), chacune avec son état (On, Off, Locked off, Managed, Unknown) et les modèles dont elle a besoin. Toutes partent cochées, ce qui veut dire désactiver ; décochez celles à garder. Appliquer installe un seul profil de configuration, **Lightspot Mac Tweaks**, que vous approuvez dans Réglages Système › Général › Gestion des appareils (Lightspot l'ouvre et attend jusqu'à 10 minutes ; `Esc` arrête l'attente) : il désactive les fonctions cochées pour tous les comptes de ce Mac et dirige le téléchargement de leurs modèles vers un port local fermé. Ce n'est qu'une fois le profil en vigueur que Lightspot demande au service d'assets d'Apple de supprimer les modèles dont aucune fonction gardée n'a besoin, en réessayant tant que macOS les utilise et en vérifiant l'inventaire jusqu'à ce qu'ils aient disparu. **Finish removing the models** termine le travail après un redémarrage ; **Turn Apple Intelligence back on** supprime le profil, ou le remplace par un profil sans Apple Intelligence quand il contient aussi des réglages de Settings. Une fonction qu'un autre profil fixe reste comme elle est, et le profil de RemoveMacAI met la section en lecture seule. Lightspot n'appelle jamais lui-même le framework privé des assets : chaque lecture et chaque suppression s'exécutent dans un processus enfant de courte durée, `Lightspot --asset-service`, si bien que les 9 à 11 Mo du framework ne restent jamais dans la mémoire de Lightspot.
- **Settings** : 41 réglages en six groupes (Privacy, Annoyances, Apple apps, Finder, Dock and windows, Typing), chacun avec son état sur ce Mac : On, Off, Partly, Managed (un autre profil le fixe, donc Lightspot n'y touche pas) ou Not on this macOS. Rien n'est coché au départ ; les préréglages **Recommended** et **Maximum privacy** cochent ceux qui sont encore désactivés. Les réglages locaux passent par cfprefsd et sont relus, et le Finder, le Dock ou SystemUIServer redémarrent une fois quand un changement le demande. Mac Analytics, les publicités personnalisées, Améliorer Siri et Dictée, Améliorer la recherche, les résultats internet de Spotlight, les suggestions de Look Up et de recherche de Safari, Game Center, la recopie de l'iPhone, Apple Music et la Book Store vont dans le même profil, qui garde sa partie Apple Intelligence telle quelle, et le plan dit que le profil s'applique à tous les comptes de ce Mac. Apple Music à trois niveaux : le service Apple Music, l'entrée de lancement de Musique pour que rien ne puisse l'ouvrir, et les touches lecture, pause et piste suivante (`com.apple.rcd`). La ligne sélectionnée et le plan montrent chaque changement sous forme de commande (`defaults write …`, `launchctl …`, `chflags …`, `profile: …`).
- **Background Items** : une ligne par `.plist` de `~/Library/LaunchAgents`, `/Library/LaunchAgents` et `/Library/LaunchDaemons`, sauf ceux de macOS (`com.apple.*`), les plists sans `Label` (les stubs vides que laisse Keystone de Google) et les fichiers qui commencent par un point. Chaque ligne indique l'app à laquelle l'élément appartient (l'`.app` où se trouve son programme, ce qu'il exécute, ou l'app que nomme son `AssociatedBundleIdentifiers`, si bien qu'un assistant de Docker s'affiche « Docker »), son étiquette et ce qu'il exécute (jamais ses autres arguments, qui peuvent contenir des jetons), et son état : On, Off, Not loaded (les éléments de connexion des Réglages Système l'ont peut-être désactivé) ou Unknown, lu avec `launchctl print-disabled` et `launchctl print`. Les programmes de mise à jour (`update` dans l'étiquette ou dans le nom du programme) portent l'étiquette **Updater** ; une ligne qui n'est ni un programme de mise à jour ni un reste prévient que désactiver l'élément peut empêcher son app de fonctionner. `Space` coche le changement de la ligne : désactiver l'élément (`launchctl disable`, puis `bootout`) ou le réactiver (`enable`, puis `bootstrap`). `⌫` marque la ligne pour la suppression, et la démarque à nouveau (la ligne affiche **Delete**) : Lightspot arrête l'élément, désactive son étiquette pour qu'une copie que son app réécrirait ne se charge pas, et met son plist à la Corbeille ; le plan montre les commandes équivalentes (`launchctl bootout`, `launchctl disable`, `mv … ~/.Trash/`). Supprimer un assistant d'une app encore installée peut empêcher l'app de fonctionner, et l'app peut le remettre à son prochain lancement ; la ligne et le plan le disent. Un **Leftover**, dont macOS confirme que le programme n'existe plus, est supprimé de la même façon et c'est la seule ligne cochée au départ. Un programme dans un dossier que macOS protège ou sur un autre disque, et un interpréteur qui reçoit du code en ligne (`-c`, `-e`), ne sont jamais jugés disparus, et un plist qui est un lien symbolique ou partage son étiquette avec un autre plist n'est jamais déplacé, donc ne peut pas être supprimé. Vos propres agents changent sous votre compte ; le changement de chaque daemon et chaque déplacement que seul un administrateur peut faire partagent une seule demande administrateur, et le changement d'un daemon vaut pour tous les comptes de ce Mac, alors que désactiver ou réactiver un élément de `/Library/LaunchAgents` ne vaut que pour votre compte ; supprimer un daemon ou un élément de `/Library/LaunchAgents` vaut pour tous les utilisateurs et peut demander votre mot de passe. Seul compte ce que launchd confirme : le reçu dit où est allé chaque plist supprimé, et ce qui tourne encore (un daemon jusqu'au redémarrage, un agent jusqu'à la déconnexion) ou ne s'est pas chargé. Un plist qui est un lien symbolique est suivi dossier par dossier, jamais vers un dossier que macOS protège, un autre disque ou `~/Library/CloudStorage`. La dernière ligne ouvre les éléments de connexion dans les Réglages Système.
- **Annuler** : avant de changer un réglage pour la première fois, Lightspot enregistre la valeur qu'il a trouvée dans `~/Library/Application Support/Lightspot/tweaks-journal.json`, et le changement n'a lieu qu'une fois cet enregistrement réussi. Cocher une ligne On l'annule : retour à cette valeur, ou à la valeur par défaut de macOS quand Lightspot n'en a enregistré aucune, comme l'indique le plan. **Undo everything Lightspot changed** remet tout ce qui est consigné et supprime le profil après une seule demande administrateur. Il réactive aussi les éléments d'arrière-plan que Lightspot a désactivés (consignés avant d'être désactivés) et ne relance que ce qui tournait avant, leurs daemons passant dans cette même demande. Une entrée dont le plist n'existe plus n'exécute rien et est abandonnée, et launchd garde son interrupteur désactivé. Il remet aussi les éléments d'arrière-plan que Lightspot a supprimés : chaque plist revient de la Corbeille à sa place, réactivé et relancé seulement comme il l'était avant ; ceux de root dans cette même demande, et seulement un fichier qui appartient à root. Il ne remplace jamais un fichier qui s'y trouve maintenant (si l'app en a réécrit un, Lightspot le réactive seulement), et un plist qui n'est plus dans la Corbeille est signalé et abandonné. Un réglage appliqué en partie est le vôtre : il est seulement complété, jamais annulé. Les fichiers que Free Up Space a mis à la Corbeille et la sauvegarde de Clear Dock Icons n'en font pas partie.
- **Mot de passe seulement quand un administrateur doit agir** : pour supprimer des instantanés, pour déplacer un élément qui appartient à un autre utilisateur ou que les permissions d'un dossier vous empêchent de déplacer (sa ligne indique **May ask for password**), pour désactiver ou réactiver un daemon, pour supprimer un daemon ou un élément de `/Library/LaunchAgents` et le remettre, et pour supprimer le profil de Lightspot. Ce qu'une opération demande comme administrateur tient dans un seul script, exécuté une seule fois, via Touch ID pour sudo ou la boîte de dialogue du mot de passe. Installer le profil, c'est vous qui le faites dans les Réglages Système.
- **Touches** : `↑↓` sélectionne (la ligne sélectionnée affiche ses éléments, ses modèles ou ses commandes), `Space` coche (sur un préréglage, ses lignes ; dans Background Items, le changement de la ligne), `⌫` marque un élément d'arrière-plan pour la suppression, `⇥` / `⇧⇥` changent de section, `↵` affiche le plan détaillé et `↵` à nouveau l'applique, `⌥↵` montre dans le Finder le premier élément d'une ligne de Free Up Space ou le plist d'un élément d'arrière-plan, `Esc` quitte le plan ou arrête d'attendre les Réglages Système, et sinon ferme la fenêtre, comme `⌘W`.
- **Reçus** : chaque opération se termine par un reçu, avec une coche verte quand elle a fait ce qui était demandé. Une fois lancée, l'opération continue même si vous fermez la fenêtre, et rouvrir Mac Tweaks montre la progression, puis le reçu. Chaque opération est consignée dans `~/Library/Application Support/Lightspot/mac-tweaks.log`. Une section dont l'analyse a été rendue caduque par l'opération d'une autre refait son analyse : Apple Intelligence et Settings partagent le profil, Settings et Background Items le journal d'annulation.
- **Jamais touché** : Free Up Space ne touche jamais rien sous `/System`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, iCloud Drive, `~/Library/Containers`, `~/Library/Group Containers`, Mail, Messages ni les sauvegardes d'iPhone (`MobileSync`), ni rien à l'intérieur d'un paquet d'app : chaque chemin doit se trouver directement dans l'un des dossiers fixes de sa ligne, tel qu'écrit et liens symboliques résolus, ne doit pas être lui-même un lien symbolique, et repasse ce contrôle juste avant d'être déplacé. Apple Intelligence et Settings ne touchent à rien de ce qu'un autre profil de configuration fixe. Background Items ne liste jamais les éléments de macOS et ne change rien hors de ses trois dossiers, lance `launchctl` directement, jamais via un shell, et, en tant que root, n'agit que sur une étiquette et un plist que l'analyse a trouvés. Mac Tweaks ne lit rien tant que vous ne l'ouvrez pas et ne fait aucune requête réseau.
- **Crédits** : Free Up Space, Apple Intelligence, Settings et Background Items reprennent la logique de [RemoveMacAI](https://github.com/omlahore/RemoveMacAI) d'omlahore (licence MIT). Son travail sur Apple Intelligence s'appuie sur [pared](https://github.com/4evy/pared) de 4evy (licence MIT), que suivent le pont de Lightspot vers le service d'assets, son catalogue de modèles et son blocage des téléchargements. Voir [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## ✨ Capacités Intégrées Supplémentaires

- **Interface exacte de macOS Spotlight** : Pilule flottante translucide en forme de cercle carré avec expansion animée et panneau d'aperçu (`NSVisualEffectView`).
- **Affichage Matériel Mach / IOKit** : Diagnostics matériels instantanés sans sous-processus (`sys`, `cpu`, `ram`, `memory`, `disk`, `battery`, `uptime`, `specs`, `resources`) :
  - Charge CPU multicœur normalisée %
  - RAM Physique Active, Résidente (Wired), Compressée, et Totale
  - Stockage libre et total du SSD de démarrage
  - Pourcentage de batterie et état de charge
- **Mathématiques Intelligentes & Conversions Souples** : Analyseur mathématique complet à descente récursive prenant en charge les unités, les devises, et les bases numériques :
  - Math : `(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - Unités : `100km in mi`, `72F in C`, `16GB in MB`
  - Devise : `$100 in EUR`, `50 GBP in USD`
  - Bases numériques : `0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **Signets, Historique & Onglets du Navigateur par Défaut** : Intégration sans redondance, uniquement pour votre navigateur par défaut actif (**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**). Les signets et l'historique récent sont lus depuis les fichiers du navigateur lui-même (l'historique couvre les 3 ou 7 derniers jours, 7 par défaut, ou peut être désactivé via **Browser History** dans la barre des menus) ; les onglets ouverts sont interrogés dans Safari et les navigateurs basés sur Chromium.
- **Presse-papiers Éphémère en Mémoire** : Tampon circulaire volatile uniquement en RAM (jusqu'à 50 éléments) accessible via `clip <query>`. N'écrit jamais sur le disque et filtre strictement les gestionnaires de mots de passe (`1Password`, `Bitwarden`).
- **Liens Profonds des Paramètres Système macOS** : 46 liens profonds directs ouvrant des volets spécifiques des paramètres de macOS (`x-apple.systempreferences:...`), trouvés avec les mêmes termes que la recherche des Réglages Système (`night shift`, `lockdown mode`, `sticky keys`), dans les langues de votre système. Sur macOS 27.2, où les Réglages Système peuvent se fermer sans que LaunchServices le remarque pendant une minute ou plus, Lightspot ouvre le volet dans les Réglages Système déjà ouverts, ou n'en lance de nouveaux que s'il n'y en a aucun, au lieu de l'alerte disant qu'ils ne sont plus ouverts ; aucune copie ne s'accumule dans le Dock.
- **Recherche Web Multi-Moteurs** : Raccourcis de préfixes intégrés : `g` (Google), `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `yt`, `ddg`, ainsi que `brew <formule>`, qui ouvre la page de cette formule sur formulae.brew.sh au lieu de lancer une recherche.

---

## 🛑 Gestion Complète de macOS Spotlight

Lightspot inclut des automatisations intégrées dans la barre de menus pour désactiver ou réactiver le Spotlight intégré d'Apple :

1. **Raccourci Spotlight (`⌘Space`)** : Désactive ou restaure les raccourcis Spotlight par défaut d'Apple, à la fois `⌘Space` (« Afficher la recherche Spotlight ») et `⌥⌘Space` (« Afficher la fenêtre de recherche du Finder »), sans nécessiter d'accès root. La modification est écrite via le démon de préférences, vérifiée par relecture et appliquée immédiatement (sans déconnexion) ; de plus, Lightspot revendique `⌘Space` dès que macOS le libère.
2. **Processus d'Arrière-plan (`com.apple.Spotlight`)** : Désactive ou active l'agent d'arrière-plan GUI de Spotlight via `launchctl`. L'activation charge et démarre aussi l'agent : Spotlight revient sans fermer la session.
3. **Indexation de Fichiers (`mdutil`)** : Arrête complètement l'indexation des métadonnées du système de fichiers (`mds` / `mds_stores`) sur tous les volumes montés.
4. **Actions Maîtresses en 1 Clic** :
   - **`Tout Désactiver (Raccourci + Processus + Indexation)...`** : Arrête complètement Apple Spotlight pour récupérer du CPU, de la RAM, de l'espace disque, et `⌘Space`.
   - **`Restaurer Spotlight par Défaut...`** : Rétablit tous les paramètres aux valeurs par défaut d'usine de macOS à tout moment.

---

## 🚀 Construction & Installation (Aucun Xcode Requis)

### 📦 Option A : Installation en une ligne (Recommandée)
Téléchargez et installez directement la dernière version précompilée. Chaque release contient `Lightspot-arm64.zip` (Apple silicon, environ 1,6 Mo) et `Lightspot-x86_64.zip` (Intel, environ 1,75 Mo), que l'installeur et la mise à jour intégrée choisissent pour votre Mac, `Lightspot.zip`, l'app universelle (environ 2,9 Mo), et `Lightspot.app.dSYM.zip`, les symboles qui servent à lire les rapports de plantage :
```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

### 🛠️ Option B : Construire depuis les sources (Dépôt local)
```bash
# 1. Construire le paquet de release
./build.sh
# ou : make build

# 2. Exécuter directement
./run.sh
# ou : make run

# 3. Installer dans /Applications (ou dans ~/Applications avec --user)
./install.sh
# ou : make install

# 4. Désinstaller
./uninstall.sh
# ou : make uninstall
```

`./build.sh` compile chaque architecture avec l'optimisation complète à l'édition de liens (LTO) et retire les noms des symboles locaux, qu'il garde dans `build/Lightspot.app.dSYM` : le binaire universel de 1.4.0 pèse 5,1 Mo, 42 % de moins que les 8,8 Mo de 1.3.9, et 2,2 Mo pour Apple silicon seul (2,9 Mo pour Intel).

### 4. Tests & Vérification
Lightspot n'a pas de cible XCTest. Trois scripts autonomes dans `scripts/` sont compilés à la volée avec les sources et s'exécutent depuis la racine du dépôt : un exécuteur de tests de logique et de moteur (84 blocs de tests), un vérificateur du système en direct (15 sections, 206 vérifications sur le Mac du développeur sous macOS 27.2 ; certaines sont ignorées s'il n'y a, par exemple, ni historique zsh ni VS Code installé, ou si GitHub est injoignable) et une vérification qui crée hors écran les vraies fenêtres de Mac Tweaks et de Clean Dev Mac sur des analyses en lecture seule, fait passer chaque section de Mac Tweaks par des réanalyses et des changements de section, et les deux fenêtres par leurs touches :
```bash
# Tests de logique de base & moteur (84 blocs de tests)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# Vérifications du système en direct (15 sections, 206 vérifications sous macOS 27.2)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify

# Les fenêtres de Mac Tweaks et de Clean Dev Mac, hors écran (environ une minute)
swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift) && /tmp/overlay_check
```

---

## ⌨️ Raccourcis & Navigation

| Touche | Action |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | Invoquer ou rejeter Lightspot n'importe où (configurable dans la barre de menus) |
| **`↓` / `↑`** | Naviguer dans les résultats de recherche |
| **`Return` (`↵`)** | Ouvrir l'application sélectionnée, le projet dans l'IDE, exécuter la commande, ou copier le calcul |
| **`⌘Return` (`⌘↵`)** | Ouvrir le projet sélectionné dans le Terminal préféré |
| **`⌥Return` (`⌥↵`)** | Révéler le projet dans le Finder / Forcer l'arrêt du processus sélectionné (`SIGKILL`) / Ouvrir la page GitHub d'un installeur / Montrer dans le Finder le premier élément d'une ligne de Mac Tweaks |
| **`⌘P`** | Épingler ou désépingler la commande d'Historique du Terminal sélectionnée |
| **`⌘⇧P`** | Ouvrir la superposition du gestionnaire de commandes épinglées |
| **`⌘⇧C`** | Ouvrir la superposition du gestionnaire de commandes personnalisées |
| **`Space`** | Cocher ou décocher une catégorie dans Clean Dev Mac ou une ligne dans Mac Tweaks |
| **`Delete` (`⌫`)** | Marquer ou démarquer un élément d'arrière-plan pour la suppression dans Mac Tweaks |
| **`Tab` (`⇥`)** | Analyser aussi vos dépôts de code dans Clean Dev Mac / Section suivante dans Mac Tweaks (`⇧⇥` la précédente) |
| **`⌘Y`** / **`⌘⇧H`** | Ouvrir la superposition du gestionnaire d'historique de recherche |
| **`Escape`** | Rejeter les superpositions, effacer le champ de recherche, ou fermer Lightspot ; dans les fenêtres de Mac Tweaks et de Clean Dev Mac, revenir en arrière, puis fermer la fenêtre |
| **`⌘W`** | Fermer la fenêtre de Mac Tweaks ou de Clean Dev Mac |
| **Cliquer en Dehors** | Rejette automatiquement le panneau flottant |

Le raccourci d'invocation est celui que vous choisissez parmi les quatre dans **Shortcut**, dans la barre des menus. macOS attribue `⌃Space` à « Sélectionner la source de saisie précédente » : si vous le choisissez, la frappe change donc aussi votre source de saisie ; le sous-menu **Shortcut** indique quel raccourci système occupe déjà la combinaison choisie.

---

## 🔒 Garanties de Confidentialité & de Sécurité

- **Zéro Indexation de Fichiers** : Lightspot n'indexe jamais vos fichiers personnels, documents, téléchargements, ou dépôts de code. Clean Dev Mac ne mesure que les dossiers de cache nommés par les règles de cdm et les quelques emplacements dont ses deux notes ont besoin (voir plus bas), seulement quand vous l'ouvrez, et ne garde que les tailles ; il ne lit jamais les conteneurs sandbox des autres apps. Pour ses lignes Android et Claude Code, il lit aussi les dates des fichiers de vos dossiers d'AVD et de `~/.claude/projects`, et les petits fichiers de `~/.claude/sessions` qui nomment les sessions en cours ; jamais ce que dit une transcription. Pour les copies de Chrome qu'un navigateur arrêté de force laisse derrière lui, il les liste dans votre propre dossier temporaire et lit l'heure de lancement de vos apps ouvertes. Pour les deux notes de cdm, il lit la quantité de swap utilisée, mesure les dossiers temporaires que macOS vide au démarrage ainsi que `~/.claude/projects`, demande à `lsof` les fichiers supprimés que vos apps gardent encore ouverts (il ne garde que leur total et les noms des trois plus gros détenteurs) et lit deux clés de `~/.claude/settings.json` (`cleanupPeriodDays`, `desktopSessionCleanupPeriodDays`), qu'il ne modifie jamais. Quand vous lui demandez d'analyser vos dépôts (`⇥`), il cherche les dépôts git de votre dossier personnel, jusqu'à six niveaux, sans entrer dans `~/Library`, `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies` ni `~/Music`, et demande au git de chaque dépôt quels fichiers il ignore. Mac Tweaks lit une liste fixe d'emplacements, seulement pour la section que vous ouvrez. Free Up Space : les noms de `/Applications` et l'`Info.plist` des Install macOS et de GarageBand, iMovie, Keynote, Numbers et Pages qui s'y trouvent ; le contenu de `~/Library/iTunes/iPhone Software Updates` et `iPad Software Updates`, de `/Library/Application Support/com.apple.idleassetsd/Customer` et de `~/Library/Caches`, avec la taille et le propriétaire de chaque élément proposé ; les trois dossiers de la bibliothèque de GarageBand et la présence de Logic Pro ou de MainStage ; la liste des simulateurs indisponibles que donne le `simctl` de Xcode et les dates des instantanés locaux que donne `tmutil` ; l'index des fonds d'écran (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) quand il y a des vidéos aériennes à proposer ; et les règles de Clean Dev Mac. Quand il applique, il vérifie les noms dans `~/.Trash` un par un et ne liste jamais la Corbeille. Apple Intelligence : l'inventaire des ensembles de modèles et de leurs tailles que tient le service d'assets, lu par le processus auxiliaire de courte durée, qui ne lit aucun dossier (seulement pendant une suppression, le nombre d'entrées du dossier d'un ensemble dans `/System/Library/AssetsV2`, jamais une liste), ainsi que les réglages des fonctions et les marqueurs des deux profils via cfprefsd. Settings : les préférences et restrictions de ses 41 réglages, les icônes du Dock et le marqueur du profil via cfprefsd, la liste des services désactivés de launchctl, les numéros d'inode de Music.app et de son exécutable, l'attribut masqué du dossier Library et son journal d'annulation. Background Items : les noms de `~/Library/LaunchAgents`, `/Library/LaunchAgents` et `/Library/LaunchDaemons` et chaque `.plist` qui s'y trouve, seulement s'il s'agit d'un fichier ordinaire de 1 Mio au plus, dont il ne garde que l'étiquette, le programme, les arguments, les identifiants des apps associées et `Disabled` (les arguments ne sont jamais affichés ni consignés) ; `launchctl print-disabled` pour votre compte et pour le système, et `launchctl print` pour chaque élément, dont il ne garde que le code de sortie, car sa sortie liste l'environnement de la tâche ; chaque programme que nomme un plist, ou le script qu'exécute un interpréteur, vérifié dossier par dossier et jamais dans un dossier que macOS protège, sur un autre disque ou dans `~/Library/CloudStorage` ; le propriétaire de chaque plist ; LaunchServices, pour les apps que nomme un plist ; et les entrées d'éléments d'arrière-plan du journal d'annulation. Tant que le journal contient des éléments d'arrière-plan, Settings lit une fois les trois dossiers pour le plan d'Undo everything. Une fois qu'une analyse a plus de cinq minutes, fermer Mac Tweaks oublie ce qu'elle a trouvé et ne garde que le total de Free Up Space et ce que l'analyse d'Apple Intelligence a lu sur les modèles.
- **Presse-papiers Éphémère Uniquement en RAM** : L'historique du presse-papiers reste exclusivement dans la mémoire volatile et ignore activement les types dissimulés/gestionnaires de mots de passe (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`). Il n'est jamais écrit sur le disque, pas même dans l'historique de recherche, qui ne conserve pas non plus le texte que vous copiez depuis les résultats de la calculatrice, des outils développeur ou des extraits.
- **Isolation du Navigateur par Défaut** : Les signets, les onglets ouverts et l'historique récent sont lus localement et uniquement depuis votre navigateur par défaut configuré, évitant le grattage (scraping) inter-navigateurs.
- **Commandes Déclenchées par l'Utilisateur** : Vos commandes, scripts et actions rapides ne s'exécutent qu'après une action explicite de l'utilisateur (`Return` ou `⌘↵`).
- **Commandes Administrateur Exécutées Une Seule Fois** : Une commande privilégiée passe par `sudo` avec Touch ID, ou par la boîte de dialogue du mot de passe de macOS, et depuis la 1.4.0 jamais deux fois : elle affiche d'abord un marqueur aléatoire, et dès que ce marqueur montre que sudo l'a lancée, son résultat est définitif ; une commande qui échoue sous Touch ID n'est donc plus relancée derrière la boîte de dialogue du mot de passe. Après le marqueur, son entrée standard est `/dev/null`, si bien que rien de ce qu'elle lance n'attend sur le terminal caché. Les scripts que Lightspot construit lui-même (le lot administrateur de Mac Tweaks, chaque argument entre apostrophes) passent par un autre point d'entrée qui les laisse tels quels. Le journal système ne reçoit que le fait qu'une commande privilégiée a été exécutée et son code de sortie, jamais son texte, qui peut contenir les chemins de vos fichiers.
- **Zéro Télémétrie, Deux Services Que Vous Contrôlez** : Aucune analyse, aucun suivi, aucun compte. Lightspot ne communique de lui-même qu'avec exactement deux services, et vous décidez des deux. Le premier est GitHub, pour les mises à jour : un `GET` non authentifié vers l'API publique des releases (`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`) avec `User-Agent: Lightspot/<version> (+https://github.com/openhoangnc/mac-lightspot)`, peu après le lancement et à l'ouverture du menu de la barre des menus, mais pas plus d'une fois par jour après une vérification réussie (une vérification échouée est relancée au lancement suivant ou à la prochaine ouverture du menu). Désactivez **`Automatically Check for Updates`** dans la barre de menus et elle ne part jamais d'elle-même. Installer une mise à jour que vous avez acceptée télécharge son zip depuis GitHub (`User-Agent: Lightspot/<version>`). Les deux passent par une session éphémère : aucune réponse ni aucun cookie n'est stocké sur le disque. Les versions plus anciennes passaient plutôt par la session partagée de macOS (la vérification des mises à jour jusqu'à la 1.2.0, la recherche d'IP avant la 1.2.0), qui conservait les réponses dans `~/Library/Caches/com.lightspot.app` et les cookies dans `~/Library/HTTPStorages` ; Lightspot supprime ces restes au lancement, et le désinstalleur les retire aussi. Le second est ipify : `GET https://api.ipify.org` (un service tiers) pour connaître votre IP publique, et uniquement lorsque vous la demandez : en tapant une requête qui la nomme (`ip`, `my ip`, `public ip`, `ipv4`) ou en appuyant sur `Return` sur la ligne **IP Address**. ipify voit votre adresse IP et un user agent macOS standard, comme n'importe quel serveur web. La réponse est gardée en mémoire 15 minutes et n'est jamais écrite sur le disque. Ouvrir **Clean Dev Mac** demande aussi à GitHub les fichiers de règles de cdm (`GET https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/index.json` et les fichiers qu'il liste, avec un user agent macOS standard, via une session éphémère), au plus une fois par heure ; ils restent en mémoire et, sans connexion, la copie intégrée à l'app est utilisée. Vous l'évitez entièrement en gardant vos propres règles dans `~/.cleandevmac/rules`. Mac Tweaks ne fait aucune requête : il lit les règles de Clean Dev Mac en mémoire, dans `~/.cleandevmac/rules` ou dans la copie intégrée à l'app, et ne les télécharge jamais. Lancer cdm dans le terminal (`⌘↵`) télécharge son script depuis la release GitHub de cdm, comme l'indiquent les instructions de cdm. Les lignes d'installation fonctionnent de même : chacune lance l'installeur de son outil dans votre terminal, et c'est ce script, pas Lightspot, qui télécharge depuis GitHub. Les recherches web, les URL et les signets sont ouverts par votre navigateur, et seulement lorsque vous appuyez sur `Return`.
- **Ce Qui Est Écrit sur le Disque** : Les préférences de Lightspot (`UserDefaults`, dans `~/Library/Preferences/com.lightspot.app.plist`), un fichier de verrou, des fichiers temporaires pendant l'installation d'une mise à jour, un reçu dans le journal de cdm quand vous nettoyez, et les petits fichiers de Mac Tweaks quand vous y appliquez quelque chose :
  - Réglages : `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state` (dernier état connu de Spotlight, pour les libellés du menu), `lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version` (vérifications automatiques des mises à jour).
  - Ce que vous créez : `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`.
  - Utilisation : `lightspot_recent_app_bundle_ids` (apps lancées récemment) et `lightspot_search_history` : les requêtes saisies et les résultats ouverts (titres, chemins d'apps et de projets, URL, commandes shell), plus les compteurs de sélection pour le classement. Consultez-le ou effacez-le dans le gestionnaire d'historique de recherche (`⌘Y`). Les sélections du presse-papiers, de la calculatrice et des outils développeur ne sont jamais enregistrées ; celles des extraits et du rapport matériel ne gardent que la requête et un compteur, jamais le texte copié.
  - `~/.cleandevmac/clean.log`, uniquement quand vous nettoyez avec Clean Dev Mac : ce que chaque nettoyage a supprimé ou mis à la Corbeille, ajouté au journal que tient cdm lui-même (plafonné à 1 Mio, comme celui de cdm). Ce que vous confirmez dans le nettoyeur est supprimé définitivement, sauf les catégories marquées Trash, qui vont à la Corbeille.
  - `~/Library/Application Support/Lightspot/mac-tweaks.log`, uniquement quand vous appliquez quelque chose dans Mac Tweaks : quand chaque opération a commencé et fini, ce qu'elle a changé, mis à la Corbeille ou supprimé, ce qui est resté et pourquoi, et combien elle a libéré. Au-delà de 1 Mio, il garde les 256 Kio les plus récents, comme le journal de cdm. Les fichiers que vous confirmez dans Free Up Space vont à la Corbeille ; les simulateurs indisponibles et les instantanés Time Machine sont supprimés définitivement.
  - `~/Library/Application Support/Lightspot/tweaks-journal.json`, le journal d'annulation de Mac Tweaks : la valeur qu'avait chaque réglage avant que Lightspot ne le change et, pour chaque élément d'arrière-plan qu'il a désactivé ou supprimé, s'il était désactivé et chargé, et pour un supprimé où était son plist et où il est allé dans la Corbeille ; chaque entrée est enregistrée avant le changement et retirée une fois annulée. Un journal que Lightspot ne peut pas lire n'est jamais écrasé : il est mis de côté sous le nom `tweaks-journal-unreadable-<date>-<id>.json`. Settings écrit aussi des préférences d'autres apps (celles du Finder, du Dock, du domaine global…), seulement celles que vous appliquez, chacune consignée d'abord.
  - `~/Library/Application Support/Lightspot/dock-backup.plist`, écrit par Clear Dock Icons avant de vider le Dock et supprimé par Restore Dock Icons une fois les icônes revenues.
  - `~/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig`, seulement pendant qu'une opération attend que vous approuviez le profil de Lightspot, et supprimé une fois qu'il est installé. Le profil lui-même, **Lightspot Mac Tweaks**, c'est vous qui l'installez dans les Réglages Système, et il s'applique à tous les comptes de ce Mac ; le supprimer là annule tout ce qu'il a changé.
  - Le désinstalleur supprime tout cela sauf les journaux d'annulation et la sauvegarde du Dock, qu'il garde pour qu'un Lightspot réinstallé puisse encore annuler, et il dit ce qui reste et comment l'annuler ; les éléments d'arrière-plan pour tous les utilisateurs que Lightspot a désactivés restent désactivés pour tous les comptes.
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`, qui empêche une deuxième copie de démarrer. Il contient le PID du processus en cours ainsi que le chemin, l'inode et la date de modification de son exécutable, pour qu'un nouveau lancement distingue la même version d'une plus récente.
  - Pendant l'installation d'une mise à jour que vous avez acceptée : le téléchargement, le paquet décompressé et un petit script d'aide dans le dossier temporaire de macOS (`NSTemporaryDirectory()`, dossiers `lightspot-update-…` et `lightspot-updater-…`), et la version précédente conservée sous le nom `Lightspot.app.lightspot-old` à côté de l'app jusqu'à ce que la nouvelle soit en place. Le script d'aide les supprime tous en terminant.
  - **Export Settings** écrit une sauvegarde JSON, historique de recherche compris, uniquement dans le fichier que vous choisissez.
