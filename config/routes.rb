Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  get "signup" => "registrations#new", as: :new_user_registration
  post "signup" => "registrations#create", as: :user_registration

  resources :projects do
    get :review_queue, on: :collection
    get :comparison_dashboard
    resources :prompts
    resources :test_cases
    resources :rubrics
    resources :evaluation_runs, only: %i[ show new create destroy ] do
      get :report, on: :member
      get :export_csv, on: :member
    end
    resources :model_responses, only: [] do
      resources :reviews, only: %i[ new create ]
    end
  end

  get "evaluation_runs/:share_token/report" => "evaluation_runs#report", as: :public_evaluation_run_report

  root "projects#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
