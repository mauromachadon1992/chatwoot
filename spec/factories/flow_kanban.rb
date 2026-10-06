FactoryBot.define do
  factory :flow_kanban_board, class: 'Custom::Kanban::Board' do
    account
    sequence(:name) { |n| "Funil #{n}" }
  end

  factory :flow_kanban_stage, class: 'Custom::Kanban::Stage' do
    board factory: :flow_kanban_board
    sequence(:name) { |n| "Etapa #{n}" }
  end

  factory :flow_kanban_card, class: 'Custom::Kanban::Card' do
    stage factory: :flow_kanban_stage
    contact { association :contact, account: stage.board.account }
    sequence(:title) { |n| "Negócio #{n}" }
  end

  factory :flow_kanban_product, class: 'Custom::Kanban::Product' do
    account
    sequence(:name) { |n| "Produto #{n}" }
    price_cents { 1_000 }
  end
end
