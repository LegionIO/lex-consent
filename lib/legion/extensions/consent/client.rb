# frozen_string_literal: true

require 'legion/extensions/consent/helpers/tiers'
require 'legion/extensions/consent/helpers/consent_map'
require 'legion/extensions/consent/runners/consent'

module Legion
  module Extensions
    module Consent
      class Client
        include Runners::Consent

        def initialize(**)
          @consent_map = Helpers::ConsentMap.new
        end

        private

        attr_reader :consent_map
      end
    end
  end
end
