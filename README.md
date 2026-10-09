# Form — トレーニング・身体データ管理 MVP

Lovable固有のビルダー指示を、Codexで編集できる通常のReact/Viteコードベースに読み替えた初期実装です。モバイルファーストのWebアプリで、将来のCapacitor/iOS化を妨げるネイティブ依存は置いていません。

## 構成

- `src/`: React画面、入力フォーム、グラフ表示、Supabase接続
- `supabase/migrations/`: テーブル、インデックス、ユーザーごとのRLS、非公開画像バケット
- `supabase/functions/analyze-training/`: 認証ユーザー本人の直近データだけを使うサーバー側AI分析
- `supabase/functions/delete-account/`: 本人確認後に画像とアカウントを削除する処理
- `VITE_SUPABASE_*`: ブラウザに置いてよいSupabase URLと公開anon keyのみ。AIキー等の秘密情報は置かない

## 起動

1. Node.js/npmを用意して `npm install`。
2. Supabaseプロジェクトを作り、`supabase/migrations/202610090001_initial_schema.sql` を適用。
3. Supabase Authでメール/パスワード登録を有効にし、開発中は必要に応じてメール確認を設定。
4. `.env.example` を `.env` にコピーし、Supabase URLとanon keyを記入。
5. `npm run dev` で起動。

### Edge Functionsの設定

Supabase Edge Functions `analyze-training` と `delete-account` をデプロイします。AI分析にはサーバー側シークレット `OPENAI_API_KEY`（任意で `AI_MODEL`）を設定します。アカウント削除には `SUPABASE_SERVICE_ROLE_KEY` をEdge Functionだけに設定します。AIキーやservice role keyを `VITE_` 変数にしたり、フロントエンドへ埋め込んだりしないでください。SupabaseのEdge Function実行環境に `SUPABASE_URL` / `SUPABASE_ANON_KEY` が提供される設定を確認してください。

## データ保護

記録テーブルは `user_id = auth.uid()` のRLSで保護し、プロフィールは `id = auth.uid()` で保護します。筋トレの子テーブルもそれぞれ所有者IDを持ち、画像バケットは先頭パスが認証ユーザーIDと一致する場合だけ操作できます。AI関数は呼び出し元のJWTでSupabaseクライアントを作り、RLSを通して本人の行だけ読み込み、生成結果も本人の行として保存します。anon keyは秘密鍵ではなく、アクセス制御はRLSを前提にしています。

## MVPの範囲と次の作業

この土台には、登録/ログイン、筋トレ（種目・複数セット）、ランニング、体重/体組成、履歴、基本の体重グラフ、期間フィルター、AIレポート保存の画面とバックエンド定義を含めています。実際の利用にはSupabaseプロジェクトとAIキーの設定が必要です。

体組成写真の選択・非公開ストレージへのアップロードを用意していますが、OCRによる数値抽出・画像の一覧/個別削除UIは未実装です。画像は `body-composition-images` バケットの所有者フォルダー内で管理できます。アカウント削除はEdge Functionで本人確認後に実行し、本人の画像とアカウントを削除します。

Apple Health / HealthKit、Nike Run Club連携、iOSネイティブ機能、App Store公開、課金、広告、SNS、医療診断は実装していません。取得元・外部ID・取得日時の列を用意し、将来のインポート重複防止に使えるようにしています。HealthKitアクセスは後でネイティブのアダプター層として追加する想定です。

## GitHub / iOS化

このコードは通常のGitリポジトリとして扱えます。GitHubへ同期後、VS Codeから編集できます。iOS化ではWeb UIとドメインロジックを維持し、Capacitorのネイティブ層からカメラ/HealthKit機能を接続してください。現時点の実装にHealthKitやNRCのAPI依存はありません。
