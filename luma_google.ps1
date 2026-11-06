# Luma Google-widget helper.
#
# Starts a tiny local web server on 127.0.0.1:<port> (default 8787). Open the page it prints and
# press "Start sharing" -- your browser's own "Choose what to share" dialog lets you pick an entire
# screen, a window, or a single browser tab. The page captures that source and streams JPEG frames
# to this helper, which relays them to the in-game Google widget.
#
# This helper never captures your screen itself -- the browser does, so the native picker (including
# single-tab capture) is exactly what Chrome/Edge give you. Nothing leaves your machine: the server
# only listens on loopback (127.0.0.1). Run luma_google.bat to launch it.
#
# Part of Luma-Google-Widget: https://github.com/PlanetCatYT/Luma-Google-Widget

param([int]$Port = 8787)

# ---- shared state -------------------------------------------------------------------------------
$script:seq      = 0
$script:lastJpeg = New-Object byte[] 0
$script:lastPush = 0           # TickCount of the most recent frame from the browser
$script:staleMs  = 3000        # if no frame for this long, report "not sharing" to the widget

# ---- http helpers -------------------------------------------------------------------------------
function Read-HttpRequest($stream) {
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    $headerEnd = -1
    while ($headerEnd -lt 0) {
        $n = $stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $ms.Write($buf, 0, $n)
        $arr = $ms.GetBuffer()
        $len = [int]$ms.Length
        for ($i = 0; $i -le $len - 4; $i++) {
            if ($arr[$i] -eq 13 -and $arr[$i + 1] -eq 10 -and $arr[$i + 2] -eq 13 -and $arr[$i + 3] -eq 10) {
                $headerEnd = $i; break
            }
        }
        if ($headerEnd -lt 0 -and $ms.Length -gt 262144) { break }
    }
    if ($headerEnd -lt 0) { return $null }

    $all = $ms.ToArray()
    $headerText = [System.Text.Encoding]::ASCII.GetString($all, 0, $headerEnd)
    $lines = $headerText -split "`r`n"
    $reqLine = $lines[0] -split ' '
    $method = $reqLine[0]
    $path = if ($reqLine.Count -ge 2) { $reqLine[1] } else { '/' }

    $contentLength = 0
    foreach ($h in $lines) {
        if ($h -match '^Content-Length:\s*(\d+)') { $contentLength = [int]$matches[1] }
    }

    $bodyStart = $headerEnd + 4
    $have = $all.Length - $bodyStart
    while ($have -lt $contentLength) {
        $n = $stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $ms.Write($buf, 0, $n)
        $have += $n
    }
    $all = $ms.ToArray()
    $body = New-Object byte[] $contentLength
    if ($contentLength -gt 0) {
        [System.Array]::Copy($all, $bodyStart, $body, 0, [math]::Min($contentLength, $all.Length - $bodyStart))
    }
    return @{ Method = $method; Path = $path; Body = $body }
}

function Send-Response {
    param($stream, [string]$status, [hashtable]$headers, [byte[]]$body)
    if ($null -eq $body) { $body = New-Object byte[] 0 }
    $head = "HTTP/1.1 $status`r`n"
    foreach ($k in $headers.Keys) { $head += "$k`: $($headers[$k])`r`n" }
    $head += "Content-Length: $($body.Length)`r`n"
    $head += "Connection: close`r`n`r`n"
    $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($headBytes, 0, $headBytes.Length)
    if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
    $stream.Flush()
}

function Send-Text {
    param($stream, [string]$status, [string]$contentType, [string]$text)
    Send-Response $stream $status @{ 'Content-Type' = $contentType; 'Access-Control-Allow-Origin' = '*' } ([System.Text.Encoding]::UTF8.GetBytes($text))
}

$pageHtml = @'
<!doctype html>
<html><head><meta charset="utf-8"><title>Luma - Google widget helper</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; font-family: Segoe UI, system-ui, sans-serif; background:#0f1016; color:#e9e9ee; }
  .wrap { max-width:560px; margin:48px auto; padding:0 20px; }
  h1 { font-size:20px; margin:0 0 4px; }
  p.sub { color:#9a9cad; margin:0 0 24px; }
  .card { background:#171822; border:1px solid #262838; border-radius:14px; padding:22px; }
  .status { display:flex; align-items:center; gap:12px; margin-bottom:20px; }
  .dot { width:10px; height:10px; border-radius:50%; background:#555; }
  .dot.on { background:#5cd67a; }
  #state { font-size:15px; }
  .opts { display:flex; gap:10px; }
  button { font:inherit; border:0; border-radius:10px; padding:11px 18px; cursor:pointer; color:#fff; }
  #start { background:#3a63ff; } #stop { background:#3a2c2c; }
  button:disabled { opacity:.45; cursor:default; }
  .hint { color:#8a8c9d; font-size:12.5px; margin-top:18px; line-height:1.55; }
  code { background:#0c0d13; padding:1px 6px; border-radius:6px; }
</style></head>
<body><div class="wrap">
  <h1>Luma - Google widget helper</h1>
  <p class="sub">Press start, then pick a screen, a window, or a single tab in your browser's dialog.</p>
  <div class="card">
    <div class="status"><div id="dot" class="dot"></div><div id="state">Not sharing</div></div>
    <div class="opts">
      <button id="start">Start sharing</button>
      <button id="stop" disabled>Stop sharing</button>
    </div>
    <div class="hint">
      <b>Start sharing</b> opens your browser's own picker (Entire Screen / Window / a single
      <b>Chrome Tab</b>) &mdash; the browser does the capture, so a single tab works here. Keep this
      page open, then flip <code>Google Widget</code> on in Luma's Fun &gt; Widgets page. You can also
      stop from the bar your browser shows while sharing.
    </div>
  </div>
</div>
<script>
  const $ = id => document.getElementById(id);
  const dot = $('dot'), state = $('state'), startBtn = $('start'), stopBtn = $('stop');
  const video = document.createElement('video');
  video.muted = true; video.playsInline = true;
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  const MAXW = 1280, FPS = 15;
  let stream = null, running = false;

  function paint(on, label) {
    dot.className = on ? 'dot on' : 'dot';
    state.textContent = on ? ('Sharing: ' + (label || 'source')) : 'Not sharing';
    startBtn.disabled = on; stopBtn.disabled = !on;
  }

  async function start() {
    try {
      stream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: FPS }, audio: false });
    } catch (e) { return; } // user cancelled the picker
    const track = stream.getVideoTracks()[0];
    const label = (track && track.label) ? track.label : 'source';
    track.addEventListener('ended', stop);
    video.srcObject = stream;
    try { await video.play(); } catch (e) {}
    running = true; paint(true, label);
    pump();
  }

  async function pump() {
    while (running) {
      const t0 = performance.now();
      const vw = video.videoWidth, vh = video.videoHeight;
      if (vw && vh) {
        const scale = Math.min(1, MAXW / vw);
        canvas.width = Math.round(vw * scale);
        canvas.height = Math.round(vh * scale);
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const blob = await new Promise(res => canvas.toBlob(res, 'image/jpeg', 0.7));
        if (blob) { try { await fetch('/push', { method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: blob }); } catch (e) {} }
      }
      const dt = performance.now() - t0;
      await new Promise(r => setTimeout(r, Math.max(0, 1000 / FPS - dt)));
    }
  }

  function stop() {
    running = false; paint(false);
    if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null; }
    fetch('/stop').catch(() => {});
  }

  startBtn.onclick = start;
  stopBtn.onclick = stop;
</script>
</body></html>
'@

# ---- server -------------------------------------------------------------------------------------
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
} catch {
    Write-Host "Could not bind to port $Port. Is another copy already running? ($($_.Exception.Message))"
    exit 1
}

Write-Host ""
Write-Host "  Luma Google-widget helper is running."
Write-Host "  Control page:  http://127.0.0.1:$Port/"
Write-Host ""
Write-Host "  1. The control page should open in your browser (open it manually if not)."
Write-Host "  2. Press 'Start sharing' and pick a screen / window / tab in the browser dialog."
Write-Host "  3. In Luma: Fun > Widgets > Google Widget -> on."
Write-Host ""
Write-Host "  Leave this window open while you use the widget. Close it to stop."
Write-Host ""

try { Start-Process "http://127.0.0.1:$Port/" } catch {}

while ($true) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
        $client.NoDelay = $true
        $stream = $client.GetStream()

        $req = Read-HttpRequest $stream
        if (-not $req) { continue }
        $path = $req.Path

        if ($path -like '/frame*') {
            $now = [Environment]::TickCount
            $fresh = $script:lastJpeg.Length -gt 0 -and ($now - $script:lastPush) -lt $script:staleMs
            if (-not $fresh) {
                Send-Response $stream "200 OK" @{ 'x-seq' = '0'; 'Content-Type' = 'text/plain'; 'Access-Control-Allow-Origin' = '*' } (New-Object byte[] 0)
            } else {
                Send-Response $stream "200 OK" @{ 'x-seq' = "$($script:seq)"; 'Content-Type' = 'image/jpeg'; 'Access-Control-Allow-Origin' = '*' } $script:lastJpeg
            }
        }
        elseif ($path -like '/push*') {
            if ($req.Body -and $req.Body.Length -gt 0) {
                $script:lastJpeg = $req.Body
                $script:seq++
                $script:lastPush = [Environment]::TickCount
            }
            Send-Text $stream "200 OK" "text/plain" "ok"
        }
        elseif ($path -like '/stop*') {
            $script:lastJpeg = New-Object byte[] 0
            $script:seq = 0
            $script:lastPush = 0
            Send-Text $stream "200 OK" "text/plain" "ok"
        }
        elseif ($path -like '/status*') {
            $now = [Environment]::TickCount
            $fresh = $script:lastJpeg.Length -gt 0 -and ($now - $script:lastPush) -lt $script:staleMs
            $json = if ($fresh) { '{"sharing":true}' } else { '{"sharing":false}' }
            Send-Text $stream "200 OK" "application/json" $json
        }
        else {
            Send-Text $stream "200 OK" "text/html; charset=utf-8" $pageHtml
        }
    } catch {
        # one bad/closed connection should never take the server down
    } finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}
