# app/directory holds the Directory:: interfaces (Lookup, FactWriter), the
# only public way into directory data. Mapping the folder to the namespace
# keeps the boundary visible in the file tree: app/directory/lookup.rb is
# Directory::Lookup. See app/directory/README.md.
module Directory; end
Rails.autoloaders.main.push_dir(Rails.root.join("app/directory"), namespace: Directory)
