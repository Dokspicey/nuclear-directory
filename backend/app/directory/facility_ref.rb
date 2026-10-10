# What Directory::Lookup returns for a facility: plain values, not a model.
Directory::FacilityRef = Data.define(:id, :slug, :name, :nrc_docket, :parent_id, :verification_status,
  :facility_type, :status, :state, :country_code, :latitude, :longitude) do
  def self.from(facility)
    new(**facility.slice(*members).symbolize_keys)
  end
end
