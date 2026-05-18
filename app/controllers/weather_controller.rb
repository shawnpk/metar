class WeatherController < ApplicationController
  RECENT_LIMIT = 5

  def index
    @recent_airports = session[:recent_airports] || []
  end

  def show
    airport_code = params[:airport_code].to_s.strip.upcase

    if airport_code.blank?
      flash[:error] = "Please enter an airport code."
      return redirect_to root_path
    end

    unless airport_code.match?(/\A[A-Z0-9]{3,4}\z/)
      flash[:error] = "'#{airport_code}' is not a valid airport code. Please enter a 3–4 character ICAO code (e.g. KJFK)."
      return redirect_to root_path
    end

    raw_metar = MetarFetcherService.fetch(airport_code)
    @airport_code = airport_code
    @raw_metar = raw_metar
    @report = MetarDecoderService.new(raw_metar).decode

    track_recent(airport_code)
  rescue MetarFetcherService::NotFoundError
    flash[:error] = "No METAR data found for #{airport_code}. Check the airport code and try again."
    redirect_to root_path
  rescue MetarFetcherService::FetchError => e
    flash[:error] = "Could not retrieve weather data: #{e.message}"
    redirect_to root_path
  end

  private

  def track_recent(airport_code)
    recent = session[:recent_airports] || []
    recent = ([ airport_code ] + recent.reject { |c| c == airport_code }).first(RECENT_LIMIT)
    session[:recent_airports] = recent
  end
end
