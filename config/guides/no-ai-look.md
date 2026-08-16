# 가이드: AI티 제거 (영상·사진 공통)

이 팀의 산출물은 **AI로 만든 티가 나면 실패**다. 기술적으로 맞게 뽑는 것보다
"사람이 찍은 것처럼 보이는가"가 최종 합격 기준이다.

## 왜 AI처럼 보이는가 — 핵심 원인

실제 카메라는 **휘도에 따라 변하는 센서 노이즈, 렌즈 수차, 색수차, 광학적 불완전성**을 남긴다.
AI 프레임에는 이게 전혀 없고, **그 부재 자체가 "가짜"로 읽힌다.**
따라서 후보정의 방향은 "더 깨끗하게"가 아니라 **"광학적 불완전성을 되돌려 넣는 것"** 이다.

주요 판별 신호:
- **이미지**: 손·글자 왜곡 / 균질한 피부 텍스처(모공·잡티·비대칭 없음) / 캐치라이트 없는 눈 /
  무질서해야 할 곳(머리카락·나뭇잎)의 반복 패턴 / 전경 뒤로 지나가는 선의 끊김 /
  조명·그림자 방향 불일치 / 얕은 피사계심도 남용 / 여러 인물의 얼굴·옷 복제(clone army)
- **영상**: 프레임 가장자리가 주피사체보다 먼저 무너짐 / 배경 물체의 정체성 변화 /
  컷마다 얼굴 드리프트 / 무게 없는 착지 등 물리 위반 / 눈 깜빡임·미세표정 부재 /
  모든 컷이 3~4초로 균일 / 룸톤 없이 나레이션+제네릭 BGM / 센터·아이레벨·정적 구도 일변도

## 생성 단계 — 프롬프트에 사진 용어를 쓴다

일러스트 어휘가 아니라 **실제 촬영 용어**로 쓰면 출력이 사진 쪽으로 이동한다.
- 필름 스톡: Kodak Portra 400 / Portra 160 / Kodak Gold / Fuji Pro 400H
  (기억 안 나면 `shot with 35mm film` 한 줄만 넣어도 효과 있음)
- 바디·렌즈: Leica Q3, Canon EOS, Sony a7 / 35mm, 85mm, anamorphic, tilt-shift
- 조명: `window light`처럼 **우연해 보이는 광원**을 지정
- 불완전성 명시: `slightly messy hair`, `natural skin texture`, `slight motion blur on feet`
- 피할 것: `hyper-detailed` 류 과잉 묘사, artistic style 키워드
- Midjourney: `--style raw` + `--stylize` 낮은~중간값
- 영상: **샷 하나당 피사체 1 / 동작 1 / 카메라 무빙 1**. 렌즈+광원+시간대+텍스처를 반드시 포함

## 후보정 — 순서가 중요하다

**컬러그레이딩 → 그레인 → 최종 블러.** 각 단계가 서로 다른 신호를 고치므로 순서를 바꾸지 않는다.
DaVinci 노드 순서는 balance → match → look → texture, LUT은 마지막 노드에만.
판단은 눈이 아니라 **웨이브폼/벡터스코프** 기준으로 한다.

### 수치 (⚠️ 출처 간 불일치 — 프리셋 확정 전 A/B 테스트 필수)

| 항목 | invideo | greenfroglabs |
|---|---|---|
| 필름 그레인 | 내장 필터 2~3% / 오버레이 20~40% | 35mm 오버레이 10~15% |

두 출처의 그레인 값이 다르다. **짧은 클립으로 비교한 뒤 팀 프리셋으로 확정하고, 확정값을 이 파일에 기록하라.**

합의된 값:
- Gaussian blur(과선명 제거): **0.3~0.8px**
- 컬러 온도 컷 간 허용 편차: **±200K**
- 오디오 라우드니스: **-14 LUFS**
- 컷 길이: **1~8초 범위에서 변주**
- 사진 그레인은 ISO에 맞춘다: ISO800 ≈ 0.8~1.2%, ISO1600 ≈ 1.5~2.0%, 한낮 실외는 더 적게

룩별 처방:
- **시네마틱**: 그레인 2~3% Overlay + optical softness + 하이라이트 약한 halation
- **UGC/폰**: 그레인 30~40% Soft Light, halation 생략, 색수차 + 미세 모션블러

### 핸드헬드 흔들림 (After Effects)
```
wiggle(2, 30)          // Position — 대부분 무난
wiggle(0.5, 0.3)       // Z Rotation — 은은한 틸트
wiggle(1.5, 8)         // Focus Distance — 미세 포커스 브리딩
```
Scale **110~120%** 로 올려 가장자리를 가리고, **Shutter Angle = 360** 을 반드시 켠다.
이게 없으면 흔들림이 핸드헬드가 아니라 지터링 슬라이드쇼로 읽힌다.
24fps + 180° 셔터(1/48s)가 기준. 셔터스피드 ≈ 프레임레이트 × 2.

## ffmpeg 실전 명령어

**루마 전용 그레인** (컬러 노이즈 방지 — 60은 강한 편이니 낮춰서 테스트):
```bash
ffmpeg -i input.mp4 -vf noise=c0s=60:c0f=t+u output.mp4
```

**색수차**:
```bash
ffmpeg -i input.mp4 -c:v libx264 -vf rgbashift=rh=-6:gh=6 -pix_fmt yuv420p output.mp4
```

**LUT / 커브 그레이딩**:
```bash
ffmpeg -i input.mp4 -vf lut3d=file=look.cube output.mp4
ffmpeg -i input.mp4 -vf curves=psfile=file.acv output.mp4
```

**그레인 오버레이 25% 합성** (`aa` 값으로 불투명도 조절):
```bash
ffmpeg -i input.mp4 -i overlay.mp4 -filter_complex \
"[1]format=yuva444p,colorchannelmixer=aa=0.25[2];[2][0]scale2ref[2][1];[1][2]overlay" output.mp4
```

**휘도 마스킹 그레인** (가장 정교 — 2배 해상도 노이즈 → 형태학 필터 → 휘도 75 근처 집중):
```bash
ffmpeg -i "in.mkv" -i "in.mkv" -filter_complex "
color=black:d=DURATION:s=3840x2160:r=24000/1001,
geq=lum_expr=random(1)*256:cb=128:cr=128,
deflate=threshold0=15, dilation=threshold0=10, eq=contrast=3, scale=1920x1080 [n];
[0] eq=saturation=0,geq=lum='0.15*(182-abs(75-lum(X,Y)))':cb=128:cr=128 [o];
[n][o] blend=c0_mode=multiply,negate [a];
color=c=black:d=DURATION:s=1920x1080:r=24000/1001 [b];
[1][a] alphamerge [c]; [b][c] overlay" \
-c:a copy -c:v libx264 -tune grain -preset veryslow -crf 12 -y out.mkv
```

**인코딩 원칙 — 이걸 빠뜨리면 앞의 작업이 전부 무의미해진다:**
그레인을 넣은 영상은 반드시 `-tune grain` + `-crf 12~16`.
없으면 인코더가 그레인을 노이즈로 보고 지워버린다.

## 도구

- 생성(리얼리즘): Veo, Kling — 물리 시뮬레이션 우위
- 생성(스타일라이즈드): Seedance, Hailuo — 단 초선명 플라스틱 피부라 grain+blur 필수
- 이미지: Midjourney(`--style raw`), Flux + 리얼리즘 LoRA(Improved Amateur Snapshot / UltraRealistic / XLabs Realism)
- 후보정: DaVinci Resolve(무료판으로 전 공정 가능), **Dehancer OFX**(필름 프로파일 + Halation + Gate Weave/Film Breath — AI 영상의 "너무 안정적인 프레임"에 직접 대응)
- 업스케일: Topaz Video AI (Nyx=센서노이즈, Artemis=압축아티팩트). 후반 **초기**에 적용. 얼굴에 강한 디노이즈 금지
- 배치: ffmpeg

⚠️ **엔진 혼용 주의**: Veo/Kling/Sora를 섞으면 여러 감독의 작업을 이어붙인 것처럼 읽힌다.
섞을 거면 마지막에 **동일한 텍스처 패스(그레인+그레이딩)** 를 전 클립에 걸어 통일한다.

---

## [VIDEO ANTI-AI CHECKLIST]

```
1. 컷 길이를 1~8초 사이에서 변주했는가? 모든 컷이 3~4초면 실패.
2. 주인공 얼굴이 컷 간 동일한가? (레퍼런스 시트 락)
3. 프레임 가장자리·배경을 검수했는가? 배경 물체의 정체성 변화·모핑이 없어야 한다.
4. 컬러그레이딩 → 그레인 → 블러 순서로 텍스처 패스를 적용했는가?
5. 모든 클립에 동일한 최종 텍스처 패스를 걸어 엔진 간 차이를 지웠는가?
6. 핸드헬드 미세 흔들림 + Scale 110~120% + Shutter Angle 360을 넣었는가?
7. 24fps + 180° 셔터 기준 모션블러가 있는가? 과선명 스터터 프레임은 실패.
8. 컷 간 조명 방향·색온도가 일관적인가? (±200K 이내)
9. 룸톤/환경음이 들어갔는가? 무음+제네릭 BGM만이면 실패. 최종 -14 LUFS.
10. 대사 컷을 음소거로 재생해 입 모양을 확인했는가?
11. 구도가 센터·아이레벨·정적 일변도가 아닌가?
12. 인코딩에 -tune grain + CRF 12~16을 썼는가?
```

## [PHOTO ANTI-AI CHECKLIST]

```
1. 프롬프트에 실제 카메라/렌즈/필름스톡/조명을 명시했는가?
2. Midjourney면 --style raw + --stylize 낮은~중간값인가?
3. 불완전성을 명시했는가? (흐트러진 머리, 자연스러운 피부 텍스처, 살짝 빗나간 초점)
4. 손·글자·반복 패턴·전경 뒤로 지나가는 선을 확대해 검수했는가?
5. 얼굴 광원과 배경 광원, 그림자 방향, 반사각이 물리적으로 맞는가?
6. 피부에 균질하지 않은 텍스처(모공·잡티·좌우 비대칭)가 있는가? 왁스 피부는 실패.
7. 눈에 캐치라이트가 있고 홍채·동공이 정상인가?
8. 보케를 과하게 쓰지 않았는가?
9. 장면 ISO에 맞는 그레인을 넣었는가?
10. 광학적 사실을 추가했는가? 미세 색수차, 부드러운 비네팅, 하이라이트 일부 blown-out, 약한 렌즈 왜곡.
11. 완벽한 대칭/중앙 구도를 깼는가?
12. 여러 인물의 얼굴·옷·색이 복제되지 않았는가? (clone army 체크)
```
