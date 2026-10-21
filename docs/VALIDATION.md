# 初期試作 0.1.0 の検証記録

実施日：2026-10-21。Linux x86_64、Godot 4.6.3.stable.official.7d41c59c4。

| 対象 | 結果・検証範囲 |
|---|---|
| 全11資料 | `docs/source/manifest.json` のSHA-256と原本を照合。一致 |
| エディター取込 | ヘッドレス取込成功。パース・スクリプトエラーなし |
| コア | 117件成功、失敗0件。実Thread競合、コマンド再送、現物・貨幣保存、死亡と銀行、セーブ破損復旧、30日シミュレーションを含む |
| ゲームシーン | `SCENE_SMOKE: PASS`。入力による移動、各画面の生成、HUDの画面内配置、文字115%設定、資産監査 |
| 日本語フォント | GDScript内の非ASCII文字に対して不足グリフなし |
| 描画 | Xorg dummy / Mesa llvmpipeでタイトル・村・市場を描画。画像を目視し、日本語とHUD配置を確認 |
| PC書き出し | Windows PE32+ / Linux ELF x86_64を生成。ZIPのCRC確認成功 |
| Linux配布実行ファイル | ソースと異なる作業ディレクトリ `/tmp` から起動。ヘッドレスのシーン検証、およびOpenGLでのタイトル・村・市場の描画成功 |

再実行：`bash scripts/check.sh`。描画確認：`bash scripts/visual_check.sh`。
配布生成：`python3 scripts/setup.py --exports` → `bash scripts/build.sh`。
配布ZIPのハッシュ：`build/SHA256SUMS.txt`。画面画像：`build/screenshots/`。
ゲームのテストは独立した保存先を使い、通常のプレイデータを書き換えない。

このクラウドではホームディレクトリが書込制限されるため、開発時は `scripts/godot.sh` でXDGの保存先を `.local/` に設定する。
Linux配布物の検証でも、専用の書込可能な `XDG_CACHE_HOME`・`XDG_CONFIG_HOME`・`XDG_DATA_HOME` を指定した。
仮想描画ではV-Sync変更非対応の警告が出る。実機のフレーム性能や入力遅延の証拠としては扱わない。

## 未検証・未達成

- Windows実機での起動、GPU差、インストール、署名、Steam Deck。
- 物理ゲームパッドでの全操作、操作感、音声・音楽、アクセシビリティ評価。
- Steamworks認証・実績・Cloud・Steam Input・ストア公開。現段階はネイティブPCの書き出しのみ。
- 実ネットワーク上の認証・競合・改ざん対策。現在のThread試験はローカルコアの整合性だけを検証する。
- 100村・10,000NPCでの性能、長期経済均衡、分散DB障害、運営復旧。
- GitHub Actionsのリモート実行。ワークフローは追加済み、同じ検証をこの環境で実行した。

残りの実装順序と各段階の合格条件は [開発計画](IMPLEMENTATION_PLAN.md) を参照。
