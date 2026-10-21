# 開発ビルド 0.2.0 の検証記録

実施日：2026-10-21。Linux x86_64、Godot 4.6.3.stable.official.7d41c59c4。

| 対象 | 結果・検証範囲 |
|---|---|
| 原本 | `docs/source/manifest.json` に全11資料を保存済み |
| エディター取込 | ヘッドレス取込成功。パース・スクリプトエラーなし |
| コア | 117件成功、失敗0件。実Thread競合、再送、現物・貨幣保存、死亡と銀行、セーブ破損復旧、30日シミュレーションを含む |
| シーン | `SCENE_SMOKE: PASS`。移動、メニュー、HUD配置、文字拡大、資産監査 |
| 三人称・物理 | `PHYSICS_SMOKE: PASS`。プレイヤーと30人のNPCのリグ、カメラ基準移動、剛体荷箱の押し出し |
| 日本語フォント | GDScript内の非ASCII文字に対して不足グリフなし |
| 音楽 | 村と遺跡のOGG各20秒を解析。実ゲームシーンでの読み込みと終了時の参照解放を確認 |
| 描画 | Xorg dummy / Mesa llvmpipeでタイトル・村・市場を表示。ソース版とLinux書き出し版の両方で画面画像を確認 |
| PC書き出し | Windows PE32+ / Linux ELF x86_64を生成。ZIPのCRC確認成功 |
| Linux配布実行ファイル | `/tmp` から起動し、`SCENE_SMOKE` と `PHYSICS_SMOKE` 成功、OpenGL画面の描画成功 |

再実行：`bash scripts/check.sh`。配布生成：`bash scripts/build.sh`。書き出し版描画：`LW_VISUAL_EXECUTABLE=/workspace/gemes/build/linux/LivingWorld.x86_64 bash scripts/visual_check.sh`。ZIPのハッシュは `build/SHA256SUMS.txt`。画面画像は `build/screenshots/`。

仮想描画ではV-Sync変更非対応の警告が出る。実機のフレーム性能や入力遅延の証拠としては扱わない。音楽を実際の再生装置で聴いた評価は未実施。

Windows実機、GPU差、物理ゲームパッド、Steamworks、ネットワークの認証・不正対策、100村・1万NPC、長時間安定性は未検証。販売品質の残件は [完成条件](RELEASE_GATES.md) に記載。
