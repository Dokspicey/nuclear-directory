# Who holds the preview slot (#328), from the open PRs that have the
# "preview" label, each with when it was last labelled:
#   [{"number": 305, "labeled_at": "2026-10-17T02:04:59Z"}, ...]
# The holder is the one labelled first (ties: the lower number), so a
# newcomer whose label hasn't been taken off yet never displaces it. Prints
# the holder's number if it isn't $pr (the PR asking), else nothing: $pr may
# deploy. The slot frees when the holder merges, closes or loses the label.
(sort_by(.labeled_at, .number) | first | .number) as $holder
| if $holder == null or $holder == $pr then empty else $holder end
