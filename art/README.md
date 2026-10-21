# Blender制作データ

Blender 4.3.2で制作。単位はメートル。テクスチャは各 `.blend` にパックしているため、ファイルを開いて編集できます。

- `characters/farmer.blend`：旅人・農夫
- `characters/merchant.blend`：商人
- `characters/healer.blend`：薬師
- `characters/guard.blend`：守り手
- `village/village_kit.blend`：家屋3種、露店、井戸、荷車、樽、荷箱、木
- `equipment/sword.blend`：刃・溝・鍔・巻き革・柄頭を持つ剣

人物のArmatureには `Idle`、`Walk`、`Run`、`Attack` のActionを保存しています。村の各資産は同名のMeshオブジェクトとして並べてあります。編集は元のオブジェクト名・骨名・Action名を保って行ってください。

編集したファイルを保存後、次のコマンドでゲーム用GLBを書き出せます。制作データ自体は上書きしません。

```bash
blender -b --python scripts/export_blender_sources.py -- --group all
# 人物だけの場合
blender -b --python scripts/export_blender_sources.py -- --group characters
```

書き出し先は `game/assets/`。人物はBlender内の正面 -Y を、書き出し時にGodotの正面 -Z に合わせます。村の展示用配置は書き出し時に原点へ戻します。Godotで再取込した後、`bash scripts/check.sh` と `bash scripts/visual_check.sh` で確認できます。

原型をコードから再生成する場合は `scripts/generate_characters.py`、`scripts/generate_village_assets.py`、`scripts/generate_equipment.py` をBlenderの `--python` に渡します。**再生成は手作業で編集した制作データを上書きする**ため、編集後の再書き出しには上記の `export_blender_sources.py` を使用してください。
