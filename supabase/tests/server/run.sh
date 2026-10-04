#!/bin/sh
# Unit tests for the edge functions' shared modules (SSRF guard, HTML text, YouTube, Apple client secret).
# Usage: sh supabase/tests/server/run.sh   (needs node and npx)
set -e
cd "$(dirname "$0")"
mkdir -p build
for m in net apple youtube models subscriptions intent deck es256 pushText push devicecheck referrals plan; do
  npx --yes esbuild@0.24.0 ../../functions/_shared/$m.ts --bundle --format=esm --platform=node --outfile=build/$m.mjs --log-level=warning
done
node test.mjs
