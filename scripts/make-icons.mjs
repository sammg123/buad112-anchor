/** Writes the Home Screen icons into public/. Run: node scripts/make-icons.mjs */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { appIcon } from '../src/phone.js';

const publicDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');
for (const size of [180, 192, 512]) fs.writeFileSync(path.join(publicDir, `icon-${size}.png`), appIcon(size));
