# What the crawler needs to fetch politely and skip unchanged work:
# - etag / last_modified: sent back on the next fetch, so an unchanged page
#   costs the server a "304 Not Modified" instead of the full page
# - extracted_sha256: the content hash the extract stage last processed,
#   so unchanged content isn't extracted again
# - blocked_streak: consecutive blocked fetches; a long streak needs a human
class AddCrawlTrackingToSources < ActiveRecord::Migration[8.1]
  def change
    change_table :sources, bulk: true do |t|
      t.string :etag
      t.string :last_modified
      t.string :extracted_sha256
      t.integer :blocked_streak, null: false, default: 0
    end
  end
end
