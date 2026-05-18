class MetarDecoderService
  COMPASS_DIRECTIONS = [
    "North", "North-Northeast", "Northeast", "East-Northeast",
    "East", "East-Southeast", "Southeast", "South-Southeast",
    "South", "South-Southwest", "Southwest", "West-Southwest",
    "West", "West-Northwest", "Northwest", "North-Northwest"
  ].freeze

  WEATHER_INTENSITY = { "-" => "Light", "+" => "Heavy", "VC" => "in the vicinity" }.freeze

  WEATHER_DESCRIPTOR = {
    "MI" => "shallow", "PR" => "partial", "BC" => "patches of", "DR" => "low drifting",
    "BL" => "blowing",  "SH" => "showers", "TS" => "thunderstorm with", "FZ" => "freezing"
  }.freeze

  WEATHER_PRECIP = {
    "DZ" => "drizzle", "RA" => "rain", "SN" => "snow",   "SG" => "snow grains",
    "IC" => "ice crystals", "PL" => "ice pellets", "GR" => "hail",
    "GS" => "small hail", "UP" => "unknown precipitation"
  }.freeze

  WEATHER_OBSCURATION = {
    "BR" => "mist", "FG" => "fog", "FU" => "smoke", "VA" => "volcanic ash",
    "DU" => "dust", "SA" => "sand", "HZ" => "haze", "PY" => "spray"
  }.freeze

  WEATHER_OTHER = {
    "PO" => "dust/sand whirls", "SQ" => "squalls",
    "FC" => "funnel cloud/tornado", "SS" => "sandstorm", "DS" => "dust storm"
  }.freeze

  SKY_COVERAGE = {
    "SKC" => "Sky clear", "CLR" => "Clear skies",
    "NSC" => "No significant clouds", "FEW" => "Few clouds",
    "SCT" => "Scattered clouds", "BKN" => "Broken clouds", "OVC" => "Overcast"
  }.freeze

  def initialize(raw_metar)
    @raw = raw_metar.strip
    # Split off remarks — everything after RMK is freeform
    parts = @raw.split(/\bRMK\b/, 2)
    tokens = parts.first.split
    # Drop optional report-type prefix (METAR or SPECI)
    tokens.shift if %w[METAR SPECI].include?(tokens.first)
    @tokens = tokens
    @remarks_raw = parts[1]&.strip
  end

  def decode
    {
      station:     parse_station,
      observed_at: parse_time,
      auto:        @tokens.include?("AUTO"),
      wind:        parse_wind,
      visibility:  parse_visibility,
      weather:     parse_weather_phenomena,
      clouds:      parse_sky_conditions,
      temperature: parse_temperature,
      dew_point:   parse_dew_point,
      altimeter:   parse_altimeter,
      remarks:     @remarks_raw,
      summary:     nil  # filled in after all fields are parsed
    }.tap { |r| r[:summary] = build_summary(r) }
  end

  private

  def parse_station
    @tokens.first
  end

  def parse_time
    token = @tokens.find { |t| t.match?(/\A\d{6}Z\z/) }
    return nil unless token

    day  = token[0..1].to_i
    hour = token[2..3].to_i
    min  = token[4..5].to_i

    # Build a full UTC Time using current year/month — METARs are always current.
    # If the constructed time is more than 1 hour ahead, the METAR day crossed a
    # month boundary (e.g., day=01 fetched on the last day of the prior month).
    now = Time.now.utc
    t = Time.utc(now.year, now.month, day, hour, min)
    return t unless t > now + 3600

    prev_month = now.month == 1 ? 12 : now.month - 1
    prev_year  = now.month == 1 ? now.year - 1 : now.year
    Time.utc(prev_year, prev_month, day, hour, min)
  end

  def parse_wind
    token = @tokens.find { |t| t.match?(/\A(VRB|\d{3})(\d{2,3})(G\d{2,3})?(KT|MPS|KMH)\z/) }
    return { raw: nil, description: "Wind information unavailable" } unless token

    match = token.match(/\A(VRB|\d{3})(\d{2,3})(G(\d{2,3}))?(KT|MPS|KMH)\z/)
    dir_raw = match[1]
    speed   = match[2].to_i
    gust    = match[4]&.to_i
    unit    = match[5]

    speed_kt = case unit
               when "MPS" then (speed * 1.944).round
               when "KMH" then (speed * 0.5400).round
               else speed
               end
    gust_kt  = case unit
               when "MPS" then gust ? (gust * 1.944).round : nil
               when "KMH" then gust ? (gust * 0.5400).round : nil
               else gust
               end

    unit_label = unit == "KT" ? "knots" : unit == "MPS" ? "m/s" : "km/h"

    direction_text =
      if dir_raw == "VRB"
        "Variable"
      elsif speed == 0
        nil
      else
        "from the #{degrees_to_compass(dir_raw.to_i)} (#{dir_raw}°)"
      end

    description =
      if speed == 0
        "Calm winds"
      elsif dir_raw == "VRB"
        desc = "Variable winds at #{speed} #{unit_label}"
        desc += ", gusting to #{gust} #{unit_label}" if gust
        desc
      else
        desc = "Wind #{direction_text} at #{speed} #{unit_label}"
        desc += ", gusting to #{gust} #{unit_label}" if gust
        desc
      end

    { raw: token, direction: dir_raw, speed_kt: speed_kt, gust_kt: gust_kt,
      description: description }
  end

  def parse_visibility
    # Check for CAVOK first
    return { raw: "CAVOK", description: "Ceiling and visibility OK (10+ km, no significant cloud)" } if @tokens.include?("CAVOK")

    # Statute miles (US format) — handles integers ("10SM"), fractions ("1/4SM"),
    # and space-separated mixed numbers ("1" "1/4SM"). Non-zero denominator required
    # to avoid ZeroDivisionError from Rational().
    sm_token = nil
    prev_token_idx = nil
    @tokens.each_with_index do |t, i|
      if t.match?(/\A\d+\/[1-9]\d*SM\z/)
        sm_token = t
        prev_token_idx = i - 1 if i > 0 && @tokens[i - 1].match?(/\A\d+\z/)
      elsif t.match?(/\A\d+SM\z/)
        sm_token = t
      end
    end

    if sm_token
      whole   = prev_token_idx ? @tokens[prev_token_idx].to_i : 0
      fraction_part = sm_token.sub("SM", "")
      fraction = Rational(fraction_part)
      total    = whole + fraction
      miles    = total == total.to_i ? total.to_i : total.to_f.round(2)
      unit_str = miles == 1 ? "mile" : "miles"
      return { raw: sm_token, description: "Visibility #{miles} statute #{unit_str}" }
    end

    if (token = @tokens.find { |t| t.match?(/\A\d{4}\z/) && t != "9999" })
      return { raw: token, description: "Visibility #{token.to_i} meters" }
    end

    if @tokens.include?("9999")
      return { raw: "9999", description: "Visibility 10+ km (excellent)" }
    end

    { raw: nil, description: "Visibility information unavailable" }
  end

  def parse_weather_phenomena
    phenomena = []
    descriptor_keys = WEATHER_DESCRIPTOR.keys

    @tokens.each do |token|
      remaining = token.dup
      parts = []

      # Extract intensity or VC prefix
      intensity = nil
      if remaining.start_with?("+")
        intensity = WEATHER_INTENSITY["+"]
        remaining = remaining[1..]
      elsif remaining.start_with?("-")
        intensity = WEATHER_INTENSITY["-"]
        remaining = remaining[1..]
      elsif remaining.start_with?("VC")
        intensity = WEATHER_INTENSITY["VC"]
        remaining = remaining[2..]
      end

      # Extract descriptor (2-char)
      descriptor = nil
      descriptor_keys.each do |key|
        if remaining.start_with?(key)
          descriptor = WEATHER_DESCRIPTOR[key]
          remaining = remaining[2..]
          break
        end
      end

      # Extract all weather codes
      while remaining.length >= 2
        code = remaining[0..1]
        if WEATHER_PRECIP.key?(code)
          parts << WEATHER_PRECIP[code]
          remaining = remaining[2..]
        elsif WEATHER_OBSCURATION.key?(code)
          parts << WEATHER_OBSCURATION[code]
          remaining = remaining[2..]
        elsif WEATHER_OTHER.key?(code)
          parts << WEATHER_OTHER[code]
          remaining = remaining[2..]
        else
          break
        end
      end

      next if parts.empty?

      phrase_parts = [ intensity, descriptor, parts.join(" and ") ].compact
      phenomena << phrase_parts.join(" ").strip.capitalize
    end

    phenomena
  end

  def parse_sky_conditions
    conditions = []

    if @tokens.include?("SKC") || @tokens.include?("CLR") || @tokens.include?("NSC")
      key = (@tokens & %w[SKC CLR NSC]).first
      return [ { raw: key, description: SKY_COVERAGE[key] } ]
    end

    @tokens.each do |token|
      if (match = token.match(/\A(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?\z/))
        coverage = SKY_COVERAGE[match[1]]
        altitude = match[2].to_i * 100
        cb_tcu   = match[3] == "CB" ? " (cumulonimbus)" : match[3] == "TCU" ? " (towering cumulus)" : ""
        conditions << { raw: token, description: "#{coverage} at #{format_number(altitude)} feet#{cb_tcu}" }
      elsif (match = token.match(/\AVV(\d{3})\z/))
        altitude = match[1].to_i * 100
        conditions << { raw: token, description: "Sky obscured, vertical visibility #{format_number(altitude)} feet" }
      end
    end

    conditions
  end

  def parse_temperature
    return nil unless temp_dew_token
    parse_celsius(temp_dew_token.split("/").first)
  end

  def parse_dew_point
    return nil unless temp_dew_token
    parse_celsius(temp_dew_token.split("/").last)
  end

  def temp_dew_token
    @temp_dew_token ||= @tokens.find { |t| t.match?(/\A(M?\d+)\/(M?\d+)\z/) }
  end

  def parse_altimeter
    token = @tokens.find { |t| t.match?(/\AA\d{4}\z/) }
    if token
      inches = token[1..].to_f / 100.0
      return { raw: token, inches: inches, description: "#{format('%.2f', inches)} inHg" }
    end

    token = @tokens.find { |t| t.match?(/\AQ\d{4}\z/) }
    if token
      hpa    = token[1..].to_i
      inches = (hpa * 0.02953).round(2)
      return { raw: token, hpa: hpa, description: "#{hpa} hPa (#{format('%.2f', inches)} inHg)" }
    end

    nil
  end

  def build_summary(r)
    parts = []

    # Sky / overall condition
    if r[:clouds].empty?
      parts << "Clear skies"
    else
      r[:clouds].each { |c| parts << c[:description] }
    end

    # Weather phenomena
    parts.concat(r[:weather]) if r[:weather].any?

    # Wind
    parts << r[:wind][:description]

    # Visibility
    parts << r[:visibility][:description]

    # Altimeter
    parts << "Pressure #{r[:altimeter][:description]}" if r[:altimeter]

    parts
  end

  def degrees_to_compass(degrees)
    index = ((degrees + 11.25) / 22.5).to_i % 16
    COMPASS_DIRECTIONS[index]
  end

  def parse_celsius(str)
    str.start_with?("M") ? -str[1..].to_i : str.to_i
  end

  def format_number(n)
    n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end
end
