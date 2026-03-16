# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:consent_domains) do
      primary_key :id
      String :domain_key, null: false, unique: true, index: true
      String :tier, null: false, default: 'consult'
      Integer :success_count, default: 0
      Integer :failure_count, default: 0
      Integer :total_actions, default: 0
      DateTime :last_changed_at
      String :history, text: true
    end
  end
end
