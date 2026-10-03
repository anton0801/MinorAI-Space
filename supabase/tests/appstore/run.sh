#!/bin/sh
# Generates a throwaway Apple-like certificate chain and runs the JWS verifier tests.
# Usage: sh supabase/tests/appstore/run.sh   (needs openssl, node, npx)
set -e
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
openssl ecparam -name secp384r1 -genkey -noout -out root.key
openssl req -new -x509 -key root.key -sha384 -days 3650 -subj "/CN=Test Root" -out root.pem
openssl ecparam -name secp384r1 -genkey -noout -out int.key
openssl req -new -key int.key -subj "/CN=Test Intermediate" -out int.csr
openssl x509 -req -in int.csr -CA root.pem -CAkey root.key -CAcreateserial -sha384 -days 3000 -extfile ext.cnf -extensions v3_int -out int.pem
openssl ecparam -name prime256v1 -genkey -noout -out leaf.key
openssl req -new -key leaf.key -subj "/CN=Test Leaf" -out leaf.csr
openssl x509 -req -in leaf.csr -CA int.pem -CAkey int.key -CAcreateserial -sha256 -days 1000 -extfile ext.cnf -extensions v3_leaf -out leaf.pem
openssl x509 -req -in leaf.csr -CA int.pem -CAkey int.key -CAcreateserial -sha256 -days 1000 -extfile ext.cnf -extensions v3_leaf_nomarker -out leaf_nomarker.pem
for c in root int leaf leaf_nomarker; do openssl x509 -in $c.pem -outform der -out $c.der; done
openssl pkcs8 -topk8 -nocrypt -in leaf.key -out leaf.p8
npx --yes esbuild@0.24.0 ../../functions/_shared/appstore.ts --format=esm --platform=node --outfile=build/appstore.mjs --log-level=warning
node test.mjs
rm -f *.key *.pem *.csr *.srl *.der *.p8
