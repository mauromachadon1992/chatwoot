require 'rails_helper'

RSpec.describe Custom::Kanban::Card do
  let(:stage) { create(:flow_kanban_stage) }
  let(:other_stage) { create(:flow_kanban_stage, board: stage.board) }

  it 'places a new card on top of its stage' do
    first = create(:flow_kanban_card, stage: stage)
    second = create(:flow_kanban_card, stage: stage)

    expect(stage.cards.ordered).to eq([second, first])
  end

  describe '#move_to!' do
    let!(:top) { create(:flow_kanban_card, stage: other_stage, position: 0) }
    let!(:bottom) { create(:flow_kanban_card, stage: other_stage, position: 1024) }
    let(:card) { create(:flow_kanban_card, stage: stage) }

    it 'lands between its new neighbours and records the stage change' do
      freeze_time do
        card.move_to!(stage: other_stage, previous_card_id: top.id, next_card_id: bottom.id)

        expect(other_stage.cards.ordered).to eq([top, card, bottom])
        expect(card.reload.stage_changed_at).to eq(Time.current)
      end
    end

    it 'goes to the top or the bottom with a single neighbour' do
      card.move_to!(stage: other_stage, next_card_id: top.id)
      expect(other_stage.cards.ordered.first).to eq(card)

      card.move_to!(stage: other_stage, previous_card_id: bottom.id)
      expect(other_stage.cards.ordered.last).to eq(card)
    end

    it 'renumbers the stage when the neighbours leave no room' do
      bottom.update!(position: top.position + 1e-9)

      card.move_to!(stage: other_stage, previous_card_id: top.id, next_card_id: bottom.id)

      expect(other_stage.cards.ordered).to eq([top, card, bottom])
      expect(bottom.reload.position - top.reload.position).to be >= described_class::POSITION_STEP
    end

    it 'refuses a stage of another board' do
      foreign_stage = create(:flow_kanban_stage)

      expect { card.move_to!(stage: foreign_stage) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
