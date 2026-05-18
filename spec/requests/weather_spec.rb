require "rails_helper"

RSpec.describe "Weather", type: :request do
  let(:airport_code) { "KJFK" }
  let(:metar_string) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

  # ---------------------------------------------------------------------------
  # GET / (index)
  # ---------------------------------------------------------------------------
  describe "GET /" do
    it "returns HTTP 200" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the search form" do
      get root_path
      expect(response.body).to include("METAR Reader")
    end
  end

  # ---------------------------------------------------------------------------
  # GET /weather (show)
  # ---------------------------------------------------------------------------
  describe "GET /weather" do
    context "with a valid airport code and a successful fetch" do
      before do
        allow(MetarFetcherService).to receive(:fetch).with(airport_code)
          .and_return(metar_string)
      end

      it "returns HTTP 200" do
        get weather_path(airport_code: airport_code)
        expect(response).to have_http_status(:ok)
      end

      it "renders the airport code in the page" do
        get weather_path(airport_code: airport_code)
        expect(response.body).to include(airport_code)
      end

      it "renders the plain-English summary section" do
        get weather_path(airport_code: airport_code)
        expect(response.body).to include("Plain-English Summary")
      end

      it "renders the raw METAR" do
        get weather_path(airport_code: airport_code)
        expect(response.body).to include("Raw METAR")
      end

      it "upcases a lowercase code before fetching" do
        allow(MetarFetcherService).to receive(:fetch).with("KJFK").and_return(metar_string)
        get weather_path(airport_code: "kjfk")
        expect(response).to have_http_status(:ok)
      end
    end

    context "with a blank airport code" do
      it "redirects to root" do
        get weather_path(airport_code: "")
        expect(response).to redirect_to(root_path)
      end

      it "sets an error flash message" do
        get weather_path(airport_code: "")
        follow_redirect!
        expect(response.body).to include("Please enter an airport code")
      end
    end

    context "with an airport code that is too long to be a valid ICAO code" do
      it "redirects to root" do
        get weather_path(airport_code: "TOOLONGCODE")
        expect(response).to redirect_to(root_path)
      end

      it "sets a validation error flash" do
        get weather_path(airport_code: "TOOLONGCODE")
        follow_redirect!
        expect(response.body).to include("not a valid airport code")
      end
    end

    context "with special characters in the airport code" do
      it "redirects to root with a validation error" do
        get weather_path(airport_code: "K!@#")
        expect(response).to redirect_to(root_path)
      end
    end

    context "when the airport is not found in the weather service" do
      before do
        allow(MetarFetcherService).to receive(:fetch)
          .and_raise(MetarFetcherService::NotFoundError, "No METAR found for ZZZZ")
      end

      it "redirects to root" do
        get weather_path(airport_code: "ZZZZ")
        expect(response).to redirect_to(root_path)
      end

      it "sets an error flash mentioning the airport code" do
        get weather_path(airport_code: "ZZZZ")
        follow_redirect!
        expect(response.body).to include("ZZZZ")
      end
    end

    context "when the weather service returns a fetch error" do
      before do
        allow(MetarFetcherService).to receive(:fetch)
          .and_raise(MetarFetcherService::FetchError, "Connection timed out")
      end

      it "redirects to root" do
        get weather_path(airport_code: airport_code)
        expect(response).to redirect_to(root_path)
      end

      it "shows a generic error message without leaking internal details" do
        get weather_path(airport_code: airport_code)
        follow_redirect!
        expect(response.body).to include("Could not retrieve weather data")
        expect(response.body).not_to include("Connection timed out")
      end
    end

    context "recent airport tracking" do
      before do
        allow(MetarFetcherService).to receive(:fetch).and_return(metar_string)
      end

      it "stores the airport code in the session after a successful lookup" do
        get weather_path(airport_code: airport_code)
        expect(session[:recent_airports]).to include(airport_code)
      end

      it "keeps at most 5 recent airports" do
        %w[KJFK KLAX KORD KDEN KSFO KMIA].each do |code|
          allow(MetarFetcherService).to receive(:fetch).with(code)
            .and_return(metar_string.sub("KJFK", code))
          get weather_path(airport_code: code)
        end
        expect(session[:recent_airports].size).to eq(5)
      end

      it "deduplicates repeated lookups" do
        2.times { get weather_path(airport_code: airport_code) }
        expect(session[:recent_airports].count(airport_code)).to eq(1)
      end
    end
  end
end
