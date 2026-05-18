require "rails_helper"

RSpec.describe MetarFetcherService do
  let(:airport_code) { "KJFK" }
  let(:metar_line)   { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
  let(:api_url)      { "https://aviationweather.gov/api/data/metar?ids=#{airport_code}" }

  describe ".fetch" do
    context "when the API returns a valid METAR" do
      before do
        stub_request(:get, api_url).to_return(status: 200, body: "#{metar_line}\n")
      end

      it "returns the first line of the response body stripped of whitespace" do
        expect(described_class.fetch(airport_code)).to eq(metar_line)
      end
    end

    context "when the API returns multiple lines" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: "#{metar_line}\nKJFK 181451Z 26010KT 10SM CLR 21/10 A2995\n")
      end

      it "returns only the first line" do
        expect(described_class.fetch(airport_code)).to eq(metar_line)
      end
    end

    context "when the API returns an empty body" do
      before do
        stub_request(:get, api_url).to_return(status: 200, body: "")
      end

      it "raises NotFoundError" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::NotFoundError)
      end
    end

    context "when the API returns a non-success HTTP status" do
      before do
        stub_request(:get, api_url).to_return(status: 500)
      end

      it "raises FetchError mentioning the status code" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::FetchError, /API returned 500/)
      end
    end

    context "when the connection times out on open" do
      before do
        stub_request(:get, api_url).to_raise(Net::OpenTimeout)
      end

      it "raises FetchError with a friendly message" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::FetchError, /did not respond/)
      end
    end

    context "when the connection times out on read" do
      before do
        stub_request(:get, api_url).to_raise(Net::ReadTimeout)
      end

      it "raises FetchError with a friendly message" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::FetchError, /took too long/)
      end
    end

    context "when the connection is refused" do
      before do
        stub_request(:get, api_url).to_raise(Errno::ECONNREFUSED)
      end

      it "raises FetchError with a friendly message" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::FetchError, /Could not connect/)
      end
    end

    context "when a socket / DNS error occurs" do
      before do
        stub_request(:get, api_url).to_raise(SocketError)
      end

      it "raises FetchError with a friendly message" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::FetchError, /Network error/)
      end
    end

    context "when an unexpected error occurs" do
      before do
        stub_request(:get, api_url).to_raise(RuntimeError, "something weird")
      end

      it "wraps it in a FetchError without leaking the original class name" do
        expect { described_class.fetch(airport_code) }
          .to raise_error(MetarFetcherService::FetchError, /unexpected error/)
      end
    end
  end
end
