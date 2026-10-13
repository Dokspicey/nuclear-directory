# The newest published backup's tag, from `gh release list --json tagName,isDraft`.
# Sorted by tag name: backup-YYYY-MM-DDTHHMMZ sorts by time as text. GitHub's
# release createdAt/created_at is the tagged commit's date, the same for every
# backup, so it can't order them.
[.[] | select((.isDraft | not) and (.tagName | startswith("backup-")))] | sort_by(.tagName) | last | .tagName // empty
