module FlowCustom::Routes
  DRAW = proc do
    namespace :api, defaults: { format: 'json' } do
      namespace :v1 do
        resources :accounts, only: [] do
          scope module: :accounts do
            namespace :kanban do
              resources :boards, only: [:index, :show, :create, :update, :destroy] do
                resources :stages, only: [:create, :update, :destroy] do
                  collection { patch :reorder }
                end
                resources :cards, only: [:index] do
                  collection { get :export }
                end
                resources :automations, only: [:index, :create, :update, :destroy] do
                  collection { get :runs }
                end
                resource :report, only: [:show]
              end
              resources :cards, only: [:show, :create, :update, :destroy] do
                member do
                  patch :move
                  post :quote
                end
                resources :conversations, only: [:create, :destroy], controller: 'card_conversations'
                resources :items, only: [:create, :update, :destroy], controller: 'card_items'
                resources :tasks, only: [:index, :create, :update, :destroy], controller: 'card_tasks'
                resources :events, only: [:index], controller: 'card_events'
                resource :ai_summary, only: [:create], controller: 'ai_summaries'
              end
              resources :tasks, only: [:index]
              resources :ai_drafts, only: [], controller: 'ai_summaries' do
                member { post :decide }
              end
              resources :notifications, only: [:index, :update] do
                collection { post :read_all }
              end
              resources :products, only: [:index, :create, :update, :destroy] do
                collection { get :export }
              end
              resources :imports, only: [:create, :show, :update] do
                member do
                  post :run
                  get :errors
                end
              end
              resources :lost_reasons, only: [:index, :create, :update, :destroy]
              resources :webhooks, only: [:index, :create, :update, :destroy] do
                member do
                  get :deliveries
                  post :test
                end
              end
              resource :settings, only: [:show, :update]
              get 'conversations/:conversation_id/cards', to: 'conversation_cards#index', as: :conversation_cards
            end
            resource :white_label, only: [:show]
          end
        end
      end
    end

    # The white label's logos and icon, public like any login page asset. `version` is the
    # blob id, so a new upload gets a new URL and the response can be cached for good.
    get 'flow/brand/:account_id/:name/:version', to: 'white_label_images#show', as: :flow_white_label_image,
                                                 constraints: { account_id: /\d+/, version: /\d+/ }
    # The installation login page's images, on the same terms.
    get 'flow/login/:name/:version', to: 'login_page_images#show', as: :flow_login_page_image,
                                     constraints: { version: /\d+/ }

    # Same URL and helper names as a super admin route, outside the super_admin controller
    # namespace (see FlowAdmin::WhiteLabelsController).
    scope path: 'super_admin', as: 'super_admin', module: 'flow_admin' do
      resources :accounts, only: [] do
        resource :white_label, only: [:show, :update] do
          get :palette
        end
      end
      resource :login_page, only: [:show, :update, :destroy] do
        get :palette
      end
    end
  end
end
