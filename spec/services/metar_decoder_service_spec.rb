require "rails_helper"

RSpec.describe MetarDecoderService do
  subject(:result) { described_class.new(metar).decode }

  # ---------------------------------------------------------------------------
  # Station
  # ---------------------------------------------------------------------------
  describe "station identification" do
    let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

    it "returns the ICAO identifier" do
      expect(result[:station]).to eq("KJFK")
    end

    context "when a METAR report-type prefix is present" do
      let(:metar) { "METAR KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:station]).to eq("KJFK") }
    end

    context "when a SPECI report-type prefix is present" do
      let(:metar) { "SPECI KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:station]).to eq("KJFK") }
    end
  end

  # ---------------------------------------------------------------------------
  # Observation time
  # ---------------------------------------------------------------------------
  describe "observation time" do
    let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

    it "parses day, hour, and minute from the Zulu time token" do
      travel_to Time.utc(2025, 5, 18, 16, 0, 0) do
        expect(result[:observed_at]).to eq(Time.utc(2025, 5, 18, 15, 51))
      end
    end

    context "when the observation time token is missing" do
      let(:metar) { "KJFK 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:observed_at]).to be_nil }
    end

    context "when the observation day crosses a month boundary" do
      # METAR day=30 but today is already the 1st — roll back to prior month
      let(:metar) { "KJFK 301950Z 27012KT 10SM FEW045 22/11 A2998" }

      it "returns a time in the previous month" do
        travel_to Time.utc(2025, 5, 1, 0, 30) do
          expect(result[:observed_at]).to eq(Time.utc(2025, 4, 30, 19, 50))
        end
      end
    end

    context "when the month boundary straddles a year boundary (December → January)" do
      let(:metar) { "KJFK 311950Z 27012KT 10SM FEW045 22/11 A2998" }

      it "rolls back to December of the previous year" do
        travel_to Time.utc(2025, 1, 1, 0, 30) do
          expect(result[:observed_at]).to eq(Time.utc(2024, 12, 31, 19, 50))
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # AUTO flag
  # ---------------------------------------------------------------------------
  describe "automated report flag" do
    context "when AUTO token is present" do
      let(:metar) { "KJFK 181551Z AUTO 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:auto]).to be true }
    end

    context "when AUTO token is absent" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:auto]).to be false }
    end
  end

  # ---------------------------------------------------------------------------
  # Wind
  # ---------------------------------------------------------------------------
  describe "wind" do
    context "with standard directional wind" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

      it "captures direction and speed" do
        aggregate_failures do
          expect(result[:wind][:direction]).to eq("270")
          expect(result[:wind][:speed_kt]).to eq(12)
          expect(result[:wind][:gust_kt]).to be_nil
        end
      end

      it "builds a human-readable description" do
        expect(result[:wind][:description]).to include("12 knots")
      end
    end

    context "with gusts" do
      let(:metar) { "KJFK 181551Z 27012G18KT 10SM FEW045 22/11 A2998" }

      it "includes the gust speed" do
        expect(result[:wind][:gust_kt]).to eq(18)
        expect(result[:wind][:description]).to include("gusting to 18 knots")
      end
    end

    context "with variable wind direction" do
      let(:metar) { "KJFK 181551Z VRB03KT 10SM FEW045 22/11 A2998" }

      it "describes variable wind" do
        expect(result[:wind][:description]).to include("Variable winds at 3 knots")
      end
    end

    context "with calm wind (00000KT)" do
      let(:metar) { "KJFK 181551Z 00000KT 10SM SKC 22/11 A2998" }

      it "describes calm conditions" do
        expect(result[:wind][:description]).to eq("Calm winds")
      end
    end

    context "with wind in metres per second" do
      let(:metar) { "EGLL 181550Z 27010MPS 9999 FEW030 15/08 Q1013" }

      it "converts MPS speed to knots" do
        expect(result[:wind][:speed_kt]).to eq(19) # 10 * 1.944 = 19.44 → 19
      end
    end

    context "when wind token is absent" do
      let(:metar) { "KJFK 181551Z 10SM FEW045 22/11 A2998" }

      it "returns an unavailable message" do
        expect(result[:wind][:description]).to eq("Wind information unavailable")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Visibility
  # ---------------------------------------------------------------------------
  describe "visibility" do
    context "with statute miles" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:visibility][:description]).to eq("Visibility 10 statute miles") }
    end

    context "with a fractional statute mile" do
      let(:metar) { "KJFK 181551Z 27012KT 1/4SM FEW045 22/11 A2998" }
      it { expect(result[:visibility][:description]).to eq("Visibility 0.25 statute miles") }
    end

    context "with a mixed whole-number and fractional statute mile" do
      let(:metar) { "KJFK 181551Z 27012KT 1 1/4SM FEW045 22/11 A2998" }
      it { expect(result[:visibility][:description]).to eq("Visibility 1.25 statute miles") }
    end

    context "with CAVOK" do
      let(:metar) { "EGLL 181550Z 27010KT CAVOK 15/08 Q1013" }
      it { expect(result[:visibility][:description]).to include("Ceiling and visibility OK") }
    end

    context "with metric 9999 (10+ km)" do
      let(:metar) { "EGLL 181550Z 27010KT 9999 FEW030 15/08 Q1013" }
      it { expect(result[:visibility][:description]).to include("10+ km") }
    end

    context "with a metric value in metres" do
      let(:metar) { "EGLL 181550Z 27010KT 0800 FEW005 15/08 Q1013" }
      it { expect(result[:visibility][:description]).to eq("Visibility 800 meters") }
    end
  end

  # ---------------------------------------------------------------------------
  # Weather phenomena
  # ---------------------------------------------------------------------------
  describe "weather phenomena" do
    context "with light rain (-RA)" do
      let(:metar) { "KJFK 181551Z 27012KT 3SM -RA FEW040 22/18 A2990" }
      it { expect(result[:weather]).to include("Light rain") }
    end

    context "with heavy snow (+SN)" do
      let(:metar) { "KJFK 181551Z 27012KT 1SM +SN OVC010 M02/M05 A2980" }
      it { expect(result[:weather]).to include("Heavy snow") }
    end

    context "with mist (BR)" do
      let(:metar) { "KJFK 181551Z 27012KT 3SM BR FEW020 18/16 A3005" }
      it { expect(result[:weather]).to include("Mist") }
    end

    context "with freezing rain (FZRA)" do
      let(:metar) { "KJFK 181551Z 27008KT 1SM FZRA OVC010 M01/M03 A2985" }
      it { expect(result[:weather]).to include(match(/freezing.*rain/i)) }
    end

    context "with thunderstorm and rain (TSRA)" do
      let(:metar) { "KJFK 181551Z 18015KT 2SM TSRA BKN030CB 24/21 A2982" }
      it { expect(result[:weather]).to include(match(/thunderstorm.*rain/i)) }
    end

    context "with no weather phenomena" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:weather]).to be_empty }
    end
  end

  # ---------------------------------------------------------------------------
  # Sky conditions
  # ---------------------------------------------------------------------------
  describe "sky conditions" do
    context "with SKC (sky clear)" do
      let(:metar) { "KJFK 181551Z 00000KT 10SM SKC 22/11 A2998" }

      it "returns a single clear-sky entry" do
        expect(result[:clouds]).to eq([ { raw: "SKC", description: "Sky clear" } ])
      end
    end

    context "with CLR" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM CLR 22/11 A2998" }
      it { expect(result[:clouds].first[:description]).to eq("Clear skies") }
    end

    context "with NSC" do
      let(:metar) { "EGLL 181550Z 27010KT 9999 NSC 15/08 Q1013" }
      it { expect(result[:clouds].first[:description]).to eq("No significant clouds") }
    end

    context "with layered cloud coverage" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 SCT080 BKN200 22/11 A2998" }

      it "returns one entry per layer" do
        expect(result[:clouds].size).to eq(3)
      end

      it "formats altitudes correctly" do
        descriptions = result[:clouds].map { |c| c[:description] }
        expect(descriptions).to include("Few clouds at 4,500 feet")
        expect(descriptions).to include("Scattered clouds at 8,000 feet")
        expect(descriptions).to include("Broken clouds at 20,000 feet")
      end
    end

    context "with cumulonimbus (CB)" do
      let(:metar) { "KJFK 181551Z 18015KT 5SM BKN030CB 24/21 A2982" }

      it "appends the CB qualifier" do
        expect(result[:clouds].first[:description]).to include("(cumulonimbus)")
      end
    end

    context "with towering cumulus (TCU)" do
      let(:metar) { "KJFK 181551Z 18015KT 5SM SCT025TCU 24/21 A2982" }
      it { expect(result[:clouds].first[:description]).to include("(towering cumulus)") }
    end

    context "with vertical visibility (VV)" do
      let(:metar) { "KJFK 181551Z 27005KT 1/4SM FG VV002 18/17 A3002" }
      it { expect(result[:clouds].first[:description]).to include("vertical visibility 200 feet") }
    end
  end

  # ---------------------------------------------------------------------------
  # Temperature and dew point
  # ---------------------------------------------------------------------------
  describe "temperature and dew point" do
    context "with positive values" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

      it "parses temperature in Celsius" do
        expect(result[:temperature]).to eq(22)
      end

      it "parses dew point in Celsius" do
        expect(result[:dew_point]).to eq(11)
      end
    end

    context "with negative values (M prefix)" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM OVC010 M05/M12 A2980" }

      it "returns a negative temperature" do
        expect(result[:temperature]).to eq(-5)
      end

      it "returns a negative dew point" do
        expect(result[:dew_point]).to eq(-12)
      end
    end

    context "when the temperature token is absent" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 A2998" }

      it { expect(result[:temperature]).to be_nil }
      it { expect(result[:dew_point]).to be_nil }
    end
  end

  # ---------------------------------------------------------------------------
  # Altimeter
  # ---------------------------------------------------------------------------
  describe "altimeter" do
    context "with A-format (inches of mercury)" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

      it "parses the pressure in inHg" do
        expect(result[:altimeter][:inches]).to be_within(0.01).of(29.98)
        expect(result[:altimeter][:description]).to eq("29.98 inHg")
      end
    end

    context "with Q-format (hectopascals)" do
      let(:metar) { "EGLL 181550Z 27010KT 9999 FEW030 15/08 Q1013" }

      it "parses hPa and converts to inHg" do
        aggregate_failures do
          expect(result[:altimeter][:hpa]).to eq(1013)
          expect(result[:altimeter][:description]).to include("1013 hPa")
        end
      end
    end

    context "when altimeter is absent" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11" }
      it { expect(result[:altimeter]).to be_nil }
    end
  end

  # ---------------------------------------------------------------------------
  # Remarks
  # ---------------------------------------------------------------------------
  describe "remarks" do
    context "when RMK section is present" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998 RMK AO2 SLP155" }
      it { expect(result[:remarks]).to eq("AO2 SLP155") }
    end

    context "when there are no remarks" do
      let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }
      it { expect(result[:remarks]).to be_nil }
    end
  end

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------
  describe "summary" do
    let(:metar) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

    it "is a non-empty array of plain-English phrases" do
      expect(result[:summary]).to be_an(Array).and be_present
    end

    it "includes wind information" do
      expect(result[:summary]).to include(match(/12 knots/))
    end

    it "includes visibility information" do
      expect(result[:summary]).to include(match(/10 statute miles/))
    end
  end
end
