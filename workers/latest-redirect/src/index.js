/**
 * Cloudflare Worker: latest-redirect
 *
 * Intercepts requests to /xiboplayer-kiosk/latest/<filename> and
 * returns a 302 redirect to the versioned path, reading the current
 * version from the LATEST file in the R2 bucket.
 *
 * Zero R2 storage overhead — no file duplication, just a redirect.
 * The LATEST file is already written by build-iso.yml on every
 * release tag push.
 *
 * URL transformation:
 *   /xiboplayer-kiosk/latest/xiboplayer-kiosk-netinstall_x86_64.iso
 *   → 302 → /xiboplayer-kiosk/0.4.35/xiboplayer-kiosk-netinstall_0.4.35_x86_64.iso
 *
 * The version string is injected before the architecture suffix
 * (_x86_64 or _aarch64) in the filename. Files without an arch
 * suffix (e.g. SHA256SUMS) redirect as-is.
 *
 * Caching: the LATEST file read is cached in-memory for 60s so
 * concurrent requests don't each hit R2. At 302-redirect time,
 * Cloudflare's CDN cache handles the actual file delivery with
 * its normal cache rules.
 */

// In-memory cache for the LATEST version string. Avoids hitting R2
// on every request. Workers have ~128 MB memory and persist across
// requests within the same isolate (~30s–5min lifetime).
let cachedVersion = null;
let cachedAt = 0;
const CACHE_TTL_MS = 60_000; // 60 seconds

/**
 * Read the current version from the LATEST file in the R2 bucket.
 * Returns the trimmed version string (e.g. "0.4.35") or null.
 */
async function getLatestVersion(bucket) {
  const now = Date.now();
  if (cachedVersion && (now - cachedAt) < CACHE_TTL_MS) {
    return cachedVersion;
  }

  const obj = await bucket.get('xiboplayer-kiosk/LATEST');
  if (!obj) return null;

  cachedVersion = (await obj.text()).trim();
  cachedAt = now;
  return cachedVersion;
}

/**
 * Transform a version-less filename into a versioned one.
 *
 * Input:  "xiboplayer-kiosk-netinstall_x86_64.iso", version "0.4.35"
 * Output: "xiboplayer-kiosk-netinstall_0.4.35_x86_64.iso"
 *
 * Pattern: insert _<version> before _(x86_64|aarch64).
 * If no arch suffix is found (e.g. "SHA256SUMS"), return as-is.
 */
function versionizeFilename(filename, version) {
  const archMatch = filename.match(/^(.+?)_(x86_64|aarch64)(\..+)$/);
  if (archMatch) {
    return `${archMatch[1]}_${version}_${archMatch[2]}${archMatch[3]}`;
  }
  // No arch suffix — return unchanged (SHA256SUMS, etc.)
  return filename;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Only intercept /xiboplayer-kiosk/latest/<something>
    const match = url.pathname.match(
      /^\/xiboplayer-kiosk\/latest\/(.+)$/
    );
    if (!match) {
      // Not a /latest/ request — passthrough to R2 origin
      return fetch(request);
    }

    const requestedFilename = match[1];

    // Read current version from R2
    const version = await getLatestVersion(env.IMAGES_BUCKET);
    if (!version) {
      return new Response(
        'LATEST version file not found in R2 bucket.\n' +
        'Has a release been published via build-iso.yml?\n',
        { status: 404, headers: { 'Content-Type': 'text/plain' } }
      );
    }

    // Build the versioned target URL
    const versionedFilename = versionizeFilename(requestedFilename, version);
    const target = `${url.origin}/xiboplayer-kiosk/${version}/${versionedFilename}`;

    // 302 Found — temporary redirect so the URL always re-checks
    // LATEST on the next request (vs 301 which browsers cache
    // permanently and would serve stale versions).
    return Response.redirect(target, 302);
  },
};
