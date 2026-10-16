# Analytics relay and country

The browser's PostHog traffic goes through `/relay/*` on this site (#205,
`RelayController`), so blockers don't drop it. On the way, each event gets the
visitor's country, looked up on our server from the request's IP with DB-IP's
"IP to Country Lite" (CC BY 4.0, credited on /privacy). PostHog's own lookup
can't do this in cookieless mode, since PostHog drops the IP first (PostHog
#48660). The IP is never put into an event. It's passed to PostHog only in
`X-Forwarded-For`, because cookieless mode counts unique visitors from a
daily hash of IP and browser. The country file is downloaded when the image is
built (`backend/Dockerfile`, into `vendor/geo`), so each deploy has the newest
one. Our own visits are marked `internal: true`: from a browser that has
signed in to the admin (a signed `nd_internal` cookie, set at sign-in and
kept after signing out, for a year; visitors never get it), or from
`INTERNAL_IPS`, an optional backup since a home IP changes. Set PostHog's
"Filter out internal and test users" to exclude `internal = true`, and sign
in to the admin once on each device you browse the site with.
