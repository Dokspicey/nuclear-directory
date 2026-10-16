# The admin's Live list (#201): every record of a tab, narrowed by a search
# and by Directory::Checks tags, with each tag's count for what's shown.
# Status is one choice (Live by default); within the other groups chips are
# OR, and groups combine with AND. A chip's count is what the list would
# show with it added, given everything chosen in the other groups.
#
#   list = Directory::LiveList.new(tab: "plants", query: "vogtle", chosen: { "flags" => [ "single-source" ] })
#   list.total            # => 3
#   list.page(1)          # => [Directory::LiveList::Row, …]
#   list.count("no-owner") # => 2
class Directory::LiveList
  # What each tab lists: per model, a relation of its records.
  TABS = {
    "all" => -> { { "Organization" => Organization.all, "Facility" => Facility.where(parent_id: nil) } },
    "companies" => -> { { "Organization" => Organization.all } },
    "plants" => -> { { "Facility" => Facility.where(parent_id: nil) } },
    "reactors" => -> { { "Facility" => Facility.where.not(nrc_docket: nil) } },
    "links" => -> { { "Relationship" => Relationship.all, "FacilityRelationship" => FacilityRelationship.all } }
  }.freeze
  TAB_LABELS = { "all" => "All", "companies" => "Companies", "plants" => "Plants", "reactors" => "Reactors", "links" => "Links" }.freeze
  DEFAULT_STATUS = "live"
  PAGE = 50

  # One record in the list. flags: labels of its flags and gaps, most urgent first.
  Row = Data.define(:type, :id, :name, :kind, :status, :flags, :changed_at)

  attr_reader :tab, :query, :chosen

  def initialize(tab: "all", query: nil, chosen: {})
    @tab = TABS.key?(tab) ? tab : "all"
    @query = query.to_s.strip.presence
    @chosen = Directory::Checks::GROUPS.keys.to_h do |group|
      keys = Array(chosen[group]).map(&:to_s) & Directory::Checks.in_group(group).map(&:key)
      [ group, Directory::Checks::SINGLE.include?(group) ? keys.first(1) : keys ]
    end
    @chosen["status"] = [ DEFAULT_STATUS ] if @chosen["status"].empty?
  end

  def total = keys.size

  # This tab's records with the chosen status only (its count on the tab).
  def self.tab_count(tab, status: DEFAULT_STATUS) = new(tab:, chosen: { "status" => [ status ] }).total

  # [type, id] of every record shown, in order (newest change first).
  def keys
    @keys ||= begin
      matching = filtered(nil)
      ordered = matching.flat_map do |type, ids|
        type.constantize.where(id: ids.to_a).pluck(:id, :updated_at).map { |id, at| [ type, id, at ] }
      end
      ordered.sort_by { |type, id, at| [ -at.to_f, type, id ] }.map { |type, id, _| [ type, id ] }
    end
  end

  def page(number)
    slice = keys.drop((number - 1) * PAGE).first(PAGE)
    rows_for(slice)
  end

  # How many records the list would show with this tag chosen as well.
  def count(key)
    tag = Directory::Checks.find(key) or return 0
    filtered(tag.group).sum { |type, ids| (ids & tag_ids(tag, type)).size }
  end

  # Where a record sits in the list, for Previous and Next on its page.
  def neighbours(type, id)
    index = keys.index([ type, id ]) or return
    { index: index + 1, total: keys.size, previous: (keys[index - 1] if index.positive?), next: keys[index + 1] }
  end

  def chosen?(key) = chosen.values.flatten.include?(key)
  def filtered? = chosen.any? { |group, keys| group == "status" ? keys != [ DEFAULT_STATUS ] : keys.any? }

  private
    # Each model's ids in this tab and search.
    def base
      @base ||= TABS.fetch(tab).call.to_h { |type, scope| [ type, search(type, scope).pluck(:id).to_set ] }
    end

    # The base, narrowed by every chosen group except one (nil: all of them).
    def filtered(except_group)
      base.to_h do |type, ids|
        narrowed = chosen.reduce(ids) do |set, (group, keys)|
          next set if group == except_group || keys.empty?

          set & keys.map { |key| tag_ids(Directory::Checks.find(key), type) }.reduce(:|)
        end
        [ type, narrowed ]
      end
    end

    def tag_ids(tag, type)
      @tag_ids ||= {}
      @tag_ids[[ tag.key, type ]] ||= tag.ids(type.constantize).to_set
    end

    def search(type, scope)
      return scope unless query

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      case type
      when "Organization" then scope.where("organizations.name ILIKE ?", pattern)
      when "Facility" then scope.where("facilities.name ILIKE ?", pattern)
      when "Relationship"
        names = Organization.where("name ILIKE ?", pattern).select(:id)
        scope.where(from_organization_id: names).or(scope.where(to_organization_id: names))
      when "FacilityRelationship"
        scope.where(organization_id: Organization.where("name ILIKE ?", pattern).select(:id))
          .or(scope.where(facility_id: Facility.where("name ILIKE ?", pattern).select(:id)))
      end
    end

    FLAGGING = %w[flags gaps].freeze

    def rows_for(slice)
      records = slice.group_by(&:first).to_h do |type, pairs|
        model = type.constantize
        scope = model.where(id: pairs.map(&:last))
        scope = scope.includes(:from_organization, :to_organization) if model == Relationship
        scope = scope.includes(:organization, :facility) if model == FacilityRelationship
        [ type, scope.index_by(&:id) ]
      end
      flag_tags = FLAGGING.flat_map { |group| Directory::Checks.in_group(group) }
      slice.filter_map do |type, id|
        record = records.dig(type, id) or next
        flags = flag_tags.select { |tag| tag.applies_to?(type.constantize) && tag_ids(tag, type).include?(id) }.map(&:label)
        Row.new(type:, id:, name: name_of(record), kind: kind_of(record), status: status_of(type, record), flags:, changed_at: record.updated_at)
      end
    end

    def name_of(record)
      case record
      when Relationship then "#{record.from_organization.name} #{verb(record.relationship_type)} #{record.to_organization.name}"
      when FacilityRelationship then "#{record.organization.name} #{verb(record.relationship_type)} #{record.facility.name}"
      else record.name
      end
    end

    def verb(type) = DataQuality::Claim::RELATIONSHIP_VERBS.fetch(type.to_s, type.to_s.humanize(capitalize: false))

    def kind_of(record)
      case record
      when Organization then "Company"
      when Facility then record.parent_id.nil? && tab != "reactors" ? "Plant" : "Reactor"
      when Relationship then "Deal"
      else "Plant link"
      end
    end

    # The record's status in a word, "Live" unless otherwise.
    def status_of(type, record)
      return "Live" if tag_ids(Directory::Checks.find("live"), type).include?(record.id)
      return "Removed · merged" if tag_ids(Directory::Checks.find("merged"), type).include?(record.id)

      { "verified" => "Hidden", "pending" => "Pending", "rejected" => "Rejected", "unpublished" => "Removed" }.fetch(record.verification_status)
    end
end
