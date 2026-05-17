module ApplicationHelper
  def temperature_display(celsius)
    return "N/A" if celsius.nil?

    f = ((celsius * 9.0 / 5.0) + 32).round
    "#{f}°F (#{celsius}°C)"
  end
end
