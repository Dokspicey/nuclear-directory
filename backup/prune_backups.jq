# Published backups to delete, oldest first (so a failure partway through never
# leaves an older backup behind a deleted newer one), keeping the newest $keep, from the
# REST API's release list. Prints "<id> <tag>" per line. Sorted by tag name
# (backup-YYYY-MM-DDTHHMMZ): created_at is the tagged commit's date, the same
# for every backup.
[.[] | select((.draft | not) and (.tag_name | startswith("backup-")))] | sort_by(.tag_name) | reverse | .[$keep:] | reverse | .[] | "\(.id) \(.tag_name)"
