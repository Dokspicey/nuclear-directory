# The open PR that holds the preview slot, other than $pr (the one asking),
# from the REST API's open issues labelled "preview" (PRs are issues there).
# Prints its number, or nothing when the slot is free: a PR frees it by
# merging, closing or losing the label (#328).
[.[] | select(.pull_request and .state == "open" and .number != $pr
  and any(.labels[]; .name == "preview"))] | sort_by(.number) | first | .number // empty
