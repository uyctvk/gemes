# 画面・アセット制作記録

方向性は、ユーザー提供の『Monster Hunter Wilds』画像と「Monster Hunter: World」のように、三人称アクションで人物・敵・目的地を同時に読める画面。HUDの生命/持久力を左上、目的を右上、地図を左下、装備を右下に置いた。紋章、色、文字、UI素材、ゲーム中のモデル、音楽は本作独自のものを使用する。

外部アセット調査では [KayKit Adventures](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) のリグ付き人物と [Khronos glTF Sample Models](https://github.com/KhronosGroup/glTF-Sample-Models) の人物を確認した。前者は小頭身、後者は本作のNPC群に適した統一的な外観ではないため組み込んでいない。今回の人物4種は `scripts/generate_characters.py` からBlenderで生成する独自GLBで、骨、顔、髪、衣服、役割別の差分を持つ。`scripts/generate_audio.py` は村と遺跡の各20秒ループと4種類の効果音を合成する。画像・音声の他作品からの抽出は行っていない。

再生成にはBlender 4.x、PythonのNumPyとfontTools、ffmpegが必要。生成済みGLB・OGG・WAV・日本語サブセットフォントはリポジトリに含めているため、プレイ時に制作ツールは不要。

## 販売品質までのアート作業

現ビルドの人物は成人体型だが幾何学的なスタイルで、表情、皮膚・布・金属の高品質テクスチャ、髪の造形、衣装差分、手指の動き、フルボディの歩行・攻撃・被弾アニメーションが不足する。村は木組み、屋根、農地、道、生活NPCを増やしたが、建築密度、屋内、遠景、天候、植生、環境物の個別性が不足する。音楽は20秒ループで、長時間プレイに必要な展開・録音・ミックスが不足する。これらを販売版の完成済みアートとは判定しない。
