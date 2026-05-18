require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#temperature_display" do
    it "returns N/A when the value is nil" do
      expect(helper.temperature_display(nil)).to eq("N/A")
    end

    it "converts 0°C to 32°F" do
      expect(helper.temperature_display(0)).to eq("32°F (0°C)")
    end

    it "converts a positive Celsius value to Fahrenheit" do
      expect(helper.temperature_display(22)).to eq("72°F (22°C)")
    end

    it "converts a negative Celsius value to Fahrenheit" do
      expect(helper.temperature_display(-5)).to eq("23°F (-5°C)")
    end

    it "rounds the Fahrenheit value to the nearest integer" do
      # 37°C = 98.6°F → rounds to 99
      expect(helper.temperature_display(37)).to eq("99°F (37°C)")
    end
  end
end
