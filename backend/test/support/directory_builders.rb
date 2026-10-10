# Small builders for directory records in tests. Records are verified unless
# told otherwise, since the public pages only show verified facts.
module DirectoryBuilders
  def role(key, parent: nil) = Role.create!(key:, name: key.to_s.humanize, parent:)
  def technology(key, name = key.to_s.humanize, parent: nil) = Technology.create!(key:, name:, parent:)

  def company(name, state: nil, city: nil, roles: [], techs: [], aliases: [], verified: true, **attributes)
    org = Organization.create!(name:, hq_state: state, hq_city: city, verification_status: verified ? "verified" : "pending", **attributes)
    ([ name ] + aliases).uniq { |alias_name| OrganizationAlias.normalize(alias_name) }
      .each { |alias_name| org.aliases.create!(alias: alias_name) }
    roles.each { |r| OrganizationRole.create!(organization: org, role: r, verification_status: "verified") }
    techs.each { |t| OrganizationTechnology.create!(organization: org, technology: t, verification_status: "verified") }
    org
  end

  def plant(name, verified: true, **attributes)
    Facility.create!(name:, verification_status: verified ? "verified" : "pending", **attributes)
  end

  def link(from, type, to, verified: true)
    status = verified ? "verified" : "pending"
    if to.is_a?(Facility)
      FacilityRelationship.create!(organization: from, facility: to, relationship_type: type, verification_status: status)
    else
      Relationship.create!(from_organization: from, to_organization: to, relationship_type: type, verification_status: status)
    end
  end
end
