# JobsDone demo assets

## Scope
Local draft media only. No publication or changes to JobsDone repository. macOS-like UI and GitHub-style PR page are rendered recreations with fictional demo-lab/demo-builder/demo-teammate data; no Apple logos, credentials, emails or real event submissions.

The earlier STORYBOARD.md was not present on this box when rendering started; its hero/main timing and factual UI specifications were reconstructed from the preceding task transcript. Code lives in remotion/, not a checkout of JobsDone.

## Asset ledger
| Asset | Source | License / permission |
|---|---|---|
| Inter variable font | https://github.com/google/fonts/tree/main/ofl/inter | SIL Open Font License 1.1; bundled public/fonts/Inter-OFL.txt |
| JetBrains Mono variable font | https://github.com/google/fonts/tree/main/ofl/jetbrainsmono | SIL Open Font License 1.1; bundled public/fonts/JetBrainsMono-OFL.txt |
| MenuBarPeon.png (real menu-bar glyph only) | petzkod5/JobsDone, Resources/MenuBarPeon.png; retrieved read-only with gh contents API | from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. Not represented as MIT or CC0. |
| WorkWork.wav | petzkod5/JobsDone, Resources/SoundPacks/peon/WorkWork.wav | from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. |
| JobsDone.wav | petzkod5/JobsDone, Resources/SoundPacks/peon/JobsDone.wav | from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. |
| Hmmm.wav | petzkod5/JobsDone, Resources/SoundPacks/peon/Hmmm.wav | from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. |
| SomethingNeedDoing.wav | petzkod5/JobsDone, Resources/SoundPacks/peon/SomethingNeedDoing.wav | from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. |
| JD monogram (versions 1–4 only; retired in v5) | Original vector-like typography/shapes made for these videos | Original generated demo artwork; CC0 dedication to extent rights exist. Not the shipped app icon. |
| Synthesized music bed and quiet clicks (versions 1–4 only; music retired in v5) | Original mathematical sine/chord/pluck synthesis in remotion/audio.py | Original generated audio; CC0 dedication to extent rights exist; no samples, no stock music |
| UI reconstruction, demo copy and animation | Original Remotion composition, with factual dimensions/strings from prior source review | Original demo composition; repository original code/docs are MIT (copyright Dylan Petzko), but no game assets covered by that license |
| Brand palette | Factual hex values from repository banner-render script | Values only; original banner not reproduced |

Repo LICENSE and THIRD_PARTY.md retained in public/repo/. They explicitly exclude Blizzard artwork/audio from the original code/docs MIT grant. Sound-pack upstream manifests' CC BY-NC 4.0 statements do not transfer Blizzard's underlying rights. Dylan's OK is scoped to this demo, not a general redistribution/commercial-use license. Versions 1–4 used no Peon portrait, app icon, banner, screenshots, game footage, or other Blizzard visuals beyond the approved menu glyph. Version 5 adds the explicitly approved portrait below.

## Audio and VO
No Kokoro narrator used (optional). The four actual event recordings are synchronized to their toast entrances; they are character event sounds, not a narrator. On-screen event captions remain on. Original music ducks approximately 10 dB around each recording, with short attack/release ramps. Audio is mastered with two-pass ffmpeg loudnorm (-14 LUFS, -1.5 dBTP, LRA 7 target), followed by measured loudness correction with oversampled peak limiting where required; final AAC is separately verified with ebur128. See QA.json and QA.md for measured output.

## Reproduction
Dependencies declared in remotion/package.json. Remotion 4.0.541 Chromium Headless Shell, CPU rendering at native output dimensions; logical UI is exactly 2x scaled, not a low-resolution video upscale. Inter and JetBrains Mono loaded before frames. Build with `node render.cjs`, synthesize with `python3 audio.py`, finish with `python3 finish.py`.

## Retrieved asset SHA-256
- `Hmmm.wav`: `51d3de60bbb1973f291b7059dc1a8c0d44ff7f524d31881c4ab790c5a2922ef2`
- `JobsDone.wav`: `32dc9c5630967c5112ca7cd1b58c1ccdb04e5891d7bbb23c99d4b393f1fcb3b6`
- `LICENSE`: `b0b36316db5ffca69c65e000b34154bc17265cde57bd6494fb6976406b3d84f1`
- `MenuBarPeon.png`: `48cccc8cfc9ade751d3d1de154dddbce5bc54891a5050561205c6cd82c42f44f`
- `SomethingNeedDoing.wav`: `6ee4f9d9f9d2fede1f953a196de8875dba2ffefa0c5c732adad3de45bbaf090e`
- `THIRD_PARTY.md`: `fd917f1fdd053e80dd5786a8de5815564cd98c4a44b577664d84d44148d3f2b4`
- `WorkWork.wav`: `18669847b60fc5b1bb41327dc075412aeb2a823d5a9d84476ddc2960baffa959`

## Revision 2 audio / layout changes
All formats are now composed in native output pixels, with no scaled desktop canvas. Narrow versions use fully bounded centered toasts, mobile-ish PR layouts and a single-column Settings window. Main length is 43 seconds; Settings remains on screen from 28–36 seconds (8 seconds). Hero ends by crossfading from its install card back to the exact initial draft-PR scene over 11–11.9 seconds, rather than fading to an empty background.

Original event WAV files remain untouched. Derived playback templates trim only source leading silence, retaining a short lead-in. Original music now ducks 10 dB (rather than the earlier stronger duck); onset and same-interval RMS measurements are in AUDIO_QA.md and qa/audio-final-verification.json. No new artwork or audio sources were added.

Revision 4 changes only hero transition logic: sequential fade-out to background followed by opening-scene fade-in. No new assets, no audio changes; original permissions and licenses above remain unchanged.


## Version 5 — visual approval stills only

The new standalone `remotion/index-v5.jsx` recreates a full-bleed Mac desktop, fictional GitHub PR, moving cursor and full-width menu bar. It uses crash zooms and original procedural confetti around the shipped toast. No Apple logos or Blizzard footage. Dylan approved the v5 visual stills and selected Bloodlust. The final v5 videos, GIF and posters live in `out-v5/`; the original approval PNGs remain in `out-v5/stills/`. Old `out/` renders are preserved.

| Asset | Source | License / permission |
|---|---|---|
| Real Peon portrait GIF; static first-frame PNG | https://api.github.com/repos/petzkod5/JobsDone/contents/Resources/Peon.gif ; retrieved read-only through `gh api`, stored `remotion/public/v5/Peon.gif` and `PeonPortrait.png` | from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. Owner approval: “Use the peon portrait.” No Blizzard license grant asserted; not MIT/CC0. |
| GitHub mark SVG | https://github.com/primer/octicons/blob/main/icons/mark-github-16.svg | MIT, copyright GitHub, Inc.; license retained as `remotion/public/v5/Octicons-LICENSE`. GitHub trademarks remain their owners' property. Used only as an incidental element in the recreated GitHub browser UI. |
| Wallpaper | Original procedural low-contrast coastal-gradient/noise artwork, `remotion/public/v5/wallpaper.png` | Original generated demo artwork; CC0 dedication to extent rights exist. No stock photo/Apple wallpaper. |
| Cursor, click feedback, confetti, desktop/browser recreation | Original SVG/CSS/Remotion shapes in `remotion/index-v5.jsx` | Original demo artwork/animation; CC0 dedication to extent rights exist. Peon imagery excluded. |
| Inter / JetBrains Mono | Same font files listed above | SIL OFL 1.1; retained local licenses. |

Peon GIF SHA-256: `15383dd39b6e344a48bf4f95de8c9d05d3cff1610d439cb08a0534cd8b54925c`.

### Warcraft III music candidates — Bloodlust approved for v5

Dylan explicitly requested a real Warcraft III soundtrack bed, acknowledged takedown risk, and requested a specific-track approval before mixing. These are Blizzard copyright, used at Dylan's explicit request, takedown risk acknowledged. Public download availability is not a redistribution/synchronization license; no rights grant by the uploader or Blizzard is claimed. Intended future treatment: very low bed, further ducked beneath the approved event WAVs. The old synthesized bed is retired for v5, not mixed alongside these candidates.

Source collection: https://archive.org/details/warcraft-iii-ost . Track/faction cross-check: https://downloads.khinsider.com/game-soundtracks/album/warcraft-iii-reign-of-chaos-soundtrack . Full downloadable URLs, measured durations, sizes and SHA-256 are recorded in `music/CANDIDATES.json`.

- **Doomhammer’s Legacy (Orc)** — Tracy W. Bush. Local `music/doomhammer-legacy.mp3`. Tentative audition loop **00:32–01:04** (32s).
- **Bloodlust (Orc)** — Derek Duke. Local `music/bloodlust.mp3`. Tentative audition loop **00:24–00:56** (32s).

Loop windows are proposals, not claimed musically seamless; final listening, beat alignment and crossfade follow track approval. The initial candidate delivery contained no mixes. Dylan subsequently selected Bloodlust for the final v5 videos; Doomhammer’s Legacy is unused.

### v5 still QA

Regenerated and visually inspected all four 1920×1080 approval stills with Read after correcting the Create pull request cursor target, preserving the entire menu bar in the normal desktop view, and widening the confetti burst. Frames: 1.7s PR/cursor, 2.7s Work work crash zoom, 7.08s Job’s done confetti payoff, 9.6s minimal end card. The zoom stills deliberately crop the desktop to follow the toast, but keep the toast content and close/button fully visible. This paragraph describes the initial approval stills. Final production and measured QA are documented below.

Measured downloaded candidate details (ffprobe):
- Doomhammer’s Legacy (Orc): **314.567s**; 7,093,962 bytes. Direct source: https://archive.org/download/warcraft-iii-ost/09%20Tracy%20W.%20Bush%20-%20Doomhammer%27s%20Legacy.mp3
- Bloodlust (Orc): **312.816s**; 6,898,788 bytes. Direct source: https://archive.org/download/warcraft-iii-ost/06%20Derek%20Duke%20-%20Bloodlust.mp3


## Final v5 production

- **Selected music: Bloodlust (Orc), Derek Duke, Warcraft III OST, Blizzard Entertainment copyright.** Used at Dylan’s explicit request and specific track approval; takedown risk acknowledged. No synchronization/redistribution license from Blizzard is claimed. Source and full download hash remain in `music/CANDIDATES.json`.
- Loop uses strong transient boundaries at **00:24.750–00:36.750**, with a **120ms circular overlap** using the source continuation through 00:36.870. The 12s loop repeats three times in the main cut. Cut-level fades are 120ms at hero head/tail, 120ms in / 550ms out for main. Hero master endpoints are zero-valued; encoded AAC seam is measured separately.
- Music-only, unducked premaster bus measures **−28.0 LUFS** in both cuts. Music is ducked **9.0 dB** during every event WAV, with a short advance attack and 200ms release. Voice/SFX bus gain is solved independently so the quiet music is not indiscriminately raised with the voices.
- Additional hits, whooshes and scratch-like chirp are **original mathematical/noise synthesis**, no samples; source `remotion/audio-v5.py`, CC0 dedication to extent rights exist. The old synthesized musical bed is not used.
- No narrator/TTS. Only approved original WorkWork, JobsDone, Hmmm and SomethingNeedDoing event WAVs; leading silence trimmed in derived playback copies, source files unchanged.
- Native 1920×1080 / 1080×1080 / 1080×1920, 30fps. Realistic Mac-style desktop and GitHub-style demo UI, with original cursor, camera transforms, screen shake, toast stamp and procedural confetti. The square/portrait use follow-camera views of the same desktop rather than restacked cards. Portrait captions are placed at 66.5% height, safely above the bottom 20%, within horizontal 5–87% bounds.
- Hero 12s, main 36s. Main adds the fictional teammate’s “actually let’s use tabs” commit and “button is 1px off” issue. Text is fictional, no real GitHub action or user information. Every primary caption lasts at least 1.5s. Confetti is drawn behind the toast, preserving title, portrait and action-button legibility.
- Hero loop uses **sequential** end-card fade-out 11.05–11.40s, plain wallpaper 11.40–11.55s, opening-state fade-in 11.55–11.90s; the fully restored opening state holds through the seam. There are never two text scenes superimposed.
- H.264 yuv420p + AAC, faststart. Final integrated loudness, exact sizes, audio onsets, and frame checks are recorded in `out-v5/MANIFEST.json` and `qa/v5/`. All approved Blizzard assets remain outside the JobsDone original-code MIT grant.

Reproduce local media only: `node render-v5.cjs`; `python3 audio-v5.py`; `python3 finish-v5.py` in `remotion/`. No JobsDone repository checkout, branch, commit, push or publication was made.

Final QA outcome: all six MP4 files verified H.264/yuv420p + AAC with moov before mdat. AAC heroes measure −14.1 LUFS; mains −14.2 LUFS. The 256-color GIF is 960×540, 12.0s, 2.30 MB, with identical first/last frames; palette preserves both Peon portrait colors and bright original confetti. Camera-aware measured voice onsets precede the first visible slide-in toast by 40–75ms (all within 100ms); decoded AAC template correlation shows no added shift. See `out-v5/QA.md`. All 288 half-second sample frames were reviewed via Read contact sheets, plus critical full-size frames and 0.1s loop-transition samples.


## Version 6 — native meme edit (supersedes v5 direction)

- **Anton caption/end-card font:** https://github.com/google/fonts/tree/main/ofl/anton ; downloaded `Anton-Regular.ttf` as `remotion/public/fonts/Anton.ttf`. **SIL Open Font License 1.1, Copyright 2020 The Anton Project Authors**. Full license: `remotion/public/fonts/Anton-OFL.txt`; copied into `out-v6/licenses/`. Heavy ALL-CAPS captions use white fill, 8px black stroke (stroke paint order), hard black shadow. Measured H cap heights: 89px at 104px font size for 1080-tall files, 146px at 170px for 1920-tall portrait files. Caption wrapping is generated from actual font measurements in `caption-layout-v6.py` / JSON, rather than shrinking or clipping long text.
- v6 has independently laid-out native desktop/browser windows in each aspect ratio, full-frame menu bars, deterministic 3-frame ease-out crash zooms from 1× to 2.4×, 8-frame random decaying shake, hard cuts back to native wide views, and original confetti simulated at 0.35× speed. No crossfades or opacity animations except the main end-card title fade. Optional white flash is not used.
- Original cursor, confetti, hits, scratch-like chirp and whooshes remain original generated artwork/audio (CC0 dedication to extent rights exist). No ripped meme sound effects. macOS/GitHub UI is a rendered recreation with fictional demo data, no Apple logos, no actual GitHub submissions.
- **Approved Blizzard-derived assets retained:** repo Peon menu glyph, repo Peon portrait (first frame), repo four event WAVs. From petzkod5/JobsDone repo, Blizzard-derived, used with Dylan's explicit OK for this demo. No other game artwork or footage.
- **Music:** approved Bloodlust (Derek Duke, Warcraft III OST), Blizzard copyright, used at Dylan’s explicit request; takedown risk acknowledged, no Blizzard synchronization license claimed. Same downloaded source/hash documented above. Source cue 24.750–36.750s is pitch-preservingly time-compressed with atempo=12/11 to an 11s loop (beat boundaries retained), with a 120ms circular overlap from the source continuation. Hero 11s; main 33s, three repeats. Unducked premaster bed approximately −28 LUFS; further 9dB duck beneath each event WAV. Brief cut-head/tail fades avoid audio discontinuities. Old synthesized music is not used.
- Inter and JetBrains Mono remain SIL OFL; incidental GitHub Octicons mark MIT; original wallpaper CC0. Corresponding font/Octicons license texts are bundled in `out-v6/licenses/`.

Reproduce the standalone local media project: `python3 caption-layout-v6.py`, `node render-v6.cjs`, `python3 audio-v6.py`, `python3 finish-v6.py`. Existing out/ and out-v5/ renders are retained. No JobsDone repo checkout or changes, pushes, uploads or publication.

Anton font SHA-256: `a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab`.

Final v6 delivery measurements: six MP4s measure **−14.1 LUFS** after AAC encoding. Unducked music premaster **−28.0 LUFS hero / −28.1 LUFS main**, with **9.0dB** event duck. Encoded event onsets land **4.542–9.979ms after the hard toast appearance**. Hero GIF: **11.0s, 960×540, 1,295,004 bytes**, identical first/last pixels. Every hero has pixel-identical source endpoints. See `QA-v6.md`, `out-v6/MANIFEST.json`, and `qa/v6/audio-final.json` for measurements and the completed frame-review checklist.

## Version 7 — merge-flow corrections; v6 meme style retained

- Same approved Peon portrait/menu glyph and four event WAVs: **from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan’s explicit OK for this demo**. Same selected **Bloodlust — Derek Duke, Warcraft III OST**, Blizzard copyright, used at Dylan’s explicit request, takedown risk acknowledged; no Blizzard synchronization/redistribution license is claimed. No new outside artwork or audio.
- Same original CC0-dedicated generated wallpaper, cursor/click graphics, shake, confetti, hits/whooshes/chirp; no ripped meme effects. No narrator/TTS; no synthesized music bed. Fonts Anton / Inter / JetBrains Mono remain SIL OFL, incidental Octicons mark MIT; full texts copied into out-v7/licenses/.
- Cursor now visibly travels to Confirm merge over **10 eased frames**, with an explicit click ring. Purple Merged badge and merged-commit timeline precede the Job’s done toast by **0.70s hero / 1.90s main**. Native social-format wide windows retain visible left/right edges. Hero starts/ends on the same calm compare page with cursor parked; source endpoints have mean pixel difference **0.000**.
- End-card install command is now Anton on a high-contrast dark rounded pill: **94px wide / 52px square / 76px portrait**; single line wide/square, deliberate two lines in portrait. The measured cap height is approximately **1.9–2.8×** that of the old small JetBrains Mono command. Caption typography and timing, crash zoom/shake, slow confetti and 0.60s deadpan hold are otherwise retained.
- Final v7 loudness: all MP4s **−14.1 LUFS**; unducked Bloodlust bed **−28.0 hero / −28.1 main LUFS**, ducked **9.0dB** further under voices. Original event onsets remain **4.542–9.979ms** after toast appearance. Hero 11s, main 33s. Hero GIF **1,300,989 bytes**, 960×540, 11s, identical endpoint pixels.

Reproduce local media: `python3 caption-layout-v7.py`; `node render-v7.cjs`; `python3 audio-v7.py`; `python3 finish-v7.py`; `python3 check-v7.py` from remotion/. Output only in out-v7/, with QA-v7.md and qa/v7/ evidence. No repository changes, push, upload or publication; all earlier outputs retained.

## Version 8 — clean deadpan captions (supersedes v7 caption typography)

- **Anton is not used anywhere in v8**, including captions, GIF, posters or end cards. It remains only in archived v6/v7 sources/assets so those versions remain reproducible. V8 caption and end-card typography is **Inter**, SIL Open Font License 1.1; browser/code text retains **JetBrains Mono**, SIL OFL. Relevant font and Octicons/MIT license texts are bundled in out-v8/licenses/ (no unused Anton license). Font source paths/licenses remain listed above.
- Captions: sentence case, original joke wording, **Inter Semibold 44px in 16:9 and square / 64px portrait**, white on rgba(0,0,0,0.6), rounded translucent pill with 12px backdrop blur; no stroke, impact shadow, pop/bounce or caption opacity animations. Fixed centers at 74% frame height wide/square and 68% portrait. Sentence-case end card uses Inter too; install command remains high-contrast and single-line wide/square, deliberately two-line portrait.
- Tiny-fix beat is exactly **2.80–4.10s in both cuts**: enlarged, highlighted **“teh” → “the”** in the visible PR comment, with “You fixed one character.” shown only during that view, ending before Merge click. No new camera movement is introduced. “Something need doing?” is extended to **13.00–14.60s / 48 frames / 1.60s**.
- Same approved Peon portrait/menu glyph and repo WAVs: **from petzkod5/JobsDone repo, Blizzard-derived, used with Dylan’s explicit OK for this demo**. Same **Bloodlust, Derek Duke, Warcraft III OST**, Blizzard copyright, used at Dylan’s explicit request, takedown risk acknowledged. No Blizzard sync/redistribution license claimed. No new third-party artwork/audio or game footage. Original generated wallpaper/cursor/confetti/SFX retain their CC0 dedication.
- Audio masters are **bit-identical to v7**; approved soundtrack level, 9dB duck, event timings and −14 LUFS target retained. No narrator/TTS or synthesized musical bed.

V8 local reproduction from remotion/: `node render-v8.cjs`; `python3 audio-v8.py`; `python3 finish-v8.py`; `python3 check-v8.py`. Earlier outputs, especially out-v7/, are untouched. No JobsDone repository changes, pushes, uploads or publication. Detailed final checks: QA-v8.md and out-v8/MANIFEST.json.

Final v8 delivery: all six MP4s **−14.1 LUFS**, hero GIF **1,252,606 bytes**, exact matching GIF/source hero endpoints. Verified clean caption layout and tiny-fix timing in all formats; see QA-v8.md.
