# Pulls a human-readable title out of a fetched page: its <title>, or
# og:title when <title> is missing. Whitespace is tidied, entities decoded
# and very long titles cut. Non-HTML responses (PDF, text) have no title.
#
#   DataQuality::PageTitle.from(html, content_type: "text/html") # => "Kairos Power breaks ground…"
module DataQuality::PageTitle
  MAX_LENGTH = 300

  def self.from(body, content_type:)
    return unless html?(body, content_type)

    doc = Nokogiri::HTML(body)
    title = doc.at_css("head title, title")&.text.presence ||
      doc.at_css('meta[property="og:title"]')&.[]("content")
    title = title.to_s.squish
    title.truncate(MAX_LENGTH, separator: " ") if title.present?
  end

  def self.html?(body, content_type)
    return content_type.to_s.match?(%r{html}i) if content_type.present?

    body.to_s.lstrip.first(200).match?(/<(!doctype html|html|head|title)\b/i)
  end
  private_class_method :html?
end
