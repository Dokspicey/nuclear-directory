# Public JSON snapshot

`GET /api/snapshot.json` (#193) is a small public summary for other sites:
the total, the eight categories with their counts, two example names and
page links, and the five most recently published entries. It's built from
published facts only, open to any origin, cached for 5 minutes in browsers
and an hour in shared caches, and served from the web process's memory. A
change made through the site (the admin, or the crawl, which runs in the same
process) clears it at once; a change from a console or another process shows
within 10 minutes, when the copy expires. In production its links always
point at `https://nuclear-directory.org` (or `PUBLIC_URL`, for a preview
deploy), never at the request's Host. Fields can be added but are never
renamed or removed. The counting rule (an entry can be in several
categories) and the shape are in `backend/app/models/directory_snapshot.rb`.
