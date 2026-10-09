module FlowCustom::Routes
  DRAW = proc do
    namespace :api, defaults: { format: 'json' } do
      namespace :v1 do
        resources :accounts, only: [] do
          scope module: :accounts do
            namespace :kanban do
              resources :boards, only: [:index, :show, :create, :update, :destroy] do
                member do
                  post :update_inboxes
                  post :update_agents
                end
                resources :stages, only: [:create, :update, :destroy] do
                  collection { patch :reorder }
                end
                resources :steps, only: [:index, :create], controller: 'compat/steps'
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
                  get :quote_preview
                end
                resources :conversations, only: [:create, :destroy], controller: 'card_conversations'
                resources :items, only: [:create, :update, :destroy], controller: 'card_items'
                resources :tasks, only: [:index, :create, :update, :destroy], controller: 'card_tasks'
                resources :events, only: [:index], controller: 'card_events'
                resource :ai_summary, only: [:create], controller: 'ai_summaries'
              end
              # `kanban/tasks` is the Pro dialect's deals; the agent's own follow-ups are `kanban/my_tasks`.
              # The deal of a conversation and its product lines, for the fazer.ai agents (capability deal.items):
              # the agent knows the conversation, not the card, so it never names a card id.
              get 'conversations/:display_id/deal', to: 'conversation_deals#show'
              get 'conversations/:display_id/deal/quote', to: 'conversation_deals#quote'
              post 'conversations/:display_id/deal/items', to: 'conversation_deals#add_item'
              delete 'conversations/:display_id/deal/items/:product_id', to: 'conversation_deals#remove_item'
              resources :my_tasks, only: [:index], controller: 'my_tasks'
              resources :tasks, only: [:index, :show, :create, :update], controller: 'compat/tasks' do
                member { post :move }
              end
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
                  post :rotate_secret
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
    # Which build answers (the fork's release, Chatwoot's version, the commit), public like /api.
    get 'flow/version', to: 'flow_version#show'

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
