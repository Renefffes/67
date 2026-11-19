# StudyMate web

Independent, mobile-friendly offline study app. It does not change the repository’s Blank.finder app or `ios/`.

## Run

Node 22 or later:

```sh
cd studymate-web
npm ci
npm run build
npm start
```

Open http://localhost:4173. For development, `npm run dev`. `npm test` checks card extraction, choices, note retrieval and backup validation.

## Install and use offline

Host **the contents of `dist/`** on any ordinary HTTPS static host (root or subdirectory). No server API, account or API key. Open it online once and wait for Settings → “Ready for offline study”. Then disable Wi-Fi and reopen. Chrome’s install button/menu adds the app on Chromebook; Safari → Share → Add to Home Screen adds it on iOS. School device policies can block installation, model downloads or storage. Browser data is per-device; export/import JSON to move decks. Clearing site data removes decks, progress and model. Browser storage can be evicted, so keep backups.

**Devin previews/Apps block service workers.** They can demonstrate the interface but cannot install this offline app. `src/offline.ts` avoids registration there and labels this limitation. Real offline use needs normal HTTPS hosting. Service workers also do not work by double-clicking `index.html` (`file://`).

## Local AI

Optional **FLAN-T5 Small**, 77 million parameters, q8, Apache-2.0, via Transformers.js 3.7.2 and ONNX Runtime WASM. CPU-only, one thread, in a Web Worker; no GPU requirement and no cross-origin-isolation headers. Download/load explicitly in Settings while online. Pinned model revision: `Xenova/flan-t5-small@311454e83bc784267fd7eef5940ee854144abbec`.

Weights are approximately **95 MB** (encoder 35.8 MB + merged decoder 59.3 MB), plus tokenizer/config and runtime. Runtime ships in the app shell; model weights are stored in Transformers.js’s browser cache after successful load. Memory requirements exceed download size. Cached models can be loaded offline on supported browsers; verify this on the actual school Chromebook. There is no promise that every managed or low-memory Chromebook supports it. Stop & free AI memory terminates the worker; clearing site data deletes its cache.

This is a small English-first instruction model, not a general-purpose ChatGPT substitute. Tutor prompts use retrieved notes and show their source. Optional AI-assisted card creation drafts the first three questions individually, retaining answers from the notes and all remaining notes-based cards. The completion message reports how many questions AI drafted, or explicitly says notes-based cards were used if the model returned no usable questions. All cards are editable. The default **notes helper is not AI**: it extracts facts and relevant passages immediately without downloading a model. Generated answers can be wrong. No notes or questions are sent to a remote inference service; Hugging Face is contacted only to download model assets. No analytics or external fonts.

## Included

- Editable decks from pasted notes; starter biology, physics and language decks.
- Normal flip flashcards with still-learning / mastered state.
- Multiple-choice learn mode (no free typing).
- Three games: matching pairs, 60-second multiple-choice sprint, true/false.
- Notes-grounded tutor with optional real on-device AI.
- Local progress, search, export/restore, PWA manifest/icons, iOS home-screen metadata.
- Versioned, scoped service-worker cache with no interference outside this app’s deployment path.

### Deployment

`npm run build` produces a self-contained static folder (model weights downloaded separately). It can be dragged into an HTTPS static host. The pull request does not reconfigure the existing repository’s Pages site, domain or native iOS build. A Pages workflow, if desired, should build **only** this folder and publish `studymate-web/dist`; review/enable the Pages environment separately.
