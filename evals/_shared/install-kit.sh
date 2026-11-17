#!/usr/bin/env bash
# Builds the eval workspace in $PWD: a one-route Express repo with the real
# installer run over it. The eval runner starts with an empty dir and loads none
# of the kit's own .claude/ (spike #32), so init.sh has to put it all in place.
set -euo pipefail

KIT="$(cd "$(dirname "$0")/../.." && pwd)"

git init -q
# CI runners have no git identity or signing key.
git config user.email eval@example.com
git config user.name eval
git config commit.gpgsign false

mkdir -p src
cat > package.json <<'JSON'
{
  "name": "eval-app",
  "dependencies": { "express": "^4.21.0" }
}
JSON
cat > src/server.js <<'JS'
const express = require('express');
const app = express();
app.get('/api/v2/user-profiles', (req, res) => res.json([]));
app.listen(3000);
JS

bash "$KIT/init.sh" </dev/null

# perl, not sed -i: BSD and GNU disagree on its argument.
perl -0pi -e 's|(## Naming\n)_Not yet defined\._|$1- API routes: kebab-case plural nouns under a version prefix, e.g. `/api/v2/user-profiles`.|' \
  _working-memory/conventions.md
