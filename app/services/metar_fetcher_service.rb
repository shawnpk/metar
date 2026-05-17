require "net/http"
require "uri"

class MetarFetcherService
  NotFoundError = Class.new(StandardError)
  FetchError    = Class.new(StandardError)

  BASE_URL = "https://aviationweather.gov/api/data/metar"

  def self.fetch(airport_code)
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(ids: airport_code)

    response = Net::HTTP.get_response(uri)

    raise FetchError, "API returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s.strip
    raise NotFoundError, "No METAR found for #{airport_code}" if body.empty?

    body.lines.first.strip
  rescue NotFoundError, FetchError
    raise
  rescue => e
    raise FetchError, e.message
  end
end
