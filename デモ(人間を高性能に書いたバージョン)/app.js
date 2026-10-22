import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { clone as cloneSkeleton } from 'three/addons/utils/SkeletonUtils.js';

// ASHEN FRONTIER – Playable 3D adventure. All NPC humanoids use real skinned GLB files.
const $=id=>document.getElementById(id);
const clamp=THREE.MathUtils.clamp;
const scene=new THREE.Scene();scene.background=new THREE.Color(0x718a80);scene.fog=new THREE.FogExp2(0x718a80,.0108);
const canvas=$('world');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(window.devicePixelRatio,1.75));renderer.setSize(innerWidth,innerHeight);
renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.08;
renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;
const camera=new THREE.PerspectiveCamera(69,innerWidth/innerHeight,.08,240);
camera.rotation.order='YXZ';
const hemi=new THREE.HemisphereLight(0xd7dfcd,0x273629,2.1);scene.add(hemi);
const sun=new THREE.DirectionalLight(0xf8d9a1,2.5);sun.position.set(-32,55,-36);sun.castShadow=true;
sun.shadow.mapSize.set(2048,2048);sun.shadow.camera.left=-90;sun.shadow.camera.right=90;sun.shadow.camera.top=90;sun.shadow.camera.bottom=-90;
sun.shadow.normalBias=.035;sun.shadow.bias=-.00012;scene.add(sun);scene.add(sun.target);
const ambient=new THREE.AmbientLight(0x7d93a2,.20);scene.add(ambient);
const mat=(c,r=1,m=0)=>new THREE.MeshStandardMaterial({color:c,roughness:r,metalness:m});
const M={grass:mat(0x415943),path:mat(0x8b806a,.97),stone:mat(0x7c8077,.92),stoneDark:mat(0x4c5754,.95),wood:mat(0x514031,.88),woodLight:mat(0x877257,.91),roof:mat(0x4b514b,.99),leaf:mat(0x274d3e),leaf2:mat(0x3c6650),leaf3:mat(0x1e3d37),bark:mat(0x50453a),gold:mat(0xb5a173,.37,.72),cloth:mat(0x52665c),iron:mat(0x747d7b,.38,.78),water:new THREE.MeshStandardMaterial({color:0x376a65,roughness:.20,metalness:.25,transparent:true,opacity:.83,side:THREE.DoubleSide}),glow:new THREE.MeshStandardMaterial({color:0x7ae8ca,emissive:0x2c947a,emissiveIntensity:1.7,roughness:.2}),enemy:mat(0x4b5a56,.9),enemyDark:mat(0x292e2b,.95),eye:new THREE.MeshBasicMaterial({color:0xe0a169})};
let rng=20261022;function rand(){rng=(rng*1664525+1013904223)>>>0;return rng/4294967296}function between(a,b){return a+(b-a)*rand()}
const solids=[];const worldMarkers=[];const pickups=[];const enemies=[];const effects=[];const theClock=new THREE.Clock();
const unitZ=new THREE.Vector3(0,0,-1);
function mesh(geo,material,parent=scene,x=0,y=0,z=0,cast=true){const o=new THREE.Mesh(geo,material);o.position.set(x,y,z);o.castShadow=cast;o.receiveShadow=true;parent.add(o);return o}
function box(x,y,z,w,h,d,material,parent=scene){return mesh(new THREE.BoxGeometry(w,h,d),material,parent,x,y,z)}
function capsule(x,y,z,r,len,material,parent=scene){return mesh(new THREE.CapsuleGeometry(r,len,7,12),material,parent,x,y,z)}
function wall(x,y,z,w,h,d,material){const o=box(x,y,z,w,h,d,material);solids.push({x,z,w,d});return o;}
function paintLabel(text,fill='#eee1b4',bg='rgba(12,24,24,0.84)'){
 const c=document.createElement('canvas');c.width=512;c.height=128;const a=c.getContext('2d');
 a.fillStyle=bg;a.fillRect(0,17,512,89);a.strokeStyle='#bfa774a0';a.strokeRect(2,19,508,85);
 a.font='bold 35px sans-serif';a.textAlign='center';a.textBaseline='middle';a.fillStyle=fill;a.fillText(text,256,60);
 const t=new THREE.CanvasTexture(c);t.colorSpace=THREE.SRGBColorSpace;
 const s=new THREE.Sprite(new THREE.SpriteMaterial({map:t,transparent:true,depthWrite:false}));s.scale.set(3.3,.83,1);return s;
}
// Terrain & pathways. The terrain is intentionally stylized; characters are never made from primitives.
const terrain=new THREE.PlaneGeometry(210,210,96,96);terrain.rotateX(-Math.PI/2);
const p=terrain.attributes.position;for(let i=0;i<p.count;i++){
 const x=p.getX(i),z=p.getZ(i);const slope=Math.min(1,Math.max(0,(Math.abs(x)-23)/22));
 const h=(Math.sin(x*.071)*Math.cos(z*.099)*.48 + Math.sin(x*.19-z*.11)*.20)*slope;
 p.setY(i,h);
}terrain.computeVertexNormals();
mesh(terrain,M.grass,scene,0,-.12,0,false);
function circlePath(x,z,rad=10){const ring=mesh(new THREE.CircleGeometry(rad,40),M.path,scene,x,-.07,z,false);ring.rotation.x=-Math.PI/2;return ring}
circlePath(0,6,15);
function pathRibbon(points,width=5){const vertices=[],uvs=[],indices=[];for(let i=0;i<points.length;i++){
 const pt=points[i],bef=points[Math.max(0,i-1)],aft=points[Math.min(points.length-1,i+1)];
 let dx=aft[0]-bef[0],dz=aft[1]-bef[1],L=Math.hypot(dx,dz)||1;dx/=L;dz/=L;
 vertices.push(pt[0]-dz*width/2,-.06,pt[1]+dx*width/2,pt[0]+dz*width/2,-.06,pt[1]-dx*width/2);
 uvs.push(0,i/3,1,i/3);if(i>0){const a=(i-1)*2;indices.push(a,a+1,a+2,a+1,a+3,a+2)}
}const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.Float32BufferAttribute(vertices,3));geo.setAttribute('uv',new THREE.Float32BufferAttribute(uvs,2));geo.setIndex(indices);geo.computeVertexNormals();mesh(geo,M.path,scene,0,0,0,false)}
pathRibbon([[0,12],[0,3],[-1,-9],[-4,-21],[-2,-36],[1,-54],[0,-72],[4,-85]],7);
pathRibbon([[0,5],[10,6],[22,-4],[29,-22],[31,-45],[28,-67]],4.5);
function rock(x,z,r=1){const geo=new THREE.DodecahedronGeometry(r,1);let o=mesh(geo,rand()<.5?M.stone:M.stoneDark,scene,x,r*.43-.07,z);o.scale.set(between(.6,1.45),between(.55,.95),between(.6,1.35));o.rotation.set(between(-.2,.2),rand()*Math.PI*2,between(-.15,.15));return o}
function shrub(x,z,r=1){for(let k=0;k<3;k++){let c=[M.leaf,M.leaf2,M.leaf3][Math.floor(rand()*3)],o=mesh(new THREE.IcosahedronGeometry(r*between(.35,.7),1),c,scene,x+between(-r/2,r/2),r*.27,z+between(-r/2,r/2));o.scale.set(1,.7,1);o.castShadow=false}}
function tree(x,z,scale=1){const group=new THREE.Group();group.position.set(x,0,z);group.scale.setScalar(scale);scene.add(group);
 const trunk=mesh(new THREE.CylinderGeometry(.19,.31,3.8,8,4),M.bark,group,0,1.85,0);trunk.rotation.z=between(-.09,.09);
 for(let i=0;i<5;i++){const yy=2.7+i*.70,rad=2.0-i*.23;let c=[M.leaf,M.leaf2,M.leaf3][i%3];const foliage=mesh(new THREE.ConeGeometry(rad,2.8,8,2),c,group,0,yy+.65,0);foliage.rotation.y=between(-.5,.5);if(i===4)foliage.scale.set(.8,.9,.8)}return group}
for(let i=0;i<115;i++){let x=between(-85,85),z=between(-100,57);
 if(Math.abs(x)<13&&z>-16&&z<22)continue;
 if(Math.abs(x)<7&&z<-15&&z>-93)continue;
 if(Math.abs(x-29)<6&&z<-5&&z>-75)continue;
 tree(x,z,between(.74,1.7));if(i%5===0)shrub(x+2,z-3,1.4)}
for(let i=0;i<130;i++){let x=between(-60,60),z=between(-100,45);if(Math.abs(x)<5&&z<6&&z>-93)continue;rock(x,z,between(.22,.85))}
for(let i=0;i<90;i++){let x=between(-60,60),z=between(-100,50);if(Math.abs(x)<7&&z<15&&z>-93)continue;shrub(x,z,between(.5,1.1))}
// Houses have detailed roof silhouettes and timber trims, not proxy box-human avatars.
function house(x,z,w=8,d=7,turn=0){const g=new THREE.Group();g.position.set(x,0,z);g.rotation.y=turn;scene.add(g);
 box(0,2.25,0,w,4.5,d,M.stone,g);
 for(let px of [-w/2+.27,w/2-.27]){box(px,2.3,d/2+.08,.35,4.5,.35,M.wood,g);box(px,2.3,-d/2-.08,.35,4.5,.35,M.wood,g)}
 for(let py of [1.2,3.6]){box(0,py,d/2+.10,w,.22,.35,M.wood,g);box(0,py,-d/2-.10,w,.22,.35,M.wood,g)}
 let roofGeo=new THREE.BufferGeometry(),verts=[-w/2-.7,4.45,-d/2-.5,w/2+.7,4.45,-d/2-.5,0,6.6,-d/2-.5,-w/2-.7,4.45,d/2+.5,w/2+.7,4.45,d/2+.5,0,6.6,d/2+.5];const idx=[0,2,1,3,4,5,0,3,5,0,5,2,1,2,5,1,5,4];roofGeo.setAttribute('position',new THREE.Float32BufferAttribute(verts,3));roofGeo.setIndex(idx);roofGeo.computeVertexNormals();mesh(roofGeo,new THREE.MeshStandardMaterial({color:0x464e4d,roughness:.97,side:THREE.DoubleSide}),g,0,0,0);
 box(0,1.2,d/2+.17,1.6,2.4,.12,M.wood,g);
 for(let px of [-w*.30,w*.30]){box(px,2.35,d/2+.24,.85,1.05,.10,M.wood,g);box(px,2.35,d/2+.30,.62,.79,.10,new THREE.MeshStandardMaterial({color:0x7b9690,emissive:0x2b463f,emissiveIntensity:.7,roughness:.2}),g)}
 for(let px of [-w*.30,w*.30])box(px,.17,d/2+.27,.9,.24,.7,M.woodLight,g);
 solids.push({x,z,w:w+1,d:d+1});return g;}
house(-9,8,8,8,.12);house(9,9,9,8,-.13);house(-10,-7,7,7,.32);house(11,-7,8,7,-.10);house(-9,24,9,8,.09);house(9,24,8,8,-.2);
// Ruin with stone arches, columns, broken wall panels.
function ruin(x,z){const g=new THREE.Group();g.position.set(x,0,z);scene.add(g);
 const base=mesh(new THREE.CylinderGeometry(12,13,.7,10),M.stoneDark,g,0,.05,0);base.receiveShadow=true;
 for(let i=0;i<9;i++){let a=i*Math.PI*2/9;let xx=Math.sin(a)*9.1,zz=Math.cos(a)*9.1;const height=i%3===0?7:between(3.2,5.8);
 const col=mesh(new THREE.CylinderGeometry(.85,1.05,height,9),M.stone,g,xx,height/2,zz);col.rotation.z=between(-.08,.08);
 const collar=mesh(new THREE.CylinderGeometry(1.25,1.2,.26,9),M.stoneDark,g,xx,height,zz);collar.rotation.z=col.rotation.z;
 for(let k=0;k<2;k++)rock(x+xx+between(-2,2),z+zz+between(-2,2),between(.6,1.2));
 }const ob=mesh(new THREE.OctahedronGeometry(1.3,1),M.glow,g,0,3.9,0);ob.userData.rotate=true;
 const pl= new THREE.PointLight(0x6ceccc,6,20);pl.position.set(0,4,0);g.add(pl);
 return {group:g,artifact:ob};}
const temple=ruin(2,-76);
// Village environmental props.
function firepit(x,z){const fire=new THREE.Group();fire.position.set(x,0,z);scene.add(fire);for(let i=0;i<11;i++){let a=i/11*Math.PI*2;const o=mesh(new THREE.IcosahedronGeometry(.26,0),M.stone,fire,Math.sin(a)*1,.20,Math.cos(a)*1);o.rotation.y=a}
 const f=mesh(new THREE.ConeGeometry(.31,1.2,7),new THREE.MeshStandardMaterial({color:0xe6a35c,emissive:0xf37736,emissiveIntensity:3}),fire,0,.75,0);f.userData.fire=true;
 const L=new THREE.PointLight(0xffa45c,7,12);L.position.set(0,1.2,0);fire.add(L);return f}
const campfire=firepit(-1,10);for(let i=0;i<11;i++){
 const x=between(-17,18),z=between(-14,30);if(Math.abs(x)<5&&Math.abs(z-10)<5)continue;
 box(x,.43,z,1,.86,1,M.wood);}
// Water pond, barely used for scenery.
const pond=mesh(new THREE.CircleGeometry(9,50),M.water,scene,37,-.027,19,false);pond.rotation.x=-Math.PI/2;pond.scale.set(1.6,1,1);
// Signposts, supply chests, world interaction markers.
function sign(x,z,name){const g=new THREE.Group();g.position.set(x,0,z);scene.add(g);box(0,1.3,0,.13,2.6,.13,M.wood,g);box(0,2.2,0,2.2,.6,.18,M.wood,g);const label=paintLabel(name);label.position.set(0,3.2,0);label.scale.set(2.3,.59,1);g.add(label)}
sign(-3,-14,'古の森 →');sign(7,20,'冒険者ギルド');
// Organic fantasy monsters. Non-human creatures are intentionally procedural;
// no fake-ball human mesh is used when a GLB humanoid is missing.
function monsterMesh(type){const root=new THREE.Group();if(type==='guardian'){
 const core=mesh(new THREE.IcosahedronGeometry(1.5,3),M.stoneDark,root,0,2.55,0);
 for(let i=0;i<3;i++){let a=i*Math.PI*2/3;let plate=mesh(new THREE.DodecahedronGeometry(.95,1),M.stone,root,Math.sin(a)*1.6,2.2,Math.cos(a)*1.6);plate.scale.set(.6,1.55,.9)}
 for(let i=0;i<6;i++){let a=i*Math.PI/3;const shard=mesh(new THREE.ConeGeometry(.25,1.5,5),M.gold,root,Math.sin(a)*1.6,3.25,Math.cos(a)*1.6);shard.rotation.z=.4*Math.cos(a)}
 const eye=mesh(new THREE.OctahedronGeometry(.64,1),M.glow,root,0,2.63,-1.38);root.userData.eye=eye;
 const light=new THREE.PointLight(0x45c8b5,3.2,9);light.position.set(0,2.6,0);root.add(light);
}else{
 const body=mesh(new THREE.SphereGeometry(1,18,12),M.enemy,root,0,.95,0);body.scale.set(.66,.61,1.12);
 const neck=mesh(new THREE.SphereGeometry(.54,16,12),M.enemy,root,0,1.11,-.85);neck.scale.set(.85,1,.95);
 const snout=mesh(new THREE.ConeGeometry(.37,.88,10),M.enemyDark,root,0,.99,-1.30);snout.rotation.x=-Math.PI/2;
 for(let side of [-1,1]){const ear=mesh(new THREE.ConeGeometry(.19,.69,7),M.enemyDark,root,side*.29,1.70,-1.0);ear.rotation.z=side*.15;
 const pupil=mesh(new THREE.SphereGeometry(.083,7,6),M.eye,root,side*.38,1.28,-1.27);pupil.scale.set(1,.8,.5);
 for(let z of [-.65,.61]){const leg=mesh(new THREE.CapsuleGeometry(.16,.42,4,8),M.enemyDark,root,side*.47,.36,z);leg.rotation.x=z>0?.19:-.1;}}
 for(let i=0;i<7;i++){const sp=mesh(new THREE.ConeGeometry(.16,.48,5),M.enemyDark,root,0,1.55,between(-.5,.6));sp.rotation.x=-.45}const tail=mesh(new THREE.ConeGeometry(.17,1.4,7),M.enemy,root,0,.97,1.22);tail.rotation.x=Math.PI/2.45;
 }return root;}
const spawns=[[-10,-29,'wolf'],[7,-37,'wolf'],[-6,-52,'wolf'],[12,-58,'wolf'],[-8,-68,'wolf'],[2,-76,'guardian']];
for(let i=0;i<spawns.length;i++){
 const [x,z,type]=spawns[i],root=monsterMesh(type);root.position.set(x,0,z);scene.add(root);
 enemies.push({id:i,root,home:new THREE.Vector3(x,0,z),goal:new THREE.Vector3(x,0,z),type,hp:type==='guardian'?280:76,maxhp:type==='guardian'?280:76,dead:false,attackCooldown:0,brain:between(0,2),phase:rand()*10,speed:type==='guardian'?1.65:2.25});
}
function floatingItem(x,z,kind){const g=new THREE.Group();g.position.set(x,0,z);scene.add(g);const orb=mesh(new THREE.OctahedronGeometry(kind==='relic'?.62:.34,1),kind==='relic'?M.gold:M.glow,g,0,1,0);orb.userData.float=true;const ring=mesh(new THREE.TorusGeometry(kind==='relic'?.77:.47,.06,7,24),M.gold,g,0,1,0);ring.rotation.x=Math.PI/2;ring.userData.float=true;const light=new THREE.PointLight(kind==='relic'?0xffd38c:0x82ffbd,2.0,7);light.position.y=1;g.add(light);const object={root:g,pos:new THREE.Vector3(x,0,z),kind,used:false,orb,ring};pickups.push(object);return object;}
const relic=floatingItem(2,-77,'relic');
for(const a of [[-13,-20],[8,-27],[-12,-55],[14,-43]])floatingItem(a[0],a[1],'herb');
const chestGroup=new THREE.Group();chestGroup.position.set(7,-.04,-13);scene.add(chestGroup);
box(0,.45,0,1.2,.9,.86,M.wood,chestGroup);box(0,.91,0,1.3,.25,.96,M.iron,chestGroup);box(0,.83,-.51,.18,.28,.05,M.gold,chestGroup);
const chest={pos:chestGroup.position,used:false};

// Player, HUD, mission, progress and save. The game is playable without a third-party humanoid asset.
const saveKey='ashen_frontier_v1';let save={q:0,kills:0,hp:100,stamina:100,herbs:2,coins:0,xp:0,level:1,relic:false,chest:false,defeated:[]};
try{const obj=JSON.parse(localStorage.getItem(saveKey)||'null');if(obj&&typeof obj==='object')save={...save,...obj,defeated:Array.isArray(obj.defeated)?obj.defeated:[]};}catch{}
const player={pos:new THREE.Vector3(0,0,15),hp:clamp(+save.hp||100,1,140),maxhp:100+(Math.max(1,save.level||1)-1)*10,stamina:100,level:save.level||1,xp:save.xp||0,coins:save.coins||0,herbs:save.herbs??2,invuln:0,dodging:0,dodgeDir:new THREE.Vector3(),attackTimer:0,attackCooldown:0,blocking:false,moveSpeed:0};
player.maxhp=100+(player.level-1)*10;player.hp=clamp(player.hp,1,player.maxhp);
for(const id of save.defeated){if(enemies[id]){enemies[id].dead=true;scene.remove(enemies[id].root)}}
if(save.relic)relic.used=true;
if(relic.used)scene.remove(relic.root);
chest.used=!!save.chest;
let playing=false,paused=true,dialog=false,inventoryOpen=false,locked=false,firstPerson=true,avatarTemplate=null,avatar=null,avatarMixer=null,avatarClips=[],npcActors=[],yaw=0,pitch=.05,camDistance=5.2,now=0,clockMinutes=8*60,saveTimer=0,toastTimer=0,killMsgTimer=0;
let walkWeight=0;let shake=0;let preventMouseUntil=0;const keys=new Set();const aim=new THREE.Vector3();
const uiTimer={damage:0};
function syncSave(){save.q=save.q||0;save.hp=player.hp;save.stamina=player.stamina;save.herbs=player.herbs;save.coins=player.coins;save.xp=player.xp;save.level=player.level;save.defeated=enemies.filter(e=>e.dead).map(e=>e.id);try{localStorage.setItem(saveKey,JSON.stringify(save))}catch{}}
window.addEventListener('beforeunload',syncSave);
function notify(txt,seconds=2.7){$('toast').textContent=txt;$('toast').classList.add('show');toastTimer=seconds}
function combatMessage(txt){$('killmsg').textContent=txt;$('killmsg').classList.add('show');killMsgTimer=1.9}
function gainXP(amount){player.xp+=amount;let need=player.level*100;while(player.xp>=need){player.xp-=need;player.level++;player.maxhp+=10;player.hp=player.maxhp;need=player.level*100;notify(`レベルアップ！ LV ${player.level}`)}hud()}
function hurt(amount){if(player.invuln>0||player.dodging>0)return;player.hp=Math.max(0,player.hp-amount);player.invuln=.72;uiTimer.damage=.6;shake=.18;hud();if(player.hp<=0)die()}
function die(){playing=false;document.exitPointerLock?.();$('startup').hidden=false;$('startup').querySelector('h1').innerHTML='YOU HAVE<br><em>FALLEN</em>';$('startup').querySelector('.lead').innerHTML='辺境の探索はここで途絶えた。<br>村から再び冒険を始めよう。';$('begin').textContent='▶ 村から再挑戦';player.pos.set(0,0,15);player.hp=player.maxhp;player.stamina=100;syncSave()}
function hud(){ $('level').textContent=String(player.level).padStart(2,'0');$('xp').textContent=`XP ${Math.floor(player.xp)} / ${player.level*100}`;
 $('coins').textContent=`◈ ${player.coins} G`;$('herb').textContent=player.herbs;$('hpbar').style.width=clamp(player.hp/player.maxhp*100,0,100)+'%';$('hpnum').textContent=`${Math.ceil(player.hp)} / ${player.maxhp}`;
 $('stbar').style.width=clamp(player.stamina,0,100)+'%';$('stnum').textContent=Math.ceil(player.stamina);
 $('invherbs').textContent='× '+player.herbs;$('invcoins').textContent=player.coins+' G';$('invrelic').textContent=save.relic?'所持':'未入手';}
const objectives=[
 ['冒険者ギルドへの招待','広場にいるギルド長アーリンと話す。','ギルドで最初の仕事を受けよう。'],
 ['森に潜む魔獣','古の森で魔獣を3体討伐する。','森の小道を進み、魔獣を倒そう。'],
 ['討伐報告','村へ戻り、ギルド長に討伐を報告する。','村のアーリンに報告しよう。'],
 ['失われた遺物','古代遺跡の中心で「暁の遺物」を回収する。','遺跡には古代の守護者がいる。'],
 ['辺境の英雄','古代の遺物を村のギルド長へ届ける。','遺物を持ってギルドへ戻ろう。'],
 ['暁の遺産','初章クリア。辺境を自由に探索できる。','章をクリアしました。引き続き探索可能です。'] ];
function questTarget(){return save.q===0||save.q===2||save.q===4?new THREE.Vector3(2,0,1):save.q===1?new THREE.Vector3(0,0,-40):new THREE.Vector3(2,0,-77)}
function updateQuest(){const data=objectives[clamp(save.q,0,5)];$('questtitle').textContent=data[0];$('questdesc').textContent=data[1];$('tips').textContent=data[2];$('questcount').textContent=save.q===1?`討伐 ${Math.min(save.kills||0,3)} / 3`:`進捗 ${Math.min(save.q,5)} / 5`;
 $('questbar').style.width=((save.q===1?(1+(Math.min(save.kills||0,3)/3))/5:Math.min(save.q,5)/5)*100)+'%';
 $('zone').textContent=player.pos.z>-15?'霧の辺境村':player.pos.z>-66?'古の森':'忘却の遺跡';}
// NPCs: rigged-skinned GLB is the only human source. World beacons are abstract placeholders, never "humans".
const npcs=[{name:'ギルド長 アーリン',x:2,z:1,role:'guild',color:0xe3c583},{name:'行商人 ベル',x:-4,z:10,role:'shop',color:0x7ee8b3}];
function markerActor(n){const root=new THREE.Group();root.position.set(n.x,0,n.z);scene.add(root);
 const pedestal=mesh(new THREE.CylinderGeometry(.84,1,.42,10),M.stoneDark,root,0,.05,0);
 const orb=mesh(new THREE.OctahedronGeometry(.44,1),new THREE.MeshStandardMaterial({color:n.color,emissive:n.color,emissiveIntensity:.65,roughness:.3}),root,0,2.05,0);orb.userData.float=true;
 const ring=mesh(new THREE.TorusGeometry(.62,.07,8,24),M.gold,root,0,2,0);ring.rotation.x=Math.PI/2;
 const sign=paintLabel(n.name);sign.position.set(0,3.55,0);root.add(sign);
 const mark={...n,root,placeholder:orb,ring,human:null,anim:null};npcActors.push(mark);return mark}
npcs.forEach(markerActor);
const playerRoot=new THREE.Group();scene.add(playerRoot);
let playerHalo=mesh(new THREE.TorusGeometry(.48,.035,6,24),M.gold,playerRoot,0,.07,0,false);playerHalo.rotation.x=Math.PI/2;playerHalo.material=new THREE.MeshBasicMaterial({color:0xd0c58c,transparent:true,opacity:.5});
function loadGLB(src){return new Promise((res,rej)=>new GLTFLoader().load(src,res,undefined,rej))}
function humanoidData(gltf){let count=0;gltf.scene.traverse(o=>{if(o.isSkinnedMesh)count++});if(!count)throw new Error('スキニング済みの人物メッシュがありません');return {gltf,skinned:count}}
function setupInstance(template,height=1.83){const m=cloneSkeleton(template);m.position.set(0,0,0);m.scale.setScalar(1);m.updateMatrixWorld(true);
 const bb=new THREE.Box3().setFromObject(m);const sy=bb.getSize(new THREE.Vector3()).y;if(!(sy>.1))throw new Error('GLBの高さが不正です');m.scale.setScalar(height/sy);m.updateMatrixWorld(true);
 const b2=new THREE.Box3().setFromObject(m);m.position.y-=b2.min.y;const c=b2.getCenter(new THREE.Vector3());m.position.x-=c.x;m.position.z-=c.z;
 m.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true;if(o.isSkinnedMesh)o.frustumCulled=false}});return m}
function mixerSetup(node,clips){const mixer=new THREE.AnimationMixer(node),acts={};for(const clip of clips){let nm=clip.name.toLowerCase();for(const k of ['idle','walk','run','attack','sword','slash','talk'])if(nm.includes(k))acts[k]=mixer.clipAction(clip)}return {mixer,acts,active:null}}
function transition(state,what){if(!state)return;if(state.active===what)return;const a=state.acts[what]||state.acts.idle;if(a){a.reset().fadeIn(.18).play();for(const x of Object.values(state.acts))if(x!==a)x.fadeOut(.18)}state.active=what}
async function setHuman(src){$('modelstatus').textContent='人物GLBをロード中…';try{
 const {gltf,skinned}=humanoidData(await loadGLB(src));
 if(avatar){playerRoot.remove(avatar);avatar=null;}for(const n of npcActors){if(n.human)n.root.remove(n.human);n.human=null;if(n.anim)n.anim.mixer.stopAllAction();}
 avatarTemplate=gltf.scene;avatarClips=gltf.animations||[];
 avatar=setupInstance(avatarTemplate);playerRoot.add(avatar);avatarMixer=mixerSetup(avatar,avatarClips);
 for(const n of npcActors){n.human=setupInstance(avatarTemplate);n.root.add(n.human);n.placeholder.visible=false;n.ring.visible=false;n.anim=mixerSetup(n.human,avatarClips);transition(n.anim,'idle');}
 firstPerson=true;$('modelstatus').textContent=`人物GLB読込成功：SkinnedMesh ${skinned} / アニメーション ${avatarClips.length}。Vキーで三人称視点に切替可能。`;
 notify('人物モデルをロードしました。VでFPS/三人称を切替');return true;
}catch(e){avatar=null;firstPerson=true;$('modelstatus').textContent='高品質人物GLB未導入：FPS視点で探索・戦闘可能です。人物は抽象的な目印で表示。 '+String(e.message||e);return false;}}
$('glbfile').addEventListener('change',async e=>{const f=e.target.files?.[0];if(!f)return;const url=URL.createObjectURL(f);try{await setHuman(url)}finally{setTimeout(()=>URL.revokeObjectURL(url),30000)}});
(async()=>{const tryUrls=['./assets/human.glb','https://threejs.org/examples/models/gltf/Soldier.glb'];for(const url of tryUrls){if(await setHuman(url))break}})();
// Ground-following locomotion, pointer lock, combat.
const keysDown=new Set();const forward=new THREE.Vector3(),right=new THREE.Vector3();let currentInteraction=null,mouseHeld=false;
function collision(x,z){if(x<-92||x>92||z<-101||z>83)return true;
 for(const s of solids)if(Math.abs(x-s.x)<s.w/2+.45&&Math.abs(z-s.z)<s.d/2+.45)return true;return false}
function nearObject(){let d=3.0,result=null;const pos=player.pos;
 for(const n of npcActors){const dist=pos.distanceTo(new THREE.Vector3(n.x,0,n.z));if(dist<d){d=dist;result={type:n.role,actor:n,label:`${n.name}に話す`}}}
 if(!chest.used){let dist=pos.distanceTo(chest.pos);if(dist<d){d=dist;result={type:'chest',label:'補給箱を開ける'}}}
 for(const p of pickups)if(!p.used){let dist=pos.distanceTo(p.pos);if(dist<d){d=dist;result={type:p.kind,object:p,label:p.kind==='relic'?'暁の遺物を拾う':'薬草を採集する'}}}
 return result;}
function interact(){if(dialog){closeDialogue();return;}if(inventoryOpen){closeInventory();return}if(!playing)return;const obj=nearObject();if(!obj){notify('周辺に調べられるものはありません');return;}
 if(obj.type==='guild'){showGuild();return}if(obj.type==='shop'){showShop();return}
 if(obj.type==='chest'){chest.used=true;save.chest=true;player.herbs+=2;player.coins+=15;chestGroup.visible=false;notify('補給箱：薬草×2・15Gを入手');hud();syncSave();return}
 if(obj.type==='herb'){obj.object.used=true;obj.object.root.visible=false;player.herbs++;notify('薬草を1個入手');hud();syncSave();return}
 if(obj.type==='relic'){if(save.q<3){notify('まずギルド長から遺跡探索の依頼を受けよう');return;}if(enemies[5]&&!enemies[5].dead){notify('守護者が遺物を守っている！');return;}
 save.relic=true;obj.object.used=true;obj.object.root.visible=false;save.q=4;notify('クエスト更新：「暁の遺物」を入手');updateQuest();syncSave();}
}
function showDialogue(who,text,buttons){dialog=true;releasePointer();$('dialogue').hidden=false;$('speaker').textContent=who;$('dialoguetext').textContent=text;
 const c=$('dialoguechoices');c.replaceChildren();for(const [label,fn] of buttons){const b=document.createElement('button');b.textContent=label;b.addEventListener('click',fn);c.appendChild(b)} }
function closeDialogue(){$('dialogue').hidden=true;dialog=false;if(playing)requestPointer()}
function showGuild(){const name='ギルド長 アーリン';if(save.q===0)showDialogue(name,'よく来た、旅の者よ。古の森に魔獣が増えている。ギルドの試練として、3体を討伐してきてくれないか。',[["依頼を受ける",()=>{save.q=1;save.kills=0;updateQuest();closeDialogue();notify('新クエスト：森に潜む魔獣');syncSave()}],['また後で',closeDialogue]]);
 else if(save.q===1)showDialogue(name,`討伐状況は ${Math.min(save.kills||0,3)} / 3 だ。油断は禁物。命を大切にしてくれ。`,[['了解',closeDialogue]]);
 else if(save.q===2)showDialogue(name,'よくやった！ 森の脅威が和らいだ。次は南の忘却の遺跡に眠る「暁の遺物」を回収してほしい。守護者には気をつけろ。',[['遺跡へ向かう',()=>{save.q=3;player.coins+=30;gainXP(45);updateQuest();hud();closeDialogue();notify('報酬：30G / XP +45');syncSave()}],['準備する',closeDialogue]]);
 else if(save.q===3)showDialogue(name,'忘却の遺跡は森の奥だ。石柱に囲まれた祭壇に遺物があるはずだ。', [['分かった',closeDialogue]]);
 else if(save.q===4)showDialogue(name,'まさか本当に持ち帰るとは……！ 君の名前は辺境の記録に刻まれるだろう。', [['遺物を渡す',()=>{save.q=5;player.coins+=120;gainXP(120);updateQuest();hud();closeDialogue();combatMessage('CHAPTER I COMPLETE');notify('初章クリア！ 報酬120G / XP +120',4);syncSave()}],['あとで',closeDialogue]]);
 else showDialogue(name,'ここはいつでも君の故郷だ。探索を続けるのもよし、次の章を待つのもよし。',[['ありがとう',closeDialogue]]);}
function showShop(){showDialogue('行商人 ベル','森の中では回復薬が命綱だよ。薬草は1個15G。必要なら買っておいき。',[['薬草を購入（15G）',()=>{if(player.coins>=15){player.coins-=15;player.herbs++;hud();syncSave();notify('薬草×1を購入')}else notify('金貨が足りません');closeDialogue()}],['店を出る',closeDialogue]])}
function heal(){if(!playing||dialog||inventoryOpen)return;if(player.herbs<=0){notify('薬草を持っていません');return}if(player.hp>=player.maxhp-1){notify('HPは十分です');return}player.herbs--;player.hp=Math.min(player.maxhp,player.hp+35);hud();notify('薬草を使った：HP +35');syncSave()}
function hitEnemy(e,damage){if(e.dead)return;e.hp-=damage;e.root.position.y=.09;shake=.07;if(e.hp<=0){e.dead=true;e.root.visible=false;player.coins+=e.type==='guardian'?85:12;gainXP(e.type==='guardian'?90:32);if(e.type==='wolf'&&save.q===1){save.kills=(save.kills||0)+1;if(save.kills>=3){save.q=2;notify('討伐完了！ ギルド長に報告しよう',4)}}combatMessage(e.type==='guardian'?'ANCIENT GUARDIAN DEFEATED':'MONSTER DEFEATED');syncSave();updateQuest()}else if(e.type==='guardian')$('bossfill').style.width=clamp(e.hp/e.maxhp*100,0,100)+'%';hud()}
function attack(){if(!playing||paused||dialog||inventoryOpen||player.hp<=0)return;if(player.attackCooldown>0||player.stamina<12)return;
 player.stamina-=12;player.attackTimer=.38;player.attackCooldown=.42;shake=.08;
 let direction=new THREE.Vector3(Math.sin(yaw),0,-Math.cos(yaw));let victim=null,minD=3.15;
 for(const e of enemies){if(e.dead)continue;const d=e.root.position.distanceTo(player.pos);if(d<minD){let vec=e.root.position.clone().sub(player.pos).normalize();const dot=vec.dot(direction);if(dot>.27){minD=d;victim=e}}}
 if(victim){hitEnemy(victim,victim.type==='guardian'?42:48);notify(victim.type==='guardian'?'古代の守護者に命中':'斬撃命中',.9)}
 else notify('空振り',.6);if(avatarMixer?.acts.attack)transition(avatarMixer,'attack');else if(avatarMixer?.acts.sword)transition(avatarMixer,'sword');}
function dodge(){if(!playing||player.dodging>0||player.stamina<30)return;player.stamina-=30;player.dodging=.35;player.invuln=.4;forward.set(Math.sin(yaw),0,-Math.cos(yaw));right.set(Math.cos(yaw),0,Math.sin(yaw));player.dodgeDir.set(0,0,0);
 if(keysDown.has('KeyS'))player.dodgeDir.sub(forward);else player.dodgeDir.add(forward);
 if(keysDown.has('KeyA'))player.dodgeDir.sub(right);if(keysDown.has('KeyD'))player.dodgeDir.add(right);player.dodgeDir.normalize();}
const sword=new THREE.Group();camera.add(sword);scene.add(camera);
const bladeMaterial=new THREE.MeshStandardMaterial({color:0xb7c6c5,metalness:.88,roughness:.27});
const grip=mesh(new THREE.CylinderGeometry(.045,.055,.42,10),M.wood,sword,0,-.2,0);grip.rotation.z=.15;
const guard=box(0,.02,0,.5,.10,.12,M.gold,sword);const blade=mesh(new THREE.ConeGeometry(.085,1.0,4),bladeMaterial,sword,0,.57,-.025);blade.rotation.z=.03;
const pommel=mesh(new THREE.SphereGeometry(.075,10,6),M.gold,sword,0,-.43,0);
function updateCamera(dt){const aimY=firstPerson?1.67:1.4;const target=new THREE.Vector3(player.pos.x,aimY,player.pos.z);
 if(firstPerson){camera.position.lerp(new THREE.Vector3(player.pos.x,aimY+Math.sin(now*11)*walkWeight*.020,player.pos.z),Math.min(1,dt*18));camera.rotation.set(-pitch,-yaw,0,'YXZ');}
 else{const dist=camDistance;const cp=new THREE.Vector3(player.pos.x-Math.sin(yaw)*dist*Math.cos(pitch),target.y+1.5+Math.sin(pitch)*dist,player.pos.z+Math.cos(yaw)*dist*Math.cos(pitch));camera.position.lerp(cp,Math.min(1,dt*9));camera.lookAt(target);}
 if(shake>0){camera.position.add(new THREE.Vector3(between(-.025,.025),between(-.025,.025),0).multiplyScalar(shake*10))}
 sword.visible=firstPerson;sword.position.set(.60,-.43,-1.15);sword.rotation.set(.21+Math.sin(now*8)*walkWeight*.04,-.2,.46);
 if(player.attackTimer>0){const pct=1-player.attackTimer/.38;sword.rotation.z=.46-Math.sin(pct*Math.PI)*2.6;sword.position.x=.6+Math.sin(pct*Math.PI)*.13}
 avatar?.scale.setScalar(avatar.scale.x);playerRoot.position.copy(player.pos);playerRoot.rotation.y=yaw+Math.PI;
 if(avatar)avatar.visible=!firstPerson;playerHalo.visible=!firstPerson;}
function playerUpdate(dt){if(!playing||paused||dialog||inventoryOpen)return;
 player.invuln=Math.max(0,player.invuln-dt);player.attackCooldown=Math.max(0,player.attackCooldown-dt);player.attackTimer=Math.max(0,player.attackTimer-dt);
 player.dodging=Math.max(0,player.dodging-dt);const moving=new THREE.Vector3();forward.set(Math.sin(yaw),0,-Math.cos(yaw));right.set(Math.cos(yaw),0,Math.sin(yaw));
 if(keysDown.has('KeyW'))moving.add(forward);if(keysDown.has('KeyS'))moving.sub(forward);if(keysDown.has('KeyD'))moving.add(right);if(keysDown.has('KeyA'))moving.sub(right);
 const running=(keysDown.has('ShiftLeft')||keysDown.has('ShiftRight'))&&player.stamina>1&&moving.lengthSq()>.01;
 if(running)player.stamina=Math.max(0,player.stamina-dt*22);else if(player.dodging<=0)player.stamina=Math.min(100,player.stamina+dt*14);
 let speed=running?7.3:4.0;if(player.blocking)speed*=.52;
 if(moving.lengthSq())moving.normalize();walkWeight=THREE.MathUtils.damp(walkWeight,moving.lengthSq()?1:0,8,dt);
 if(player.dodging>0){moving.copy(player.dodgeDir);speed=14;}let nx=player.pos.x+moving.x*dt*speed,nz=player.pos.z+moving.z*dt*speed;
 if(!collision(nx,player.pos.z))player.pos.x=nx;if(!collision(player.pos.x,nz))player.pos.z=nz;
 if(avatarMixer){avatarMixer.mixer.update(dt);const state=player.attackTimer>0?(avatarMixer.acts.attack?'attack':avatarMixer.acts.sword?'sword':'idle'):moving.lengthSq()?(running?'run':'walk'):'idle';transition(avatarMixer,state)}
 if(mouseHeld)attack();
}
function enemyUpdate(dt){if(!playing||paused||dialog||inventoryOpen)return;for(const e of enemies){if(e.dead)continue;
 e.attackCooldown=Math.max(0,e.attackCooldown-dt);e.brain-=dt;e.phase+=dt;
 const dist=e.root.position.distanceTo(player.pos);if(e.type==='guardian')$('bossbar').hidden=dist>19;
 if(dist<17){e.goal.copy(player.pos);if(dist<2.3&&e.attackCooldown<=0){hurt(e.type==='guardian'?22:11);e.attackCooldown=e.type==='guardian'?2.1:1.55;notify('敵の攻撃を受けた！',.75)}}
 else if(e.brain<0){e.brain=between(2,5);e.goal.set(e.home.x+between(-5,5),0,e.home.z+between(-5,5));}
 const toward=e.goal.clone().sub(e.root.position);toward.y=0;if(toward.length()>dist*.3&&dist<2.4){}else if(toward.length()>.6){toward.normalize();const speed=e.speed*(dist<17?1:.42);e.root.position.addScaledVector(toward,dt*speed);const desired=Math.atan2(-toward.x,-toward.z);let dif=THREE.MathUtils.euclideanModulo(desired-e.root.rotation.y+Math.PI,Math.PI*2)-Math.PI;e.root.rotation.y+=clamp(dif,-dt*3.4,dt*3.4);}
 if(e.type==='guardian')e.root.position.y=Math.sin(e.phase*1.1)*.15;else e.root.position.y=Math.abs(Math.sin(e.phase*7))*.045;
 }}
function miniMap(){const c=$('minimap'),ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);ctx.save();ctx.beginPath();ctx.arc(W/2,H/2,W/2-3,0,Math.PI*2);ctx.clip();
 ctx.fillStyle='#25382f';ctx.fillRect(0,0,W,H);const scale=1.65;function at(x,z){return [W/2+(x-player.pos.x)*scale,H/2+(z-player.pos.z)*scale]}
 ctx.lineWidth=12;ctx.strokeStyle='#7a7861';ctx.beginPath();for(let i=-92;i<=25;i+=2){const pt=at(Math.sin(i*.06)*3,i);if(i===-92)ctx.moveTo(...pt);else ctx.lineTo(...pt)}ctx.stroke();
 for(let n of npcs){let [x,y]=at(n.x,n.z);ctx.beginPath();ctx.fillStyle='#79c7a0';ctx.arc(x,y,4,0,Math.PI*2);ctx.fill()}
 for(const e of enemies)if(!e.dead){let [x,y]=at(e.root.position.x,e.root.position.z);ctx.fillStyle='#d98673';ctx.beginPath();ctx.arc(x,y,e.type==='guardian'?5:3,0,Math.PI*2);ctx.fill()}
 if(save.q<5){const t=questTarget(),[x,y]=at(t.x,t.z);ctx.fillStyle='#f4d986';ctx.beginPath();ctx.arc(x,y,6,0,Math.PI*2);ctx.fill();ctx.strokeStyle='#e0c178';ctx.beginPath();ctx.arc(x,y,9,0,Math.PI*2);ctx.stroke()}
 ctx.save();ctx.translate(W/2,H/2);ctx.rotate(-yaw);ctx.fillStyle='#f1eeda';ctx.beginPath();ctx.moveTo(0,-9);ctx.lineTo(-6,7);ctx.lineTo(0,4);ctx.lineTo(6,7);ctx.closePath();ctx.fill();ctx.restore();ctx.restore();
 ctx.strokeStyle='#d0c49b';ctx.lineWidth=2;ctx.beginPath();ctx.arc(W/2,H/2,W/2-2,0,Math.PI*2);ctx.stroke();}
let zoneTimer=0;
function frame(){let dt=Math.min(theClock.getDelta(),.052);now+=dt;const scaled=paused?0:dt;clockMinutes=(clockMinutes+scaled*.75)%(24*60);
 playerUpdate(scaled);enemyUpdate(scaled);updateCamera(dt);
 for(const n of npcActors){if(n.anim){n.anim.mixer.update(scaled);transition(n.anim,'idle')}else{n.placeholder.position.y=2.05+Math.sin(now*1.6+n.x)*.13;n.ring.rotation.z+=scaled*.3}}
 for(const p of pickups){if(!p.used){p.orb.rotation.y+=scaled*.7;p.orb.position.y=1.1+Math.sin(now*2+p.pos.x)*.17;p.ring.position.y=p.orb.position.y}}
 temple.artifact.rotation.y+=scaled*.38;campfire.scale.y=1+Math.sin(now*10)*.18;
 shake=Math.max(0,shake-dt*.62);uiTimer.damage=Math.max(0,uiTimer.damage-dt*2);$('hitflash').style.opacity=uiTimer.damage.toFixed(2);
 if(toastTimer>0){toastTimer-=dt;if(toastTimer<=0)$('toast').classList.remove('show')}
 if(killMsgTimer>0){killMsgTimer-=dt;if(killMsgTimer<=0)$('killmsg').classList.remove('show')}
 if(playing&&!paused&&!dialog&&!inventoryOpen){currentInteraction=nearObject();$('interaction').hidden=!currentInteraction;if(currentInteraction)$('interactlabel').textContent=currentInteraction.label;
 saveTimer+=dt;if(saveTimer>8){syncSave();saveTimer=0}zoneTimer+=dt;if(zoneTimer>.26){zoneTimer=0;updateQuest();const v=questTarget();$('questdistance').textContent=save.q<5?`${Math.round(v.distanceTo(player.pos))}m`:'CLEAR';$('daytime').textContent=`DAY 01 · ${String(Math.floor(clockMinutes/60)).padStart(2,'0')}:${String(Math.floor(clockMinutes%60)).padStart(2,'0')}`;miniMap();hud();}}
 if(player.hp>0){$('bossfill').style.width=clamp(enemies[5].hp/enemies[5].maxhp*100,0,100)+'%';}
 renderer.render(scene,camera);
}
renderer.setAnimationLoop(frame);
// Mouse/keyboard events: retain playable v3-style pointer lock workflow.
function requestPointer(){if(!playing||inventoryOpen||dialog)return;canvas.requestPointerLock?.().catch(()=>{});}
function releasePointer(){if(document.pointerLockElement===canvas)document.exitPointerLock?.()}
function begin(){playing=true;paused=false;dialog=false;inventoryOpen=false;player.hp=Math.max(1,player.hp);$('startup').hidden=true;$('pause').hidden=true;$('inventory').hidden=true;requestPointer();hud();updateQuest()}
$('begin').addEventListener('click',begin);
canvas.addEventListener('click',()=>{if(!playing)return;if(!locked){requestPointer();return}attack()});
canvas.addEventListener('mousedown',e=>{if(e.button===0){mouseHeld=true;if(locked)attack()}if(e.button===2){player.blocking=true}});
document.addEventListener('mouseup',e=>{if(e.button===0)mouseHeld=false;if(e.button===2)player.blocking=false});
canvas.addEventListener('contextmenu',e=>e.preventDefault());
document.addEventListener('pointerlockchange',()=>{locked=document.pointerLockElement===canvas;if(playing&&!dialog&&!inventoryOpen){paused=!locked;$('pause').hidden=locked;mouseHeld=false}});
document.addEventListener('mousemove',e=>{if(!locked||!playing||dialog||inventoryOpen)return;yaw+=e.movementX*.0024;pitch=clamp(pitch+e.movementY*.0020,-.74,.89)});
canvas.addEventListener('wheel',e=>{camDistance=clamp(camDistance+Math.sign(e.deltaY)*.42,2.8,8.5);e.preventDefault()},{passive:false});
document.addEventListener('keydown',e=>{keysDown.add(e.code);if(['Space','Tab','ArrowUp','ArrowDown'].includes(e.code))e.preventDefault();if(e.repeat)return;
 if(e.code==='KeyE')interact();if(e.code==='KeyH')heal();if(e.code==='KeyQ')dodge();if(e.code==='KeyV'){if(avatar){firstPerson=!firstPerson;notify(firstPerson?'FPS視点':'三人称視点')}else notify('人物GLB未導入のためFPS視点でプレイします')}
 if(e.code==='Tab'&&playing){if(!inventoryOpen)openInventory();else closeInventory()}
 if(e.code==='Space')attack();});
document.addEventListener('keyup',e=>keysDown.delete(e.code));
window.addEventListener('blur',()=>{keysDown.clear();mouseHeld=false});
function openInventory(){inventoryOpen=true;releasePointer();$('inventory').hidden=false;hud()}
function closeInventory(){inventoryOpen=false;$('inventory').hidden=true;if(playing)requestPointer()}
$('closeinventory').onclick=closeInventory;$('backgame').onclick=closeInventory;
$('dialogclose').onclick=closeDialogue;
$('resume').onclick=()=>{paused=false;$('pause').hidden=true;requestPointer()};
$('reset').onclick=()=>{if(confirm('セーブデータを消去して最初から始めますか？')){try{localStorage.removeItem(saveKey)}catch{}location.reload()}};
window.addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight)});
window.addEventListener('error',e=>{console.error(e.error||e.message);$('error').hidden=false;$('error').textContent='描画中に問題が発生しました：'+e.message});
chestGroup.visible=!chest.used;hud();updateQuest();miniMap();
// Debug interface for automated functional checks (read-only snapshot, no bypass of gameplay).
window.__ASHEN_DEBUG__={status:()=>({playing,paused,locked,firstPerson,humanLoaded:!!avatar,quests:save.q,kills:save.kills||0,hp:player.hp,enemiesAlive:enemies.filter(e=>!e.dead).length,position:{x:player.pos.x,z:player.pos.z}})};
