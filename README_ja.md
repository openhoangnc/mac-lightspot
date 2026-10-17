# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **純粋なSwiftで構築された、macOS Spotlightの軽量かつピクセルパーフェクトな代替ツール — ファイルのインデックス作成による肥大化を避け、瞬時の速度を求める開発者やパワーユーザーのために設計されています。**

Lightspotは、macOS Spotlightのモダンなフローティングピルデザインと半透明のガラスのような美しさ（`NSVisualEffectView`）を忠実に再現しています。その内部では、**バックグラウンドでのファイルインデックス作成を一切行わず**、アイドル時の定期的な処理は0.6秒ごとの軽量なクリップボード確認のみ、**RAM使用量25MB未満**で、サブミリ秒の応答性（検索時間1.0ミリ秒未満）を実現します。

![Lightspot スクリーンショット](screenshot.png)

---

## ⚡ クイックスタート

### 📦 ワンライナーのダウンロード＆インストール
ターミナルに以下のコマンドをコピー＆ペーストするだけで、最新の **Lightspot** が自動的にダウンロード・解凍され、`/Applications` フォルダに直接インストールされます：

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

*(オプション: `~/Applications` にインストールしたい場合は `--user` を指定します: `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash -s -- --user`)*

---

### 🗑️ 完全アンインストール
完全に削除したい場合は、このコマンドで安全にアプリを終了し、自動起動設定を解除し、ユーザー設定を消去して、アプリ本体を削除します。Lightspot が Apple Spotlight を無効にしていた場合は再び有効にします（インデックス作成の再有効化には管理者パスワードが必要です。後で実行する場合は表示される `sudo mdutil -a -i on` コマンドを使ってください）：

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash
```

*(オプション: `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash -s -- --dry-run` は何も変更せずに変更内容だけを表示します。代わりに `--keep-spotlight-disabled` を指定すると Spotlight を無効のままにします。)*

---

## 💡 なぜLightspotなのか？

Appleの組み込みSpotlightは、カジュアルなファイル検索のために設計されました。しかし、開発者やパワーユーザーにとって、Spotlightのバックグラウンドプロセスはシステムに深刻な摩擦を引き起こすことがよくあります。**Lightspotはこれを解決するために作られました。**

### 問題点: AppleのSpotlight

1. **CPUとバッテリーの消耗:** バックグラウンドデーモン（`mds`、`mdworker`）がファイルを積極的にインデックス化します。単純な `npm install` や `git checkout` だけでCPU使用率が100%に張り付き、ファンが回転し、バッテリー寿命が削られます。
2. **見つからないアプリケーション:** Spotlightのインデックスは頻繁に破損し、TerminalやSlackなどのアプリを見つけるという最も基本的な作業に失敗することがあります。これを修正するには、難解な `mdutil` コマンドを実行してインデックスをゼロから再構築する必要があります。
3. **膨れ上がるディスク使用量:** Spotlightはメタデータを隠しフォルダ `/.Spotlight-V100` に密かにキャッシュします。開発者のマシンでは、このインデックスが日常的に**50GB〜200GB**に膨れ上がり、高価なSSDストレージを無駄に消費します。
4. **メモリの独占:** Spotlightのプロセスは頻繁にリークを起こし、数ギガバイトのユニファイドRAMを消費します。このメモリは、IDEやDocker、ローカルのLLMなどのために利用可能であるべきです。
5. **望まないファイルのクロール:** システム設定を通じて `node_modules`、`.git`、`.venv` などの巨大なフォルダを除外する作業は、操作性が悪く遅いことで悪名高く、macOSのアップデート中にリセットされることもしばしばです。

*(コミュニティの報告を参照: [High CPU](https://www.reddit.com/r/MacOS/comments/1p10c3f/pages_caused_insane_cpu_spikes_on_macos_i_think_i/), [Missing Apps](https://www.reddit.com/r/MacOS/comments/1gjhiha/spotlight_not_looking_for_apps/), [Storage Waste](https://dev.to/vvo/how-to-avoid-spotlight-using-hundreds-of-gbs-and-rebuild-its-index-4kki), [Memory Leaks](https://discussions.apple.com/thread/256167358?sortBy=rank))*

---

## ⚡ 解決策: ゼロインデックスアーキテクチャ

Lightspotは根本的に異なるアプローチをとることでこれらの問題を解決します: **バックグラウンドでのファイルインデックス作成をゼロに。**

ハードドライブ全体を積極的にクロールする代わりに、Lightspotはパワーユーザーが実際に検索するもの（アプリケーション、IDEのプロジェクト、ブラウザのタブ・ブックマーク・履歴、開発者用ユーティリティ、カスタムコマンド）に厳密に焦点を当てています。

### 比較マトリックス

| 指標 | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **ファイルインデックス作成** | 制御されないバックグラウンドクロール | オプション / 設定可能 | **なし** (アーキテクチャによる保証) |
| **アイドル時のCPU使用率** | 動作時に100%+までスパイク | 1% – 5% (バックグラウンド) | **最小限** (インデックスなし。0.6秒ごとのクリップボード確認のみ) |
| **ディスクストレージ** | 10 GB – 200 GB+ の隠しキャッシュ | 100 MB – 1 GB | **インデックスもキャッシュもなし** (`UserDefaults` の設定とロックファイルのみ) |
| **RAMフットプリント** | 500 MB – 2 GB+ | 200 MB – 500 MB | **約15 – 25 MB** (Pure Swift) |
| **アプリの起動** | 頻繁に壊れ、再構築が必要 | 信頼できる | **100%の信頼性** (直接スキャン) |
| **検索レイテンシ** | デバウンス処理あり (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (瞬時の同期処理) |
| **オフライン・プライバシー** | SiriのテレメトリをAppleに送信 | 同期にはアカウントが必要 | **ローカル動作、テレメトリフリー**（通信はオプションの更新確認と、ユーザーが求めたときのIP照会のみ） |

---

## 🛠️ 開発者ファーストのカスタマイズとパワーユーザー向けワークフロー

Lightspotは、ゼロから開発者のメインのコマンドセンターとして設計されました。ターミナル、エディタ、スクリプト、ワークフローのあらゆるニーズに合わせてカスタマイズ可能です：

### 1. ⚡ カスタムコマンドとスクリプトランナー (`⌘⇧C`)
インタラクティブなカスタムコマンドエディタを **`⌘⇧C`** で開き、カスタムショートカットを作成および整理できます：
- **4つのランナーエンジン**:
  - `terminal`: お好みのターミナルエミュレータで直接コマンドを実行します。
  - `shell`: `/bin/zsh` 経由でバックグラウンドにてヘッドレスで実行します。
  - `applescript`: ネイティブのmacOS AppleScript自動化を実行します。
  - `url`: デフォルトのブラウザでテンプレートURLを開きます。
- **動的パラメータの展開**:
  - `{query}`、`%s`、または `%@` を使用して、コマンドの後に入力した引数に置換します。
- **プレフィックストリガー**:
  - コマンドに独自のプレフィックスを割り当て、`<プレフィックス> <クエリ>` と入力します（例：ヘッダーをcurlする `c <url>`、pingする `png <host>`）。エディタの **Presets** メニューには、`gh`、`g`、`yt`、`so`、`ddg`、`wiki`、`npm`、`png`、`c` の9つのプリセットコマンドが用意されています。
- **カスタムキーワードとアイコン**:
  - 即座に発見できるファジーキーワードを追加できます。コマンドのアイコンは既定でランナーのアプリアイコン（ブラウザ、ターミナル、Script Editor）になり、ランナー組み込みのシンボルへの切り替えや、独自の画像ファイル／アプリファイルの選択も可能です。

### 2. 💬 動的テキストスニペット
Lightspotには `date`、`iso`、`uuid`、`shrug`、`flip` の5つのテキストスニペットが組み込まれており、コピーする瞬間に動的変数が展開されます：
- `{{date}}`: 現在の日付 (`YYYY-MM-DD`)
- `{{time}}`: 現在の時刻 (`HH:mm:ss`)
- `{{iso}}`: ISO 8601 UTC タイムスタンプ (`2026-09-05T14:30:00Z`)
- `{{uuid}}`: ランダムなUUID v4
- `{{clipboard}}`: 現在のクリップボードの内容

スニペットのキーワード（例：`iso`、`uuid`、`date`）または名前の一部を入力して **`↵`** を押すと、評価された文字列がクリップボードに直接コピーされます。

### 3. 💻 7つのモダンなターミナルエミュレータから選択
Lightspotは、お気に入りのターミナルエミュレータと統合します。メニューバーからいつでも切り替え可能です：
- **Ghostty**、**Warp**、**Alacritty**、**iTerm2**、**Kitty**、**WezTerm**、そして **Apple Terminal**。（Warp はフォルダを開けますが、他のアプリからコマンドを渡す手段がないため、Warp を選択している場合、履歴・ピン留め・カスタムのターミナルコマンドは Apple Terminal で実行されます。）
- **"Terminal in Finder Folder"**: `term` と入力するかアクションを押すと、現在Finderで開いているディレクトリで、好みのターミナルを即座に起動します。

### 4. 📂 複数のIDEの最近のプロジェクトの検出
Lightspotは、以下の最近のワークスペースを自動的に監視します：
- **VS Code**、**Cursor**、**Zed**、**JetBrains IDE** (IntelliJ IDEA、PyCharm（Community 版を含む）、WebStorm、GoLand、CLion、RustRover、Rider、PhpStorm、DataGrip、RubyMine、DataSpell)、**Android Studio**、および **Sublime Text**。
- **キーボード修飾キー**:
  - `↵` (Return): 関連付けられたIDEでワークスペースを開きます。
  - `⌘↵` (Command + Return): プロジェクトのルートディレクトリでお好みのターミナルを起動します。
  - `⌥↵` (Option + Return): Finderでプロジェクトフォルダを表示します。

### 5. 🔌 プロセスキラーとポートターミネーター (`kill`)
残存している開発サーバー、スタックしたバックグラウンドタスク、または暴走したプロセスをすばやく終了します：
- **ポートでキル:** `kill :3000`, `kill :8080`, `kill :5173` (`lsof` 経由でそのポートを*リッスン*しているプロセスを解決します。ポートに接続しているだけのクライアントは表示されません)。
- **プロセス名またはPIDでキル:** `kill node`, `kill python`, `kill 14205`。システムプロセス（`launchd`、`kernel_task`、`WindowServer`、`loginwindow`）と Lightspot 自身は候補に表示されません。
- **終了レベル:**
  - `↵` (Return): 正常な終了 (`SIGTERM`)。
  - `⌥↵` (Option + Return): 強制終了 (`SIGKILL`)。

### 6. 🛠️ 組み込みのオフライン開発者向けユーティリティ (DevTools)
Webユーティリティを開いたりCLIパッケージをインストールしたりせずに、一般的な開発者向け操作をミリ秒単位で実行します：
- **`uuid`**: 暗号論的に安全なランダムUUID v4を生成します。
- **`b64 <text>`** / **`b64d <base64>`**（または **`b64 decode <base64>`**）: Base64のエンコードおよびデコード。
- **`urlencode <url>`** / **`urldecode <url>`**: URLのパーセントエンコーディング。
- **`hash <text>`** / **`hash sha256|sha1|md5 <text>`**: 瞬時の暗号化チェックサム。3種類を一度に表示するか、指定したアルゴリズムのみを表示します。
- **`jwt <token>`**: JWTのヘッダーとペイロードをデコードし、整形して表示します。
- **`json <raw>`**: 縮小されたJSONをフォーマット、インデント、および検証します。
- **`epoch`** / **`now`**: 現在のUnixタイムスタンプ。**`epoch <タイムスタンプ>`** で人間が読める日付に変換し、**`epoch 2024-01-15 10:30`** でタイムスタンプに逆変換します（ローカル時刻、またはタイムゾーン付きのISO 8601）。
- **`#3498db`**: ワンクリックでHex、RGB、HSLをコピーできるライブカラープレビュースウォッチ。

### 7. 🔐 Sudoと特権アクション用のヘッドレスタッチID
特権的なメンテナンスアクション（`Flush DNS Cache`、`Purge Inactive Memory`）を、生体認証（指紋認証）を使って実行します：
- **ターミナルのポップアップなし**: バックグラウンドの擬似ターミナル（PTY）を介して実行され、macOSの `pam_tid.so` を呼び出して瞬時にTouch ID認証を行います。
- **ターミナルでのSudo用Touch IDの切り替え**: 検索可能なクイックアクション（`touch id` または `sudo` と入力）で、管理者認証のプロンプトの後に `/etc/pam.d/sudo_local` を編集し、通常のターミナルでの `sudo` コマンドでもTouch IDを使用できるようにします。サブタイトルには、sudo用Touch IDが現在有効かどうかが表示されます。

### 8. 📜 zshの履歴とピン留めされたコマンド (`⌘P` / `⌘⇧P`)
- ローカルの `~/.zsh_history`（またはカスタムの `$HISTFILE`）を、瞬時のサブミリ秒のランキングで検索します。
- 履歴のコマンド上で **`⌘P`** を押すと、ランチャーの上部にピン留めされます。
- **`⌘⇧P`** を押すと、ピン留めされたコマンドを管理、並べ替え、または削除できます。

### 9. 📦 設定のバックアップとマシン間の同期
- メニューバーの **Export Settings…** / **Import Settings…** で、設定をクリーンなJSONファイルにエクスポート／インポートできます。対象は、カスタムコマンド、ピン留めされたシェルコマンド、検索履歴とランキング、最近使ったアプリ、および環境設定（グローバルホットキー、ログイン時の起動、メニューバーアイコンの表示、ブラウザ履歴の期間）です。テキストスニペット、優先ターミナル、既定のWeb検索エンジンは含まれません。
- 自動的なパスのサニタイズにより、`/Users/username` が `~` に置き換えられるため、設定を仕事用と個人用のMac間でシームレスに共有できます。

### 10. 🔄 組み込みの自動アップデート
- GitHub Releasesをバックグラウンドで確認し（起動の少し後と、メニューバーのメニューを開いたとき）、メニューバーから新しいバージョンを提示します。確認に成功すると次の確認まで1日空けます。失敗した場合（オフライン、レート制限）は、次回の起動時またはメニューを開いたときに再試行します。**`Check for Updates...`** でその場で実行でき、**`Automatically Check for Updates`** で自動確認を完全に無効化できます。
- その場で更新します: Lightspotがリリースをダウンロードして検証し、自身のバンドルを置き換えて再起動します。**`Skip This Version`** を選べば、確認を無効化せずにそのリリースだけを見送れます。
- すべてのダウンロードには関門があります: HTTPSのみ、GitHubのホストのみ（リダイレクト後に再確認）、展開されたバンドルはLightspotのバンドル識別子・実行可能なバイナリ・公表されたバージョンとの完全一致が必須で、インストール済みより古いビルドは決して受け入れません。
- リリースはアドホック署名です（このプロジェクトはDeveloper IDを同梱していません）。そのため検証できるコード署名は存在せず、上記のチェックとGitHubへのHTTPSが信頼モデルのすべてです。これは `install.sh` が既に求めているものと同じです。

---

## ✨ 追加の組み込み機能

- **正確なmacOS Spotlight UI**: アニメーションによる展開とプレビューペインを備えた、半透明の角丸ピルデザイン（`NSVisualEffectView`）。
- **Mach / IOKit ハードウェアHUD**: 即時の、サブプロセスなしのハードウェア診断（`sys`, `cpu`, `ram`, `battery`, `uptime`）:
  - 正規化されたマルチコアCPU負荷 %
  - アクティブ、ワイヤード、圧縮、および合計の物理RAM
  - ブートSSDの空き容量と合計ストレージ
  - バッテリーのパーセンテージと充電ステータス
- **スマートな計算と柔軟な変換**: 単位、通貨、および基数をサポートする完全な再帰下降解析の計算機:
  - 計算: `(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - 単位: `100km in mi`, `72F in C`, `16GB in MB`
  - 通貨: `$100 in EUR`, `50 GBP in USD`
  - 基数: `0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **デフォルトブラウザのブックマーク、履歴、タブ**: 重複ゼロで、アクティブなデフォルトブラウザのみを統合します（**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**）。ブックマークと最近の履歴はブラウザ自身のファイルから読み取られ（履歴は直近3日または7日分、デフォルトは7日で、メニューバーの **Browser History** からオフにもできます）、開いているタブはSafariとChromiumベースのブラウザから取得します。
- **インメモリの一時的なクリップボード**: `clip <query>` 経経由でアクセスできる揮発性のRAM専用リングバッファ（最大50アイテム）。ディスクに書き込むことはなく、パスワードマネージャー（`1Password`, `Bitwarden`）を厳格にフィルタリングします。
- **macOSのシステム設定へのディープリンク**: 特定のmacOS設定ペイン（`x-apple.systempreferences:...`）を直接開く35のディープリンク。
- **マルチエンジンWeb検索**: 組み込みのプレフィックスショートカット: `g` (Google), `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `yt`, `ddg`、さらに `brew <formula>`（検索ではなく、formulae.brew.sh上のそのformulaのページを開きます）。

---

## 🛑 完全なmacOS Spotlightの管理

Lightspotには、Appleの組み込みSpotlightを無効または再有効化するためのメニューバー内の自動化機能が含まれています：

1. **Spotlightのショートカット (`⌘Space`)**: Appleのデフォルトのホットキー、`⌘Space`（「Spotlight検索を表示」）と `⌥⌘Space`（「Finderの検索ウインドウを表示」）の両方を、root権限なしで無効化または復元します。変更は環境設定デーモンを通じて書き込まれ、読み戻して検証され、ログアウトなしで即時に適用されます。さらに、macOSがキーを手放すと同時にLightspotが `⌘Space` を自分のものとして登録します。
2. **バックグラウンドプロセス (`com.apple.Spotlight`)**: `launchctl` を介してSpotlight GUIのバックグラウンドエージェントを無効化または有効化します。有効化するとエージェントの読み込みと起動も行うため、ログアウトせずにSpotlightが戻ります。
3. **ファイルインデックス作成 (`mdutil`)**: マウントされているすべてのボリュームにわたり、ファイルシステムのメタデータインデックス作成（`mds` / `mds_stores`）を完全にシャットダウンします。
4. **ワンクリックのマスターアクション**:
   - **`Disable Everything (Shortcut + Process + Indexing)...`**: AppleのSpotlightを完全にシャットダウンし、CPU、RAM、ディスク容量、および `⌘Space` を取り戻します。
   - **`Restore Default Spotlight...`**: いつでもすべての設定を工場のmacOSデフォルトに戻します。

---

## 🚀 ビルドとインストール (Xcodeは不要)

### 📦 方法A: ワンライナーインストール (推奨)
最新のビルド済みリリースを直接ダウンロードしてインストールします：
```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

### 🛠️ 方法B: ソースコードからビルド (ローカル環境)
```bash
# 1. リリースバンドルをビルド
./build.sh
# または: make build

# 2. 直接実行
./run.sh
# または: make run

# 3. /Applications にインストール (または --user で ~/Applications へ)
./install.sh
# または: make install

# 4. アンインストール
./uninstall.sh
# または: make uninstall
```

### 4. テストと検証
LightspotにはXCTestターゲットはありません。`scripts/` 配下の2つの独立したスクリプトをソースとともにその場でコンパイルして実行します：ロジックとエンジンのテストランナー（34のテストブロック）と、ライブシステム検証ツール（10セクション、フル装備のマシンで88チェック。zshの履歴やVS Codeがない場合などは一部がスキップされます）：
```bash
# コアロジックとエンジンのテスト (34のテストブロック)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# ライブシステムチェック (10セクション、フル装備のマシンで88チェック)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ ショートカットとナビゲーション

| キー | アクション |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | どこからでもLightspotを呼び出す、または閉じる (メニューバーで設定可能) |
| **`↓` / `↑`** | 検索結果をナビゲート |
| **`Return` (`↵`)** | 選択したアプリやIDEのプロジェクトを開く、コマンドを実行する、または計算結果をコピーする |
| **`⌘Return` (`⌘↵`)** | お好みのターミナルで選択したプロジェクトを開く |
| **`⌥Return` (`⌥↵`)** | Finderでプロジェクトを表示する / 選択したプロセスを強制終了する (`SIGKILL`) |
| **`⌘P`** | 選択したターミナル履歴のコマンドをピン留め、またはピン留め解除する |
| **`⌘⇧P`** | ピン留めされたコマンドマネージャーのオーバーレイを開く |
| **`⌘⇧C`** | カスタムコマンドマネージャーのオーバーレイを開く |
| **`⌘Y` / `⌘⇧H`** | 検索履歴マネージャーのオーバーレイを開く |
| **`Escape`** | オーバーレイを閉じる、検索フィールドをクリアする、またはLightspotを閉じる |
| **外側をクリック** | フローティングパネルを自動的に閉じる |

呼び出しに使うショートカットは、メニューバーの **Shortcut** で4つのうちから選びます。macOSは `⌃Space` を「前の入力ソースを選択」に割り当てているため、これを選ぶとキー操作で入力ソースも切り替わります。**Shortcut** サブメニューには、選んだ組み合わせをすでに使っているシステムのショートカットが表示されます。

---

## 🔒 プライバシーとセキュリティの保証

- **ファイルインデックス作成ゼロ**: Lightspotは、個人のファイル、ドキュメント、ダウンロード、またはコードリポジトリをインデックス化することは決してありません。
- **RAM専用の一時的なクリップボード**: クリップボードの履歴は揮発性メモリ内にのみ留まり、隠蔽されたタイプ/パスワードマネージャー（`org.nspasteboard.ConcealedType`、`1Password`、`Bitwarden`）を積極的に無視します。ディスクには一切書き込まれず、検索履歴にも残りません。検索履歴は、計算機・開発者ツール・スニペットの結果からコピーしたテキストも保存しません。
- **デフォルトブラウザの分離**: ブックマーク、開いているタブ、最近の閲覧履歴は、設定されたデフォルトブラウザからのみ、このMac上で読み取られ、クロスブラウザのスクレイピングを回避します。
- **ユーザー操作によるコマンド実行**: あなたのコマンド、スクリプト、クイックアクションは、明示的なユーザーアクション（`Return` または `⌘↵`）があった場合にのみ実行されます。
- **テレメトリゼロ、通信先は2つだけ（どちらもあなたの管理下）**: 分析、トラッキング、アカウントは一切ありません。Lightspot自身が通信するサービスは2つだけで、どちらもあなたが決められます。1つ目はアップデートのためのGitHubです。公開リリースAPI（`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`）への認証なしの `GET` で、`User-Agent: Lightspot/<バージョン> (+https://github.com/openhoangnc/mac-lightspot)` を付けて、起動の少し後とメニューバーのメニューを開いたときに送信しますが、確認に成功した後は1日1回までです（失敗した確認は次回の起動時またはメニューを開いたときに再試行します）。メニューバーで **`Automatically Check for Updates`** をオフにすれば、自動では一度も実行されません。承認したアップデートをインストールするときは、そのzipをGitHubからダウンロードします（`User-Agent: Lightspot/<バージョン>`）。どちらもエフェメラルセッションを使うため、レスポンスやCookieがディスクに保存されることはありません。以前のバージョンはmacOSの共有セッションを使っていたため（アップデート確認は1.2.0まで、IPの照会は1.2.0より前）、レスポンスが `~/Library/Caches/com.lightspot.app` に、Cookieが `~/Library/HTTPStorages` に残っていました。Lightspotは起動時にこれらの残りを削除し、アンインストーラーも削除します。2つ目はipifyで、パブリックIPを調べるための `GET https://api.ipify.org`（サードパーティのサービス）で、あなたが求めたときにだけ送信されます：IPを指すクエリ（`ip`, `my ip`, `public ip`, `ipv4`）を入力したとき、または **IP Address** の行で `Return` を押したときです。他のWebサーバーと同様に、ipifyにはあなたのIPアドレスと標準的なmacOSのユーザーエージェントが見えます。結果はメモリ内に15分間保持され、ディスクには書き込まれません。Web検索、URL、ブックマークはブラウザが開き、それも `Return` を押したときだけです。
- **ディスクに書き込まれるもの**: Lightspot自身の環境設定（`UserDefaults`、`~/Library/Preferences/com.lightspot.app.plist`）、ロックファイル1つ、そしてアップデートのインストール中の一時ファイルです：
  - 設定: `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state`（メニュー表示用に、最後に確認したSpotlightの状態）、`lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version`（自動アップデート確認）。
  - あなたが作成したもの: `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`。
  - 利用履歴: `lightspot_recent_app_bundle_ids`（最近起動したアプリ）と `lightspot_search_history`：入力したクエリと開いた結果（タイトル、アプリやプロジェクトのパス、URL、シェルコマンド）、およびランキング用の選択回数。検索履歴マネージャー（`⌘Y`）で確認・消去できます。クリップボード、計算機、開発者ツールの選択は記録されません。スニペットとハードウェアレポートの選択は、クエリと回数のみを保持し、コピーしたテキストは保存しません。
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`：2つ目のコピーが起動するのを防ぎます。実行中のプロセスのPIDと、その実行ファイルのパス・inode・更新日時を記録し、新たな起動が同じビルドか新しいビルドかを判別できるようにします。
  - 承認したアップデートのインストール中：ダウンロードしたファイル、展開したバンドル、小さなヘルパースクリプトをmacOSの一時ディレクトリ（`NSTemporaryDirectory()`、`lightspot-update-…` と `lightspot-updater-…` フォルダ）に置き、新しいバージョンが配置されるまで以前のバージョンを `Lightspot.app.lightspot-old` としてアプリの隣に残します。ヘルパーは終了時にこれらをすべて削除します。
  - **Export Settings** は、検索履歴を含むJSONバックアップを、あなたが選んだファイルにのみ書き込みます。
