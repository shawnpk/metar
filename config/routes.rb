Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "weather#index"
  get "/weather", to: "weather#show", as: :weather
end
