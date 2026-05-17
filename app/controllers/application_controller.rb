class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  around_action :use_client_timezone

  private

  def use_client_timezone
    Time.use_zone(client_timezone) { yield }
  end

  def client_timezone
    session[:timezone] ||= resolve_timezone
  end

  def resolve_timezone
    result = Geocoder.search(request.remote_ip).first
    tz = result&.data&.dig("timezone")
    tz.present? ? tz : "UTC"
  rescue StandardError
    "UTC"
  end
end
