Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The directory and search results: one page for browsing and searching (#40).
  get "companies" => "directory#index", as: :companies
  get "companies/:slug" => "companies#show", as: :company
  get "plants/:slug" => "plants#show", as: :plant
  get "corrections/new" => "corrections#new", as: :new_correction
  post "corrections" => "corrections#create", as: :corrections
  get "corrections/sent" => "corrections#sent", as: :correction_sent

  get "privacy" => "pages#privacy", as: :privacy
  get "disclaimer" => "pages#disclaimer", as: :disclaimer
  get "bot" => "pages#bot", as: :bot
  get "sitemap.xml" => "sitemaps#show", as: :sitemap, format: false, defaults: { format: :xml }
  get "robots.txt" => "sitemaps#robots", as: :robots, format: false

  # The home page and its instant search (#41). /search returns a Turbo Frame
  # of grouped results for the home and header search fields.
  root "home#show"
  get "search" => "search#index", as: :search

  # The admin (#86): one account, signed in at /admin/session/sign-in. Every
  # decision goes through DataQuality::Review.
  resource :session, only: %i[new create destroy], path: "admin/session", path_names: { new: "sign-in" }
  namespace :admin do
    root "candidates#index"
    resources :candidates, only: %i[index edit update] do
      collection do
        post :approve
        post :reject
      end
    end
    resources :pending_facts, only: :index, path: "pending" do
      collection do
        post :approve
        post :reject
      end
    end
    scope "facts/:type/:id", as: :fact, constraints: { type: /[A-Z][A-Za-z]+/, id: /\d+/ } do
      get "/" => "facts#show"
      post "unpublish" => "facts#unpublish", as: :unpublish
      post "republish" => "facts#republish", as: :republish
    end
  end

  # Living reference for the design system (see DESIGN.md). Not public.
  get "design" => "design_system#show", as: :design_system if Rails.env.local?
  # Development shows Rails' debug page for a 404; this previews the real one.
  get "design/not-found/*path" => "errors#not_found", format: false if Rails.env.local?

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
