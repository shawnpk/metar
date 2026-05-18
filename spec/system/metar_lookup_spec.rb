require "rails_helper"

RSpec.describe "METAR lookup", type: :system do
  let(:metar_string) { "KJFK 181551Z 27012KT 10SM FEW045 22/11 A2998" }

  # ---------------------------------------------------------------------------
  # Homepage
  # ---------------------------------------------------------------------------
  describe "homepage" do
    before { visit root_path }

    it "displays the application title" do
      expect(page).to have_content("METAR Reader")
    end

    it "renders the airport code search field" do
      expect(page).to have_field(:airport_code)
    end

    it "renders the decode submit button" do
      expect(page).to have_button("Decode")
    end
  end

  # ---------------------------------------------------------------------------
  # Successful search
  # ---------------------------------------------------------------------------
  describe "searching for a valid airport code" do
    before do
      allow(MetarFetcherService).to receive(:fetch).with("KJFK")
        .and_return(metar_string)
      visit root_path
      fill_in :airport_code, with: "KJFK"
      click_button "Decode"
    end

    it "shows the airport code as a heading" do
      expect(page).to have_css("h1", text: "KJFK")
    end

    it "shows the plain-English summary section" do
      expect(page).to have_content("Plain-English Summary")
    end

    it "shows the raw METAR section" do
      expect(page).to have_content("Raw METAR")
      expect(page).to have_content(metar_string)
    end

    it "shows temperature detail card" do
      expect(page).to have_content("Temperature")
    end

    it "shows wind detail card" do
      expect(page).to have_content("Wind")
    end

    it "shows visibility detail card" do
      expect(page).to have_content("Visibility")
    end

    it "provides a back-to-search link" do
      expect(page).to have_link("← New Search")
    end
  end

  # ---------------------------------------------------------------------------
  # Validation errors
  # ---------------------------------------------------------------------------
  describe "submitting a blank airport code" do
    before do
      visit root_path
      fill_in :airport_code, with: ""
      click_button "Decode"
    end

    it "stays on the homepage" do
      expect(page).to have_content("METAR Reader")
    end

    it "shows a blank-code error message" do
      expect(page).to have_content("Please enter an airport code")
    end
  end

  describe "submitting an invalid ICAO format" do
    before do
      visit root_path
      fill_in :airport_code, with: "AB"
      click_button "Decode"
    end

    it "shows a validation error" do
      expect(page).to have_content("not a valid airport code")
    end
  end

  # ---------------------------------------------------------------------------
  # Service errors
  # ---------------------------------------------------------------------------
  describe "when the airport code is not found" do
    before do
      allow(MetarFetcherService).to receive(:fetch)
        .and_raise(MetarFetcherService::NotFoundError, "No METAR found for ZZZZ")
      visit root_path
      fill_in :airport_code, with: "ZZZZ"
      click_button "Decode"
    end

    it "shows a not-found error mentioning the code" do
      expect(page).to have_content("No METAR data found for ZZZZ")
    end
  end

  describe "when the weather service is unavailable" do
    before do
      allow(MetarFetcherService).to receive(:fetch)
        .and_raise(MetarFetcherService::FetchError, "Connection timed out")
      visit root_path
      fill_in :airport_code, with: "KJFK"
      click_button "Decode"
    end

    it "shows a generic fetch error without leaking internal details" do
      expect(page).to have_content("Could not retrieve weather data")
      expect(page).not_to have_content("Connection timed out")
    end
  end

  # ---------------------------------------------------------------------------
  # Recent searches
  # ---------------------------------------------------------------------------
  describe "recent searches" do
    before do
      allow(MetarFetcherService).to receive(:fetch).and_return(metar_string)
    end

    it "shows a recently searched airport code on the homepage" do
      visit root_path
      fill_in :airport_code, with: "KJFK"
      click_button "Decode"
      click_link "← New Search"
      expect(page).to have_link("KJFK")
    end

    it "navigates to the weather page when a recent airport link is clicked" do
      visit root_path
      fill_in :airport_code, with: "KJFK"
      click_button "Decode"
      click_link "← New Search"
      click_link "KJFK"
      expect(page).to have_css("h1", text: "KJFK")
    end

    it "does not show recent searches when none have been made" do
      visit root_path
      expect(page).not_to have_content("Recent searches")
    end
  end
end
