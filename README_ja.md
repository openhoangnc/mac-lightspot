# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **純粋なSwiftで構築された、macOS Spotlightの軽量かつピクセルパーフェクトな代替ツール — ファイルのインデックス作成による肥大化を避け、瞬時の速度を求める開発者やパワーユーザーのために設計されています。**

Lightspotは、macOS Spotlightのモダンなフローティングピルデザインと半透明のガラスのような美しさ（`NSVisualEffectView`）を忠実に再現しています。その内部では、**バックグラウンドでのファイルインデックス作成を一切行わず**、アイドル時の定期的な処理は0.6秒ごとの軽量なクリップボード確認のみ、**RAM使用量25MB未満**で、サブミリ秒の応答性（検索時間1.0ミリ秒未満）を実現します。

![Lightspot スクリーンショット](screenshot.png)

---

## ⚡ クイックスタート

### 📦 ワンライナーのダウンロード＆インストール
ターミナルに以下のコマンドをコピー＆ペーストするだけで、最新の **Lightspot** が自動的にダウンロード・解凍され、`/Applications` フォルダに直接インストールされます。ダウンロードするのはこのMac用のビルドで、Appleシリコンでは約1.6 MB、Intelでは約1.75 MBです。Mac自身のプロセッサ（`sysctl hw.optional.arm64`）で判断するので、Rosettaで動くターミナルでもAppleシリコン用のビルドが入ります：

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

Mac Tweaksによる変更は、オフにしたバックグラウンド項目も含めて残ります（すべてのユーザー向けの項目は、すべてのアカウントでオフのままです）。アンインストーラーは取り消し用のジャーナルとDockのバックアップを残し、残ったものを元に戻す方法を表示します：Lightspotを入れ直してMac TweaksのSettingsで **Undo everything Lightspot changed** を選ぶ、システム設定 › 一般 › デバイス管理で **Lightspot Mac Tweaks** を削除する、または **Restore Dock Icons** を実行してください。

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
| **ディスクストレージ** | 10 GB – 200 GB+ の隠しキャッシュ | 100 MB – 1 GB | **インデックスもキャッシュもなし** (`UserDefaults` の設定とロックファイル、そしてクリーンや適用をしたときだけ書く小さなファイル：記録ログ、Mac Tweaksの取り消し用ジャーナル、Dockのバックアップ) |
| **RAMフットプリント** | 500 MB – 2 GB+ | 200 MB – 500 MB | **約15 – 25 MB** (Pure Swift) |
| **アプリの起動** | 頻繁に壊れ、再構築が必要 | 信頼できる | **100%の信頼性** (直接スキャン) |
| **検索レイテンシ** | デバウンス処理あり (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (瞬時の同期処理) |
| **オフライン・プライバシー** | SiriのテレメトリをAppleに送信 | 同期にはアカウントが必要 | **ローカル動作、テレメトリフリー**（通信はオプションの更新確認、ユーザーが求めたときのIP照会、Clean Dev Macを開いたときのcdmのクリーンアップルールの取得のみ） |

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
- その場で更新します: LightspotがリリースからこのMac用のビルド（Appleシリコンでは `Lightspot-arm64.zip`、Intelでは `Lightspot-x86_64.zip`。Mac自身のプロセッサで判断するので、Rosettaで動いているコピーもネイティブのビルドに移ります。それがないリリースではユニバーサルアプリの `Lightspot.zip`）をダウンロードして検証し、自身のバンドルを置き換え、新しいバージョンを起動し、その起動が終わってから終了します。Lightspotが消える時間はありません。**`Skip This Version`** を選べば、確認を無効化せずにそのリリースだけを見送れます。Lightspot 1.2.0〜1.3.9のアップデーターはユニバーサルの `Lightspot.zip` をダウンロードするので、1.4.0はユニバーサルアプリとして入り、その後のアップデートはこのMac用のビルドになります。
- すべてのダウンロードには関門があります: HTTPSのみ、GitHubのホストのみ（リダイレクト後に再確認）、展開されたバンドルはLightspotのバンドル識別子・このMacのプロセッサ用のコードを含む実行可能なバイナリ（Mach-Oヘッダから読み取ります）・公表されたバージョンとの完全一致が必須で、インストール済みより古いビルドは決して受け入れません。
- リリースはアドホック署名です（このプロジェクトはDeveloper IDを同梱していません）。そのため検証できるコード署名は存在せず、上記のチェックとGitHubへのHTTPSが信頼モデルのすべてです。これは `install.sh` が既に求めているものと同じです。

### 11. 🧹 Clean Dev Mac (`cdm`)
[CleanDevMac](https://github.com/cleandevmac/cdm)（`cdm`）は、ディスクを圧迫している開発用キャッシュやビルド成果物を見つけるツールです。Lightspotはこれを専用のウインドウで実行します。ウインドウは動かすことができ、Finder、パスワードの確認、ターミナルのcdmが前面に出ても開いたままです。`cdm`、`clean dev mac`、またはキャッシュ名（`derived data`、`npm cache`）を入力して **`↵`** を押します：
- **まず計測し、やみくもに選択しない**: cdmのルールが扱う各カテゴリ（XcodeのDerivedData、Go、npm/pnpm/Yarn、Gradle、Cargo、pip/uv、CocoaPods、JetBrains、ブラウザとElectronアプリのキャッシュ、使われていないAndroidイメージ、clangのモジュールキャッシュ、強制終了したChromeが残すコピーなど）を `du` と同じ方法で計測し、大きい順に並べ、cdmの安全なデフォルトにチェックを入れます。ウインドウにはクリーン前後のディスク状況が表示されます。cdmと同じく、該当するときは2つの注記も表示します。1つは、再起動で空く容量（スワップ、macOSが起動時に空にする一時フォルダ、アプリが開いたままの削除済みファイル）が空き容量を上回るときの、その見積もりです。もう1つは、Claude Codeのセッション履歴が1 GBを超え、保持期間を過ぎたトランスクリプトがあるときの、Claude DesktopとCoworkのセッションもClaude Codeに削除させる設定 `desktopSessionCleanupPeriodDays` の案内です。Lightspotがこの設定を書き換えることはありません。
- **インストール済みのSDK一式と古いセッション（チェックなし）**: cdmのオプトインの行も表示されます。PlatformIOのツールチェーン、AndroidのNDK・CMake・SDKソース、最新版を除くすべてのAndroid build-toolsとプラットフォーム、60日間だれも起動していないAVDのシステムイメージ（行にそのAVDの名前が出ます。イメージを入れ直すまで、そのAVDは起動しません）、そして30日間触れていないClaude Codeのセッション（必ずゴミ箱へ）。各行に元に戻す方法が書かれています。
- **コードリポジトリも**：キャッシュの計測後、Clean Dev Macはcdmと同じように、コードリポジトリのビルド成果物や依存関係のゴミもスキャンするかを尋ねます。**`⇥`** を押してください。リポジトリごとに1行、`node_modules`、`dist`、`build`、`target`、`__pycache__` などgitで無視されたファイルが、チェックなしで表示されます。リポジトリ自身のgitが無視していないものは提示されず（追跡されている `build/` は残ります）、`.env*` ファイルや別のリポジトリを含むフォルダーも決して提示されません。再生成できるフォルダーは削除し、その他の無視されたファイルはゴミ箱に移動します。
- **キー操作**: `↑↓` で選択（選択中の行にはパスとサイズが表示されます）、`Space` でチェック、`⇥` でコードリポジトリをスキャン、`↵` で項目別のプランを表示し、もう一度 `↵` でクリーン、`⌥↵` で選択中のキャッシュをFinderで表示、`⌘↵` でターミナルのcdmを実行、`Esc` でプランから戻り、プランがないときは `⌘W` と同じくウインドウを閉じます。スキャンやクリーンはウインドウを閉じても続きます。
- **cdmと同じルール**: Lightspotはcdm自身のルールファイルを読み込みます。`~/.cleandevmac/rules` があればそれを、なければGitHub上のcdmの最新ルールを、それもなければアプリに組み込まれたコピーを使います。cdmが新たに掃除できるようになったキャッシュは、Lightspotでも掃除できます。
- **cdmと同じ安全性**: 何かを実行する前に、すべてのパスがcdmの安全チェックを通ります。ホームフォルダ内、またはcdmのルールがキャッシュを指定している `/private/var/folders` 内の自分専用の一時フォルダ内（どちらもシンボリックリンクを解決した上で）にあることが必須で、`~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/Movies`、`~/Music`、`~/.ssh`、`~/.gnupg`、iCloud Driveには決して触れません。クリーンの前に、キャッシュを書き戻してしまう実行中のアプリをプランに表示します（先に終了してください）。クリーンのたびに、cdmと同じ `~/.cleandevmac/clean.log` に記録されます。
- **残りはキー1つで**: Docker / Podman、Rustのツールチェーンとオフラインドキュメント（`rustup` で削除）、アンインストール済みアプリの残りデータ、サンドボックスアプリのキャッシュには、コンテナエンジン、rustup、またはアプリのスキャンが必要です。そのため `⌘↵` で、cdm本体を最新リリースから直接、好みのターミナルで実行します。

### 12. 📦 キー1つでインストール：setup-zsh、MacStats、開発ツール
`install`（またはツール名）を入力して **`↵`** を押すと、Lightspotがそのツール自身のインストーラーを好みのターミナルで実行するので、各ステップを確認できます。
- **Install setup-zsh**（[setup-zsh](https://github.com/openhoangnc/setup-zsh)）：履歴のどこにでもマッチするzshの自動補完、シンタックスハイライト、gitの状態を表示するプロンプト。`setup.sh` を実行し、それを読み込んだ新しいzshを開きます。インストール後は、同じ行で更新できます。
- **Install MacStats**（[mac-stats](https://github.com/openhoangnc/mac-stats)）：CPU、RAM、ネットワーク速度、CPU温度をメニューバーに表示します。`install.sh` を実行し、`/Applications` に配置して起動します。
- **Install Dev Tools**：setup-zshの `install-dev-tool` メニュー。Homebrew、Node.js、Go、Pythonとuv、Rust、JDK、Bun、Git、VS Code、Chrome、OrbStack、Android Studioなどに加え、グローバルパッケージの更新もできます。`install node`、`install go`、`install rust` などと入力してください。setup-zshがない場合は、先にそれをインストールします。
- 各行にはツールがすでにインストール済みかどうかが表示され、**`⌥↵`** でGitHubのページを開きます。

### 13. 🎛️ macOSの調整
dotfilesのREADMEからコピーしてくるような `defaults write` のワンライナーを、クイックアクションにしました。切り替え系はどれも現在の設定を読み取って反転するので、同じ行で元に戻せます：
- **Dock**：**Clear Dock Icons**（Dockのアイコンを `~/Library/Application Support/Lightspot/dock-backup.plist` に保存してから、固定されたアプリをすべて取り除き、Dockを再起動）、**Restore Dock Icons**（アイコンを元の位置に戻し、その後に追加したアイコンは残して、再起動したDockにアイコンが表示されたときだけバックアップを削除。どちらも起動したばかりのDockが落ち着くのを待ち、再起動で変更が失われたらもう一度試します）、**Toggle Dock Auto-Hide**、**Toggle Instant Dock Auto-Hide**（遅延なし）、**Toggle Dock Recent Apps**、**Restart Dock**。
- **Finder**：**Toggle Hidden Files in Finder**、**Toggle File Extensions in Finder**、**Toggle Finder Path Bar**、**Toggle Desktop Icons**（画面共有の前に便利）、**Toggle .DS_Store on Network & USB Drives**、**Restart Finder**。
- **入力とスクリーンショット**：**Toggle Press-and-Hold Accents**（キーを押し続けるとリピート）、**Toggle Smart Quotes & Dashes**、**Toggle Screenshot Shadows**。

どれも管理者パスワードは不要です。Clear Dock IconsはRestore Dock Iconsで元に戻せ、切り替え系は同じ行で戻せます。状態の表示と取り消し付きでさらに41の設定を変えるには、Mac TweaksのSettings（セクション14）を使ってください。

### 14. 🧰 Mac Tweaks (`free up space`)
Mac Tweaksは、macOSが抱えている容量を解放し、このMacのすべてのアカウントでApple Intelligenceをオフにし、41のmacOS設定を取り消し可能な形で変更し、他のアプリが入れたlaunchdのエージェントとデーモンをオフにしたり削除したりします。`mac tweaks`、`free up space`、`debloat`、または消したいもの（`remove garageband`、`macos installers`、`time machine snapshots`、`app caches`）を入力して **`↵`** を押すか、メニューバーで **Clean Dev Mac...** のすぐ下にある **Mac Tweaks...** を選びます。`turn off apple intelligence` ならApple Intelligenceのセクションが、`stop music from opening`、`turn off apple music`、`turn off mac analytics`、`turn off personalized ads`、`show the library folder` ならSettingsのセクションが、`turn off background items`、`turn off launch agents`、`disable launch agents`、`turn off google updater`、`leftover launch agents`、`launch daemons` ならBackground Itemsのセクションが開きます。専用のウインドウにセクションごとのタブ付きで開き、どのセクションも何かを変える前に項目別のプランを、終わった後に結果を表示します。プロファイルを承認するためにシステム設定へ切り替えたときや、Touch IDの確認に答えるときも、ウインドウは開いたままです。好きな場所に動かせ（位置は記憶されます）、閉じるボタン、`⌘W`、または `Esc` で閉じます。（セクション13の `defaults` 切り替えはクイックアクションで、Mac Tweaksの一部ではありません。）
- **Free Up Space** は各行をClean Dev Macと同じ方法で計測します。提示するものがない行は表示せず、0バイトのものは提示しません。最初の3行にはチェックが入っています：
  - **macOS installers**：`/Applications` にある古い `Install macOS*.app`。Appleのバンドル識別子（`com.apple.InstallAssistant…`）を持つものだけです。
  - **iPhone and iPad updates**：Finderがダウンロードしたアップデート（`~/Library/iTunes/iPhone Software Updates` と `iPad Software Updates`）。
  - **Unavailable simulators**：ランタイムがもうインストールされていないシミュレータ。Xcodeの `simctl` を使い、`/usr/bin/xcrun` は決して実行しません。そのため、Command Line ToolsだけのMacにはこの行が出ず、そのインストーラーも開きません。
  - **Time Machine local snapshots**：ローカルスナップショット。数で表示します（macOSはサイズを返しません）。
  - **Aerial videos**：このMacのすべてのアカウントが共有する空撮ビデオ（`/Library/Application Support/com.apple.idleassetsd/Customer`）。各アカウント自身のコピーはClean Dev Macの行です。
  - **GarageBand and its sound library**：GarageBandとそのサウンドライブラリ。Logic ProかMainStageがインストールされている間は、ライブラリは残ります。
  - **iMovie**、**Keynote**、**Numbers**、**Pages**：Apple製のものだけです。Apple製でない `Pages.app` は残ります。
  - **App caches**：`~/Library/Caches` のキャッシュ。ただし、macOS自身のもの（`com.apple.*` とmacOSが書くその他の名前）、Lightspotのもの、そしてClean Dev Macのルールが扱うものはすべて除くので、Mac TweaksとClean Dev Macが同じフォルダを重複して数えることはありません。Mac Tweaksはこれらのルールを、Clean Dev Macのメモリ、`~/.cleandevmac/rules`、またはアプリ内のコピーから読み、決してダウンロードしません。
  - リンクの行が3つ：**Apple Intelligence models**（そのセクションをスキャンした後、モデルがディスクにある間だけ、サイズ付きで表示）はApple Intelligenceのセクションを、**Developer caches and project junk** はClean Dev Macを、**More in System Settings** はシステム設定のストレージを開きます。
- **Free Up Spaceのファイルの行き先**：ゴミ箱です。ゴミ箱を空にするまでは取り出せます。シミュレータ（`simctl delete unavailable`）とスナップショット（`tmutil deletelocalsnapshots`）はすぐに削除され、その行にもそう表示されます。バックアップディスク上のバックアップには触れません。結果には、解放した容量、ゴミ箱に移動したもの、削除したもの、そして残ったものとその理由が表示されます。たとえば、App Managementの許可がないためにmacOSがLightspotに移動させないアプリなどです（`⌥↵` でFinderに表示）。
- **Apple Intelligence**（Appleシリコン、macOS 15.1以降）：このmacOSにある機能ごとに1行（Siri、ChatGPTなどのAI拡張機能、Writing Tools、Genmoji、Image Playground、メール・通知・メッセージ・Safari・メモの要約、インラインの入力予測、Spatial Photos、Photos Clean Up、Xcodeの予測コード補完）で、それぞれの状態（On、Off、Locked off、Managed、Unknown）と必要なモデルを表示します。どの機能も最初はチェックが入っていて、これはオフにするという意味です。残したいものはチェックを外してください。適用すると構成プロファイル **Lightspot Mac Tweaks** を1つインストールし、それをシステム設定 › 一般 › デバイス管理で承認します（Lightspotがプロファイルを開き、最大10分待ちます。`Esc` で待つのをやめます）。このプロファイルは、チェックした機能をこのMacのすべてのアカウントでオフにし、そのモデルのダウンロード先を閉じたローカルのポートに向けます。プロファイルが有効になってから初めて、Lightspotは残した機能が必要としないモデルの削除をAppleのアセットサービスに頼み、macOSがまだ使っている間は再試行し、なくなるまでインベントリを確認します。**Finish removing the models** は再起動の後に残りを片付け、**Turn Apple Intelligence back on** はプロファイルを削除します（Settingsの設定も入っている場合は、Apple Intelligenceを除いたプロファイルに置き換えます）。他のプロファイルが設定している機能はそのままにし、RemoveMacAIのプロファイルがあるとこのセクションは読み取り専用になります。Lightspot自身は非公開のアセットフレームワークを呼び出しません。読み取りと削除はすべて短時間だけ動く子プロセス `Lightspot --asset-service` で行うため、フレームワークが使う9〜11 MBがLightspotのメモリに残ることはありません。
- **Settings**：6つのグループ（Privacy、Annoyances、Apple apps、Finder、Dock and windows、Typing）に分かれた41の設定で、それぞれこのMacでの状態を表示します：On、Off、Partly、Managed（他のプロファイルが設定しているので、Lightspotは触れません）、Not on this macOS。最初はどれにもチェックが入っていません。プリセット **Recommended** と **Maximum privacy** は、まだオフのものにチェックを入れます。ローカルの設定はcfprefsdを通して書き込み、読み直して確認し、必要なときだけFinder、Dock、SystemUIServerをそれぞれ1回再起動します。Mac Analytics、パーソナライズされた広告、Siriと音声入力の改善、検索の改善、Spotlightのインターネット結果、Look UpとSafariの検索候補、Game Center、iPhoneミラーリング、Apple Music、Book Storeは同じプロファイルに入り、プロファイルのApple Intelligenceの部分はそのまま保たれます。プランには、このプロファイルがこのMacのすべてのアカウントに適用されることが表示されます。Apple Musicは3段階：Apple Musicのサービス、何もミュージックを開けないようにするミュージックの起動エントリ、そして再生・一時停止・スキップのキー（`com.apple.rcd`）です。選択中の行とプランには、各変更がコマンド（`defaults write …`、`launchctl …`、`chflags …`、`profile: …`）として表示されます。
- **Background Items**：`~/Library/LaunchAgents`、`/Library/LaunchAgents`、`/Library/LaunchDaemons` にある `.plist` を1つにつき1行で表示します。macOS自身のもの（`com.apple.*`）、`Label` のないplist（GoogleのKeystoneが残す空のスタブ）、ドットで始まるファイルは除きます。各行には、その項目が属するアプリ（プログラムが入っている `.app`、実行するもの、または `AssociatedBundleIdentifiers` が示すアプリ。たとえばDockerのヘルパーは「Docker」と表示されます）、ラベルと実行するもの（トークンを含むことがあるため、その他の引数は決して表示しません）、そして状態を表示します：On、Off、Not loaded（システム設定のログイン項目でオフにされている可能性があります）、Unknown。状態は `launchctl print-disabled` と `launchctl print` で読みます。アップデーター（ラベルかプログラム名に `update` を含むもの）には **Updater** のタグが付き、アップデーターでも残骸でもない行には、オフにするとそのアプリが動かなくなるおそれがあるという注意が表示されます。`Space` でその行の変更にチェックを入れます：オフにする（`launchctl disable` の後に `bootout`）か、オンに戻す（`enable` の後に `bootstrap`）です。`⌫` を押すと代わりにその行を削除の対象にし、もう一度押すと外します（行に **Delete** と表示されます）。Lightspotは項目を停止し、アプリが同じものを書き戻しても読み込まれないようラベルをオフにしてから、plistをゴミ箱に移動します。プランには同等のコマンド（`launchctl bootout`、`launchctl disable`、`mv … ~/.Trash/`）が表示されます。まだインストールされているアプリのヘルパーを削除すると、そのアプリが動かなくなることがあり、アプリが次に起動したときに書き戻すこともあります。行とプランにその旨が表示されます。プログラムがもう存在しないことをmacOSが確認した **Leftover** も同じように削除され、最初からチェックが入っているのはこの行だけです。macOSが保護しているフォルダや別のディスクにあるプログラムと、インラインコード（`-c`、`-e`）を渡されたインタープリタは、決して「消えた」とは判断しません。plistがシンボリックリンクのものや、ラベルが別のplistと同じものは決して移動しないので、削除できません。自分のエージェントは自分の権限で変更し、各デーモンの変更と、管理者にしかできない移動は1回の管理者の確認にまとめます。デーモンの変更はこのMacのすべてのアカウントに適用されますが、`/Library/LaunchAgents` の項目をオフ／オンにするのは自分のアカウントだけです。デーモンや `/Library/LaunchAgents` の項目の削除はすべてのユーザーに適用され、パスワードを求められることがあります。launchdが確認したものだけを結果に数え、削除した各plistの移動先、まだ動いているもの（デーモンは再起動まで、エージェントはログアウトまで）や読み込まれなかったものは結果に表示されます。シンボリックリンクのplistはフォルダを1つずつたどり、macOSが保護しているフォルダ、別のディスク、`~/Library/CloudStorage` には決して入りません。最後の行はシステム設定のログイン項目を開きます。
- **取り消し**：Lightspotは設定を初めて変える前に、見つけた値を `~/Library/Application Support/Lightspot/tweaks-journal.json` に保存し、保存に成功したときだけ変更します。On の行にチェックを入れると取り消しになり、プランのとおり、その値に戻すか、Lightspotが何も保存していない場合はmacOSの既定値に戻します。**Undo everything Lightspot changed** は記録されたすべての変更を元に戻し、管理者の確認1回でプロファイルを削除します。Lightspotがオフにしたバックグラウンド項目も（オフにする前にジャーナルに記録してあります）オンに戻し、以前動いていたものだけを再び起動します。デーモンは同じ1回の確認で戻します。plistがなくなった項目は何も実行せずに記録から外し、launchdのスイッチはオフのまま残ります。Lightspotが削除したバックグラウンド項目も元に戻します。各plistはゴミ箱から元の場所に戻り、以前と同じ場合だけオンにして起動します。root所有のものは同じ1回の確認で戻し、rootが所有するファイルだけを戻します。今その場所にあるファイルは決して置き換えません（アプリが書き戻していた場合は、オンに戻すだけです）。ゴミ箱にもうないものはその旨を表示して記録から外します。一部だけ適用されている設定はあなた自身のものなので、完成させるだけで、取り消すことはありません。Free Up Spaceがゴミ箱に移したファイルとClear Dock Iconsのバックアップは対象外です。
- **パスワードは管理者が必要なときだけ**：スナップショットの削除、他のユーザーが所有する項目や、フォルダのアクセス権のために自分では移動できない項目の移動（その行には **May ask for password** と表示されます）、デーモンのオフ／オン、デーモンや `/Library/LaunchAgents` の項目の削除とその復元、そしてLightspotのプロファイルの削除です。適用に管理者権限が必要な部分は1つのスクリプトにまとめ、sudo用Touch IDまたはパスワードダイアログで1回だけ実行します。プロファイルのインストールは、システム設定であなた自身がクリックして行います。
- **キー操作**：`↑↓` で選択（選択中の行には項目、モデル、またはコマンドが表示されます）、`Space` でチェック（プリセットではその行すべて、Background Itemsではその行の変更）、`⌫` でバックグラウンド項目を削除の対象に、`⇥` / `⇧⇥` でセクションを切り替え、`↵` で項目別のプランを表示し、もう一度 `↵` で適用、`⌥↵` でFree Up Spaceの行の最初の項目、またはバックグラウンド項目のplistをFinderで表示、`Esc` でプランから戻るか、システム設定を待つのをやめます。どちらでもないときは `⌘W` と同じくウインドウを閉じます。
- **結果**：どの適用も最後に結果を表示し、頼んだとおりにできたときは緑のチェックが付きます。適用はウインドウを閉じても続き、Mac Tweaksを開き直すと進行状況、続いて結果が表示されます。適用のたびに `~/Library/Application Support/Lightspot/mac-tweaks.log` に記録されます。別のセクションの適用でスキャン結果が古くなったセクションは、もう一度スキャンします：Apple IntelligenceとSettingsはプロファイルを、SettingsとBackground Itemsは取り消し用のジャーナルを共有しているためです。
- **決して触れないもの**：Free Up Spaceは、`/System` 以下のすべて、`~/Desktop`、`~/Documents`、`~/Downloads`、`~/Pictures`、`~/Movies`、`~/Music`、iCloud Drive、`~/Library/Containers`、`~/Library/Group Containers`、メール、メッセージ、iPhoneのバックアップ（`MobileSync`）、そしてアプリバンドルの中身には決して触れません。各パスは、書かれたままでもシンボリックリンクを解決した後でも、その行の固定フォルダの直下になければならず、それ自体がシンボリックリンクであってはならず、移動の直前にもう一度このチェックを通ります。Apple IntelligenceとSettingsは、他の構成プロファイルが設定しているものには触れません。Background Itemsは、macOS自身の項目を一覧に出さず、3つのフォルダの外にあるものは何も変えません。`launchctl` はシェルを通さず直接実行し、root権限ではスキャンで見つけたラベルとplistにだけ作用します。Mac Tweaksは開くまで何も読まず、ネットワークへの通信も一切行いません。
- **クレジット**：Free Up Space、Apple Intelligence、Settings、Background Itemsは、omlahoreによる [RemoveMacAI](https://github.com/omlahore/RemoveMacAI)（MITライセンス）の処理を移植したものです。そのApple Intelligenceの部分は4evyによる [pared](https://github.com/4evy/pared)（MITライセンス）に基づいており、Lightspotのアセットサービスへのブリッジ、モデルのカタログ、ダウンロードのブロックもそれに従っています。[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) を参照してください。

---

## ✨ 追加の組み込み機能

- **正確なmacOS Spotlight UI**: アニメーションによる展開とプレビューペインを備えた、半透明の角丸ピルデザイン（`NSVisualEffectView`）。
- **Mach / IOKit ハードウェアHUD**: 即時の、サブプロセスなしのハードウェア診断（`sys`, `cpu`, `ram`, `memory`, `disk`, `battery`, `uptime`, `specs`, `resources`）:
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
- **macOSのシステム設定へのディープリンク**: 特定のmacOS設定ペイン（`x-apple.systempreferences:...`）を直接開く46のディープリンク。システム設定自体の検索と同じキーワード（`night shift`, `lockdown mode`, `sticky keys`）で、システムの言語のまま検索できます。macOS 27.2では、システム設定が終了してもLaunchServicesが1分以上それに気づかないことがあります。そのときLightspotは「もう開いていない」という警告を出す代わりに、起動中のシステム設定でパネルを開き、起動中のものがないときだけ新しく起動します。Dockにコピーが増えることはありません。
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
最新のビルド済みリリースを直接ダウンロードしてインストールします。各リリースには、インストーラーとアップデーターがMacに合わせて選ぶ `Lightspot-arm64.zip`（Appleシリコン、約1.6 MB）と `Lightspot-x86_64.zip`（Intel、約1.75 MB）、ユニバーサルアプリの `Lightspot.zip`（約2.9 MB）、クラッシュレポートを読むためのシンボル `Lightspot.app.dSYM.zip` が含まれます：
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

`./build.sh` は各アーキテクチャを完全なリンク時最適化（LTO）でコンパイルし、ローカルシンボルの名前を取り除きます（名前は `build/Lightspot.app.dSYM` に残します）。1.4.0のユニバーサルバイナリは5.1 MBで、1.3.9の8.8 MBより42%小さく、Appleシリコン用だけなら2.2 MB（Intel用は2.9 MB）です。

### 4. テストと検証
LightspotにはXCTestターゲットはありません。`scripts/` 配下の3つの独立したスクリプトをソースとともにその場でコンパイルし、リポジトリのルートから実行します：ロジックとエンジンのテストランナー（84のテストブロック）、ライブシステム検証ツール（15セクション、開発者のMac（macOS 27.2）で206チェック。zshの履歴やVS Codeがない場合や、GitHubに接続できない場合などは一部がスキップされます）、そして本物のMac TweaksとClean Dev Macのウインドウを読み取り専用のスキャンで画面外に作り、Mac Tweaksの各セクションを再スキャンとセクション切り替えに、両方のウインドウをキー操作に通すチェックです：
```bash
# コアロジックとエンジンのテスト (84のテストブロック)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# ライブシステムチェック (15セクション、macOS 27.2で206チェック)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify

# Mac TweaksとClean Dev Macのウインドウを画面外で確認 (約1分)
swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift) && /tmp/overlay_check
```

---

## ⌨️ ショートカットとナビゲーション

| キー | アクション |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | どこからでもLightspotを呼び出す、または閉じる (メニューバーで設定可能) |
| **`↓` / `↑`** | 検索結果をナビゲート |
| **`Return` (`↵`)** | 選択したアプリやIDEのプロジェクトを開く、コマンドを実行する、または計算結果をコピーする |
| **`⌘Return` (`⌘↵`)** | お好みのターミナルで選択したプロジェクトを開く |
| **`⌥Return` (`⌥↵`)** | Finderでプロジェクトを表示する / 選択したプロセスを強制終了する (`SIGKILL`) / インストーラーのGitHubページを開く / Mac Tweaksの行の最初の項目をFinderで表示する |
| **`⌘P`** | 選択したターミナル履歴のコマンドをピン留め、またはピン留め解除する |
| **`⌘⇧P`** | ピン留めされたコマンドマネージャーのオーバーレイを開く |
| **`⌘⇧C`** | カスタムコマンドマネージャーのオーバーレイを開く |
| **`Space`** | Clean Dev Macのカテゴリ、またはMac Tweaksの行のチェックを切り替える |
| **`Delete` (`⌫`)** | Mac Tweaksでバックグラウンド項目を削除の対象にする、または外す |
| **`Tab` (`⇥`)** | Clean Dev Macでコードリポジトリもスキャンする / Mac Tweaksで次のセクションへ（`⇧⇥` で前へ） |
| **`⌘Y` / `⌘⇧H`** | 検索履歴マネージャーのオーバーレイを開く |
| **`Escape`** | オーバーレイを閉じる、検索フィールドをクリアする、またはLightspotを閉じる。Mac TweaksとClean Dev Macのウインドウでは戻り、続けて押すとウインドウを閉じる |
| **`⌘W`** | Mac TweaksまたはClean Dev Macのウインドウを閉じる |
| **外側をクリック** | フローティングパネルを自動的に閉じる |

呼び出しに使うショートカットは、メニューバーの **Shortcut** で4つのうちから選びます。macOSは `⌃Space` を「前の入力ソースを選択」に割り当てているため、これを選ぶとキー操作で入力ソースも切り替わります。**Shortcut** サブメニューには、選んだ組み合わせをすでに使っているシステムのショートカットが表示されます。

---

## 🔒 プライバシーとセキュリティの保証

- **ファイルインデックス作成ゼロ**: Lightspotは、個人のファイル、ドキュメント、ダウンロード、またはコードリポジトリをインデックス化することは決してありません。Clean Dev Macが計測するのはcdmのルールが指すキャッシュフォルダと、2つの注記に必要な少数の場所（後述）だけで、開いている間だけ実行し、サイズ以外は何も保持しません。他のアプリのサンドボックスコンテナは決して読み込みません。AndroidとClaude Codeの行のために、AVDフォルダと `~/.claude/projects` 内のファイルの日付、そして実行中のセッションを示す `~/.claude/sessions` の小さなファイルも読みます。トランスクリプトの中身は読みません。強制終了したChromeが残すコピーについては、自分専用の一時フォルダ内のコピーを一覧し、実行中のアプリの起動時刻を読みます。cdmの2つの注記のために、使用中のスワップ量を読み、macOSが起動時に空にする一時フォルダと `~/.claude/projects` のサイズを計測し、アプリが開いたままの削除済みファイルを `lsof` に問い合わせ（保持するのは合計と上位3つのアプリ名だけです）、`~/.claude/settings.json` の2つのキー（`cleanupPeriodDays`、`desktopSessionCleanupPeriodDays`）を読みます。このファイルに書き込むことはありません。コードリポジトリのスキャンを求めたとき（`⇥`）は、ホームフォルダ内のgitリポジトリを6階層まで探しますが、`~/Library`、`~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/Movies`、`~/Music` には入らず、各リポジトリのgitに無視しているファイルを尋ねます。Mac Tweaksが読むのは決まった場所だけで、それも開いたセクションの分だけです。Free Up Space：`/Applications` 内の名前と、そこにあるInstall macOSアプリおよびGarageBand、iMovie、Keynote、Numbers、Pagesの `Info.plist`、`~/Library/iTunes/iPhone Software Updates` と `iPad Software Updates`、`/Library/Application Support/com.apple.idleassetsd/Customer`、`~/Library/Caches` の中身（提示する項目ごとのサイズと所有者を含む）、GarageBandの3つのライブラリフォルダと、Logic ProまたはMainStageがインストールされているかどうか、Xcodeの `simctl` が返す使用できないシミュレータの一覧と、`tmutil` が返すローカルスナップショットの日付、空撮ビデオを提示するときの壁紙インデックス（`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`）、そしてClean Dev Macのルールです。適用時には `~/.Trash` 内の名前を1つずつ確認し、ゴミ箱の一覧は決して取得しません。Apple Intelligence：アセットサービスが持つモデルセットとそのサイズのインベントリ（短時間だけ動く補助プロセスが読み、フォルダは読みません。削除の途中でだけ、`/System/Library/AssetsV2` にあるセットのフォルダの項目数を読みますが、一覧は取得しません）、そして機能の設定と2つのプロファイルのマーカーをcfprefsd経由で読みます。Settings：41の設定の環境設定と制限、Dockのアイコン、プロファイルのマーカーをcfprefsd経由で読み、launchctlの無効化されたサービスの一覧、Music.appとその実行ファイルのinode番号、Libraryフォルダの非表示属性、そして取り消し用のジャーナルを読みます。Background Items：`~/Library/LaunchAgents`、`/Library/LaunchAgents`、`/Library/LaunchDaemons` 内の名前と、そこにある各 `.plist`（1 MiB以下の通常ファイルのときだけ読み、ラベル、プログラム、引数、関連アプリの識別子、`Disabled` だけを残します。引数は表示も記録もしません）、自分のアカウントとシステムの `launchctl print-disabled`、各項目の `launchctl print`（出力にはジョブの環境変数が含まれるため、終了ステータスだけを残します）、plistが示す各プログラム、またはインタープリタが実行するスクリプト（フォルダを1つずつたどって確認し、macOSが保護しているフォルダ、別のディスク、`~/Library/CloudStorage` の中は決して見ません）、各plistの所有者、plistが示すアプリについてのLaunchServicesの情報、そして取り消し用のジャーナルのバックグラウンド項目のエントリです。ジャーナルにバックグラウンド項目があるときは、SettingsもUndo everythingのプランのために3つのフォルダを1回読みます。スキャンから5分を過ぎていれば、Mac Tweaksを閉じたときに見つけたものを破棄し、Free Up Spaceの合計と、Apple Intelligenceのスキャンがモデルについて読んだ内容だけを残します。
- **RAM専用の一時的なクリップボード**: クリップボードの履歴は揮発性メモリ内にのみ留まり、隠蔽されたタイプ/パスワードマネージャー（`org.nspasteboard.ConcealedType`、`1Password`、`Bitwarden`）を積極的に無視します。ディスクには一切書き込まれず、検索履歴にも残りません。検索履歴は、計算機・開発者ツール・スニペットの結果からコピーしたテキストも保存しません。
- **デフォルトブラウザの分離**: ブックマーク、開いているタブ、最近の閲覧履歴は、設定されたデフォルトブラウザからのみ、このMac上で読み取られ、クロスブラウザのスクレイピングを回避します。
- **ユーザー操作によるコマンド実行**: あなたのコマンド、スクリプト、クイックアクションは、明示的なユーザーアクション（`Return` または `⌘↵`）があった場合にのみ実行されます。
- **管理者コマンドは1回だけ実行**: 特権コマンドは、Touch ID付きの `sudo`、またはmacOSのパスワードダイアログで実行され、1.4.0からは決して2回実行されません。コマンドはまずランダムなマーカーを出力し、そのマーカーでsudoがコマンドを開始したとわかった時点で結果が確定します。そのため、Touch IDで実行して失敗したコマンドが、パスワードダイアログの後ろでもう一度実行されることはもうありません。マーカーの後の標準入力は `/dev/null` なので、実行したものが隠れたターミナルで入力を待ち続けることもありません。Lightspotが自分で組み立てるスクリプト（すべての引数をシングルクォートで囲んだMac Tweaksの管理者バッチ）は、内容を一切変えない別の入口を通ります。システムログに残るのは特権コマンドが実行されたかどうかと終了ステータスだけで、ファイルのパスを含みうるコマンドの本文は残りません。
- **テレメトリゼロ、通信先は2つだけ（どちらもあなたの管理下）**: 分析、トラッキング、アカウントは一切ありません。Lightspot自身が通信するサービスは2つだけで、どちらもあなたが決められます。1つ目はアップデートのためのGitHubです。公開リリースAPI（`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`）への認証なしの `GET` で、`User-Agent: Lightspot/<バージョン> (+https://github.com/openhoangnc/mac-lightspot)` を付けて、起動の少し後とメニューバーのメニューを開いたときに送信しますが、確認に成功した後は1日1回までです（失敗した確認は次回の起動時またはメニューを開いたときに再試行します）。メニューバーで **`Automatically Check for Updates`** をオフにすれば、自動では一度も実行されません。承認したアップデートをインストールするときは、そのzipをGitHubからダウンロードします（`User-Agent: Lightspot/<バージョン>`）。どちらもエフェメラルセッションを使うため、レスポンスやCookieがディスクに保存されることはありません。以前のバージョンはmacOSの共有セッションを使っていたため（アップデート確認は1.2.0まで、IPの照会は1.2.0より前）、レスポンスが `~/Library/Caches/com.lightspot.app` に、Cookieが `~/Library/HTTPStorages` に残っていました。Lightspotは起動時にこれらの残りを削除し、アンインストーラーも削除します。2つ目はipifyで、パブリックIPを調べるための `GET https://api.ipify.org`（サードパーティのサービス）で、あなたが求めたときにだけ送信されます：IPを指すクエリ（`ip`, `my ip`, `public ip`, `ipv4`）を入力したとき、または **IP Address** の行で `Return` を押したときです。他のWebサーバーと同様に、ipifyにはあなたのIPアドレスと標準的なmacOSのユーザーエージェントが見えます。結果はメモリ内に15分間保持され、ディスクには書き込まれません。**Clean Dev Mac** を開くと、GitHubにcdmのルールファイルも要求します（`GET https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/index.json` と、そこに記載されたファイル。標準的なmacOSのユーザーエージェントで、エフェメラルセッションを使用）。頻度は最大で1時間に1回で、ルールはメモリ内にのみ保持され、オフライン時はアプリに組み込まれたコピーを使います。自分のルールを `~/.cleandevmac/rules` に置けば、この通信は一切発生しません。Mac Tweaksは通信を一切行いません。Clean Dev Macのルールは、メモリ、`~/.cleandevmac/rules`、またはアプリ内のコピーから読み、決してダウンロードしません。ターミナルでcdmを実行する（`⌘↵`）と、cdm自身の手順と同じく、cdmのGitHubリリースからスクリプトをダウンロードします。インストール用の行も同様で、各ツールのインストーラーをターミナルで実行し、GitHubからのダウンロードはLightspotではなくそのスクリプトが行います。Web検索、URL、ブックマークはブラウザが開き、それも `Return` を押したときだけです。
- **ディスクに書き込まれるもの**: Lightspot自身の環境設定（`UserDefaults`、`~/Library/Preferences/com.lightspot.app.plist`）、ロックファイル1つ、アップデートのインストール中の一時ファイル、クリーン時にcdmのログへ追記される記録、そしてMac Tweaksで適用したときの小さなファイルです：
  - 設定: `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state`（メニュー表示用に、最後に確認したSpotlightの状態）、`lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version`（自動アップデート確認）。
  - あなたが作成したもの: `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`。
  - 利用履歴: `lightspot_recent_app_bundle_ids`（最近起動したアプリ）と `lightspot_search_history`：入力したクエリと開いた結果（タイトル、アプリやプロジェクトのパス、URL、シェルコマンド）、およびランキング用の選択回数。検索履歴マネージャー（`⌘Y`）で確認・消去できます。クリップボード、計算機、開発者ツールの選択は記録されません。スニペットとハードウェアレポートの選択は、クエリと回数のみを保持し、コピーしたテキストは保存しません。
  - `~/.cleandevmac/clean.log`：Clean Dev Macでクリーンしたときだけ書き込まれます。各クリーンで削除またはゴミ箱に移動したものを、cdm自身が使うログに追記します（cdmと同じく1 MiBが上限）。クリーナーで確定したものは完全に削除されます。ただし、Trashと表示されたカテゴリはゴミ箱に移動します。
  - `~/Library/Application Support/Lightspot/mac-tweaks.log`：Mac Tweaksで何かを適用したときだけ書き込まれます。適用ごとの開始と終了の時刻、変更・ゴミ箱への移動・削除をしたもの、残ったものとその理由、解放した容量を記録します。1 MiBを超えると最新の256 KiBだけを残します（cdmのログと同じ）。Free Up Spaceで確定したファイルはゴミ箱に移動し、使用できないシミュレータとTime Machineのスナップショットは完全に削除されます。
  - `~/Library/Application Support/Lightspot/tweaks-journal.json`：Mac Tweaksの取り消し用ジャーナルです。Lightspotが変更する前の各設定の値と、Lightspotがオフにした、または削除した各バックグラウンド項目がオフだったか・読み込まれていたか、削除した項目のplistがあった場所とゴミ箱での移動先を、変更の前に保存し、取り消すと消します。Lightspotが読めないジャーナルは決して上書きせず、`tweaks-journal-unreadable-<日付>-<id>.json` として脇に置きます。Settingsは他のアプリの環境設定（Finder、Dock、グローバルドメインなど）にも書き込みますが、適用したものだけで、それぞれ先にジャーナルに記録します。
  - `~/Library/Application Support/Lightspot/dock-backup.plist`：Clear Dock IconsがDockを空にする前に書き込み、アイコンが戻るとRestore Dock Iconsが削除します。
  - `~/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig`：Lightspotのプロファイルの承認を適用が待っている間だけ置かれ、インストールされると削除されます。プロファイル **Lightspot Mac Tweaks** 自体は、あなたがシステム設定でインストールするもので、このMacのすべてのアカウントに適用されます。そこで削除すれば、プロファイルが変えたものはすべて元に戻ります。
  - アンインストーラーは、取り消し用のジャーナルとDockのバックアップ以外のこれらをすべて削除します。この2つは入れ直したLightspotが取り消せるように残し、何が残り、どう元に戻すかを表示します。Lightspotがオフにした、すべてのユーザー向けのバックグラウンド項目は、すべてのアカウントでオフのままです。
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`：2つ目のコピーが起動するのを防ぎます。実行中のプロセスのPIDと、その実行ファイルのパス・inode・更新日時を記録し、新たな起動が同じビルドか新しいビルドかを判別できるようにします。
  - 承認したアップデートのインストール中：ダウンロードしたファイル、展開したバンドル、小さなヘルパースクリプトをmacOSの一時ディレクトリ（`NSTemporaryDirectory()`、`lightspot-update-…` と `lightspot-updater-…` フォルダ）に置き、新しいバージョンが配置されるまで以前のバージョンを `Lightspot.app.lightspot-old` としてアプリの隣に残します。ヘルパーは終了時にこれらをすべて削除します。
  - **Export Settings** は、検索履歴を含むJSONバックアップを、あなたが選んだファイルにのみ書き込みます。
