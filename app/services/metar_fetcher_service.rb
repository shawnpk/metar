require "net/http"
require "uri"

class MetarFetcherService
  NotFoundError = Class.new(StandardError)
  FetchError    = Class.new(StandardError)

  BASE_URL = "https://aviationweather.gov/api/data/metar"

  def self.fetch(airport_code)
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(ids: airport_code)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: 5, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    raise FetchError, "API returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s.strip
    raise NotFoundError, "No METAR found for #{airport_code}" if body.empty?

    body.lines.first.strip
  rescue NotFoundError, FetchError
    raise
  rescue Net::OpenTimeout
    raise FetchError, "Connection timed out — the weather service did not respond"
  rescue Net::ReadTimeout
    raise FetchError, "The weather service took too long to respond"
  rescue Errno::ECONNREFUSED
    raise FetchError, "Could not connect to the weather service"
  rescue SocketError
    raise FetchError, "Network error — check your internet connection"
  rescue => e
    raise FetchError, "An unexpected error occurred while fetching weather data"
  end
end
