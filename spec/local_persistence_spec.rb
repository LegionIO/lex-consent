# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'json'
require 'tmpdir'

RSpec.describe 'lex-consent local SQLite persistence' do
  let(:db_path) { File.join(Dir.tmpdir, "consent_test_#{Process.pid}_#{rand(9999)}.db") }
  let(:db) { Sequel.sqlite(db_path) }

  before do
    # Create the schema in the temp DB
    db.create_table(:consent_domains) do
      primary_key :id
      String :domain_key, null: false, unique: true
      String :tier, null: false, default: 'consult'
      Integer :success_count, default: 0
      Integer :failure_count, default: 0
      Integer :total_actions, default: 0
      DateTime :last_changed_at
      String :history, text: true
    end

    # Stub Legion::Data::Local to use our temp DB
    stub_const('Legion::Data::Local', Module.new do
      def self.connected?
        true
      end

      def self.connection
        @_connection
      end

      def self._set_connection(conn)
        @_connection = conn
      end
    end)

    Legion::Data::Local._set_connection(db)
  end

  after do
    db.disconnect
    File.delete(db_path) if File.exist?(db_path)
  end

  describe 'save_to_local' do
    it 'writes domain state to the database' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.record_outcome('email', success: true)
      map.record_outcome('email', success: true)
      map.save_to_local

      row = db[:consent_domains].where(domain_key: 'email').first
      expect(row).not_to be_nil
      expect(row[:domain_key]).to eq('email')
      expect(row[:tier]).to eq('consult')
      expect(row[:success_count]).to eq(2)
      expect(row[:total_actions]).to eq(2)
    end

    it 'updates an existing row on second save' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.record_outcome('email', success: true)
      map.save_to_local

      map.record_outcome('email', success: false)
      map.save_to_local

      rows = db[:consent_domains].where(domain_key: 'email').all
      expect(rows.size).to eq(1)
      expect(rows.first[:failure_count]).to eq(1)
      expect(rows.first[:total_actions]).to eq(2)
    end

    it 'serializes tier as a string' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.set_tier('scheduling', :autonomous)
      map.save_to_local

      row = db[:consent_domains].where(domain_key: 'scheduling').first
      expect(row[:tier]).to eq('autonomous')
    end

    it 'serializes history as JSON' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.set_tier('scheduling', :autonomous)
      map.save_to_local

      row = db[:consent_domains].where(domain_key: 'scheduling').first
      parsed = JSON.parse(row[:history])
      expect(parsed).to be_an(Array)
      expect(parsed.first['from']).to eq('consult')
      expect(parsed.first['to']).to eq('autonomous')
    end

    it 'persists multiple domains' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.record_outcome('email', success: true)
      map.record_outcome('calendar', success: false)
      map.save_to_local

      expect(db[:consent_domains].count).to eq(2)
    end
  end

  describe 'load_from_local' do
    it 'restores domain state from the database' do
      db[:consent_domains].insert(
        domain_key:    'email',
        tier:          'act_notify',
        success_count: 5,
        failure_count: 1,
        total_actions: 6,
        history:       '[]'
      )

      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      expect(map.get_tier('email')).to eq(:act_notify)
      expect(map.domains['email'][:success_count]).to eq(5)
      expect(map.domains['email'][:total_actions]).to eq(6)
    end

    it 'restores history as an array of hashes with symbol keys' do
      history_json = JSON.generate([{ 'from' => 'consult', 'to' => 'act_notify', 'at' => Time.now.utc.to_s }])
      db[:consent_domains].insert(
        domain_key:    'scheduling',
        tier:          'act_notify',
        success_count: 10,
        failure_count: 0,
        total_actions: 10,
        history:       history_json
      )

      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      history = map.domains['scheduling'][:history]
      expect(history).to be_an(Array)
      expect(history.first[:from]).to eq(:consult)
      expect(history.first[:to]).to eq(:act_notify)
    end

    it 'handles empty history JSON gracefully' do
      db[:consent_domains].insert(
        domain_key:    'empty_history',
        tier:          'consult',
        success_count: 0,
        failure_count: 0,
        total_actions: 0,
        history:       '[]'
      )

      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      expect(map.domains['empty_history'][:history]).to eq([])
    end
  end

  describe 'round-trip persistence' do
    it 'saves and restores earned tier' do
      # First instance: build history and promote
      map1 = Legion::Extensions::Consent::Helpers::ConsentMap.new
      15.times { map1.record_outcome('tasks', success: true) }
      map1.set_tier('tasks', :act_notify)
      map1.save_to_local

      # Second instance: loads from DB
      map2 = Legion::Extensions::Consent::Helpers::ConsentMap.new
      expect(map2.get_tier('tasks')).to eq(:act_notify)
      expect(map2.domains['tasks'][:success_count]).to eq(15)
      expect(map2.domains['tasks'][:total_actions]).to eq(15)
    end

    it 'round-trips multiple domains independently' do
      map1 = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map1.set_tier('email', :autonomous)
      map1.record_outcome('calendar', success: true)
      map1.record_outcome('calendar', success: false)
      map1.save_to_local

      map2 = Legion::Extensions::Consent::Helpers::ConsentMap.new
      expect(map2.get_tier('email')).to eq(:autonomous)
      expect(map2.get_tier('calendar')).to eq(:consult)
      expect(map2.domains['calendar'][:success_count]).to eq(1)
      expect(map2.domains['calendar'][:failure_count]).to eq(1)
    end
  end

  describe 'graceful no-op when Legion::Data::Local is unavailable' do
    before do
      # Simulate no Legion::Data::Local defined
      hide_const('Legion::Data::Local')
    end

    it 'save_to_local does nothing without raising' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.record_outcome('email', success: true)
      expect { map.save_to_local }.not_to raise_error
    end

    it 'load_from_local does nothing without raising (no DB loaded at init)' do
      expect { Legion::Extensions::Consent::Helpers::ConsentMap.new }.not_to raise_error
    end

    it 'starts with default in-memory state' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      expect(map.get_tier('email')).to eq(:consult)
    end
  end

  describe 'graceful no-op when Legion::Data::Local is defined but not connected' do
    before do
      stub_const('Legion::Data::Local', Module.new do
        def self.connected?
          false
        end
      end)
    end

    it 'save_to_local does nothing without raising' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      map.record_outcome('email', success: true)
      expect { map.save_to_local }.not_to raise_error
    end

    it 'initialize completes without raising' do
      expect { Legion::Extensions::Consent::Helpers::ConsentMap.new }.not_to raise_error
    end

    it 'starts with default in-memory state' do
      map = Legion::Extensions::Consent::Helpers::ConsentMap.new
      expect(map.get_tier('email')).to eq(:consult)
    end
  end
end
