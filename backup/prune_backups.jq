# Published backups to delete, oldest first, keeping the newest $keep, from the
# REST API's release list. Prints "<id> <tag>" per line. Sorted by tag name
# (backup-YYYY-MM-DDTHHMMZ): created_at is the tagged commit's date, the same
# for every backup.
[.[] | select((.draft | not) and (.tag_name | startswith("backup-")))] | sort_by(.tag_name) | reverse | .[$keep:][] | "\(.id) \(.tag_name)"
