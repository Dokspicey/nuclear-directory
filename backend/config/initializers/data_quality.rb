# The data quality workflow (crawl → extract → match → verify) is a
# self-contained module under app/data_quality. Files there define
# constants in the DataQuality namespace, e.g. app/data_quality/pipeline.rb
# is DataQuality::Pipeline. See app/data_quality/README.md.
module DataQuality; end

Rails.autoloaders.main.push_dir(Rails.root.join("app/data_quality"), namespace: DataQuality)
