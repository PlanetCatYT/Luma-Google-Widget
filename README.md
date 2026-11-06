# Luma-Google-Widget

PC-side helpers for the [Luma](https://github.com/PlanetCatYT/Luma) Fun tab — the Google widget
helper, plus a gif → sprite-sheet converter. Both are plain
Windows scripts — no install, no dependencies beyond what ships with Windows. Everything runs
locally; nothing is uploaded anywhere.

---

## 📺 Google Widget helper — `luma_google.bat`

The **Google Widget** (Luma → Fun → Widgets) shows a live view inside the game. This helper is a
tiny local server + a control page; the **page uses your browser's own "Choose what to share"
dialog** to capture a source and streams it to the widget. Because the browser does the capture, you
can share an **entire screen, a single window, or one browser tab** — including a single Chrome tab,
which an outside program can't grab on its own.

**Use it:**

1. Double-click **`luma_google.bat`**.
2. A control page opens at `http://127.0.0.1:8787/` — press **Start sharing**.
3. Your browser's picker appears — choose **Entire Screen**, **Window**, or **Chrome Tab**.
4. In Luma, go to **Fun → Widgets → Google Widget** and flip it on. The chosen source streams in.
5. Press **Stop sharing** (on the page or the bar your browser shows while sharing), or close the
   helper window, to stop.

**Notes:**

- Open the control page in a modern browser (Chrome, Edge, Firefox). It's served from
  `127.0.0.1`, a secure origin, so the share dialog is allowed.
- It only listens on `127.0.0.1` (loopback) — nothing leaves your machine. The helper never
  captures your screen itself; the browser does.
- Default port is `8787`. To use another, run `luma_google.bat 9000` and set the matching **Helper
  Port** in the widget's menu section.
- Frames are capped at ~15 fps and downscaled to 1280px wide so it stays light.
- If the widget keeps saying *"Waiting for the helper…"*, the server isn't running — launch the
  `.bat`. If it says *"press Start sharing"*, the server is up but you haven't picked a source yet —
  press Start on the control page.

---

## 🎞️ Gif → sprite-sheet converter — `luma_gif.bat`

Turns animated `.gif` files into the sprite-sheet format Luma's Sky Animation slots read
(`anim.png` + `anim.txt`).

**Use it:**

1. **Drag one or more `.gif` files onto `luma_gif.bat`.**
2. Each gif becomes a folder inside a new `Luma_sky` folder next to the script, e.g.
   `Luma_sky/myanim/` containing:
   - `anim.png` — every frame packed into one ≤1024×1024 grid.
   - `anim.txt` — one line: `cols rows frameCount fps cellW cellH`.
3. Copy the folders from `Luma_sky` into your executor's `workspace/Luma_sky/` folder.

The grid is chosen automatically to keep frames as large as possible inside 1024×1024, and the fps
is read from the gif's own frame delays.

---

## Safety

Windows may flag a freshly-downloaded `.bat`/`.ps1` ("Windows protected your PC" / blocked file).
The `.bat` files call `Unblock-File` on their own `.ps1` and run with `-ExecutionPolicy Bypass` for
that one process only — they don't change any system-wide setting. Read the scripts first if you
like; they're short and un-obfuscated.
