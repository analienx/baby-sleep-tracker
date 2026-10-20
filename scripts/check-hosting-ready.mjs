import {readFileSync} from 'node:fs';

// Hosting's public external-account-deletion flow MUST NOT be deployed with
// a placeholder App Check key: doing so would falsely advertise compliance.
const content = readFileSync(new URL('../hosting/config.js', import.meta.url), 'utf8');
const found = content.match(/appCheckSiteKey\s*=\s*['"]([^'"]+)['"]/);
const valid = found && !found[1].startsWith('SET_') && found[1].length >= 20;
if (!valid) {
  process.stderr.write('Configure the production Web App / reCAPTCHA Enterprise App Check site key in hosting/config.js before deploying Hosting.\n');
  process.exitCode = 1;
} else {
  process.stdout.write('Hosting App Check site-key configuration present. Verify registration and enforcement in Firebase Console.\n');
}
