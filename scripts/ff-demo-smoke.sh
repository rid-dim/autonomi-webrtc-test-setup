#!/bin/bash
# Firefox smoke test for the public demo via raw WebDriver (needs: brew install geckodriver).
# Loads the page, waits for the auto-loaded figure, clicks a gallery item, screenshots to /tmp/ff_demo.png.
set -e
GD_PORT=4447
geckodriver --port $GD_PORT > /tmp/geckodriver.log 2>&1 &
GD_PID=$!
trap 'curl -s -X DELETE http://127.0.0.1:$GD_PORT/session/$SID >/dev/null 2>&1; kill $GD_PID 2>/dev/null' EXIT
sleep 1.5
SID=$(curl -s -X POST http://127.0.0.1:$GD_PORT/session -H 'Content-Type: application/json' -d '{"capabilities":{"alwaysMatch":{"browserName":"firefox","moz:firefoxOptions":{"args":[]}}}}' | python3 -c "import json,sys;print(json.load(sys.stdin)['value']['sessionId'])")
echo "session: $SID"
curl -s -X POST http://127.0.0.1:$GD_PORT/session/$SID/url -H 'Content-Type: application/json' -d '{"url":"https://webrtc-demo.autonomi.space"}' >/dev/null
# poll the app log + gallery/figure state for up to 40s
for i in $(seq 1 20); do
  sleep 2
  STATE=$(curl -s -X POST http://127.0.0.1:$GD_PORT/session/$SID/execute/sync -H 'Content-Type: application/json' -d '{"script":"const log=(document.getElementById(\"log\")||{}).textContent||\"\";const fig=document.querySelector(\"#figure-box img\");const bg=getComputedStyle(document.getElementById(\"bg\")||document.body).opacity;return JSON.stringify({figLoaded:!!fig,logTail:log.slice(-200)});","args":[]}' | python3 -c "import json,sys;print(json.load(sys.stdin)['value'])")
  echo "[$((i*2))s] $STATE"
  echo "$STATE" | grep -q '"figLoaded":true' && break
done
# click the first gallery Load button (earthrise = 2nd card) and wait for netloaded card
curl -s -X POST http://127.0.0.1:$GD_PORT/session/$SID/execute/sync -H 'Content-Type: application/json' -d '{"script":"const btns=[...document.querySelectorAll(\"#gallery button\")];if(btns[1])btns[1].click();return btns.length;","args":[]}' >/dev/null
for i in $(seq 1 20); do
  sleep 2
  R=$(curl -s -X POST http://127.0.0.1:$GD_PORT/session/$SID/execute/sync -H 'Content-Type: application/json' -d '{"script":"const cards=[...document.querySelectorAll(\".netloaded\")];const imgs=[...document.querySelectorAll(\"#gallery img\")];const log=(document.getElementById(\"log\")||{}).textContent||\"\";return JSON.stringify({netloaded:cards.length,galleryImgs:imgs.length,logTail:log.slice(-160)});","args":[]}')
  V=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin)['value'])")
  echo "[gallery $((i*2))s] $V"
  echo "$V" | grep -q '"galleryImgs":1' && { echo FIREFOX_GALLERY_OK; break; }
done
# screenshot
curl -s http://127.0.0.1:$GD_PORT/session/$SID/screenshot | python3 -c "import json,sys,base64;open('/tmp/ff_demo.png','wb').write(base64.b64decode(json.load(sys.stdin)['value']))"
echo "screenshot: /tmp/ff_demo.png"
