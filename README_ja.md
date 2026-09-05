# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **純粋なSwiftで構築された、macOS Spotlightの軽量かつピクセルパーフェクトな代替ツール — ファイルのインデックス作成による肥大化を避け、瞬時の速度を求める開発者やパワーユーザーのために設計されています。**

Lightspotは、macOS Spotlightのモダンなフローティングピルデザインと半透明のガラスのような美しさ（`NSVisualEffectView`）を忠実に再現しています。その内部では、**バックグラウンドでのファイルインデックス作成を一切行わず**、**アイドル時のCPU使用率0.0%**、**RAM使用量25MB未満**で、サブミリ秒の応答性（検索時間1.0ミリ秒未満）を実現します。

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

ハードドライブ全体を積極的にクロールする代わりに、Lightspotはパワーユーザーが実際に検索するもの（アプリケーション、IDEのプロジェクト、ブラウザのタブ、開発者用ユーティリティ、カスタムコマンド）に厳密に焦点を当てています。

### 比較マトリックス

| 指標 | Apple Spotlight | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **ファイルインデックス作成** | 制御されないバックグラウンドクロール | オプション / 設定可能 | **なし** (アーキテクチャによる保証) |
| **アイドル時のCPU使用率** | 動作時に100%+までスパイク | 1% – 5% (バックグラウンド) | **0.0%** (完全にスリープ) |
| **ディスクストレージ** | 10 GB – 200 GB+ の隠しキャッシュ | 100 MB – 1 GB | **0 KB** (ディスクフットプリントゼロ) |
| **RAMフットプリント** | 500 MB – 2 GB+ | 200 MB – 500 MB | **約15 – 25 MB** (Pure Swift) |
| **アプリの起動** | 頻繁に壊れ、再構築が必要 | 信頼できる | **100%の信頼性** (直接スキャン) |
| **検索レイテンシ** | デバウンス処理あり (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (瞬時の同期処理) |
| **オフライン・プライバシー** | SiriのテレメトリをAppleに送信 | 同期にはアカウントが必要 | **100%ローカル、オフライン、テレメトリフリー** |

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
  - 1〜3文字のカスタムプレフィックスを割り当てます（例：dockerログを追跡する `dlog <container>`、ヘッダーをcurlする `c <url>`、pingする `png <host>`）。
- **カスタムキーワードとアイコン**:
  - 即座に発見できるファジーキーワードを追加し、SF Symbolsまたはbase64のアプリアイコンを使用してアイコンをカスタマイズします。

### 2. 💬 動的テキストスニペット (`⌘P` / `snippets`)
自動的な動的変数の展開を持つ再利用可能なテキストスニペットを定義できます：
- `{{date}}`: 現在の日付 (`YYYY-MM-DD`)
- `{{time}}`: 現在の時刻 (`HH:mm:ss`)
- `{{iso}}`: ISO 8601 UTC タイムスタンプ (`2026-09-05T14:30:00Z`)
- `{{uuid}}`: ランダムなUUID v4
- `{{clipboard}}`: 現在のクリップボードの内容

スニペットのキーワード（例：`iso`、`uuid`、`date`）を入力して **`↵`** を押すと、評価された文字列がクリップボードに直接コピーされます。

### 3. 💻 7つのモダンなターミナルエミュレータから選択
Lightspotは、お気に入りのターミナルエミュレータと統合します。メニューバーからいつでも切り替え可能です：
- **Ghostty**、**Warp**、**Alacritty**、**iTerm2**、**Kitty**、**WezTerm**、そして **Apple Terminal**。
- **"Terminal in Finder Folder"**: `term` と入力するかアクションを押すと、現在Finderで開いているディレクトリで、好みのターミナルを即座に起動します。

### 4. 📂 複数のIDEの最近のプロジェクトの検出
Lightspotは、以下の最近のワークスペースを自動的に監視します：
- **VS Code**、**Cursor**、**Zed**、**JetBrains Suite** (IntelliJ IDEA, WebStorm, PyCharm, CLion, GoLand, Rider など)、および **Sublime Text**。
- **キーボード修飾キー**:
  - `↵` (Return): 関連付けられたIDEでワークスペースを開きます。
  - `⌘↵` (Command + Return): プロジェクトのルートディレクトリでお好みのターミナルを起動します。
  - `⌥↵` (Option + Return): Finderでプロジェクトフォルダを表示します。

### 5. 🔌 プロセスキラーとポートターミネーター (`kill`)
残存している開発サーバー、スタックしたバックグラウンドタスク、または暴走したプロセスをすばやく終了します：
- **ポートでキル:** `kill :3000`, `kill :8080`, `kill :5173` (自動的に `lsof` 経由でリスニング中のPIDを解決します)。
- **プロセス名またはPIDでキル:** `kill node`, `kill python`, `kill 14205`。
- **終了レベル:**
  - `↵` (Return): 正常な終了 (`SIGTERM`)。
  - `⌥↵` (Option + Return): 強制終了 (`SIGKILL`)。

### 6. 🛠️ 組み込みのオフライン開発者向けユーティリティ (DevTools)
Webユーティリティを開いたりCLIパッケージをインストールしたりせずに、一般的な開発者向け操作をミリ秒単位で実行します：
- **`uuid`**: 暗号論的に安全なランダムUUID v4を生成します。
- **`b64 <text>`** / **`b64d <hash>`**: Base64のエンコードおよびデコード。
- **`urlencode <url>`** / **`urldecode <url>`**: URLのパーセントエンコーディング。
- **`hash sha256 <text>`** / **`sha1`** / **`md5`**: 瞬時の暗号化チェックサム。
- **`jwt <token>`**: JWTのヘッダーとペイロードをデコードし、整形して表示します。
- **`json <raw>`**: 縮小されたJSONをフォーマット、インデント、および検証します。
- **`epoch`** / **`now`**: Unixタイムスタンプと人間が読める日付との相互変換。
- **`#3498db`**: ワンクリックでHex、RGB、HSLをコピーできるライブカラープレビュースウォッチ。

### 7. 🔐 Sudoと特権アクション用のヘッドレスタッチID
特権的なメンテナンスアクション（`Flush DNS Cache`、`Purge Inactive Memory`）を、生体認証（指紋認証）を使って実行します：
- **ターミナルのポップアップなし**: バックグラウンドの擬似ターミナル（PTY）を介して実行され、macOSの `pam_tid.so` を呼び出して瞬時にTouch ID認証を行います。
- **ターミナルでのSudo用Touch IDの切り替え**: `/etc/pam.d/sudo_local` を設定するためのワンクリックのメニューアクション。これにより、通常のターミナルでの `sudo` コマンドでもTouch IDを使用できるようになります。

### 8. 📜 zshの履歴とピン留めされたコマンド (`⌘P` / `⌘⇧P`)
- ローカルの `~/.zsh_history`（またはカスタムの `$HISTFILE`）を、瞬時のサブミリ秒のランキングで検索します。
- 履歴のコマンド上で **`⌘P`** を押すと、ランチャーの上部にピン留めされます。
- **`⌘⇧P`** を押すと、ピン留めされたコマンドを管理、並べ替え、または削除できます。

### 9. 📦 設定のバックアップとマシン間の同期
- すべての設定（カスタムコマンド、ピン留めされたアイテム、スニペット、ホットキー）をクリーンなJSONファイルにエクスポートします。
- 自動的なパスのサニタイズにより、`/Users/username` が `~` に置き換えられるため、設定を仕事用と個人用のMac間でシームレスに共有できます。

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
- **デフォルトブラウザのブックマークとタブ**: 重複ゼロで、アクティブなデフォルトブラウザのみのブックマークと開いているタブの統合（**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**）。
- **インメモリの一時的なクリップボード**: `clip <query>` 経経由でアクセスできる揮発性のRAM専用リングバッファ（最大50アイテム）。ディスクに書き込むことはなく、パスワードマネージャー（`1Password`, `Bitwarden`）を厳格にフィルタリングします。
- **macOSのシステム設定へのディープリンク**: 特定のmacOS設定ペイン（`x-apple.systempreferences:...`）を直接開く35以上のディープリンク。
- **マルチエンジンWeb検索**: 組み込みのプレフィックスショートカット: `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `brew`, `yt`, `ddg`。

---

## 🛑 完全なmacOS Spotlightの管理

Lightspotには、Appleの組み込みSpotlightを無効または再有効化するためのメニューバー内の自動化機能が含まれています：

1. **Spotlightのショートカット (`⌘Space`)**: macOSのシンボリックホットキーにあるAppleのデフォルトの `⌘Space` ホットキーを、root権限なしで無効化または復元します。
2. **バックグラウンドプロセス (`com.apple.Spotlight`)**: `launchctl` を介してSpotlight GUIのバックグラウンドエージェントを無効化または有効化します。
3. **ファイルインデックス作成 (`mdutil`)**: マウントされているすべてのボリュームにわたり、ファイルシステムのメタデータインデックス作成（`mds` / `mds_stores`）を完全にシャットダウンします。
4. **ワンクリックのマスターアクション**:
   - **`Disable Everything (Shortcut + Process + Indexing)...`**: AppleのSpotlightを完全にシャットダウンし、CPU、RAM、ディスク容量、および `⌘Space` を取り戻します。
   - **`Restore Default Spotlight...`**: いつでもすべての設定を工場のmacOSデフォルトに戻します。

---

## 🚀 ビルドとインストール (Xcodeは不要)

Lightspotは標準のSwiftツールとシンプルなシェルスクリプトでビルドされます。Xcode IDEのインストールは必要ありません。

### 1. ビルド
```bash
./build.sh
# または: make build
```
リリースバイナリ（`-Osize -wmo`）をコンパイルし、デバッグシンボルをストリップし、`Info.plist`と高解像度アイコンをバンドルして、`build/Lightspot.app`をコード署名します。

### 2. 実行
```bash
./run.sh
# または: make run
```

### 3. `/Applications` へのインストール
```bash
./install.sh
# または: make install
# (--user を渡すと ~/Applications にインストールされます)
```

### 4. テストと検証
Lightspotには112の自動テストスイートと、ライブシステムでのランタイムチェックが含まれています：
```bash
# コアロジックとエンジンのテスト (24のテストスイート)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/test_engine

# ライブシステムチェック (88の検証チェック)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ ショートカットとナビゲーション

| キー | アクション |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** | どこからでもLightspotを呼び出す、または閉じる (メニューバーで設定可能) |
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

---

## 📁 プロジェクト構造

```
mac-lightspot/
├── Package.swift                 # SPM マニフェスト (Swift 6, macOS 13+)
├── Makefile                      # make build / run / install / uninstall / clean
├── build.sh                      # リリースビルドと.appパッケージャースクリプト
├── run.sh                        # ビルドと起動のヘルパー
├── install.sh                    # /Applications または ~/Applications へのインストール
├── uninstall.sh                  # クリーンな削除スクリプト
├── README.md                     # ドキュメントと根拠
├── CLAUDE.md                     # アーキテクチャ、不変条件、および開発者ガイド
├── Resources/
│   ├── Info.plist                # LSUIElement=1, パーミッション, バンドルメタデータ
│   └── AppIcon.icns              # マルチサイズのmacOSアプリケーションアイコン
├── scripts/
│   ├── generate_icon.sh          # プログラムによるアイコンジェネレーター (Core Graphics + iconutil)
│   ├── test_engine.swift         # 自動テストランナー (24のテストスイート)
│   └── deep_verify.swift         # ライブシステムの検証 (88のチェック)
└── Sources/
    └── Lightspot/
        ├── AppMain.swift         # @main エントリポイントとNSApplicationDelegate
        ├── Core/
        │   ├── Models.swift      # SearchResult, ResultCategory, SearchAction, FuzzyMatcher
        │   ├── AppScanner.swift  # 高速な非同期アプリスキャナとメモリアイコンキャッシュ
        │   ├── BrowserIntegrationProvider.swift # デフォルトブラウザのブックマークとタブ
        │   ├── CalculatorEngine.swift # 計算パーサーと変換ディスパッチャー
        │   ├── ClipboardHistoryManager.swift    # インメモリの一時的なクリップボードリングバッファ
        │   ├── ConversionEngine.swift   # 単位、通貨、基数、温度のエンジン
        │   ├── CustomCommandsStore.swift # カスタムユーザーコマンドモデルと永続化
        │   ├── DevToolsProvider.swift   # UUID, Base64, Hash, JWT, JSON, カラーウォッチ
        │   ├── NetworkInfoProvider.swift # ローカルIPv4とパブリックインターネットIPアドレス
        │   ├── ProcessKillerProvider.swift # 名前、PID、およびポートプロセス終了ツール
        │   ├── QuickActionsProvider.swift # フォーカスされたシステムアクションとFinder内のターミナル
        │   ├── RecentProjectsProvider.swift # 複数のIDEプロジェクトスキャナ (VS Code, Cursor, Zed, JetBrains, Sublime)
        │   ├── SearchEngine.swift       # 同期検索アグリゲーターとランキング
        │   ├── SearchHistoryManager.swift # 検索クエリと選択履歴
        │   ├── SettingsBackup.swift     # 設定のエクスポートとインポートのバックアップ
        │   ├── SettingsProvider.swift   # 35以上のmacOSシステム設定へのディープリンク
        │   ├── ShellHistoryProvider.swift # zsh履歴パーサーとピン留めされたコマンド
        │   ├── SnippetsStore.swift      # 変数補完を伴うテキスト展開スニペット
        │   ├── SystemInfoProvider.swift # サブプロセスなしのMach/IOKitハードウェアダッシュボード
        │   └── WebSearchProvider.swift  # マルチエンジン検索とプレフィックスショートカット
        ├── System/
        │   ├── HotkeyManager.swift      # Carbonグローバルホットキー
        │   ├── MenuBarController.swift  # メニューバーステータス項目と設定
        │   ├── SettingsBackupController.swift # 設定インポート/エクスポートコントローラー
        │   ├── SpotlightManager.swift   # macOS Spotlightの無効化/復元自動化
        │   └── TerminalLauncher.swift   # 7つのターミナルエミュレータ用ランチャーとFinder検出
        └── UI/
            ├── CustomCommandsView.swift # カスタムコマンドマネージャーのオーバーレイ
            ├── HistoryManagerView.swift # 検索履歴マネージャーのオーバーレイ
            ├── PinnedCommandsView.swift # ピン留めされたコマンドマネージャーのオーバーレイ
            ├── PreviewPaneView.swift    # リッチな詳細カードとライブプレビュー
            ├── SearchFieldView.swift    # NSTextFieldブリッジとカスタムフィールドエディター
            ├── SearchViewModel.swift    # リアクティブなビューモデルとキーイベントルーター
            ├── SpotlightComponents.swift# 検索結果の行、ボタン、カテゴリヘッダー
            ├── SpotlightPanel.swift     # Vibrancyを伴うフローティングボーダーレスNSPanel
            └── SpotlightView.swift      # ルートのSwiftUIビュー
```

---

## 🔒 プライバシーとセキュリティの保証

- **ファイルインデックス作成ゼロ**: Lightspotは、個人のファイル、ドキュメント、ダウンロード、またはコードリポジトリをインデックス化することは決してありません。
- **RAM専用の一時的なクリップボード**: クリップボードの履歴は揮発性メモリ内にのみ留まり（ディスクに書き込まれることはありません）、隠蔽されたタイプ/パスワードマネージャー（`org.nspasteboard.ConcealedType`、`1Password`、`Bitwarden`）を積極的に無視します。
- **デフォルトブラウザの分離**: ブックマークとタブは、設定されたデフォルトブラウザからのみ読み取られ、クロスブラウザのスクレイピングを回避します。
- **サンドボックス化されたサブプロセス**: コマンドとスクリプトは、明示的なユーザーアクション（`Return` または `⌘↵`）があった場合にのみ実行されます。
- **テレメトリゼロと100%オフライン**: ネットワークリクエスト、リモート分析、トラッキングは一切ありません。
