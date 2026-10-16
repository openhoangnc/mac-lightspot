# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **Un remplaçant léger et au pixel près pour macOS Spotlight, conçu en pur Swift — conçu pour les développeurs et les utilisateurs expérimentés qui veulent une vitesse instantanée sans la lourdeur de l'indexation des fichiers.**

Lightspot reproduit fidèlement le design moderne en forme de pilule flottante et l'esthétique de verre translucide de macOS Spotlight (`NSVisualEffectView`). Sous le capot, il offre une réactivité inférieure à la milliseconde (< 1,0 ms de recherche) avec **zéro indexation de fichiers en arrière-plan**. Au repos, son seul travail périodique est une légère vérification du presse-papiers toutes les 0,6 s, et il utilise moins de **25 Mo de RAM**.

![Capture d'écran de Lightspot](screenshot.png)

---

## ⚡ Démarrage Rapide

### 📦 Téléchargement & Installation en une ligne
Copiez et collez simplement cette commande dans votre Terminal pour télécharger, extraire et installer automatiquement la dernière version de **Lightspot** dans votre dossier `/Applications` :

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
| **Stockage Disque** | 10 Go – 200 Go+ cache caché | 100 Mo – 1 Go | **Ni index ni cache** (vos réglages dans `UserDefaults` et un fichier de verrou) |
| **Empreinte RAM** | 500 Mo – 2 Go+ | 200 Mo – 500 Mo | **~15 – 25 Mo** (Pur Swift) |
| **Lancement d'App** | Se casse fréquemment ; requiert des reconstructions | Fiable | **100% Fiable** (Analyse directe) |
| **Latence de Recherche** | Temporisée (50 – 200 ms) | 10 – 30 ms | **< 1,0 ms** (Synchrone instantané) |
| **Confidentialité Hors Ligne** | Envoie la télémétrie de Siri à Apple | Compte requis pour la synchro | **Local & Sans Télémétrie** (réseau uniquement pour une vérification des mises à jour optionnelle et une recherche d'IP que vous demandez) |

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
- Installation sur place : Lightspot télécharge la release, la vérifie, remplace son propre bundle et redémarre. **`Skip This Version`** met en sourdine une release précise sans désactiver les vérifications.
- Chaque téléchargement est filtré : HTTPS uniquement, hôtes GitHub uniquement (revérifiés après les redirections), le bundle décompressé doit porter l'identifiant de bundle de Lightspot, un exécutable fonctionnel et exactement la version annoncée, et une version antérieure à celle déjà installée n'est jamais acceptée.
- Les releases sont signées en ad-hoc (ce projet ne fournit aucun Developer ID), il n'y a donc aucune signature de code à vérifier : les contrôles ci-dessus et HTTPS vers GitHub constituent tout le modèle de confiance, celui-là même que `install.sh` exige déjà.

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
- **Signets, Historique & Onglets du Navigateur par Défaut** : Intégration sans redondance, uniquement pour votre navigateur par défaut actif (**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**). Les signets et l'historique récent sont lus depuis les fichiers du navigateur lui-même (l'historique couvre les 3 ou 7 derniers jours, 7 par défaut, ou peut être désactivé via **Browser History** dans la barre des menus) ; les onglets ouverts sont interrogés dans Safari et les navigateurs basés sur Chromium.
- **Presse-papiers Éphémère en Mémoire** : Tampon circulaire volatile uniquement en RAM (jusqu'à 50 éléments) accessible via `clip <query>`. N'écrit jamais sur le disque et filtre strictement les gestionnaires de mots de passe (`1Password`, `Bitwarden`).
- **Liens Profonds des Paramètres Système macOS** : 35 liens profonds directs ouvrant des volets spécifiques des paramètres de macOS (`x-apple.systempreferences:...`).
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
Téléchargez et installez directement la dernière version précompilée :
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

### 4. Tests & Vérification
Lightspot n'a pas de cible XCTest. Deux scripts autonomes dans `scripts/` sont compilés à la volée avec les sources : un exécuteur de tests de logique et de moteur (32 blocs de tests) et un vérificateur du système en direct (10 sections, 88 vérifications sur une machine complète ; certaines sont ignorées s'il n'y a, par exemple, ni historique zsh ni VS Code installé) :
```bash
# Tests de logique de base & moteur (32 blocs de tests)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift && /tmp/test_engine

# Vérifications du système en direct (10 sections, 88 vérifications sur une machine complète)
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

## 🔒 Garanties de Confidentialité & de Sécurité

- **Zéro Indexation de Fichiers** : Lightspot n'indexe jamais vos fichiers personnels, documents, téléchargements, ou dépôts de code.
- **Presse-papiers Éphémère Uniquement en RAM** : L'historique du presse-papiers reste exclusivement dans la mémoire volatile et ignore activement les types dissimulés/gestionnaires de mots de passe (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`). Il n'est jamais écrit sur le disque, pas même dans l'historique de recherche, qui ne conserve pas non plus le texte que vous copiez depuis les résultats de la calculatrice, des outils développeur ou des extraits.
- **Isolation du Navigateur par Défaut** : Les signets, les onglets ouverts et l'historique récent sont lus localement et uniquement depuis votre navigateur par défaut configuré, évitant le grattage (scraping) inter-navigateurs.
- **Commandes Déclenchées par l'Utilisateur** : Vos commandes, scripts et actions rapides ne s'exécutent qu'après une action explicite de l'utilisateur (`Return` ou `⌘↵`).
- **Zéro Télémétrie, Deux Services Que Vous Contrôlez** : Aucune analyse, aucun suivi, aucun compte. Lightspot ne communique de lui-même qu'avec exactement deux services, et vous décidez des deux. Le premier est GitHub, pour les mises à jour : un `GET` non authentifié vers l'API publique des releases (`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`) avec `User-Agent: Lightspot/<version> (+https://github.com/openhoangnc/mac-lightspot)`, peu après le lancement et à l'ouverture du menu de la barre des menus, mais pas plus d'une fois par jour après une vérification réussie (une vérification échouée est relancée au lancement suivant ou à la prochaine ouverture du menu). Désactivez **`Automatically Check for Updates`** dans la barre de menus et elle ne part jamais d'elle-même. Installer une mise à jour que vous avez acceptée télécharge son zip depuis GitHub (`User-Agent: Lightspot/<version>`). Les deux passent par une session éphémère : aucune réponse ni aucun cookie n'est stocké sur le disque. Le second est ipify : `GET https://api.ipify.org` (un service tiers) pour connaître votre IP publique, et uniquement lorsque vous la demandez : en tapant une requête qui la nomme (`ip`, `my ip`, `public ip`, `ipv4`) ou en appuyant sur `Return` sur la ligne **IP Address**. ipify voit votre adresse IP et un user agent macOS standard, comme n'importe quel serveur web. La réponse est gardée en mémoire 15 minutes et n'est jamais écrite sur le disque. Les recherches web, les URL et les signets sont ouverts par votre navigateur, et seulement lorsque vous appuyez sur `Return`.
- **Ce Qui Est Écrit sur le Disque** : Les préférences de Lightspot (`UserDefaults`, dans `~/Library/Preferences/com.lightspot.app.plist`), un fichier de verrou, et des fichiers temporaires pendant l'installation d'une mise à jour :
  - Réglages : `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state` (dernier état connu de Spotlight, pour les libellés du menu), `lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version` (vérifications automatiques des mises à jour).
  - Ce que vous créez : `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`.
  - Utilisation : `lightspot_recent_app_bundle_ids` (apps lancées récemment) et `lightspot_search_history` : les requêtes saisies et les résultats ouverts (titres, chemins d'apps et de projets, URL, commandes shell), plus les compteurs de sélection pour le classement. Consultez-le ou effacez-le dans le gestionnaire d'historique de recherche (`⌘Y`). Les sélections du presse-papiers, de la calculatrice et des outils développeur ne sont jamais enregistrées ; celles des extraits et du rapport matériel ne gardent que la requête et un compteur, jamais le texte copié.
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`, qui empêche une deuxième copie de démarrer. Il contient le PID du processus en cours ainsi que le chemin, l'inode et la date de modification de son exécutable, pour qu'un nouveau lancement distingue la même version d'une plus récente.
  - Pendant l'installation d'une mise à jour que vous avez acceptée : le téléchargement, le paquet décompressé et un petit script d'aide dans le dossier temporaire de macOS (`NSTemporaryDirectory()`, dossiers `lightspot-update-…` et `lightspot-updater-…`), et la version précédente conservée sous le nom `Lightspot.app.lightspot-old` à côté de l'app jusqu'à ce que la nouvelle soit en place. Le script d'aide les supprime tous en terminant.
  - **Export Settings** écrit une sauvegarde JSON, historique de recherche compris, uniquement dans le fichier que vous choisissez.
