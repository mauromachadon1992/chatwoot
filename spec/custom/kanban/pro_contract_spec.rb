require 'rails_helper'

# The Pro Kanban dialect the fazer.ai agents' client expects (custom/contracts/pro-kanban.md, the
# same copy as in flow-agents-ee). Each operation is filled in by its sprint of Phase P in
# custom/ROADMAP.md and skipped by name until then, so this list and the harness report stay the
# same 15 lines.
RSpec.describe 'Pro Kanban contract' do
  contract_files = %w[custom/contracts/pro-kanban.md custom/contracts/pro-kanban.v1.schema.json]

  operations = [
    [1, 'GET /kanban/boards', 'C1'],
    [2, 'POST /kanban/boards', 'C1'],
    [3, 'PUT /kanban/boards/:id', 'C1'],
    [4, 'GET /kanban/boards/:id/steps', 'C1'],
    [5, 'POST /kanban/boards/:id/steps', 'C1'],
    [6, 'POST /kanban/boards/:id/update_inboxes', 'C4'],
    [7, 'POST /kanban/boards/:id/update_agents', 'C4'],
    [8, 'GET /kanban/tasks', 'C1'],
    [9, 'POST /kanban/tasks', 'C1'],
    [10, 'POST /kanban/tasks/:id/move', 'C1'],
    [11, 'GET /kanban/tasks/:id', 'C1'],
    [12, 'PATCH /kanban/tasks/:id (custom_attributes)', 'C2'],
    [13, 'PATCH /kanban/tasks/:id (labels)', 'C2'],
    [14, 'PATCH /kanban/tasks/:id (title, description, priority, dates)', 'C2'],
    [15, 'GET /conversations/:display_id (kanban_task)', 'C3']
  ]

  it 'keeps the contract files equal to the hash recorded for both repositories' do
    actual = Digest::SHA256.hexdigest(contract_files.map { |file| Rails.root.join(file).read }.join)

    expect(actual).to eq(Rails.root.join('custom/contracts/CONTRACT.sha256').read.strip)
  end

  operations.each do |number, request, sprint|
    it "answers operation #{number}, #{request}, in the Pro shape", skip: "Phase P, #{sprint}" do
      expect(number).to be_positive
    end
  end
end
