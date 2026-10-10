// Anonymous page views through PostHog (#66). The layout adds the
// posthog-key / posthog-host meta tags only on public pages, for people (not
// bots), and only when analytics is configured; see TracksAnalytics.
//
// Cookieless and anonymous: nothing is stored in the browser, nobody is
// identified, no session replay, no surveys. The library loads when the
// browser is idle, so it never slows a page down.
const meta = (name) => document.querySelector(`meta[name="${name}"]`)?.content

function start(key, host) {
  import("posthog-js").then(({ default: posthog }) => {
    posthog.init(key, {
      api_host: host,
      cookieless_mode: "always",
      persistence: "memory",
      person_profiles: "never",
      capture_pageview: "history_change", // counts Turbo navigations too
      disable_session_recording: true,
      disable_surveys: true,
      // A Turbo visit can reach /design from a public page; never count it.
      before_send: (event) => (event?.properties?.$pathname?.startsWith("/design") ? null : event),
    })
  })
}

const key = meta("posthog-key")
const host = meta("posthog-host")
if (key && host && !window.posthogStarted) {
  window.posthogStarted = true
  const begin = () => start(key, host)
  "requestIdleCallback" in window ? requestIdleCallback(begin) : setTimeout(begin, 1)
}
